import uuid
import pytest
from app.db import query
from conftest import send,sign_in,book,pay
from scripts.send_notifications import deliver


@pytest.mark.integration
def test_payment_quote_guard_receipt_and_owner(app,users,flight):
    c=sign_in(app,users[0]); other=sign_in(app,users[1]); b=book(c,flight); bid=b['BookingID']
    payload=dict(Success=True,IdempotencyKey=uuid.uuid4().hex,ExpectedAmount=1)
    assert send(c,f'/api/bookings/{bid}/payments',payload).status_code==409
    assert query('SELECT COUNT(*) N FROM dbo.Payments WHERE BookingID=?',(bid,),one=True)['N']==0
    payload['ExpectedAmount']=1100000
    r=send(c,f'/api/bookings/{bid}/payments',payload); assert r.status_code==200,r.json
    pid=r.json['payment']['PaymentID']
    assert other.get(f'/api/payments/{pid}/receipt').status_code==404
    receipt=c.get(f'/api/payments/{pid}/receipt'); assert receipt.status_code==200 and receipt.data.startswith(b'%PDF-')


@pytest.mark.integration
def test_boarding_reference_permission_state_and_replay(app,users,flight):
    c=sign_in(app,users[0]); admin=sign_in(app,users[2]); b=book(c,flight); assert pay(c,b['BookingID']).status_code==200
    tid=c.get(f"/api/bookings/{b['BookingID']}").json['tickets'][0]['TicketID']
    query('UPDATE dbo.Flights SET DepartureTime=DATEADD(hour,10,SYSUTCDATETIME()),ArrivalTime=DATEADD(hour,12,SYSUTCDATETIME()) WHERE FlightID=?',(flight['FlightID'],))
    checked=send(c,f'/api/tickets/{tid}/check-in').json['checkin']; cid=checked['CheckInID']
    assert send(c,'/api/admin/check-ins/verify',dict(Reference=checked['Reference'])).status_code==403
    assert send(admin,'/api/admin/check-ins/verify',dict(Reference='bad')).status_code==400
    assert send(admin,'/api/admin/check-ins/verify',dict(Reference='AEROFLOW-DEMO:'+checked['Reference'])).json['checkin']['TicketStatus']=='VALID'
    assert send(admin,f'/api/admin/check-ins/{cid}/board').status_code==409
    assert send(admin,f"/api/admin/flights/{flight['FlightID']}/status",dict(Status='BOARDING'),method='PUT').status_code==200
    first=send(admin,f'/api/admin/check-ins/{cid}/board'); assert first.status_code==200,first.json
    assert send(admin,f'/api/admin/check-ins/{cid}/board').json==first.json
    assert query("SELECT COUNT(*) N FROM dbo.AuditLogs WHERE Entity='CheckIns' AND EntityID=? AND Action='BOARDED'",(cid,),one=True)['N']==1


@pytest.mark.integration
def test_operations_catalogs_reports_and_permissions(app,users):
    c=sign_in(app,users[0]); admin=sign_in(app,users[2])
    for path in ('/admin/passengers','/admin/loyalty','/admin/catalog/routes','/admin/catalog/loyalty-tiers','/admin/catalog/services','/admin/reports/revenue.pdf'):
        assert c.get('/api'+path).status_code==403
        r=admin.get('/api'+path); assert r.status_code==200,(path,r.json)
        if path.endswith('.pdf'): assert r.data.startswith(b'%PDF-')
    assert admin.get('/api/admin/reports/revenue.pdf?from=2020-01-01&to=2026-01-01').status_code==400
    tier=next(x for x in admin.get('/api/admin/catalog/loyalty-tiers').json['items'] if x['MinimumPoints']==0)
    assert send(admin,f"/api/admin/catalog/loyalty-tiers/{tier['LoyaltyTierID']}",{**tier,'MinimumPoints':1},method='PUT').status_code==400


def test_email_message_unicode_demo_marker_and_stable_id():
    class Mailbox:
        def send_message(self,message): self.message=message
    box=Mailbox();deliver(box,(123,'customer@example.invalid','Thay đổi chuyến bay','Cửa lên máy bay A12'),'demo@example.invalid')
    assert box.message['Message-ID']=='<aeroflow-notification-123@aeroflow.local>'
    assert box.message['To']=='customer@example.invalid'
    assert 'A12' in box.message.get_content() and 'mô phỏng' in box.message.get_content()
