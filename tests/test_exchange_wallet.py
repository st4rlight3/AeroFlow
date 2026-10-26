from decimal import Decimal
from datetime import timedelta
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import uuid
import pytest
from app.db import query
from conftest import send,sign_in,book,pay

pytestmark=pytest.mark.integration

def new_flight(flight):
    d=flight['DepartureTime']+timedelta(days=1)
    # Position the same aircraft back at the origin before its next departure.
    positioning=flight['DepartureTime']+timedelta(hours=4)
    query('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?',(None,'Z'+uuid.uuid4().hex[:7],flight['AircraftID'],flight['DestinationID'],flight['OriginID'],positioning,positioning+timedelta(hours=2)))
    fid=query('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?',(None,'X'+uuid.uuid4().hex[:7],flight['AircraftID'],flight['OriginID'],flight['DestinationID'],d,d+timedelta(hours=2)),one=True)['FlightID']
    query('EXEC dbo.sp_SaveFare ?,?,?,?',(fid,flight['FareClassID'],1200000,.1));return fid

def test_exchange_atomic_price_guard_idempotent_and_airline_refund(app,users,flight):
    c=sign_in(app,users[0]); other=sign_in(app,users[1]); admin=sign_in(app,users[2]); b=book(c,flight); bid=b['BookingID']; assert pay(c,bid).status_code==200
    sid=c.get(f'/api/itineraries/{bid}').json['segments'][0]['BookingSegmentID']; fid=new_flight(flight)
    choice=dict(FlightID=fid,FareClassID=flight['FareClassID']); quote=send(c,f'/api/segments/{sid}/exchange-quote',choice)
    assert quote.status_code==200,quote.json; assert Decimal(quote.json['Difference'])==420000
    assert send(other,f'/api/segments/{sid}/exchange-quote',choice).status_code==404
    key=uuid.uuid4().hex
    assert send(c,f'/api/segments/{sid}/exchange',{**choice,'IdempotencyKey':key,'ExpectedDifference':1}).status_code==409
    assert query("SELECT COUNT(*) N FROM dbo.Tickets WHERE BookingSegmentID=? AND Status='VALID'",(sid,),one=True)['N']==1
    assert query('SELECT COUNT(*) N FROM dbo.BookingChanges WHERE BookingID=?',(bid,),one=True)['N']==0
    payload={**choice,'IdempotencyKey':key,'ExpectedDifference':quote.json['Difference']}
    r=send(c,f'/api/segments/{sid}/exchange',payload); assert r.status_code==200,r.json
    assert send(c,f'/api/segments/{sid}/exchange',payload).json==r.json
    rows=c.get(f'/api/itineraries/{bid}').json
    assert sorted(t['Status'] for t in rows['tickets'])==['VALID','VOID']
    assert sorted(s['SegmentStatus'] for s in rows['segments'])==['ACTIVE','EXCHANGED']
    summary=c.get(f'/api/bookings/{bid}').json['booking']
    assert summary['FlightID']==fid and summary['SegmentCount']==1
    assert Decimal(c.get(f'/api/bookings/{bid}').json['booking']['TotalAmount'])==1520000
    assert send(admin,f'/api/admin/flights/{fid}/status',dict(Status='CANCELLED'),method='PUT').status_code==200
    refund=query("SELECT SUM(Amount) A FROM dbo.Payments WHERE BookingID=? AND Kind='REFUND'",(bid,),one=True)['A']
    assert refund==1520000

def test_exchange_forbidden_fare_and_ownership(app,users,flight):
    c=sign_in(app,users[0]); other=sign_in(app,users[1]); b=book(c,flight); pay(c,b['BookingID']); sid=c.get(f"/api/itineraries/{b['BookingID']}").json['segments'][0]['BookingSegmentID']; fid=new_flight(flight)
    payload=dict(FlightID=fid,FareClassID=flight['FareClassID'],ExpectedDifference=420000,IdempotencyKey=uuid.uuid4().hex)
    assert send(other,f'/api/segments/{sid}/exchange',payload).status_code==404
    query('UPDATE dbo.TicketRules SET ChangeAllowed=0 WHERE TicketID IN (SELECT TicketID FROM dbo.Tickets WHERE BookingSegmentID=?)',(sid,))
    assert send(c,f'/api/segments/{sid}/exchange',payload).status_code==409

def test_credit_refund_and_concurrent_spending(app,users,flight):
    c=sign_in(app,users[0]); b=book(c,flight); pay(c,b['BookingID']); tid=c.get(f"/api/bookings/{b['BookingID']}").json['tickets'][0]['TicketID']
    r=send(c,f'/api/tickets/{tid}/cancel',dict(RefundMethod='CREDIT')); assert r.status_code==200,r.json
    assert Decimal(c.get('/api/wallet').json['balance'])==880000
    assert send(c,f'/api/tickets/{tid}/cancel',dict(RefundMethod='CREDIT')).json==r.json
    assert send(c,f'/api/tickets/{tid}/cancel',dict(RefundMethod='MOCK')).status_code==409
    query('EXEC dbo.sp_SaveFare ?,?,?,?',(flight['FlightID'],flight['FareClassID'],500000,.1))
    bs=[book(c,flight,1),book(c,flight,2)]; clients=[sign_in(app,users[0]),sign_in(app,users[0])]; barrier=Barrier(2)
    def purchase(i): barrier.wait(); return send(clients[i],f"/api/bookings/{bs[i]['BookingID']}/payments",dict(Success=True,Method='CREDIT',IdempotencyKey=uuid.uuid4().hex))
    with ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(purchase,range(2)))
    assert sorted(r.status_code for r in results)==[200,409]
    assert Decimal(c.get('/api/wallet').json['balance'])==330000

def test_loyalty_redemption_reservation_release(app,users,flight):
    c=sign_in(app,users[0]); first=book(c,flight); pay(c,first['BookingID']); second=book(c,flight,1); bid=second['BookingID']
    assert c.get('/api/loyalty').json['summary']['AvailablePoints']==110
    r=send(c,f'/api/bookings/{bid}/options',dict(Extras=[],Points=100),method='PUT'); assert r.status_code==200,r.json
    assert Decimal(r.json['price']['TotalAmount'])==1000000
    assert c.get('/api/loyalty').json['summary']['AvailablePoints']==10
    assert send(c,f'/api/bookings/{bid}/options',dict(Extras=[],Points=111),method='PUT').status_code==409
    assert c.get('/api/loyalty').json['summary']['AvailablePoints']==10
    assert send(c,f'/api/bookings/{bid}/cancel').status_code==200
    assert c.get('/api/loyalty').json['summary']['AvailablePoints']==110

def test_exchange_cheaper_fare_refunds_difference(app,users,flight):
    c=sign_in(app,users[0]); b=book(c,flight); pay(c,b['BookingID']); sid=c.get(f"/api/itineraries/{b['BookingID']}").json['segments'][0]['BookingSegmentID']; fid=new_flight(flight)
    query('EXEC dbo.sp_SaveFare ?,?,?,?',(fid,flight['FareClassID'],500000,.1))
    choice=dict(FlightID=fid,FareClassID=flight['FareClassID']); q=send(c,f'/api/segments/{sid}/exchange-quote',choice); assert Decimal(q.json['Difference'])==-350000
    r=send(c,f'/api/segments/{sid}/exchange',{**choice,'IdempotencyKey':uuid.uuid4().hex,'ExpectedDifference':q.json['Difference']}); assert r.status_code==200,r.json
    assert query('SELECT Kind,Amount FROM dbo.Payments WHERE PaymentID=?',(r.json['change']['PaymentID'],),one=True)==dict(Kind='REFUND',Amount=Decimal('350000.00'))
