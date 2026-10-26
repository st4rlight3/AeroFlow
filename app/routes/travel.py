"""Travel catalogue and customer workflows. SQL owns prices, stock and payment state."""
import hashlib
import io
import json
import re
from datetime import datetime, timezone
from flask import Blueprint, g, jsonify, request, session, send_file
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics.shapes import Drawing
from reportlab.graphics import renderSVG
from ..db import query, connection
from ..errors import ApiError
from ..security import authenticated
from ..validation import body, text, integer, decimal_value, iso_date, email

bp = Blueprint('travel', __name__, url_prefix='/api/travel')

def optional_user():
    uid = session.get('uid')
    if uid and query('SELECT UserID FROM dbo.Users WHERE UserID=? AND IsActive=1 AND SessionVersion=?', (uid, session.get('version')), one=True):
        return uid
    return None

def selection(d):
    start = iso_date(d.get('StartDate'))
    end = iso_date(d.get('EndDate', str(start)))
    slot = d.get('SlotCode', 'DEFAULT')
    if not isinstance(slot, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,20}', slot):
        raise ApiError('Khung giờ không hợp lệ.')
    code = d.get('VoucherCode') or ''
    if not isinstance(code, str) or (code and not re.fullmatch(r'[A-Za-z0-9-]{3,40}', code)):
        raise ApiError('Mã ưu đãi không hợp lệ.')
    return dict(PackageID=integer(d,'PackageID'), StartDate=str(start), EndDate=str(end), SlotCode=slot,
                Quantity=integer(d,'Quantity',1,99), GuestCount=integer(d,'GuestCount',1,4950), VoucherCode=code.upper() or None)

def quote(d, uid=None):
    s = selection(d)
    row = query('DECLARE @j nvarchar(max); EXEC dbo.sp_TravelQuote ?,?,?,?,?,?,?,?,@j OUTPUT; SELECT @j Json;',
                (*s.values(), uid), one=True)
    return json.loads(row['Json'])

def owned(bid):
    row = query('SELECT b.*,d.IanaTimeZone,v.Code VoucherCode,v.Status VoucherStatus FROM dbo.TravelBookings b JOIN dbo.TravelProducts p ON p.ProductID=b.ProductID JOIN dbo.TravelDestinations d ON d.DestinationID=p.DestinationID LEFT JOIN dbo.TravelVouchers v ON v.BookingID=b.BookingID WHERE b.BookingID=? AND b.UserID=?', (bid,g.user['UserID']), one=True)
    if not row: raise ApiError('Không tìm thấy đơn đặt dịch vụ.',404)
    if row['Status']=='HELD' and row['ExpiresAt']<=datetime.now(timezone.utc).replace(tzinfo=None):
        row['Status']='EXPIRED'  # effective state; cleanup on next stock mutation
    return row

@bp.get('/categories')
def categories():
    return jsonify(items=query('SELECT c.*,(SELECT COUNT(*) FROM dbo.TravelProducts p JOIN dbo.TravelProviders pr ON pr.ProviderID=p.ProviderID WHERE p.CategoryCode=c.Code AND p.IsPublished=1 AND pr.Status=\'ACTIVE\') ProductCount FROM dbo.TravelCategories c ORDER BY SortOrder'))

@bp.get('/destinations')
def destinations():
    term = request.args.get('q','').strip()[:100]
    return jsonify(items=query('SELECT d.* FROM dbo.TravelDestinations d WHERE (Name LIKE ? OR CountryName LIKE ?) AND EXISTS(SELECT 1 FROM dbo.TravelProducts p JOIN dbo.TravelProviders pr ON pr.ProviderID=p.ProviderID WHERE p.DestinationID=d.DestinationID AND p.IsPublished=1 AND pr.Status=\'ACTIVE\') ORDER BY CountryName,Name', ('%'+term+'%','%'+term+'%')))

@bp.get('/products')
def products():
    a=request.args
    where=["p.IsPublished=1", "p.ProviderStatus='ACTIVE'"]; params=[]
    source='dbo.vw_TravelProducts p';source_params=[];price='p.FromPrice';extra=''
    if a.get('StartDate'):
        start=iso_date(a['StartDate']);end=iso_date(a.get('EndDate') or str(start))
        if end<start or (end-start).days>30:raise ApiError('Khoảng ngày tối đa 30 ngày.')
        units=max(1,(end-start).days);guests=integer(a,'Guests',1,50) if a.get('Guests') else 1
        source+=""" CROSS APPLY(SELECT CAST(? AS date) StartDate,CAST(? AS date) EndDate,CAST(? AS int) Guests,CAST(? AS int) Units) ctx
        OUTER APPLY(SELECT MIN(ch.Total) SelectedTotal FROM(
         SELECT SUM(i.UnitPrice)*CEILING(CONVERT(decimal(9,2),ctx.Guests)/k.MaxGuests) Total
         FROM dbo.TravelPackages k JOIN dbo.vw_TravelAvailability i ON i.PackageID=k.PackageID
         WHERE k.ProductID=p.ProductID AND k.IsActive=1 AND i.IsClosed=0 AND i.StartsAt>SYSUTCDATETIME()
         AND ((k.UnitCode IN ('NIGHT','DAY') AND ctx.EndDate>ctx.StartDate) OR (k.UnitCode NOT IN ('NIGHT','DAY') AND ctx.EndDate=ctx.StartDate))
         AND i.ServiceDate>=ctx.StartDate AND i.ServiceDate<CASE WHEN ctx.EndDate>ctx.StartDate THEN ctx.EndDate ELSE DATEADD(day,1,ctx.StartDate) END
         AND i.AvailableQuantity>=CEILING(CONVERT(decimal(9,2),ctx.Guests)/k.MaxGuests)
         GROUP BY k.PackageID,k.MaxGuests,i.SlotCode HAVING COUNT(*)=ctx.Units
        ) ch) price"""
        source_params=[start,end,guests,units];price='price.SelectedTotal';extra=',price.SelectedTotal,ctx.Guests SearchGuests,ctx.Units SearchUnits'
        where.append('price.SelectedTotal IS NOT NULL')
    for arg,col in [('Category','CategoryCode'),('Destination','DestinationID')]:
        if a.get(arg):
            where.append('p.'+col+'=?'); params.append(integer(a,arg) if arg=='Destination' else text(a,arg,1,20))
    if a.get('q'):
        term='%'+text(a,'q',1,100)+'%';where.append('(p.Title LIKE ? OR p.DestinationName LIKE ? OR p.Summary LIKE ?)');params.extend((term,term,term))
    for arg,op in [('MinPrice','>='),('MaxPrice','<=')]:
        if a.get(arg):where.append(price+op+'?');params.append(decimal_value(a,arg))
    if a.get('Stars'):where.append('p.StarRating>=?');params.append(integer(a,'Stars',0,5))
    if a.get('Rating'):where.append('p.Rating>=?');params.append(decimal_value(a,'Rating',0,5))
    orders={'price':price+' ASC','price-desc':price+' DESC','rating':'p.Rating DESC,p.ReviewCount DESC','popular':'p.ReviewCount DESC','new':'p.CreatedAt DESC'}
    order=orders.get(a.get('Sort','popular'))
    if not order:raise ApiError('Cách sắp xếp không hợp lệ.')
    page=integer(a,'Page',1,10000) if a.get('Page') else 1
    clause=' AND '.join(where)
    count=query('SELECT COUNT(*) Total FROM '+source+' WHERE '+clause,(*source_params,*params),one=True)['Total']
    rows=query('SELECT p.*'+extra+' FROM '+source+' WHERE '+clause+' ORDER BY '+order+',p.ProductID OFFSET ? ROWS FETCH NEXT 18 ROWS ONLY',(*source_params,*params,(page-1)*18))
    return jsonify(items=rows,total=count,page=page,pageSize=18)

@bp.get('/products/<int:pid>')
def product(pid):
    p=query("SELECT * FROM dbo.vw_TravelProducts WHERE ProductID=? AND IsPublished=1 AND ProviderStatus='ACTIVE'",(pid,),one=True)
    if not p:raise ApiError('Dịch vụ không tồn tại.',404)
    return jsonify(product=p,images=query('SELECT ImagePath,Caption FROM dbo.TravelProductImages WHERE ProductID=? ORDER BY SortOrder',(pid,)),
      packages=query('SELECT k.*,(SELECT MIN(i.ServiceDate) FROM dbo.vw_TravelAvailability i WHERE i.PackageID=k.PackageID AND i.IsClosed=0 AND i.AvailableQuantity>0 AND i.StartsAt>SYSUTCDATETIME()) NextDate FROM dbo.TravelPackages k WHERE ProductID=? AND IsActive=1 ORDER BY PackageID',(pid,)),
      amenities=query('SELECT a.* FROM dbo.TravelAmenities a JOIN dbo.TravelProductAmenities x ON x.AmenityID=a.AmenityID WHERE x.ProductID=?',(pid,)),
      reviews=query('SELECT TOP(30) r.Rating,r.Title,r.Comment,r.CreatedAt,LEFT(u.FullName,1)+N\'***\' Reviewer FROM dbo.TravelReviews r JOIN dbo.Users u ON u.UserID=r.UserID WHERE r.ProductID=? AND r.IsVisible=1 ORDER BY r.CreatedAt DESC',(pid,)))

@bp.get('/featured')
def featured():
    return jsonify(items=query("WITH choices AS(SELECT p.*,ROW_NUMBER() OVER(PARTITION BY p.DestinationID ORDER BY CASE WHEN c.SortOrder=p.DestinationID%12 THEN 0 ELSE 1 END,p.ReviewCount DESC,p.ProductID) rn FROM dbo.vw_TravelProducts p JOIN dbo.TravelCategories c ON c.Code=p.CategoryCode WHERE p.IsPublished=1 AND p.ProviderStatus='ACTIVE' AND p.FromPrice IS NOT NULL) SELECT TOP(12) * FROM choices WHERE rn=1 ORDER BY DestinationID"))

@bp.get('/packages/<int:pid>/availability')
def availability(pid):
    start=iso_date(request.args.get('StartDate'));end=iso_date(request.args.get('EndDate',str(start)))
    if end<start or (end-start).days>62:raise ApiError('Khoảng ngày tối đa 62 ngày.')
    return jsonify(items=query("SELECT i.* FROM dbo.vw_TravelAvailability i JOIN dbo.TravelProducts p ON p.ProductID=i.ProductID JOIN dbo.TravelProviders pr ON pr.ProviderID=p.ProviderID JOIN dbo.TravelPackages k ON k.PackageID=i.PackageID WHERE i.PackageID=? AND i.ServiceDate BETWEEN ? AND ? AND p.IsPublished=1 AND pr.Status='ACTIVE' AND k.IsActive=1 ORDER BY i.ServiceDate,i.StartsAt",(pid,start,end)))

@bp.post('/quotes')
def prices():return jsonify(quote=quote(body(),optional_user()))

@bp.post('/bookings')
@authenticated()
def create_booking():
    d=body();s=selection(d)
    contact=dict(ContactName=text(d,'ContactName',2,120),ContactEmail=email({'Email':d.get('ContactEmail')}),ContactPhone=text(d,'ContactPhone',6,24),Notes=d.get('Notes',''))
    if not re.fullmatch(r'[+0-9 ()-]{6,24}',contact['ContactPhone']):raise ApiError('Số điện thoại không hợp lệ.')
    if not isinstance(contact['Notes'],str) or len(contact['Notes'])>1000:raise ApiError('Ghi chú tối đa 1000 ký tự.')
    key=text(d,'IdempotencyKey',8,80);expected=decimal_value(d,'ExpectedTotal')
    fingerprint=hashlib.sha256(json.dumps({**s,**contact,'ExpectedTotal':format(expected,'.2f')},sort_keys=True,ensure_ascii=False).encode()).hexdigest()
    row=query('EXEC dbo.sp_TravelCreateBooking '+','.join('?' for _ in range(15)),(g.user['UserID'],*s.values(),*contact.values(),key,fingerprint,expected),one=True)
    return jsonify(booking=row),201

@bp.get('/bookings')
@authenticated()
def bookings():
    return jsonify(items=query("SELECT b.*,CASE WHEN Status='HELD' AND ExpiresAt<=SYSUTCDATETIME() THEN 'EXPIRED' ELSE Status END EffectiveStatus FROM dbo.TravelBookings b WHERE UserID=? ORDER BY CreatedAt DESC",(g.user['UserID'],)))

@bp.get('/bookings/<int:bid>')
@authenticated()
def booking(bid):
    return jsonify(booking=owned(bid),items=query('SELECT bi.*,i.ServiceDate,i.StartsAt,i.EndsAt FROM dbo.TravelBookingItems bi JOIN dbo.TravelInventory i ON i.InventoryID=bi.InventoryID WHERE bi.BookingID=? ORDER BY ServiceDate',(bid,)),payments=query('SELECT * FROM dbo.TravelPayments WHERE BookingID=? ORDER BY PaymentID',(bid,)),review=query('SELECT * FROM dbo.TravelReviews WHERE BookingID=?',(bid,),one=True),fulfillment=query('SELECT * FROM dbo.TravelFulfillments WHERE BookingID=?',(bid,),one=True))

@bp.get('/bookings/<int:bid>/receipt')
@authenticated()
def receipt(bid):
    from reportlab.pdfgen import canvas
    from ..services.documents import font_name
    b=owned(bid)
    if b['Status']!='CONFIRMED':raise ApiError('Đơn chưa có phiếu xác nhận hợp lệ.',409)
    name=font_name()
    out=io.BytesIO();c=canvas.Canvas(out,pagesize=(595,842));c.setTitle('AeroFlow '+b['Reference'])
    c.setFillColorRGB(.05,.32,.27);c.rect(0,690,595,152,fill=1,stroke=0);c.setFillColorRGB(1,1,1);c.setFont(name,28);c.drawString(45,780,'AeroFlow');c.setFont(name,15);c.drawString(45,740,'PHIẾU DỊCH VỤ / DEMO')
    c.setFillColorRGB(.08,.22,.19);c.setFont(name,12)
    lines=[b['Reference'],b['ProductTitle'],b['PackageName'],f"{b['StartDate']} → {b['EndDate']}",f"{b['Quantity']} {b['UnitLabel']} · {b['GuestCount']} khách",b['ContactName'],f"Tổng thanh toán: {b['Total']:,.0f} VND",f"Hoàn {b['RefundPercent']}% nếu hủy trước {b['CancelCutoffHours']} giờ."]
    import textwrap
    y=650
    for line in lines:
        for fragment in textwrap.wrap(str(line),65):c.drawString(45,y,fragment);y-=25
    qr=QrCodeWidget('AEROFLOW:TRAVEL:'+b['VoucherCode'],barWidth=170,barHeight=170);drawing=Drawing(170,170);drawing.add(qr)
    from reportlab.graphics import renderPDF
    renderPDF.draw(drawing,c,45,160);c.setFont(name,10);c.drawString(45,125,'Dữ liệu mô phỏng cho đồ án. Không có giá trị sử dụng thương mại.')
    c.save();out.seek(0);return send_file(out,mimetype='application/pdf',as_attachment=True,download_name='AeroFlow-'+b['Reference']+'.pdf')

@bp.post('/bookings/<int:bid>/payments')
@authenticated()
def pay(bid):
    d=body()
    if not isinstance(d.get('Success'),bool):raise ApiError('Kết quả mô phỏng phải là true hoặc false.')
    return jsonify(payment=query('EXEC dbo.sp_TravelPay ?,?,?,?,?',(g.user['UserID'],bid,text(d,'IdempotencyKey',8,80),d['Success'],decimal_value(d,'ExpectedAmount')),one=True))

@bp.post('/bookings/<int:bid>/cancel')
@authenticated()
def cancel(bid):
    return jsonify(booking=query('EXEC dbo.sp_TravelCancel ?,?,?',(g.user['UserID'],bid,text(body(),'IdempotencyKey',8,80)),one=True))

@bp.get('/bookings/<int:bid>/qr')
@authenticated()
def qr(bid):
    b=owned(bid)
    if b['Status']!='CONFIRMED' or b['VoucherStatus']!='ACTIVE':raise ApiError('Phiếu không còn hiệu lực.',409)
    drawing=Drawing(210,210)
    drawing.add(QrCodeWidget('AEROFLOW:TRAVEL:'+b['VoucherCode'],barWidth=210,barHeight=210))
    out=io.BytesIO(renderSVG.drawToString(drawing).encode('utf-8'))
    return send_file(out,mimetype='image/svg+xml',download_name=b['Reference']+'.svg')

@bp.post('/bookings/<int:bid>/review')
@authenticated()
def review(bid):
    b=owned(bid);d=body()
    if b['Status']!='CONFIRMED' or b['ServiceEndsAt']>datetime.now(timezone.utc).replace(tzinfo=None):raise ApiError('Bạn có thể đánh giá sau khi hoàn thành dịch vụ.',409)
    row=query('SET NOCOUNT ON; INSERT dbo.TravelReviews(BookingID,UserID,ProductID,Rating,Title,Comment) VALUES(?,?,?,?,?,?); SELECT CONVERT(int,SCOPE_IDENTITY()) ReviewID;',
     (bid,g.user['UserID'],b['ProductID'],integer(d,'Rating',1,5),text(d,'Title',3,150),text(d,'Comment',10,2000)),one=True)
    return jsonify(review=row),201

@bp.get('/coupons')
def coupons():
    return jsonify(items=query('SELECT Code,Title,Kind,Amount,MaxDiscount,MinSubtotal,ValidUntil,CategoryCode FROM dbo.TravelCoupons WHERE IsActive=1 AND SYSUTCDATETIME() BETWEEN ValidFrom AND ValidUntil ORDER BY CouponID'))

@bp.get('/wishlist')
@authenticated()
def wishlist():return jsonify(items=query('SELECT p.* FROM dbo.vw_TravelProducts p JOIN dbo.TravelWishlists w ON w.ProductID=p.ProductID WHERE w.UserID=? AND p.IsPublished=1 AND p.ProviderStatus=\'ACTIVE\' ORDER BY w.CreatedAt DESC',(g.user['UserID'],)))

@bp.route('/wishlist/<int:pid>',methods=['PUT','DELETE'])
@authenticated()
def wishlist_save(pid):
    if request.method=='DELETE':query('DELETE dbo.TravelWishlists WHERE UserID=? AND ProductID=?',(g.user['UserID'],pid))
    else:
        product_exists=query("SELECT ProductID FROM dbo.vw_TravelProducts WHERE ProductID=? AND IsPublished=1 AND ProviderStatus='ACTIVE'",(pid,),one=True)
        if not product_exists:raise ApiError('Dịch vụ không tồn tại.',404)
        query('IF NOT EXISTS(SELECT 1 FROM dbo.TravelWishlists WITH(UPDLOCK,HOLDLOCK) WHERE UserID=? AND ProductID=?) INSERT dbo.TravelWishlists(UserID,ProductID) VALUES(?,?)',(g.user['UserID'],pid,g.user['UserID'],pid))
    return jsonify(ok=True)

@bp.route('/cart',methods=['GET','POST'])
@authenticated()
def cart():
    if request.method=='GET':return jsonify(items=query('SELECT c.*,p.ProductID,p.Title,k.Name PackageName,p.ImagePath FROM dbo.TravelCart c JOIN dbo.TravelPackages k ON k.PackageID=c.PackageID JOIN dbo.vw_TravelProducts p ON p.ProductID=k.ProductID WHERE UserID=? ORDER BY CartID',(g.user['UserID'],)))
    d=body();s=selection(d);quote(s,g.user['UserID'])
    row=query('SET NOCOUNT ON; INSERT dbo.TravelCart(UserID,PackageID,StartDate,EndDate,SlotCode,Quantity,GuestCount) VALUES(?,?,?,?,?,?,?); SELECT CONVERT(int,SCOPE_IDENTITY()) CartID;',
       (g.user['UserID'],s['PackageID'],s['StartDate'],s['EndDate'],s['SlotCode'],s['Quantity'],s['GuestCount']),one=True)
    return jsonify(item=row),201

@bp.delete('/cart/<int:cid>')
@authenticated()
def cart_delete(cid):
    query('DELETE dbo.TravelCart WHERE CartID=? AND UserID=?',(cid,g.user['UserID']));return jsonify(ok=True)

@bp.route('/trips',methods=['GET','POST'])
@authenticated()
def trips():
    if request.method=='GET':return jsonify(items=query('SELECT * FROM dbo.TravelTrips WHERE UserID=? ORDER BY TripID DESC',(g.user['UserID'],)))
    d=body();row=query('SET NOCOUNT ON; INSERT dbo.TravelTrips(UserID,Name,StartDate,EndDate) VALUES(?,?,?,?); SELECT CONVERT(int,SCOPE_IDENTITY()) TripID;',
     (g.user['UserID'],text(d,'Name',3,150),iso_date(d.get('StartDate')),iso_date(d.get('EndDate'))),one=True)
    return jsonify(trip=row),201

@bp.route('/trips/<int:tid>/stops',methods=['GET','POST'])
@authenticated()
def stops(tid):
    t=query('SELECT * FROM dbo.TravelTrips WHERE TripID=? AND UserID=?',(tid,g.user['UserID']),one=True)
    if not t:raise ApiError('Không tìm thấy lịch trình.',404)
    if request.method=='GET':return jsonify(trip=t,items=query('SELECT * FROM dbo.TravelTripStops WHERE TripID=? ORDER BY VisitDate,SortOrder',(tid,)))
    d=body();visit=iso_date(d.get('VisitDate'))
    if not t['StartDate']<=visit<=t['EndDate']:raise ApiError('Ngày ghé thăm phải nằm trong lịch trình.')
    row=query('SET NOCOUNT ON; INSERT dbo.TravelTripStops(TripID,VisitDate,SortOrder,Name,Notes) VALUES(?,?,?,?,?); SELECT CONVERT(int,SCOPE_IDENTITY()) StopID;',
      (tid,visit,integer(d,'SortOrder',0,999),text(d,'Name',2,200),text(d,'Notes',0,1000)),one=True)
    return jsonify(stop=row),201

@bp.delete('/trips/<int:tid>/stops/<int:sid>')
@authenticated()
def stop_delete(tid,sid):
    query('DELETE s FROM dbo.TravelTripStops s JOIN dbo.TravelTrips t ON t.TripID=s.TripID WHERE s.StopID=? AND t.TripID=? AND t.UserID=?',(sid,tid,g.user['UserID']));return jsonify(ok=True)

@bp.route('/support',methods=['GET','POST'])
@authenticated()
def support():
    if request.method=='GET':return jsonify(items=query('SELECT * FROM dbo.TravelSupportTickets WHERE UserID=? ORDER BY TicketID DESC',(g.user['UserID'],)))
    d=body();bid=integer(d,'BookingID') if d.get('BookingID') else None
    if bid:owned(bid)
    with connection() as conn:
        tid=conn.execute('INSERT dbo.TravelSupportTickets(UserID,BookingID,Subject) OUTPUT INSERTED.TicketID VALUES(?,?,?)',g.user['UserID'],bid,text(d,'Subject',3,150)).fetchone()[0]
        conn.execute('INSERT dbo.TravelSupportMessages(TicketID,SenderID,Message) VALUES(?,?,?)',tid,g.user['UserID'],text(d,'Message',5,2000))
    return jsonify(TicketID=tid),201

@bp.route('/support/<int:tid>',methods=['GET','POST'])
@authenticated()
def support_thread(tid):
    t=query('SELECT * FROM dbo.TravelSupportTickets WHERE TicketID=? AND UserID=?',(tid,g.user['UserID']),one=True)
    if not t:raise ApiError('Không tìm thấy yêu cầu.',404)
    if request.method=='POST':
        if t['Status']=='CLOSED':raise ApiError('Yêu cầu đã đóng.',409)
        query('INSERT dbo.TravelSupportMessages(TicketID,SenderID,Message) VALUES(?,?,?); UPDATE dbo.TravelSupportTickets SET Status=\'OPEN\' WHERE TicketID=?',(tid,g.user['UserID'],text(body(),'Message',2,2000),tid))
    return jsonify(ticket=t,messages=query('SELECT m.*,u.FullName FROM dbo.TravelSupportMessages m JOIN dbo.Users u ON u.UserID=m.SenderID WHERE TicketID=? ORDER BY MessageID',(tid,)))

@bp.get('/articles')
def articles():return jsonify(items=query('SELECT ArticleID,Slug,Title,Summary,ImagePath FROM dbo.TravelArticles WHERE IsPublished=1 ORDER BY ArticleID'))

@bp.get('/articles/<int:aid>')
def article(aid):
    item=query('SELECT * FROM dbo.TravelArticles WHERE ArticleID=? AND IsPublished=1',(aid,),one=True)
    if not item:raise ApiError('Không tìm thấy bài viết.',404)
    return jsonify(article=item)

@bp.post('/provider/apply')
@authenticated()
def provider_apply():
    d=body()
    if query('SELECT ProviderID FROM dbo.TravelProviders WHERE OwnerUserID=?',(g.user['UserID'],),one=True):raise ApiError('Bạn đã gửi hồ sơ đối tác.',409)
    return jsonify(provider=query('SET NOCOUNT ON; INSERT dbo.TravelProviders(OwnerUserID,Name,Description,Status,IsDemo) VALUES(?,?,?,\'PENDING\',0); SELECT CONVERT(int,SCOPE_IDENTITY()) ProviderID;',
     (g.user['UserID'],text(d,'Name',3,150),text(d,'Description',10,1000)),one=True)),201

@bp.get('/provider')
@authenticated()
def provider_dashboard():
    provider=query('SELECT * FROM dbo.TravelProviders WHERE OwnerUserID=?',(g.user['UserID'],),one=True)
    if not provider:return jsonify(provider=None,products=[],bookings=[])
    if provider['Status']!='ACTIVE':return jsonify(provider=provider,products=[],bookings=[])
    return jsonify(provider=provider,products=query('SELECT * FROM dbo.vw_TravelProducts WHERE ProviderID=? ORDER BY ProductID DESC',(provider['ProviderID'],)),
      bookings=query("SELECT TOP(300) b.BookingID,b.Reference,b.ProductTitle,b.StartDate,b.EndDate,b.Quantity,b.GuestCount,b.Status,b.ContactName,b.ContactPhone,b.Total FROM dbo.TravelBookings b JOIN dbo.TravelProducts p ON p.ProductID=b.ProductID WHERE p.ProviderID=? AND b.Status='CONFIRMED' ORDER BY b.CreatedAt DESC",(provider['ProviderID'],)))
