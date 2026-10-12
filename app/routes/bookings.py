from flask import Blueprint, g, jsonify
from ..db import query
from ..security import authenticated
from ..validation import body, text
from ..errors import ApiError
from ..services.booking_service import create_booking, owned_booking

bp = Blueprint('bookings', __name__, url_prefix='/api/bookings')

@bp.post('')
@authenticated()
def create():
    return jsonify(booking=create_booking(body(), g.user['UserID'])), 201

@bp.get('')
@authenticated()
def history():
    # Cleanup only this customer's flights, with the same SQL lock discipline.
    ids = query("SELECT DISTINCT FlightID FROM dbo.Bookings WHERE UserID=? AND Status='HELD' AND ExpiresAt<=SYSUTCDATETIME()", (g.user['UserID'],))
    for row in ids:
        query('EXEC dbo.sp_ExpireFlightHolds ?', (row['FlightID'],))
    return jsonify(items=query('SELECT * FROM dbo.vw_BookingDetails WHERE UserID=? ORDER BY CreatedAt DESC', (g.user['UserID'],)))

@bp.get('/<int:booking_id>')
@authenticated()
def detail(booking_id):
    b = owned_booking(booking_id, g.user)
    tickets = query('SELECT t.TicketID,t.TicketNumber,t.Amount,t.Status,t.RefundPercent,p.FullName,p.DateOfBirth,RIGHT(p.DocumentNumber,4) DocumentLast4,c.Name FareName,c.BaggageKg,s.SeatNumber FROM dbo.BookingPassengers bp JOIN dbo.Passengers p ON p.PassengerID=bp.PassengerID JOIN dbo.Tickets t ON t.BookingPassengerID=bp.BookingPassengerID JOIN dbo.FareClasses c ON c.FareClassID=bp.FareClassID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID JOIN dbo.AircraftSeats s ON s.SeatID=a.SeatID WHERE bp.BookingID=? ORDER BY t.TicketID', (booking_id,))
    payments = query('SELECT PaymentID,Amount,Kind,Status,CreatedAt FROM dbo.Payments WHERE BookingID=? ORDER BY PaymentID', (booking_id,))
    return jsonify(booking=b, tickets=tickets, payments=payments)

@bp.post('/<int:booking_id>/payments')
@authenticated()
def pay(booking_id):
    owned_booking(booking_id, g.user)
    d = body()
    if type(d.get('Success')) is not bool:
        raise ApiError('Success phải là true hoặc false cho thanh toán giả lập.')
    return jsonify(payment=query('EXEC dbo.sp_ConfirmPayment ?,?,?,?', (g.user['UserID'], booking_id, text(d, 'IdempotencyKey', 16, 80), d['Success']), one=True))

@bp.post('/<int:booking_id>/cancel')
@authenticated()
def cancel(booking_id):
    owned_booking(booking_id, g.user)
    return jsonify(result=query('EXEC dbo.sp_CancelBooking ?,?', (g.user['UserID'], booking_id), one=True))
