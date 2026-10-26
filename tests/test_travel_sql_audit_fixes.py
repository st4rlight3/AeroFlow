"""Real SQL Server regressions for the service cutoff and provider ownership rules."""
from datetime import timedelta
import time
import uuid

import pyodbc
import pytest

from app.db import connection, query
from tests.conftest import send, sign_in


@pytest.fixture
def timed_service(sql_ready):
    """Each call creates independent, future PERSON inventory in the isolated test DB."""
    def make(seconds=120):
        dest = query('SELECT TOP(1) DestinationID,TimeZoneName FROM dbo.TravelDestinations ORDER BY DestinationID', one=True)
        provider = query("SELECT TOP(1) ProviderID FROM dbo.TravelProviders WHERE Status='ACTIVE' ORDER BY ProviderID", one=True)
        assert dest and provider, 'Seed the travel catalogue before running the integration suite.'
        product = query("SET NOCOUNT ON; INSERT dbo.TravelProducts(CategoryCode,DestinationID,ProviderID,Slug,Title,Summary,Description,Address,Latitude,Longitude,IsPublished) VALUES('activities',?,?,?,N'Trải nghiệm kiểm thử thời hạn',N'Kiểm thử riêng',N'Dữ liệu kiểm thử riêng',N'Điểm hẹn kiểm thử',0,0,1); SELECT CONVERT(int,SCOPE_IDENTITY()) ID;",
                        (dest['DestinationID'], provider['ProviderID'], 'test-cutoff-' + uuid.uuid4().hex), one=True)['ID']
        package = query("SET NOCOUNT ON; INSERT dbo.TravelPackages(ProductID,Name,Description,UnitCode,UnitLabel,MaxGuests,RefundPercent,CancelCutoffHours) VALUES(?,N'Gói thử thời hạn',N'Độc lập với dữ liệu trình diễn','PERSON',N'người',1,100,0); SELECT CONVERT(int,SCOPE_IDENTITY()) ID;", (product,), one=True)['ID']
        start = query('SELECT DATEADD(second,?,CONVERT(datetime2(0),SYSUTCDATETIME())) StartsAt', (seconds,), one=True)['StartsAt']
        service_date = query("SELECT CONVERT(date,(CAST(? AS datetime2) AT TIME ZONE 'UTC') AT TIME ZONE ?) ServiceDate", (start, dest['TimeZoneName']), one=True)['ServiceDate']
        inventory = query("SET NOCOUNT ON; INSERT dbo.TravelInventory(PackageID,ServiceDate,SlotCode,StartsAt,EndsAt,Capacity,UnitPrice) VALUES(?,?,'CUT_OFF',?,?,2,1000000); SELECT CONVERT(int,SCOPE_IDENTITY()) ID;",
                          (package, service_date, start, start + timedelta(hours=1)), one=True)['ID']
        return dict(ProductID=product, PackageID=package, InventoryID=inventory, ServiceStartsAt=start,
                    StartDate=str(service_date), EndDate=str(service_date), SlotCode='CUT_OFF', Quantity=1, GuestCount=1)
    return make


def hold(client, service):
    selection = {k: service[k] for k in ('PackageID', 'StartDate', 'EndDate', 'SlotCode', 'Quantity', 'GuestCount')}
    result = send(client, '/api/travel/bookings', dict(selection, ContactName='Khách kiểm thử', ContactEmail='cutoff@example.test',
                  ContactPhone='0901234567', ExpectedTotal='1000000', IdempotencyKey=uuid.uuid4().hex))
    assert result.status_code == 201, result.get_json()
    return result.get_json()['booking']


def payment(client, booking, key):
    return send(client, f'/api/travel/bookings/{booking["BookingID"]}/payments',
                dict(Success=True, ExpectedAmount=booking['Total'], IdempotencyKey=key))


def wait_until_started(start):
    # SQL's clock is authoritative. Tests wait at most 15 seconds, never minutes.
    for _ in range(60):
        if query('SELECT CASE WHEN SYSUTCDATETIME()>=CAST(? AS datetime2) THEN 1 ELSE 0 END Started', (start,), one=True)['Started']:
            return
        time.sleep(.25)
    pytest.fail('The short test service did not reach its SQL Server start time.')


def test_near_start_hold_deadline_is_service_start(app, users, timed_service):
    client = sign_in(app, users[0])
    booking = hold(client, timed_service())
    row = query('SELECT CreatedAt,ExpiresAt,ServiceStartsAt FROM dbo.TravelBookings WHERE BookingID=?', (booking['BookingID'],), one=True)
    assert row['ExpiresAt'] == row['ServiceStartsAt']
    assert row['CreatedAt'] < row['ExpiresAt'] <= row['CreatedAt'] + timedelta(minutes=10)
    with pytest.raises(pyodbc.Error, match='CK_TravelBooking_ServiceHold'):
        query('UPDATE dbo.TravelBookings SET ExpiresAt=DATEADD(second,1,ServiceStartsAt) WHERE BookingID=?', (booking['BookingID'],))
    assert query('SELECT ExpiresAt FROM dbo.TravelBookings WHERE BookingID=?', (booking['BookingID'],), one=True)['ExpiresAt'] == row['ServiceStartsAt']


def test_payment_at_or_after_service_start_has_no_side_effects(app, users, timed_service):
    client = sign_in(app, users[0])
    service = timed_service(seconds=7)
    booking = hold(client, service)
    wait_until_started(service['ServiceStartsAt'])
    result = payment(client, booking, uuid.uuid4().hex)
    assert result.status_code == 409, result.get_json()
    assert query('SELECT COUNT(*) N FROM dbo.TravelPayments WHERE BookingID=?', (booking['BookingID'],), one=True)['N'] == 0
    assert query('SELECT COUNT(*) N FROM dbo.TravelVouchers WHERE BookingID=?', (booking['BookingID'],), one=True)['N'] == 0
    assert client.get(f'/api/travel/bookings/{booking["BookingID"]}').get_json()['booking']['Status'] == 'EXPIRED'


def test_successful_payment_replay_still_works_after_service_start(app, users, timed_service):
    client = sign_in(app, users[0])
    service = timed_service(seconds=8)
    booking = hold(client, service)
    key = uuid.uuid4().hex
    first = payment(client, booking, key)
    assert first.status_code == 200, first.get_json()
    wait_until_started(service['ServiceStartsAt'])
    replay = payment(client, booking, key)
    assert replay.status_code == 200, replay.get_json()
    assert replay.get_json()['payment']['PaymentID'] == first.get_json()['payment']['PaymentID']
    assert payment(client, booking, uuid.uuid4().hex).status_code == 409
    assert query("SELECT COUNT(*) N FROM dbo.TravelPayments WHERE BookingID=? AND Kind='CHARGE' AND Status='SUCCESS'", (booking['BookingID'],), one=True)['N'] == 1
    assert query('SELECT COUNT(*) N FROM dbo.TravelVouchers WHERE BookingID=?', (booking['BookingID'],), one=True)['N'] == 1


def test_direct_confirmation_after_service_start_rolls_back_charge(app, users, timed_service):
    client = sign_in(app, users[0])
    service = timed_service(seconds=7)
    booking = hold(client, service)
    wait_until_started(service['ServiceStartsAt'])
    with pytest.raises(pyodbc.Error, match='52010'):
        with connection() as conn:
            conn.execute("INSERT dbo.TravelPayments(BookingID,Kind,Status,Amount,IdempotencyKey) VALUES(?,'CHARGE','SUCCESS',1000000,?)", booking['BookingID'], uuid.uuid4().hex)
            conn.execute("UPDATE dbo.TravelBookings SET Status='CONFIRMED' WHERE BookingID=?", booking['BookingID'])
    assert query('SELECT Status FROM dbo.TravelBookings WHERE BookingID=?', (booking['BookingID'],), one=True)['Status'] == 'HELD'
    assert query('SELECT COUNT(*) N FROM dbo.TravelPayments WHERE BookingID=?', (booking['BookingID'],), one=True)['N'] == 0


def test_provider_owner_is_unique_while_system_providers_can_have_null_owner(users):
    owner = users[0]['UserID']
    first = query("SET NOCOUNT ON; INSERT dbo.TravelProviders(OwnerUserID,Name,Status,IsDemo) VALUES(?,N'Hồ sơ kiểm thử duy nhất','PENDING',0); SELECT CONVERT(int,SCOPE_IDENTITY()) ID;", (owner,), one=True)['ID']
    with pytest.raises(pyodbc.Error, match='UX_TravelProvider_Owner'):
        query("INSERT dbo.TravelProviders(OwnerUserID,Name,Status,IsDemo) VALUES(?,N'Hồ sơ kiểm thử trùng','PENDING',0)", (owner,))
    rows = query('SELECT ProviderID FROM dbo.TravelProviders WHERE OwnerUserID=?', (owner,))
    assert rows == [{'ProviderID': first}]
    token = uuid.uuid4().hex
    for suffix in ('A', 'B'):
        query("INSERT dbo.TravelProviders(OwnerUserID,Name,Status,IsDemo) VALUES(NULL,?,'ACTIVE',1)", ('System test ' + token + suffix,))
    assert query('SELECT COUNT(*) N FROM dbo.TravelProviders WHERE OwnerUserID IS NULL AND Name LIKE ?', ('System test ' + token + '%',), one=True)['N'] == 2
