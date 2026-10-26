"""Actual SQL Server integration and simultaneous capacity tests; no stock/price mocks."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime,timedelta,timezone
from decimal import Decimal
from threading import Barrier
import uuid
import pyodbc
import pytest
from app.db import query
from tests.conftest import send,sign_in

@pytest.fixture
def travel_item(sql_ready):
    token=uuid.uuid4().hex
    dest=query('SELECT TOP(1) DestinationID FROM dbo.TravelDestinations ORDER BY DestinationID',one=True)
    assert dest,'Run scripts/seed_travel.py --apply before the marketplace suite.'
    provider=query('SELECT TOP(1) ProviderID FROM dbo.TravelProviders WHERE Status=\'ACTIVE\'',one=True)['ProviderID']
    p=query('SET NOCOUNT ON; INSERT dbo.TravelProducts(CategoryCode,DestinationID,ProviderID,Slug,Title,Summary,Description,Address,Latitude,Longitude,IsPublished) VALUES(\'hotels\',?,?,?,N\'Khách sạn kiểm thử\',N\'Kiểm thử\',N\'Dữ liệu kiểm thử riêng\',N\'Địa chỉ kiểm thử\',0,0,1); SELECT CONVERT(int,SCOPE_IDENTITY()) ID;',
      (dest['DestinationID'],provider,'test-'+token),one=True)['ID']
    pk=query('SET NOCOUNT ON; INSERT dbo.TravelPackages(ProductID,Name,Description,UnitCode,UnitLabel,MaxGuests,RefundPercent,CancelCutoffHours,ChangeAllowed,ChangeFee) VALUES(?,N\'Gói kiểm thử\',N\'Hoàn trước 24 giờ\',\'NIGHT\',N\'phòng / đêm\',2,100,24,0,0); SELECT CONVERT(int,SCOPE_IDENTITY()) ID;',(p,),one=True)['ID']
    day=(datetime.now(timezone.utc)+timedelta(days=20)).date()
    ids=[]
    for n in range(3):
        start=datetime.combine(day+timedelta(days=n),datetime.min.time())+timedelta(hours=7)
        ids.append(query('SET NOCOUNT ON; INSERT dbo.TravelInventory(PackageID,ServiceDate,SlotCode,StartsAt,EndsAt,Capacity,UnitPrice) VALUES(?,?,\'DEFAULT\',?,?,1,?); SELECT CONVERT(int,SCOPE_IDENTITY()) ID;',
          (pk,day+timedelta(days=n),start,start+timedelta(hours=22),1000000+n*100000),one=True)['ID'])
    return dict(ProductID=p,PackageID=pk,StartDate=str(day),EndDate=str(day+timedelta(days=1)),SlotCode='DEFAULT',Quantity=1,GuestCount=2,InventoryIDs=ids)

def selection(t,**extra):return {k:v for k,v in {**t,**extra}.items() if k!='InventoryIDs' and k!='ProductID'}
def payload(t,**extra):return dict(selection(t),ContactName='Khách thử',ContactEmail='demo@example.test',ContactPhone='0901234567',Notes='',ExpectedTotal='1000000',IdempotencyKey=uuid.uuid4().hex,**extra)
def reserve(c,t,**extra):
    r=send(c,'/api/travel/bookings',payload(t,**extra));assert r.status_code==201,r.get_json();return r.get_json()['booking']
def pay(c,b,success=True,key=None):return send(c,f'/api/travel/bookings/{b["BookingID"]}/payments',dict(Success=success,IdempotencyKey=key or uuid.uuid4().hex,ExpectedAmount=b['Total']))

def test_catalogue_and_filters(client,sql_ready):
    assert len(client.get('/api/travel/categories').get_json()['items'])==12
    r=client.get('/api/travel/products?Category=hotels&Sort=price').get_json()
    assert r['total']>=11
    prices=[Decimal(x['FromPrice']) for x in r['items'] if x['FromPrice'] is not None]
    assert prices==sorted(prices)
    assert client.get('/api/travel/products?MaxPrice=1').get_json()['total']==0
    assert client.get('/api/travel/products?Sort=Price;DROP').status_code==400
    assert client.get('/api/travel/products?Sort=new').status_code==200

def test_quote_sums_every_night(client,travel_item):
    d=selection(travel_item,EndDate=str(datetime.fromisoformat(travel_item['StartDate']).date()+timedelta(days=2)))
    q=send(client,'/api/travel/quotes',d);assert q.status_code==200,q.get_json()
    assert Decimal(str(q.get_json()['quote']['Total']))==2100000
    assert len(q.get_json()['quote']['Lines'])==2

def test_missing_night_is_unavailable(client,travel_item):
    query('UPDATE dbo.TravelInventory SET IsClosed=1 WHERE InventoryID=?',(travel_item['InventoryIDs'][1],))
    d=selection(travel_item,EndDate=str(datetime.fromisoformat(travel_item['StartDate']).date()+timedelta(days=2)))
    assert send(client,'/api/travel/quotes',d).status_code==409

def test_guest_and_date_validation(client,travel_item):
    assert send(client,'/api/travel/quotes',selection(travel_item,GuestCount=3)).status_code==400
    assert send(client,'/api/travel/quotes',selection(travel_item,EndDate=travel_item['StartDate'])).status_code==400
    assert send(client,'/api/travel/quotes',{}).status_code==400

def test_booking_and_idempotency(app,users,travel_item):
    c=sign_in(app,users[0]);d=payload(travel_item)
    a=send(c,'/api/travel/bookings',d);b=send(c,'/api/travel/bookings',d)
    assert a.status_code==b.status_code==201,(a.get_json(),b.get_json())
    assert a.get_json()['booking']['BookingID']==b.get_json()['booking']['BookingID']
    assert send(c,'/api/travel/bookings',{**d,'ContactName':'Người khác'}).status_code==409

def test_simultaneous_last_room(app,users,travel_item):
    clients=[sign_in(app,u) for u in users[:2]]
    # Get CSRF before the barrier, so both stock requests start together.
    tokens=[c.get('/api/csrf').get_json()['token'] for c in clients];barrier=Barrier(2)
    def run(i):
        barrier.wait();r=clients[i].post('/api/travel/bookings',json=payload(travel_item),headers={'X-CSRF-Token':tokens[i]});return r.status_code
    with ThreadPoolExecutor(max_workers=2) as pool:statuses=list(pool.map(run,range(2)))
    assert sorted(statuses)==[201,409]
    assert query('SELECT AvailableQuantity FROM dbo.vw_TravelAvailability WHERE InventoryID=?',(travel_item['InventoryIDs'][0],),one=True)['AvailableQuantity']==0

def test_payment_failure_retry_and_duplicate(app,users,travel_item):
    c=sign_in(app,users[0]);b=reserve(c,travel_item);key=uuid.uuid4().hex
    assert pay(c,b,False,key).status_code==200
    assert pay(c,b,False,key).status_code==200
    assert pay(c,b,True,key).status_code==409
    success=uuid.uuid4().hex
    assert pay(c,b,True,success).status_code==200
    assert pay(c,b,True,success).status_code==200
    assert pay(c,b,True).status_code==409
    rows=query('SELECT * FROM dbo.TravelPayments WHERE BookingID=?',(b['BookingID'],))
    assert len(rows)==2
    assert sum(x['Status']=='SUCCESS' for x in rows)==1
    qr=c.get(f'/api/travel/bookings/{b["BookingID"]}/qr')
    assert qr.status_code==200 and qr.mimetype=='image/svg+xml' and b'<svg' in qr.data

def test_price_change_rollback(app,users,travel_item):
    c=sign_in(app,users[0]);query('UPDATE dbo.TravelInventory SET UnitPrice=1200000 WHERE InventoryID=?',(travel_item['InventoryIDs'][0],))
    r=send(c,'/api/travel/bookings',payload(travel_item));assert r.status_code==409
    assert query('SELECT COUNT(*) N FROM dbo.TravelBookings WHERE ProductID=?',(travel_item['ProductID'],),one=True)['N']==0
    assert query('SELECT COUNT(*) N FROM dbo.TravelBookingItems WHERE PackageID=?',(travel_item['PackageID'],),one=True)['N']==0

def test_owner_authorization_and_csrf(app,users,travel_item):
    a,b=[sign_in(app,u) for u in users[:2]];booking=reserve(a,travel_item);bid=booking['BookingID']
    assert b.get(f'/api/travel/bookings/{bid}').status_code==404
    assert b.get(f'/api/travel/bookings/{bid}/qr').status_code==404
    assert pay(b,booking).status_code==404
    assert a.post('/api/travel/bookings',json=payload(travel_item)).status_code==403
    assert a.get('/api/admin/travel/products').status_code==403

def test_expired_hold_releases_stock(app,users,travel_item):
    a,b=[sign_in(app,u) for u in users[:2]];old=reserve(a,travel_item)
    query("UPDATE dbo.TravelBookings SET CreatedAt=DATEADD(minute,-30,SYSUTCDATETIME()),ExpiresAt=DATEADD(minute,-20,SYSUTCDATETIME()) WHERE BookingID=?",(old['BookingID'],))
    assert pay(a,old).status_code==409
    assert a.get(f'/api/travel/bookings/{old["BookingID"]}').get_json()['booking']['Status']=='EXPIRED'
    reserve(b,travel_item)
    assert query('SELECT Status FROM dbo.TravelBookings WHERE BookingID=?',(old['BookingID'],),one=True)['Status']=='EXPIRED'

def test_cancel_refund_and_snapshots(app,users,travel_item):
    c=sign_in(app,users[0]);b=reserve(c,travel_item);assert pay(c,b).status_code==200
    query('UPDATE dbo.TravelPackages SET RefundPercent=0 WHERE PackageID=?',(travel_item['PackageID'],))
    d={'IdempotencyKey':uuid.uuid4().hex};path=f'/api/travel/bookings/{b["BookingID"]}/cancel'
    assert send(c,path,d).status_code==200
    assert send(c,path,d).status_code==200
    assert query("SELECT Amount FROM dbo.TravelPayments WHERE BookingID=? AND Kind='REFUND'",(b['BookingID'],),one=True)['Amount']==1000000
    assert c.get(f'/api/travel/bookings/{b["BookingID"]}/qr').status_code==409
    assert query('SELECT AvailableQuantity FROM dbo.vw_TravelAvailability WHERE InventoryID=?',(travel_item['InventoryIDs'][0],),one=True)['AvailableQuantity']==1

def test_admin_capacity_protection_and_schedule_immutable(app,users,travel_item):
    c=sign_in(app,users[0]);b=reserve(c,travel_item);admin=sign_in(app,users[2]);iid=travel_item['InventoryIDs'][0]
    r=send(admin,'/api/admin/travel/inventory',dict(InventoryID=iid,Capacity=0,UnitPrice=1000000,IsClosed=False),'PATCH');assert r.status_code==409
    with pytest.raises(pyodbc.Error):query('UPDATE dbo.TravelInventory SET EndsAt=DATEADD(hour,1,EndsAt) WHERE InventoryID=?',(iid,))
    assert query('SELECT Capacity FROM dbo.TravelInventory WHERE InventoryID=?',(iid,),one=True)['Capacity']==1

def test_sql_injection_is_data(client,travel_item):
    r=client.get('/api/travel/products',query_string={'q':"'; DROP TABLE dbo.TravelProducts;--"})
    assert r.status_code==200 and r.get_json()['total']==0
    assert query('SELECT COUNT(*) N FROM dbo.TravelProducts',one=True)['N']>0

def test_review_requires_completed_booking(app,users,travel_item):
    c=sign_in(app,users[0]);b=reserve(c,travel_item);assert pay(c,b).status_code==200
    assert send(c,f'/api/travel/bookings/{b["BookingID"]}/review',dict(Rating=5,Title='Đánh giá thử',Comment='Không được đánh giá trước chuyến đi')).status_code==409

def test_wishlist_cart_and_ownership(app,users,travel_item):
    a,b=[sign_in(app,u) for u in users[:2]];pid=travel_item['ProductID']
    assert send(a,f'/api/travel/wishlist/{pid}',{},'PUT').status_code==200
    assert send(a,f'/api/travel/wishlist/{pid}',{},'PUT').status_code==200
    assert len(a.get('/api/travel/wishlist').get_json()['items'])==1
    assert b.get('/api/travel/wishlist').get_json()['items']==[]
    assert send(a,'/api/travel/cart',selection(travel_item)).status_code==201
    cart=a.get('/api/travel/cart').get_json()['items'][0];assert cart['ProductID']==pid
    assert send(b,'/api/travel/cart/'+str(cart['CartID']),{},'DELETE').status_code==200
    assert len(a.get('/api/travel/cart').get_json()['items'])==1

def test_trip_and_support_boundaries(app,users,travel_item):
    a,b=[sign_in(app,u) for u in users[:2]]
    r=send(a,'/api/travel/trips',dict(Name='Chuyến đi thử',StartDate='2026-12-01',EndDate='2026-12-03'));assert r.status_code==201
    tid=r.get_json()['trip']['TripID']
    assert b.get(f'/api/travel/trips/{tid}/stops').status_code==404
    assert send(a,f'/api/travel/trips/{tid}/stops',dict(Name='Đi dạo',VisitDate='2026-12-04',SortOrder=1,Notes='')).status_code==400
    assert send(a,f'/api/travel/trips/{tid}/stops',dict(Name='Đi dạo',VisitDate='2026-12-02',SortOrder=1,Notes='')).status_code==201
    r=send(a,'/api/travel/support',dict(Subject='Hỏi về dịch vụ',Message='Tôi muốn kiểm tra điều kiện.'));assert r.status_code==201
    assert b.get('/api/travel/support/'+str(r.get_json()['TicketID'])).status_code==404

def test_direct_sql_stock_overflow_rollback(app,users,travel_item):
    a,b=[sign_in(app,u) for u in users[:2]];first=reserve(a,travel_item)
    # No second API booking can reserve the last room; manual capacity edits are also guarded.
    with pytest.raises(pyodbc.Error):query('UPDATE dbo.TravelInventory SET Capacity=0 WHERE InventoryID=?',(travel_item['InventoryIDs'][0],))
    assert query('SELECT AvailableQuantity FROM dbo.vw_TravelAvailability WHERE InventoryID=?',(travel_item['InventoryIDs'][0],),one=True)['AvailableQuantity']==0

def test_inventory_id_foreign_package_fk(travel_item):
    with pytest.raises(pyodbc.Error):query('INSERT dbo.TravelBookingItems(BookingID,InventoryID,PackageID,Quantity,UnitPrice) VALUES(-1,?,?,1,100)',(travel_item['InventoryIDs'][0],travel_item['PackageID']))

def test_admin_overview_views(app,users,sql_ready):
    admin=sign_in(app,users[2]);r=admin.get('/api/admin/travel/overview');assert r.status_code==200,r.get_json()
    assert Decimal(r.get_json()['summary']['NetRevenue'])==query('SELECT COALESCE(SUM(NetRevenue),0) Total FROM dbo.vw_TravelRevenue',one=True)['Total']

def test_seed_is_non_destructive(sql_ready):
    from scripts.seed_travel import seed
    before=query('SELECT COUNT(*) N,COALESCE(SUM(Total),0) V FROM dbo.TravelBookings',one=True)
    # A clean test database may contain only a short seed window. Filling its
    # missing dates is valid; check preservation on both import and rerun.
    seed(datetime(2026,12,1).date(),62)
    assert query('SELECT COUNT(*) N,COALESCE(SUM(Total),0) V FROM dbo.TravelBookings',one=True)==before
    assert seed(datetime(2026,12,1).date(),62)==dict(destinations=0,products=0,packages=0,inventory=0)
    assert query('SELECT COUNT(*) N,COALESCE(SUM(Total),0) V FROM dbo.TravelBookings',one=True)==before

@pytest.mark.parametrize('category',['hotels','activities','tours','spa','esim','buses','transfers','cars','cruises','trains','visas','events'])
def test_each_service_can_quote_book_pay_and_download(app,users,category):
    c=sign_in(app,users[0])
    pk=query('SELECT TOP(1) k.PackageID,k.UnitCode FROM dbo.TravelPackages k JOIN dbo.TravelProducts p ON p.ProductID=k.ProductID WHERE p.CategoryCode=? AND p.Slug LIKE \'demo-%\' ORDER BY k.PackageID',(category,),one=True)
    d=dict(PackageID=pk['PackageID'],StartDate='2026-12-15',EndDate='2026-12-16' if pk['UnitCode'] in ('NIGHT','DAY') else '2026-12-15',SlotCode='DEFAULT',Quantity=1,GuestCount=1)
    q=send(c,'/api/travel/quotes',d);assert q.status_code==200,q.get_json()
    total=q.get_json()['quote']['Total'];r=send(c,'/api/travel/bookings',dict(d,ContactName='Khách dùng dịch vụ',ContactEmail='demo@example.test',ContactPhone='0901234567',ExpectedTotal=total,IdempotencyKey=uuid.uuid4().hex));assert r.status_code==201,r.get_json()
    b=r.get_json()['booking'];assert pay(c,b).status_code==200
    details=c.get('/api/travel/bookings/'+str(b['BookingID']));assert details.status_code==200
    assert details.get_json()['fulfillment']['Kind']==('ESIM' if category=='esim' else 'VOUCHER')
    pdf=c.get('/api/travel/bookings/'+str(b['BookingID'])+'/receipt');assert pdf.status_code==200 and pdf.data.startswith(b'%PDF') and len(pdf.data)>2000
    assert send(c,'/api/travel/bookings/'+str(b['BookingID'])+'/cancel',{'IdempotencyKey':uuid.uuid4().hex}).status_code==200

def test_catalogue_create_package_local_range_and_provider(app,users,sql_ready):
    customer=sign_in(app,users[0]);admin=sign_in(app,users[2])
    r=send(customer,'/api/travel/provider/apply',dict(Name='Đối tác thử '+uuid.uuid4().hex[:8],Description='Hồ sơ hư cấu để kiểm tra quyền truy cập.'));assert r.status_code==201
    pid=r.get_json()['provider']['ProviderID']
    assert customer.get('/api/travel/provider').get_json()['provider']['Status']=='PENDING'
    assert send(admin,'/api/admin/travel/providers/'+str(pid),dict(Status='ACTIVE'),'PATCH').status_code==200
    dest=query("SELECT DestinationID FROM dbo.TravelDestinations WHERE Slug='demo-sin'",one=True)['DestinationID']
    r=send(admin,'/api/admin/travel/products',dict(CategoryCode='activities',ProviderID=pid,DestinationID=dest,Title='Trải nghiệm thử tại Singapore',Slug='test-product-'+uuid.uuid4().hex,Summary='Một dịch vụ kiểm thử',Description='Mô tả đủ dài cho dịch vụ kiểm thử.',Address='Điểm hẹn thử Singapore'));assert r.status_code==201,r.get_json()
    product=r.get_json()['product']['ProductID']
    r=send(admin,'/api/admin/travel/packages',dict(ProductID=product,Name='Gói thử',Description='Một lượt trải nghiệm',UnitCode='PERSON',UnitLabel='người',MaxGuests=1,RefundPercent=100,CancelCutoffHours=24));assert r.status_code==201,r.get_json()
    package=r.get_json()['package']['PackageID']
    range_data=dict(PackageID=package,StartDate='2026-12-20',EndDate='2026-12-22',LocalStart='09:00',LocalEnd='10:30',EndDayOffset=0,SlotCode='MORNING',Capacity=5,UnitPrice=390000)
    r=send(admin,'/api/admin/travel/inventory/range',range_data);assert r.status_code==200 and r.get_json()['created']==3,r.get_json()
    assert send(admin,'/api/admin/travel/inventory/range',range_data).get_json()['existing']==3
    assert send(admin,f'/api/admin/travel/products/{product}',dict(IsPublished=True),'PATCH').status_code==200
    # Singapore 09:00 is UTC 01:00, not the admin browser's local timezone.
    assert query('SELECT TOP(1) DATEPART(hour,StartsAt) H FROM dbo.TravelInventory WHERE PackageID=?',(package,),one=True)['H']==1
    dashboard=customer.get('/api/travel/provider').get_json();assert [p['ProductID'] for p in dashboard['products']]==[product]
    other=sign_in(app,users[1]);assert other.get('/api/travel/provider').get_json()['provider'] is None

def test_coupon_holds_release_but_paid_use_stays_consumed(app,users,sql_ready):
    c=sign_in(app,users[0]);code='TEST-'+uuid.uuid4().hex[:16]
    query("INSERT dbo.TravelCoupons(Code,Title,Kind,Amount,MaxDiscount,MinSubtotal,UsageLimit,PerUserLimit,ValidFrom,ValidUntil) VALUES(?,N'Test quota','PERCENT',10,300000,0,1,1,'2026-01-01','2027-02-01')",(code,))
    packages=query("SELECT TOP(2) k.PackageID FROM dbo.TravelPackages k JOIN dbo.TravelProducts p ON p.ProductID=k.ProductID WHERE p.CategoryCode='hotels' AND p.Slug LIKE 'demo-%' ORDER BY k.PackageID")
    def make(pk):
        d=dict(PackageID=pk,StartDate='2026-12-22',EndDate='2026-12-23',SlotCode='DEFAULT',Quantity=1,GuestCount=1,VoucherCode=code)
        q=send(c,'/api/travel/quotes',d)
        if q.status_code!=200:return q
        return send(c,'/api/travel/bookings',dict(d,ContactName='Khách thử',ContactEmail='demo@example.test',ContactPhone='0901234567',ExpectedTotal=q.get_json()['quote']['Total'],IdempotencyKey=uuid.uuid4().hex))
    first=make(packages[0]['PackageID']);assert first.status_code==201
    assert make(packages[1]['PackageID']).status_code==409
    b=first.get_json()['booking'];assert send(c,f'/api/travel/bookings/{b["BookingID"]}/cancel',{'IdempotencyKey':uuid.uuid4().hex}).status_code==200
    second=make(packages[1]['PackageID']);assert second.status_code==201
    b=second.get_json()['booking'];assert pay(c,b).status_code==200
    assert send(c,f'/api/travel/bookings/{b["BookingID"]}/cancel',{'IdempotencyKey':uuid.uuid4().hex}).status_code==200
    assert make(packages[0]['PackageID']).status_code==409

def test_snapshot_cannot_be_rewritten_in_ssms(app,users,travel_item):
    c=sign_in(app,users[0]);b=reserve(c,travel_item)
    with pytest.raises(pyodbc.Error):query('UPDATE dbo.TravelBookings SET RefundPercent=0 WHERE BookingID=?',(b['BookingID'],))
    assert query('SELECT RefundPercent FROM dbo.TravelBookings WHERE BookingID=?',(b['BookingID'],),one=True)['RefundPercent']==100

def test_featured_is_diverse_and_unique(client,sql_ready):
    r=client.get('/api/travel/featured');assert r.status_code==200,r.get_json()
    rows=r.get_json()['items'];assert len(rows)>=11
    assert len({p['DestinationID'] for p in rows})==len(rows)

def test_search_dates_total_price_and_capacity(client,travel_item):
    end=str(datetime.fromisoformat(travel_item['StartDate']).date()+timedelta(days=2))
    args=dict(Category='hotels',StartDate=travel_item['StartDate'],EndDate=end,Guests=2,Sort='new')
    r=client.get('/api/travel/products',query_string=args);assert r.status_code==200,r.get_json()
    item=next(p for p in r.get_json()['items'] if p['ProductID']==travel_item['ProductID'])
    assert Decimal(item['SelectedTotal'])==2100000 and item['SearchUnits']==2
    r=client.get('/api/travel/products',query_string={**args,'MaxPrice':2099999});assert r.status_code==200
    assert all(p['ProductID']!=travel_item['ProductID'] for p in r.get_json()['items'])

    # Three guests need two rooms; this independent test inventory only has one.
    r=client.get('/api/travel/products',query_string={**args,'Guests':3});assert r.status_code==200
    assert all(p['ProductID']!=travel_item['ProductID'] for p in r.get_json()['items'])

def test_expiration_worker_updates_state_and_audit(app,users,travel_item):
    import runpy
    from pathlib import Path
    c=sign_in(app,users[0]);b=reserve(c,travel_item)
    query("UPDATE dbo.TravelBookings SET CreatedAt=DATEADD(minute,-30,SYSUTCDATETIME()),ExpiresAt=DATEADD(minute,-20,SYSUTCDATETIME()) WHERE BookingID=?",(b['BookingID'],))
    runpy.run_path(str(Path(__file__).resolve().parents[1]/'scripts'/'expire_holds.py'),run_name='__main__')
    assert query('SELECT Status FROM dbo.TravelBookings WHERE BookingID=?',(b['BookingID'],),one=True)['Status']=='EXPIRED'
    assert query("SELECT COUNT(*) N FROM dbo.TravelAuditLog WHERE Entity='BOOKING' AND EntityID=? AND Action='EXPIRE'",(b['BookingID'],),one=True)['N']==1

def test_voucher_redeem_once_in_service_window(app,users,travel_item):
    c=sign_in(app,users[0]);a=sign_in(app,users[2]);now=datetime.now(timezone.utc).replace(tzinfo=None,microsecond=0)
    query("UPDATE dbo.TravelPackages SET UnitCode='PERSON',UnitLabel=N'người' WHERE PackageID=?",(travel_item['PackageID'],))
    # An unused activity slot starting soon lets us exercise the real redemption window.
    starts=now+timedelta(minutes=30)
    service_date=query("SELECT CONVERT(date,(CAST(? AS datetime2) AT TIME ZONE 'UTC') AT TIME ZONE d.TimeZoneName) ServiceDate FROM dbo.TravelPackages k JOIN dbo.TravelProducts p ON p.ProductID=k.ProductID JOIN dbo.TravelDestinations d ON d.DestinationID=p.DestinationID WHERE k.PackageID=?",(starts,travel_item['PackageID']),one=True)['ServiceDate']
    query('UPDATE dbo.TravelInventory SET ServiceDate=?,StartsAt=?,EndsAt=? WHERE InventoryID=?',(service_date,starts,now+timedelta(hours=2),travel_item['InventoryIDs'][0]))
    d={**travel_item,'StartDate':str(service_date),'EndDate':str(service_date),'GuestCount':1}
    b=reserve(c,d);assert pay(c,b).status_code==200
    code=c.get(f'/api/travel/bookings/{b["BookingID"]}').get_json()['booking']['VoucherCode']
    assert send(a,'/api/admin/travel/redeem',{'Code':code}).status_code==200
    assert send(a,'/api/admin/travel/redeem',{'Code':code}).status_code==409
    assert c.get(f'/api/travel/bookings/{b["BookingID"]}/qr').status_code==409
    assert send(c,f'/api/travel/bookings/{b["BookingID"]}/cancel',{'IdempotencyKey':uuid.uuid4().hex}).status_code==409


def test_night_inventory_cannot_end_on_same_local_day(travel_item):
    with pytest.raises(pyodbc.Error):
        query('UPDATE dbo.TravelInventory SET EndsAt=DATEADD(hour,1,StartsAt) WHERE InventoryID=?',(travel_item['InventoryIDs'][0],))
    assert query('SELECT DATEDIFF(hour,StartsAt,EndsAt) Hours FROM dbo.TravelInventory WHERE InventoryID=?',(travel_item['InventoryIDs'][0],),one=True)['Hours']==22
