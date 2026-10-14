import hashlib
import uuid
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import pytest
from app.db import query
from conftest import send,sign_in,book,pay
from scripts.issue_reset_token import issue

pytestmark=pytest.mark.integration

def test_saved_travellers_and_preferences(app,users):
    c=sign_in(app,users[0]); other=sign_in(app,users[1]); d=dict(FullName='Nguyễn Lưu Thử',DateOfBirth='1990-01-02',DocumentNumber='DEMO-'+uuid.uuid4().hex[:10],Assistance='WHEELCHAIR')
    r=send(c,'/api/travellers',d); assert r.status_code==201; tid=r.json['id']
    assert c.get('/api/travellers').json['items'][0]['Assistance']=='WHEELCHAIR'
    assert send(other,f'/api/travellers/{tid}',d,method='PUT').status_code==404
    assert send(other,f'/api/travellers/{tid}',method='DELETE').status_code==404
    assert send(c,'/api/travellers',d).status_code==409
    assert send(c,'/api/preferences',dict(PreferredCabin='PREMIUM',SeatPreference='AISLE',Reminders=False),method='PUT').status_code==200
    assert c.get('/api/preferences').json['preferences']['PreferredCabin']=='PREMIUM'
    assert send(c,f'/api/travellers/{tid}',method='DELETE').status_code==200

def test_password_change_revokes_all_sessions(app,users):
    c=sign_in(app,users[0]); second=sign_in(app,users[0]); new='New-'+uuid.uuid4().hex
    assert send(c,'/api/auth/change-password',dict(CurrentPassword='wrong',NewPassword=new)).status_code==401
    assert send(c,'/api/auth/change-password',dict(CurrentPassword=users[0]['Password'],NewPassword=new)).status_code==200
    assert c.get('/api/me').status_code==401 and second.get('/api/me').status_code==401
    assert send(c,'/api/auth/login',dict(Email=users[0]['Email'],Password=new)).status_code==200

def test_reset_token_single_use_expiry_and_replacement(app,users):
    c=app.test_client(); old=issue(users[0]['Email']); token=issue(users[0]['Email']); new='Reset-'+uuid.uuid4().hex
    assert send(c,'/api/auth/reset-password',dict(Token=old,NewPassword=new)).status_code==400
    hashed=hashlib.sha256(token.encode()).hexdigest()
    assert query('SELECT TokenHash FROM dbo.PasswordResetTokens WHERE TokenHash=?',(hashed,),one=True)
    assert send(c,'/api/auth/reset-password',dict(Token=token,NewPassword=new)).status_code==200
    assert send(c,'/api/auth/reset-password',dict(Token=token,NewPassword=new)).status_code==400
    expired=issue(users[0]['Email']); query('UPDATE dbo.PasswordResetTokens SET ExpiresAt=DATEADD(second,-1,SYSUTCDATETIME()) WHERE TokenHash=?',(hashlib.sha256(expired.encode()).hexdigest(),))
    assert send(c,'/api/auth/reset-password',dict(Token=expired,NewPassword=new)).status_code==400

def test_checkin_pdf_revocation_notifications_and_loyalty(app,users,flight):
    c=sign_in(app,users[0]); other=sign_in(app,users[1]); admin=sign_in(app,users[2]); b=book(c,flight); bid=b['BookingID']; ticket=c.get(f'/api/bookings/{bid}').json['tickets'][0]['TicketID']
    assert c.get(f'/api/tickets/{ticket}/pdf').status_code==409
    key=uuid.uuid4().hex; assert pay(c,bid,key=key).status_code==200; assert pay(c,bid,key=key).status_code==200
    assert c.get('/api/loyalty').json['summary']['Points']==110
    assert other.get(f'/api/tickets/{ticket}/pdf').status_code==404
    assert send(c,f'/api/tickets/{ticket}/check-in').status_code==409
    query('UPDATE dbo.Flights SET DepartureTime=DATEADD(hour,12,SYSUTCDATETIME()),ArrivalTime=DATEADD(hour,14,SYSUTCDATETIME()) WHERE FlightID=?',(flight['FlightID'],))
    assert c.get(f'/api/tickets/{ticket}').json['ticket']['Eligible']==1
    r=send(c,f'/api/tickets/{ticket}/check-in'); assert r.status_code==200,r.json
    assert send(c,f'/api/tickets/{ticket}/check-in').json['checkin']['Reference']==r.json['checkin']['Reference']
    pdf=c.get(f'/api/tickets/{ticket}/pdf?type=boarding'); assert pdf.status_code==200 and pdf.data.startswith(b'%PDF-')
    assert 'attachment' in pdf.headers['Content-Disposition']
    assert c.get(f'/api/tickets/{ticket}/pdf').status_code==200
    assert send(c,'/api/admin/reminders').status_code==403
    first=send(admin,'/api/admin/reminders'); assert first.status_code==200
    assert send(admin,'/api/admin/reminders').json['result']['Created']==0
    assert send(admin,f"/api/admin/flights/{flight['FlightID']}/operations",dict(Gate='A12',OperationNote='Thử thông báo'),method='PUT').status_code==200
    notices=c.get('/api/notifications').json['items']; assert any('A12' in n['Message'] for n in notices)
    nid=notices[0]['NotificationID']; assert send(other,f'/api/notifications/{nid}/read',method='PUT').status_code==404
    assert send(c,f'/api/notifications/{nid}/read',method='PUT').status_code==200
    assert c.get('/api/bookings/lookup?pnr='+b['PNR']).json['booking']['BookingID']==bid
    assert other.get('/api/bookings/lookup?pnr='+b['PNR']).status_code==404
    assert send(admin,f"/api/admin/flights/{flight['FlightID']}/status",{'Status':'CANCELLED'},method='PUT').status_code==200
    assert c.get(f'/api/tickets/{ticket}').json['ticket']['CheckInStatus']=='REVOKED'
    assert c.get(f'/api/tickets/{ticket}/pdf?type=boarding').status_code==409
    assert c.get('/api/loyalty').json['summary']['Points']==0

def test_concurrent_checkin_has_one_reference(app,users,flight):
    c=sign_in(app,users[0]); b=book(c,flight); assert pay(c,b['BookingID']).status_code==200
    tid=c.get(f"/api/bookings/{b['BookingID']}").json['tickets'][0]['TicketID']
    query('UPDATE dbo.Flights SET DepartureTime=DATEADD(hour,10,SYSUTCDATETIME()),ArrivalTime=DATEADD(hour,12,SYSUTCDATETIME()) WHERE FlightID=?',(flight['FlightID'],))
    clients=[sign_in(app,users[0]),sign_in(app,users[0])]; barrier=Barrier(2)
    def call(client): barrier.wait(); return send(client,f'/api/tickets/{tid}/check-in')
    with ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(call,clients))
    assert [r.status_code for r in results]==[200,200]
    assert results[0].json['checkin']['Reference']==results[1].json['checkin']['Reference']
    assert query('SELECT COUNT(*) N FROM dbo.CheckIns WHERE TicketID=?',(tid,),one=True)['N']==1
    query('UPDATE dbo.Flights SET DepartureTime=DATEADD(minute,59,SYSUTCDATETIME()),ArrivalTime=DATEADD(hour,3,SYSUTCDATETIME()) WHERE FlightID=?',(flight['FlightID'],))
    assert send(c,f'/api/tickets/{tid}/check-in').status_code==409

def test_price_snapshot_cannot_be_edited(app,users,flight):
    import pyodbc
    c=sign_in(app,users[0]); b=book(c,flight); tid=c.get(f"/api/bookings/{b['BookingID']}").json['tickets'][0]['TicketID']
    with pytest.raises(pyodbc.Error): query('UPDATE dbo.Tickets SET SeatFee=100000 WHERE TicketID=?',(tid,))
