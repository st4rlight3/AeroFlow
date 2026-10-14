import hashlib
import re
from datetime import date
from flask import Blueprint, g, jsonify, request, session, send_file
from werkzeug.security import check_password_hash, generate_password_hash
from ..db import connection, query
from ..errors import ApiError
from ..security import authenticated, throttle_login, csrf_token
from ..validation import body, text, iso_date, utc_datetime
from ..services.booking_service import owned_booking
from ..services.documents import ticket_pdf

bp=Blueprint('customer',__name__,url_prefix='/api')
ASSISTANCE=('NONE','WHEELCHAIR','HEARING','VISION')

@bp.get('/travellers')
@authenticated()
def travellers():
    return jsonify(items=query('SELECT TravellerID,FullName,DateOfBirth,DocumentNumber,Assistance FROM dbo.SavedTravellers WHERE UserID=? ORDER BY TravellerID',(g.user['UserID'],)))

@bp.route('/travellers',methods=['POST'])
@bp.route('/travellers/<int:traveller_id>',methods=['PUT','DELETE'])
@authenticated()
def save_traveller(traveller_id=None):
    uid=g.user['UserID']
    if request.method=='DELETE':
        rows=query('DELETE dbo.SavedTravellers OUTPUT deleted.TravellerID WHERE TravellerID=? AND UserID=?',(traveller_id,uid))
        if not rows: raise ApiError('Không tìm thấy hành khách đã lưu.',404)
        return jsonify(message='Đã xóa hành khách lưu sẵn. Vé đã đặt giữ nguyên thông tin.')
    d=body(); name=text(d,'FullName',2); dob=iso_date(d.get('DateOfBirth')); doc=text(d,'DocumentNumber',5,30); assistance=d.get('Assistance','NONE')
    if dob>date.today() or dob.year<1900 or assistance not in ASSISTANCE: raise ApiError('Ngày sinh hoặc hỗ trợ đặc biệt không hợp lệ.')
    with connection() as conn:
        if traveller_id:
            row=conn.execute('UPDATE dbo.SavedTravellers SET FullName=?,DateOfBirth=?,DocumentNumber=?,Assistance=? OUTPUT inserted.TravellerID WHERE TravellerID=? AND UserID=?',name,dob,doc,assistance,traveller_id,uid).fetchone()
            if not row: raise ApiError('Không tìm thấy hành khách đã lưu.',404)
        else:
            if conn.execute('SELECT COUNT(*) FROM dbo.SavedTravellers WITH(UPDLOCK,HOLDLOCK) WHERE UserID=?',uid).fetchone()[0]>=20: raise ApiError('Tối đa 20 hành khách lưu sẵn.')
            row=conn.execute('INSERT dbo.SavedTravellers(UserID,FullName,DateOfBirth,DocumentNumber,Assistance) OUTPUT inserted.TravellerID VALUES(?,?,?,?,?)',uid,name,dob,doc,assistance).fetchone()
    return jsonify(id=row[0]),201 if not traveller_id else 200

@bp.route('/preferences',methods=['GET','PUT'])
@authenticated()
def preferences():
    uid=g.user['UserID']
    if request.method=='PUT':
        d=body()
        if d.get('PreferredCabin') not in ('ECONOMY','PREMIUM','BUSINESS','FIRST') or d.get('SeatPreference') not in ('ANY','WINDOW','AISLE') or type(d.get('Reminders')) is not bool: raise ApiError('Tùy chọn không hợp lệ.')
        with connection() as conn:
            conn.execute('SELECT UserID FROM dbo.Users WITH(UPDLOCK,HOLDLOCK) WHERE UserID=?',uid).fetchone()
            if not conn.execute('SELECT UserID FROM dbo.UserPreferences WHERE UserID=?',uid).fetchone(): conn.execute('INSERT dbo.UserPreferences(UserID) VALUES(?)',uid)
            email_notify=d.get('EmailNotifications',False)
            if type(email_notify) is not bool: raise ApiError('Tùy chọn email cần là true/false.')
            conn.execute('UPDATE dbo.UserPreferences SET PreferredCabin=?,SeatPreference=?,Reminders=?,EmailNotifications=? WHERE UserID=?',d['PreferredCabin'],d['SeatPreference'],d['Reminders'],email_notify,uid)
    return jsonify(preferences=query("SELECT COALESCE(p.PreferredCabin,'ECONOMY') PreferredCabin,COALESCE(p.SeatPreference,'ANY') SeatPreference,COALESCE(p.Reminders,1) Reminders,COALESCE(p.EmailNotifications,0) EmailNotifications FROM dbo.Users u LEFT JOIN dbo.UserPreferences p ON p.UserID=u.UserID WHERE u.UserID=?",(uid,),one=True))

@bp.post('/auth/change-password')
@authenticated()
def change_password():
    throttle_login(); d=body(); old=text(d,'CurrentPassword',1,128); new=text(d,'NewPassword',12,128)
    with connection() as conn:
        row=conn.execute('SELECT PasswordHash FROM dbo.Users WITH(UPDLOCK,HOLDLOCK) WHERE UserID=?',g.user['UserID']).fetchone()
        if not check_password_hash(row[0],old): raise ApiError('Mật khẩu hiện tại không đúng.',401)
        conn.execute('UPDATE dbo.Users SET PasswordHash=?,SessionVersion=SessionVersion+1 WHERE UserID=?',generate_password_hash(new,method='scrypt'),g.user['UserID'])
        conn.execute('UPDATE dbo.PasswordResetTokens SET UsedAt=SYSUTCDATETIME() WHERE UserID=? AND UsedAt IS NULL',g.user['UserID'])
    session.clear()
    return jsonify(message='Đã đổi mật khẩu. Vui lòng đăng nhập lại trên các thiết bị.',csrf=csrf_token())

@bp.post('/auth/reset-password')
def reset_password():
    throttle_login(); d=body(); token=text(d,'Token',32,120); password=text(d,'NewPassword',12,128)
    digest=hashlib.sha256(token.encode()).hexdigest()
    with connection() as conn:
        # Lock user first: same order as change-password and the recovery CLI.
        uid=conn.execute('SELECT UserID FROM dbo.PasswordResetTokens WHERE TokenHash=?',digest).fetchone()
        if not uid: raise ApiError('Mã khôi phục không hợp lệ hoặc đã hết hạn.',400)
        conn.execute('SELECT UserID FROM dbo.Users WITH(UPDLOCK,HOLDLOCK) WHERE UserID=?',uid[0]).fetchone()
        row=conn.execute('SELECT t.UserID FROM dbo.PasswordResetTokens t JOIN dbo.Users u ON u.UserID=t.UserID WHERE t.TokenHash=? AND t.UsedAt IS NULL AND t.ExpiresAt>SYSUTCDATETIME() AND u.IsActive=1',digest).fetchone()
        if not row: raise ApiError('Mã khôi phục không hợp lệ hoặc đã hết hạn.',400)
        conn.execute('UPDATE dbo.Users SET PasswordHash=?,SessionVersion=SessionVersion+1 WHERE UserID=?',generate_password_hash(password,method='scrypt'),row[0])
        conn.execute('UPDATE dbo.PasswordResetTokens SET UsedAt=SYSUTCDATETIME() WHERE UserID=? AND UsedAt IS NULL',row[0])
    session.clear()
    return jsonify(message='Đã đặt lại mật khẩu. Vui lòng đăng nhập.',csrf=csrf_token())

@bp.get('/notifications')
@authenticated()
def notifications():
    return jsonify(items=query('SELECT TOP(100) * FROM dbo.Notifications WHERE UserID=? ORDER BY NotificationID DESC',(g.user['UserID'],)))

@bp.put('/notifications/<int:notification_id>/read')
@authenticated()
def read_notification(notification_id):
    rows=query('UPDATE dbo.Notifications SET IsRead=1 OUTPUT inserted.NotificationID WHERE NotificationID=? AND UserID=?',(notification_id,g.user['UserID']))
    if not rows: raise ApiError('Không tìm thấy thông báo.',404)
    return jsonify(message='Đã đánh dấu đã đọc.')

@bp.get('/loyalty')
@authenticated()
def loyalty():
    return jsonify(summary=query('SELECT * FROM dbo.vw_LoyaltySummary WHERE UserID=?',(g.user['UserID'],),one=True),tiers=query('SELECT * FROM dbo.LoyaltyTiers ORDER BY MinimumPoints'),items=query('SELECT TOP(100) l.Points,l.Reason,l.CreatedAt,b.PNR FROM dbo.LoyaltyLedger l JOIN dbo.Payments p ON p.PaymentID=l.PaymentID JOIN dbo.Bookings b ON b.BookingID=p.BookingID WHERE l.UserID=? ORDER BY l.LoyaltyID DESC',(g.user['UserID'],)))

@bp.get('/bookings/lookup')
@authenticated()
def lookup():
    pnr=request.args.get('pnr','').strip().upper()
    if not re.fullmatch('[A-Z0-9]{8}',pnr): raise ApiError('Mã PNR gồm 8 chữ hoặc số.')
    row=query('SELECT BookingID FROM dbo.Bookings WHERE PNR=? AND UserID=?',(pnr,g.user['UserID']),one=True)
    if not row: raise ApiError('Không tìm thấy đặt chỗ trong tài khoản của bạn.',404)
    return jsonify(booking=row)

def ticket_details(ticket_id):
    row=query('''SELECT t.TicketID,t.TicketNumber,t.Status TicketStatus,t.Amount,t.BaseFare,t.TaxAmount,t.SeatFee,t.BreakdownSource,
      b.BookingID,b.PNR,b.UserID,b.Status BookingStatus,p.FullName,p.Assistance,s.SeatNumber,fc.Name FareName,
      f.FlightID,f.FlightNumber,f.DepartureTime,f.ArrivalTime,f.EstimatedDeparture,f.Gate,f.OperationNote,f.Status FlightStatus,
      o.Code OriginCode,d.Code DestinationCode,ci.Reference,ci.Status CheckInStatus,ci.CheckedInAt,ci.BoardedAt,
      dbo.fn_TicketPaidValue(t.TicketID) PaidValue,
      COALESCE((SELECT SUM(e.Quantity*e.UnitPrice) FROM dbo.BookingExtras e WHERE e.TicketID=t.TicketID),0) ExtrasAmount,
      COALESCE((SELECT td.Amount FROM dbo.TicketDiscounts td WHERE td.TicketID=t.TicketID),0) DiscountAmount,
      CASE WHEN t.Status='VALID' AND b.Status='CONFIRMED' AND a.IsActive=1 AND f.Status IN ('SCHEDULED','BOARDING')
      AND SYSUTCDATETIME()>=DATEADD(hour,-24,COALESCE(f.EstimatedDeparture,f.DepartureTime)) AND SYSUTCDATETIME()<DATEADD(hour,-1,COALESCE(f.EstimatedDeparture,f.DepartureTime)) THEN 1 ELSE 0 END Eligible
      FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Bookings b ON b.BookingID=bp.BookingID
      JOIN dbo.Passengers p ON p.PassengerID=bp.PassengerID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID
      JOIN dbo.AircraftSeats s ON s.SeatID=a.SeatID JOIN dbo.Flights f ON f.FlightID=a.FlightID JOIN dbo.FareClasses fc ON fc.FareClassID=t.FareClassID
      JOIN dbo.Airports o ON o.AirportID=f.OriginID JOIN dbo.Airports d ON d.AirportID=f.DestinationID LEFT JOIN dbo.CheckIns ci ON ci.TicketID=t.TicketID
      WHERE t.TicketID=?''',(ticket_id,),one=True)
    if not row or (row['UserID']!=g.user['UserID'] and g.user['Role']!='ADMIN'): raise ApiError('Không tìm thấy vé.',404)
    if row.get('Reference'): row['Reference']=str(row['Reference'])
    return row

@bp.get('/tickets/<int:ticket_id>')
@authenticated()
def ticket(ticket_id): return jsonify(ticket=ticket_details(ticket_id))

@bp.post('/tickets/<int:ticket_id>/check-in')
@authenticated()
def check_in(ticket_id):
    row=query('EXEC dbo.sp_CheckIn ?,?',(g.user['UserID'],ticket_id),one=True)
    row['Reference']=str(row['Reference'])
    return jsonify(checkin=row)

@bp.get('/tickets/<int:ticket_id>/pdf')
@authenticated()
def pdf(ticket_id):
    row=ticket_details(ticket_id); boarding=request.args.get('type')=='boarding'
    if row['TicketStatus']!='VALID' or row['BookingStatus']!='CONFIRMED': raise ApiError('Vé chưa có hiệu lực.',409)
    if boarding and (row['CheckInStatus']!='ACTIVE' or row['FlightStatus']=='CANCELLED'): raise ApiError('Cần check-in hợp lệ để tải thẻ lên máy bay.',409)
    return send_file(ticket_pdf(row,boarding),mimetype='application/pdf',as_attachment=True,download_name=f"AeroFlow_{'Boarding' if boarding else 'Ticket'}_{row['TicketNumber']}.pdf")

@bp.get('/flights/status')
def flight_status():
    number=request.args.get('number','').strip().upper()
    if not re.fullmatch('[A-Z0-9]{3,8}',number): raise ApiError('Nhập mã chuyến bay từ 3 đến 8 ký tự.')
    return jsonify(items=query('SELECT TOP(30) f.FlightNumber,f.DepartureTime,f.ArrivalTime,f.EstimatedDeparture,f.Gate,f.OperationNote,f.Status,o.Code OriginCode,d.Code DestinationCode FROM dbo.Flights f JOIN dbo.Airports o ON o.AirportID=f.OriginID JOIN dbo.Airports d ON d.AirportID=f.DestinationID WHERE f.FlightNumber=? ORDER BY f.DepartureTime DESC',(number,)))

@bp.put('/admin/flights/<int:flight_id>/operations')
@authenticated(admin=True)
def operations(flight_id):
    d=body(); gate=str(d.get('Gate','')).strip(); note=str(d.get('OperationNote','')).strip()
    estimated=utc_datetime(d['EstimatedDeparture']) if d.get('EstimatedDeparture') else None
    if len(gate)>12 or len(note)>300: raise ApiError('Cửa tối đa 12 ký tự; ghi chú tối đa 300 ký tự.')
    with connection() as conn:
        conn.execute('EXEC dbo.sp_LockFlight 0')
        row=conn.execute('SELECT DepartureTime,Status FROM dbo.Flights WHERE FlightID=?',flight_id).fetchone()
        if not row: raise ApiError('Không tìm thấy chuyến bay.',404)
        if row[1] not in ('SCHEDULED','BOARDING'): raise ApiError('Chuyến bay đã kết thúc hoặc bị hủy.',409)
        if estimated and not 0<=(estimated-row[0]).total_seconds()<=86400: raise ApiError('Giờ dự kiến phải từ giờ lịch đến tối đa 24 giờ sau lịch.')
        conn.execute('UPDATE dbo.Flights SET Gate=?,EstimatedDeparture=?,OperationNote=? WHERE FlightID=?',gate or None,estimated,note or None,flight_id)
    return jsonify(message='Đã cập nhật khai thác và thông báo cho khách.')

@bp.get('/admin/check-ins')
@authenticated(admin=True)
def checkins():
    return jsonify(items=query('SELECT TOP(300) c.CheckInID,c.TicketID,CONVERT(varchar(36),c.Reference) Reference,c.Status,c.CheckedInAt,c.RevokedAt,c.BoardedAt,b.PNR,p.FullName,f.FlightNumber,s.SeatNumber FROM dbo.CheckIns c JOIN dbo.Tickets t ON t.TicketID=c.TicketID JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Bookings b ON b.BookingID=bp.BookingID JOIN dbo.Passengers p ON p.PassengerID=bp.PassengerID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID JOIN dbo.Flights f ON f.FlightID=a.FlightID JOIN dbo.AircraftSeats s ON s.SeatID=a.SeatID ORDER BY c.CheckInID DESC'))

@bp.post('/admin/reminders')
@authenticated(admin=True)
def reminders(): return jsonify(result=query('EXEC dbo.sp_GenerateReminders',one=True))
