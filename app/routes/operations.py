import uuid
from flask import Blueprint,g,jsonify,request,send_file
from ..db import query
from ..security import authenticated
from ..errors import ApiError
from ..validation import body,iso_date,text
from ..services.documents import report_pdf
from datetime import date,timedelta

bp=Blueprint('operations',__name__,url_prefix='/api')

@bp.get('/admin/passengers')
@authenticated(admin=True)
def passengers():
    return jsonify(items=query('SELECT TOP(500) p.PassengerID,p.FullName,p.DateOfBirth,RIGHT(p.DocumentNumber,4) DocumentLast4,p.Assistance,b.PNR,b.Status FROM dbo.Passengers p JOIN dbo.BookingPassengers bp ON bp.PassengerID=p.PassengerID JOIN dbo.Bookings b ON b.BookingID=bp.BookingID ORDER BY p.PassengerID DESC'))

@bp.get('/admin/loyalty')
@authenticated(admin=True)
def loyalty():
    return jsonify(items=query('SELECT TOP(500) u.FullName,u.Email,l.Points,l.AvailablePoints,l.TierName FROM dbo.vw_LoyaltySummary l JOIN dbo.Users u ON u.UserID=l.UserID ORDER BY l.Points DESC'))

@bp.post('/admin/check-ins/<int:checkin_id>/board')
@authenticated(admin=True)
def board(checkin_id):
    row=query('EXEC dbo.sp_BoardPassenger ?,?',(g.user['UserID'],checkin_id),one=True);row['Reference']=str(row['Reference']);return jsonify(checkin=row)

@bp.post('/admin/check-ins/verify')
@authenticated(admin=True)
def verify():
    value=text(body(),'Reference',1,80).removeprefix('AEROFLOW-DEMO:')
    try: ref=str(uuid.UUID(value))
    except ValueError: raise ApiError('Mã QR mô phỏng không hợp lệ.') from None
    row=query('SELECT c.CheckInID,c.Status,c.BoardedAt,t.TicketNumber,t.Status TicketStatus,f.FlightNumber,f.Status FlightStatus,p.FullName,s.SeatNumber FROM dbo.CheckIns c JOIN dbo.Tickets t ON t.TicketID=c.TicketID JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Passengers p ON p.PassengerID=bp.PassengerID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID JOIN dbo.Flights f ON f.FlightID=a.FlightID JOIN dbo.AircraftSeats s ON s.SeatID=a.SeatID WHERE c.Reference=?',(ref,),one=True)
    if not row: raise ApiError('Không tìm thấy mã check-in.',404)
    return jsonify(checkin=row)

@bp.get('/payments/<int:payment_id>/receipt')
@authenticated()
def receipt(payment_id):
    row=query('SELECT p.*,b.PNR,b.UserID,u.FullName FROM dbo.Payments p JOIN dbo.Bookings b ON b.BookingID=p.BookingID JOIN dbo.Users u ON u.UserID=b.UserID WHERE p.PaymentID=?',(payment_id,),one=True)
    if not row or (row['UserID']!=g.user['UserID'] and g.user['Role']!='ADMIN'): raise ApiError('Không tìm thấy giao dịch.',404)
    rows=[['Mã giao dịch',row['PaymentID']],['Mã đặt chỗ',row['PNR']],['Khách hàng',row['FullName']],['Loại',row['Kind']],['Trạng thái',row['Status']],['Hình thức',row['Settlement']],['Số tiền',f"{row['Amount']:,.0f} VND"],['Thời gian UTC',row['CreatedAt']]]
    return send_file(report_pdf('Biên nhận giao dịch mô phỏng',['Nội dung','Chi tiết'],rows),mimetype='application/pdf',as_attachment=True,download_name=f'AeroFlow_Receipt_{payment_id}.pdf')

@bp.get('/admin/reports/revenue.pdf')
@authenticated(admin=True)
def revenue_pdf():
    start=iso_date(request.args.get('from',(date.today()-timedelta(days=30)).isoformat()));end=iso_date(request.args.get('to',date.today().isoformat()))
    if start>end or (end-start).days>366: raise ApiError('Khoảng ngày không hợp lệ, tối đa 366 ngày.')
    rows=query('EXEC dbo.sp_GetRevenueReport ?,?',(start,end))
    return send_file(report_pdf('Doanh thu '+start.isoformat()+' — '+end.isoformat(),['Ngày UTC','Tiền thu','Hoàn tiền','Doanh thu ròng'],[[r['Date'],r['GrossRevenue'],r['Refunds'],r['NetRevenue']] for r in rows]),mimetype='application/pdf',as_attachment=True,download_name='AeroFlow_Revenue.pdf')
