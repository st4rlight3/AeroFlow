"""Back office and provider ownership boundary for marketplace data."""
import json
from flask import Blueprint,g,jsonify,request
from ..db import query,connection
from ..errors import ApiError
from ..security import authenticated
from ..validation import body,text,integer,decimal_value,iso_date,utc_datetime

bp=Blueprint('travel_admin',__name__,url_prefix='/api/admin/travel')

@bp.get('/overview')
@authenticated(admin=True)
def overview():
    return jsonify(summary=query("SELECT (SELECT COUNT(*) FROM dbo.TravelProducts) Products,(SELECT COUNT(*) FROM dbo.TravelBookings) Bookings,(SELECT COUNT(*) FROM dbo.TravelBookings WHERE Status='CONFIRMED') Confirmed,COALESCE((SELECT SUM(NetRevenue) FROM dbo.vw_TravelRevenue),0) NetRevenue",one=True),
      revenue=query('SELECT * FROM dbo.vw_TravelRevenue ORDER BY RevenueDate'),categories=query('SELECT c.Name,COUNT(b.BookingID) Bookings,COALESCE(SUM(CASE WHEN b.Status=\'CONFIRMED\' THEN b.Total ELSE 0 END),0) ConfirmedValue FROM dbo.TravelCategories c LEFT JOIN dbo.TravelProducts p ON p.CategoryCode=c.Code LEFT JOIN dbo.TravelBookings b ON b.ProductID=p.ProductID GROUP BY c.Code,c.Name ORDER BY c.Name'))

@bp.get('/products')
@authenticated(admin=True)
def products():return jsonify(items=query('SELECT * FROM dbo.vw_TravelProducts ORDER BY ProductID DESC'),providers=query('SELECT * FROM dbo.TravelProviders ORDER BY Name'))

def bool_field(d,k):
    if not isinstance(d.get(k),bool):raise ApiError(f'{k} phải là true hoặc false.')
    return d[k]

@bp.route('/products/<int:pid>',methods=['GET','PATCH'])
@authenticated(admin=True)
def product(pid):
    p=query('SELECT * FROM dbo.TravelProducts WHERE ProductID=?',(pid,),one=True)
    if not p:raise ApiError('Không tìm thấy dịch vụ.',404)
    if request.method=='GET':return jsonify(product=p,packages=query('SELECT * FROM dbo.TravelPackages WHERE ProductID=?',(pid,)))
    d=body();allowed={'Title','Summary','Description','Address','IsPublished','StarRating','DurationMinutes'}
    if set(d)-allowed:raise ApiError('Trường cập nhật không được hỗ trợ.')
    values={}
    for k,mi,ma in [('Title',3,200),('Summary',3,500),('Description',10,20000),('Address',3,250)]:
        if k in d:values[k]=text(d,k,mi,ma)
    for k,ma in [('StarRating',5),('DurationMinutes',100000)]:
        if k in d:values[k]=integer(d,k,0,ma)
    if 'IsPublished' in d:values['IsPublished']=bool_field(d,'IsPublished')
    if not values:raise ApiError('Chưa có thay đổi.')
    with connection() as conn:
        conn.execute('EXEC dbo.sp_TravelLock ?',pid)
        conn.execute('UPDATE dbo.TravelProducts SET '+','.join(k+'=?' for k in values)+',UpdatedAt=SYSUTCDATETIME() WHERE ProductID=?',*values.values(),pid)
        conn.execute("INSERT dbo.TravelAuditLog(ActorID,Entity,EntityID,Action) VALUES(?,'PRODUCT',?,'UPDATE')",g.user['UserID'],pid)
    return jsonify(ok=True)

@bp.post('/products')
@authenticated(admin=True)
def create_product():
    d=body();dest=integer(d,'DestinationID');provider=integer(d,'ProviderID')
    place=query('SELECT * FROM dbo.TravelDestinations WHERE DestinationID=?',(dest,),one=True)
    if not place:raise ApiError('Điểm đến không tồn tại.')
    slug=text(d,'Slug',3,150)
    import re
    if not re.fullmatch('[a-z0-9-]+',slug):raise ApiError('Slug chỉ gồm chữ thường, số và dấu gạch ngang.')
    row=query('SET NOCOUNT ON; INSERT dbo.TravelProducts(CategoryCode,DestinationID,ProviderID,Slug,Title,Summary,Description,Address,Latitude,Longitude) VALUES(?,?,?,?,?,?,?,?,?,?); SELECT CONVERT(int,SCOPE_IDENTITY()) ProductID;',
      (text(d,'CategoryCode',1,20),dest,provider,slug,text(d,'Title',3,200),text(d,'Summary',3,500),text(d,'Description',10,20000),text(d,'Address',3,250),place['Latitude'],place['Longitude']),one=True)
    query('INSERT dbo.TravelProductImages(ProductID,ImagePath,Caption,SortOrder) VALUES(?,?,?,0)',(row['ProductID'],place['ImagePath'],text(d,'Title',3,200)))
    return jsonify(product=row),201

@bp.post('/packages')
@authenticated(admin=True)
def create_package():
    d=body();unit=text(d,'UnitCode',3,12)
    if unit not in ('NIGHT','DAY','PERSON','BOOKING'):raise ApiError('Đơn vị không hợp lệ.')
    row=query('SET NOCOUNT ON; INSERT dbo.TravelPackages(ProductID,Name,Description,UnitCode,UnitLabel,MaxGuests,RefundPercent,CancelCutoffHours,ChangeAllowed,ChangeFee) VALUES(?,?,?,?,?,?,?,?,0,0); SELECT CONVERT(int,SCOPE_IDENTITY()) PackageID;',
      (integer(d,'ProductID'),text(d,'Name',3,150),text(d,'Description',5,2000),unit,text(d,'UnitLabel',2,30),integer(d,'MaxGuests',1,50),decimal_value(d,'RefundPercent',0,100),integer(d,'CancelCutoffHours',0,720)),one=True)
    return jsonify(package=row),201

@bp.route('/inventory',methods=['GET','POST','PATCH'])
@authenticated(admin=True)
def inventory():
    if request.method=='GET':
        return jsonify(items=query('SELECT TOP(400) * FROM dbo.vw_TravelAvailability WHERE PackageID=? ORDER BY ServiceDate,SlotCode',(integer(request.args,'PackageID'),)))
    d=body()
    with connection() as conn:
        if request.method=='PATCH':
            iid=integer(d,'InventoryID');pk=conn.execute('SELECT k.ProductID FROM dbo.TravelInventory i JOIN dbo.TravelPackages k ON k.PackageID=i.PackageID WHERE i.InventoryID=?',iid).fetchone()
            if not pk:raise ApiError('Không tìm thấy lịch.',404)
            conn.execute('EXEC dbo.sp_TravelLock ?',pk[0])
            conn.execute('UPDATE dbo.TravelInventory SET Capacity=?,UnitPrice=?,IsClosed=? WHERE InventoryID=?',integer(d,'Capacity',0,5000),decimal_value(d,'UnitPrice',1,100000000),bool_field(d,'IsClosed'),iid)
        else:
            package=integer(d,'PackageID');pk=conn.execute('SELECT ProductID FROM dbo.TravelPackages WHERE PackageID=?',package).fetchone()
            if not pk:raise ApiError('Không tìm thấy gói.',404)
            conn.execute('EXEC dbo.sp_TravelLock ?',pk[0])
            start=utc_datetime(d.get('StartsAt'));end=utc_datetime(d.get('EndsAt'))
            iid=conn.execute('INSERT dbo.TravelInventory(PackageID,ServiceDate,SlotCode,StartsAt,EndsAt,Capacity,UnitPrice) OUTPUT INSERTED.InventoryID VALUES(?,?,?,?,?,?,?)',package,iso_date(d.get('ServiceDate')),text(d,'SlotCode',1,20),start,end,integer(d,'Capacity',0,5000),decimal_value(d,'UnitPrice',1,100000000)).fetchone()[0]
        conn.execute("INSERT dbo.TravelAuditLog(ActorID,Entity,EntityID,Action) VALUES(?,'INVENTORY',?,'SAVE')",g.user['UserID'],iid)
    return jsonify(InventoryID=iid)

@bp.get('/bookings')
@authenticated(admin=True)
def bookings():return jsonify(items=query('SELECT TOP(500) b.*,u.Email FROM dbo.TravelBookings b JOIN dbo.Users u ON u.UserID=b.UserID ORDER BY b.BookingID DESC'))

@bp.post('/inventory/range')
@authenticated(admin=True)
def inventory_range():
    from datetime import datetime,timedelta
    import re
    d=body();package=integer(d,'PackageID');start=iso_date(d.get('StartDate'));end=iso_date(d.get('EndDate'))
    if end<start or (end-start).days>61:raise ApiError('Mỗi lần tạo tối đa 62 ngày.')
    begin=text(d,'LocalStart',5,5);finish=text(d,'LocalEnd',5,5);slot=text(d,'SlotCode',1,20)
    if not re.fullmatch(r'([01]\d|2[0-3]):[0-5]\d',begin) or not re.fullmatch(r'([01]\d|2[0-3]):[0-5]\d',finish) or not re.fullmatch('[A-Za-z0-9_-]+',slot):raise ApiError('Khung giờ chưa hợp lệ.')
    offset=integer(d,'EndDayOffset',0,30);capacity=integer(d,'Capacity',0,5000);price=decimal_value(d,'UnitPrice',1,100000000);created=0
    with connection() as conn:
        pk=conn.execute('SELECT k.ProductID,d.TimeZoneName FROM dbo.TravelPackages k JOIN dbo.TravelProducts p ON p.ProductID=k.ProductID JOIN dbo.TravelDestinations d ON d.DestinationID=p.DestinationID WHERE k.PackageID=?',package).fetchone()
        if not pk:raise ApiError('Không tìm thấy gói.',404)
        conn.execute('EXEC dbo.sp_TravelLock ?',pk[0])
        for n in range((end-start).days+1):
            date=start+timedelta(days=n)
            local_begin=datetime.fromisoformat(str(date)+'T'+begin);local_end=datetime.fromisoformat(str(date+timedelta(days=offset))+'T'+finish)
            if local_end<=local_begin:raise ApiError('Giờ kết thúc phải sau giờ bắt đầu.')
            # Let the same SQL Server timezone catalogue used by flight operations do the conversion.
            times=conn.execute("SELECT CONVERT(datetime2(0),(CAST(? AS datetime2) AT TIME ZONE ?) AT TIME ZONE 'UTC'),CONVERT(datetime2(0),(CAST(? AS datetime2) AT TIME ZONE ?) AT TIME ZONE 'UTC')",local_begin,pk[1],local_end,pk[1]).fetchone()
            if not conn.execute('SELECT InventoryID FROM dbo.TravelInventory WHERE PackageID=? AND ServiceDate=? AND SlotCode=?',package,date,slot).fetchone():
                conn.execute('INSERT dbo.TravelInventory(PackageID,ServiceDate,SlotCode,StartsAt,EndsAt,Capacity,UnitPrice) VALUES(?,?,?,?,?,?,?)',package,date,slot,times[0],times[1],capacity,price);created+=1
        conn.execute("INSERT dbo.TravelAuditLog(ActorID,Entity,EntityID,Action,Details) VALUES(?,'PACKAGE',?,'ADD_DATES',?)",g.user['UserID'],package,str(created))
    return jsonify(created=created,existing=(end-start).days+1-created)

@bp.get('/payments')
@authenticated(admin=True)
def payments():return jsonify(items=query('SELECT TOP(1000) p.*,b.Reference FROM dbo.TravelPayments p JOIN dbo.TravelBookings b ON b.BookingID=p.BookingID ORDER BY PaymentID DESC'))

@bp.post('/redeem')
@authenticated(admin=True)
def redeem():
    code=text(body(),'Code',32,32).upper()
    with connection() as conn:
        row=conn.execute('SELECT v.VoucherID,b.ProductID FROM dbo.TravelVouchers v JOIN dbo.TravelBookings b ON b.BookingID=v.BookingID WHERE v.Code=?',code).fetchone()
        if not row:raise ApiError('Không tìm thấy phiếu.',404)
        conn.execute('EXEC dbo.sp_TravelLock ?',row[1])
        found=conn.execute("SET NOCOUNT ON; DECLARE @used TABLE(VoucherID int); UPDATE v SET Status='REDEEMED',RedeemedAt=SYSUTCDATETIME(),RedeemedBy=? OUTPUT INSERTED.VoucherID INTO @used FROM dbo.TravelVouchers v JOIN dbo.TravelBookings b ON b.BookingID=v.BookingID WHERE v.Code=? AND v.Status='ACTIVE' AND b.Status='CONFIRMED' AND SYSUTCDATETIME()>=DATEADD(hour,-2,b.ServiceStartsAt) AND SYSUTCDATETIME()<=b.ServiceEndsAt; SELECT VoucherID FROM @used;",g.user['UserID'],code).fetchone()
        if not found:raise ApiError('Phiếu đã dùng, đã hủy hoặc chưa đến thời gian sử dụng.',409)
        conn.execute("INSERT dbo.TravelAuditLog(ActorID,Entity,EntityID,Action) VALUES(?,'VOUCHER',?,'REDEEM')",g.user['UserID'],row[0])
    return jsonify(ok=True)

@bp.route('/coupons',methods=['GET','POST'])
@authenticated(admin=True)
def coupons():
    if request.method=='GET':return jsonify(items=query('SELECT * FROM dbo.TravelCoupons ORDER BY CouponID DESC'))
    d=body();kind=text(d,'Kind',5,8)
    if kind not in ('FIXED','PERCENT'):raise ApiError('Loại ưu đãi không hợp lệ.')
    code=text(d,'Code',3,40).upper()
    import re
    if not re.fullmatch('[A-Z0-9-]+',code):raise ApiError('Mã ưu đãi chỉ gồm chữ, số và dấu gạch ngang.')
    query('INSERT dbo.TravelCoupons(Code,Title,Kind,Amount,MaxDiscount,MinSubtotal,UsageLimit,PerUserLimit,ValidFrom,ValidUntil,CategoryCode) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
     (code,text(d,'Title',3,150),kind,decimal_value(d,'Amount',1,100 if kind=='PERCENT' else 100000000),decimal_value(d,'MaxDiscount',1),decimal_value(d,'MinSubtotal'),integer(d,'UsageLimit',1,1000000),integer(d,'PerUserLimit',1,1000),utc_datetime(d.get('ValidFrom')),utc_datetime(d.get('ValidUntil')),d.get('CategoryCode') or None))
    return jsonify(ok=True),201

@bp.patch('/coupons/<int:cid>')
@authenticated(admin=True)
def coupon_toggle(cid):
    query('UPDATE dbo.TravelCoupons SET IsActive=? WHERE CouponID=?',(bool_field(body(),'IsActive'),cid));return jsonify(ok=True)

@bp.get('/reviews')
@authenticated(admin=True)
def reviews():return jsonify(items=query('SELECT TOP(500) * FROM dbo.TravelReviews ORDER BY ReviewID DESC'))

@bp.patch('/reviews/<int:rid>')
@authenticated(admin=True)
def moderate(rid):
    query('UPDATE dbo.TravelReviews SET IsVisible=? WHERE ReviewID=?',(bool_field(body(),'IsVisible'),rid));return jsonify(ok=True)

@bp.route('/providers',methods=['GET'])
@authenticated(admin=True)
def providers():return jsonify(items=query('SELECT * FROM dbo.TravelProviders ORDER BY ProviderID DESC'))

@bp.patch('/providers/<int:pid>')
@authenticated(admin=True)
def provider_status(pid):
    value=text(body(),'Status',6,12)
    if value not in ('ACTIVE','PENDING','SUSPENDED'):raise ApiError('Trạng thái không hợp lệ.')
    query('UPDATE dbo.TravelProviders SET Status=? WHERE ProviderID=?',(value,pid));return jsonify(ok=True)

@bp.get('/support')
@authenticated(admin=True)
def support():return jsonify(items=query('SELECT TOP(300) t.*,u.Email FROM dbo.TravelSupportTickets t JOIN dbo.Users u ON u.UserID=t.UserID ORDER BY TicketID DESC'))

@bp.route('/support/<int:tid>',methods=['GET','POST'])
@authenticated(admin=True)
def support_reply(tid):
    if not query('SELECT TicketID FROM dbo.TravelSupportTickets WHERE TicketID=?',(tid,),one=True):raise ApiError('Không tìm thấy yêu cầu.',404)
    if request.method=='POST':
        d=body();status=d.get('Status','ANSWERED')
        if status not in ('ANSWERED','CLOSED'):raise ApiError('Trạng thái không hợp lệ.')
        query('INSERT dbo.TravelSupportMessages(TicketID,SenderID,Message) VALUES(?,?,?); UPDATE dbo.TravelSupportTickets SET Status=? WHERE TicketID=?',(tid,g.user['UserID'],text(d,'Message',2,2000),status,tid))
    return jsonify(messages=query('SELECT m.*,u.FullName FROM dbo.TravelSupportMessages m JOIN dbo.Users u ON u.UserID=m.SenderID WHERE TicketID=? ORDER BY MessageID',(tid,)))

@bp.get('/audit')
@authenticated(admin=True)
def audit():return jsonify(items=query('SELECT TOP(500) * FROM dbo.TravelAuditLog ORDER BY AuditID DESC'))
