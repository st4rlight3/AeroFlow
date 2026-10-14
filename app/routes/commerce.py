import json
import re
from flask import Blueprint,g,jsonify,request
from ..db import query
from ..security import authenticated
from ..errors import ApiError
from ..validation import body,integer,text,decimal_value,utc_datetime
from ..services.booking_service import owned_booking
from .customer import ticket_details

bp=Blueprint('commerce',__name__,url_prefix='/api')

@bp.get('/services')
def services(): return jsonify(items=query('SELECT * FROM dbo.Services WHERE IsActive=1 ORDER BY ServiceID'))

@bp.get('/bookings/<int:booking_id>/options')
@authenticated()
def options(booking_id):
    b=owned_booking(booking_id,g.user)
    tickets=query('SELECT t.TicketID,t.TicketNumber,t.Amount,t.Status,p.FullName,f.FlightNumber,dbo.fn_TicketPaidValue(t.TicketID) PaidValue,dbo.fn_TicketRefundValue(t.TicketID) RefundValue FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Passengers p ON p.PassengerID=bp.PassengerID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID JOIN dbo.Flights f ON f.FlightID=a.FlightID WHERE bp.BookingID=? ORDER BY t.TicketID',(booking_id,))
    extras=query('SELECT e.* FROM dbo.BookingExtras e JOIN dbo.Tickets t ON t.TicketID=e.TicketID JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID WHERE bp.BookingID=?',(booking_id,))
    return jsonify(booking=b,tickets=tickets,extras=extras,discount=query('SELECT Code,Amount FROM dbo.BookingDiscounts WHERE BookingID=?',(booking_id,),one=True),points=query('SELECT Points,Amount FROM dbo.LoyaltySpends WHERE BookingID=?',(booking_id,),one=True))

@bp.put('/bookings/<int:booking_id>/options')
@authenticated()
def save_options(booking_id):
    owned_booking(booking_id,g.user);d=body();extras=d.get('Extras',[]);code=d.get('Code','')
    if not isinstance(extras,list) or len(extras)>540 or any(not isinstance(x,dict) for x in extras): raise ApiError('Danh sách dịch vụ không hợp lệ.')
    if not isinstance(code,str) or (code and not re.fullmatch('[A-Za-z0-9-]{3,30}',code)): raise ApiError('Mã giảm giá không hợp lệ.')
    normalized=[dict(TicketID=integer(x,'TicketID'),ServiceID=integer(x,'ServiceID'),Quantity=integer(x,'Quantity',1,5)) for x in extras]
    if len({(x['TicketID'],x['ServiceID']) for x in normalized})!=len(normalized): raise ApiError('Không lặp dịch vụ trên cùng vé.')
    points=integer(d,'Points',0,1000000) if 'Points' in d else 0
    return jsonify(price=query('EXEC dbo.sp_SetBookingOptions ?,?,?,?,?',(g.user['UserID'],booking_id,json.dumps(normalized),code.upper() or None,points),one=True))

@bp.post('/tickets/<int:ticket_id>/cancel')
@authenticated()
def cancel_ticket(ticket_id):
    ticket_details(ticket_id)
    d=body(); method=d.get('RefundMethod','MOCK')
    if method not in ('MOCK','CREDIT'): raise ApiError('Cách hoàn tiền không hợp lệ.')
    return jsonify(refund=query('EXEC dbo.sp_CancelTicket ?,?,?',(g.user['UserID'],ticket_id,method=='CREDIT'),one=True))

@bp.get('/wallet')
@authenticated()
def wallet():
    return jsonify(balance=query('SELECT COALESCE(SUM(Amount),0) Balance FROM dbo.TravelCreditLedger WHERE UserID=?',(g.user['UserID'],),one=True)['Balance'],items=query('SELECT TOP(100) c.Amount,c.CreatedAt,p.Kind,b.PNR FROM dbo.TravelCreditLedger c JOIN dbo.Payments p ON p.PaymentID=c.PaymentID JOIN dbo.Bookings b ON b.BookingID=p.BookingID WHERE c.UserID=? ORDER BY c.CreditID DESC',(g.user['UserID'],)))

@bp.get('/bookings/<int:booking_id>/changes')
@authenticated()
def changes(booking_id):
    owned_booking(booking_id,g.user)
    return jsonify(items=query('SELECT c.*,fo.FlightNumber OldFlight,fn.FlightNumber NewFlight FROM dbo.BookingChanges c JOIN dbo.BookingSegments so ON so.BookingSegmentID=c.OldSegmentID JOIN dbo.Flights fo ON fo.FlightID=so.FlightID JOIN dbo.BookingSegments sn ON sn.BookingSegmentID=c.NewSegmentID JOIN dbo.Flights fn ON fn.FlightID=sn.FlightID WHERE c.BookingID=? ORDER BY c.ChangeID',(booking_id,)))

@bp.post('/segments/<int:segment_id>/exchange-quote')
@authenticated()
def exchange_price(segment_id):
    from ..services.exchange import quote_exchange
    d=body();return jsonify(quote_exchange(segment_id,integer(d,'FlightID'),integer(d,'FareClassID'),g.user))

@bp.post('/segments/<int:segment_id>/exchange')
@authenticated()
def exchange(segment_id):
    d=body()
    return jsonify(change=query('EXEC dbo.sp_ExchangeSegment ?,?,?,?,?,?',(g.user['UserID'],segment_id,integer(d,'FlightID'),integer(d,'FareClassID'),text(d,'IdempotencyKey',16,80),decimal_value(d,'ExpectedDifference',-1000000000,1000000000)),one=True))

@bp.get('/admin/discount-codes')
@authenticated(admin=True)
def discount_codes(): return jsonify(items=query('SELECT * FROM dbo.DiscountCodes ORDER BY DiscountCodeID DESC'))

@bp.route('/admin/discount-codes',methods=['POST'])
@bp.route('/admin/discount-codes/<int:code_id>',methods=['PUT'])
@authenticated(admin=True)
def save_code(code_id=None):
    d=body();code=text(d,'Code',3,30).upper();kind=d.get('Kind');method=d.get('Method')
    if not re.fullmatch('[A-Z0-9-]+',code) or kind not in ('PROMO','VOUCHER') or method not in ('PERCENT','FIXED') or type(d.get('IsActive')) is not bool: raise ApiError('Thông tin mã giảm giá không hợp lệ.')
    values=(code,kind,method,decimal_value(d,'Value',.01,50 if method=='PERCENT' else 10000000),decimal_value(d,'MaxDiscount',.01,10000000),decimal_value(d,'MinimumSpend',0,100000000),utc_datetime(d.get('ValidFrom')),utc_datetime(d.get('ValidTo')),integer(d,'MaxUses',1,1000000),d['IsActive'])
    if values[7]<=values[6]: raise ApiError('Thời gian kết thúc phải sau thời gian bắt đầu.')
    if code_id:
        row=query('UPDATE dbo.DiscountCodes SET Code=?,Kind=?,Method=?,Value=?,MaxDiscount=?,MinimumSpend=?,ValidFrom=?,ValidTo=?,MaxUses=?,IsActive=? OUTPUT inserted.DiscountCodeID WHERE DiscountCodeID=?',values+(code_id,),one=True)
        if not row: raise ApiError('Không tìm thấy mã giảm giá.',404)
    else: row=query('INSERT dbo.DiscountCodes(Code,Kind,Method,Value,MaxDiscount,MinimumSpend,ValidFrom,ValidTo,MaxUses,IsActive) OUTPUT inserted.DiscountCodeID VALUES(?,?,?,?,?,?,?,?,?,?)',values,one=True)
    return jsonify(result=row)
