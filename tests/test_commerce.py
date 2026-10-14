from decimal import Decimal
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import uuid
import pytest
from app.db import query
from conftest import send,sign_in,book,pay,booking_data

pytestmark=pytest.mark.integration

def test_services_discount_partial_then_full_refund(app,users,flight):
    c=sign_in(app,users[0]); other=sign_in(app,users[1]); data=booking_data(flight); data['Passengers']+=booking_data(flight,1)['Passengers']
    r=send(c,'/api/bookings',data); assert r.status_code==201; bid=r.json['booking']['BookingID']
    ts=c.get(f'/api/bookings/{bid}').json['tickets']; svc=next(s for s in c.get('/api/services').json['items'] if s['Code']=='BAG10')
    payload=dict(Extras=[dict(TicketID=t['TicketID'],ServiceID=svc['ServiceID'],Quantity=1) for t in ts],Code='ULTIMATE10')
    assert send(other,f'/api/bookings/{bid}/options',payload,method='PUT').status_code==404
    price=send(c,f'/api/bookings/{bid}/options',payload,method='PUT'); assert price.status_code==200,price.json
    assert Decimal(price.json['price']['TotalAmount'])==2500000
    # Invalid replacement must rollback, preserving all prior snapshots.
    bad=send(c,f'/api/bookings/{bid}/options',dict(Extras=[],Code='NO-SUCH-CODE'),method='PUT'); assert bad.status_code==409
    assert len(c.get(f'/api/bookings/{bid}/options').json['extras'])==2
    payment=pay(c,bid); assert Decimal(payment.json['payment']['Amount'])==2500000
    ticket=c.get(f"/api/tickets/{ts[0]['TicketID']}").json['ticket']
    assert Decimal(ticket['PaidValue'])==1250000
    assert Decimal(ticket['ExtrasAmount'])==250000 and Decimal(ticket['DiscountAmount'])==100000
    assert c.get(f"/api/tickets/{ts[0]['TicketID']}/pdf").data.startswith(b'%PDF-')
    assert send(c,f'/api/bookings/{bid}/options',payload,method='PUT').status_code==409
    tid=ts[0]['TicketID']; result=send(c,f'/api/tickets/{tid}/cancel'); assert result.status_code==200,result.json
    assert Decimal(result.json['refund']['Amount'])==1000000
    assert send(c,f'/api/tickets/{tid}/cancel').json==result.json
    assert c.get(f'/api/bookings/{bid}').json['booking']['Status']=='CONFIRMED'
    assert send(c,f'/api/bookings/{bid}/cancel').status_code==200
    refunds=query("SELECT Amount FROM dbo.Payments WHERE BookingID=? AND Kind='REFUND'",(bid,))
    assert len(refunds)==2 and sum(x['Amount'] for x in refunds)==2000000
    assert query('SELECT SUM(Amount) A FROM dbo.TicketDiscounts WHERE TicketID IN (?,?)',(ts[0]['TicketID'],ts[1]['TicketID']),one=True)['A']==200000

def test_airline_refund_includes_services_minus_discount(app,users,flight):
    c=sign_in(app,users[0]); admin=sign_in(app,users[2]); b=book(c,flight); bid=b['BookingID']; tid=c.get(f'/api/bookings/{bid}').json['tickets'][0]['TicketID']; svc=c.get('/api/services').json['items'][0]
    price=send(c,f'/api/bookings/{bid}/options',dict(Extras=[dict(TicketID=tid,ServiceID=svc['ServiceID'],Quantity=1)],Code='DEMO100K'),method='PUT')
    assert price.status_code==200,price.json; assert pay(c,bid).status_code==200
    assert send(admin,f"/api/admin/flights/{flight['FlightID']}/status",{'Status':'CANCELLED'},method='PUT').status_code==200
    refund=query("SELECT Amount FROM dbo.Payments WHERE BookingID=? AND Kind='REFUND'",(bid,),one=True)
    assert refund['Amount']==Decimal(price.json['price']['TotalAmount'])

def test_last_promo_use_is_concurrent_safe(app,users,flight):
    code='T'+uuid.uuid4().hex[:18]
    query("INSERT dbo.DiscountCodes(Code,Kind,Method,Value,MaxDiscount,MinimumSpend,ValidFrom,ValidTo,MaxUses) VALUES(?,'PROMO','FIXED',100000,100000,0,DATEADD(day,-1,SYSUTCDATETIME()),DATEADD(day,1,SYSUTCDATETIME()),1)",(code,))
    clients=[sign_in(app,users[0]),sign_in(app,users[1])]; bookings=[book(clients[0],flight,0),book(clients[1],flight,1)]; barrier=Barrier(2)
    def call(i): barrier.wait(); return send(clients[i],f"/api/bookings/{bookings[i]['BookingID']}/options",dict(Extras=[],Code=code),method='PUT')
    with ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(call,range(2)))
    assert sorted(r.status_code for r in results)==[200,409]
    assert query('SELECT COUNT(*) N FROM dbo.BookingDiscounts WHERE Code=?',(code,),one=True)['N']==1

def test_no_partial_cancellation_inside_cutoff(app,users,flight):
    c=sign_in(app,users[0]); b=book(c,flight); pay(c,b['BookingID']); tid=c.get(f"/api/bookings/{b['BookingID']}").json['tickets'][0]['TicketID']
    query('UPDATE dbo.Flights SET DepartureTime=DATEADD(hour,23,SYSUTCDATETIME()),ArrivalTime=DATEADD(hour,25,SYSUTCDATETIME()) WHERE FlightID=?',(flight['FlightID'],))
    assert send(c,f'/api/tickets/{tid}/cancel').status_code==409
    assert c.get(f'/api/tickets/{tid}').json['ticket']['TicketStatus']=='VALID'

def test_service_validation_and_admin_codes(app,users,flight):
    c=sign_in(app,users[0]); admin=sign_in(app,users[2]); b=book(c,flight); tid=c.get(f"/api/bookings/{b['BookingID']}").json['tickets'][0]['TicketID']; services=c.get('/api/services').json['items']
    meals=[dict(TicketID=tid,ServiceID=s['ServiceID'],Quantity=1) for s in services if s['Category']=='MEAL']
    assert send(c,f"/api/bookings/{b['BookingID']}/options",dict(Extras=meals),method='PUT').status_code==400
    assert c.get('/api/admin/discount-codes').status_code==403
    assert admin.get('/api/admin/discount-codes').status_code==200

def test_seat_fee_is_snapshot_and_layout_stays_locked(app,users,flight):
    import pyodbc
    c=sign_in(app,users[0]); seat=flight['Seats'][0]['SeatID']
    query('UPDATE dbo.AircraftSeats SET SeatFee=90000,IsPriority=1 WHERE SeatID=?',(seat,))
    payload=dict(JourneyType='ONE_WAY',Segments=[dict(FlightID=flight['FlightID'],FareClassID=flight['FareClassID'],JourneyGroup=1)],Passengers=[dict(FullName='Khách phí ghế',DateOfBirth='1995-01-01',DocumentNumber='DEMO-FEE',TypeCode='ADULT')],Selections=[dict(PassengerIndex=0,SegmentIndex=0,SeatID=seat)])
    q=send(c,'/api/itineraries/quote',payload); assert Decimal(q.json['Total'])==1190000
    b=send(c,'/api/itineraries',{**payload,'ExpectedTotal':q.json['Total']}); assert b.status_code==201,b.json
    query('UPDATE dbo.AircraftSeats SET SeatFee=150000 WHERE SeatID=?',(seat,))
    assert Decimal(c.get(f"/api/bookings/{b.json['booking']['BookingID']}").json['booking']['TotalAmount'])==1190000
    with pytest.raises(pyodbc.Error): query("UPDATE dbo.AircraftSeats SET Cabin='FIRST' WHERE SeatID=?",(seat,))
