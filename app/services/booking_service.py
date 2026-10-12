import json
from datetime import date
from ..db import query
from ..errors import ApiError
from ..validation import text, integer, iso_date

def owned_booking(booking_id, user):
    b = query('SELECT * FROM dbo.vw_BookingDetails WHERE BookingID=? AND (UserID=? OR ?=1)', (booking_id, user['UserID'], int(user['Role']=='ADMIN')), one=True)
    if not b:
        raise ApiError('Không tìm thấy đơn đặt vé.', 404, 'NOT_FOUND')
    query('EXEC dbo.sp_ExpireFlightHolds ?', (b['FlightID'],))
    return query('SELECT * FROM dbo.vw_BookingDetails WHERE BookingID=?', (booking_id,), one=True)

def create_booking(data, uid):
    flight_id = integer(data, 'FlightID')
    passengers = data.get('Passengers')
    if not isinstance(passengers, list) or not 1 <= len(passengers) <= 9:
        raise ApiError('Cần từ 1 đến 9 hành khách.')
    clean = []
    for p in passengers:
        if not isinstance(p, dict):
            raise ApiError('Thông tin hành khách không hợp lệ.')
        dob = iso_date(p.get('DateOfBirth'))
        if not date(1900, 1, 1) <= dob <= date.today():
            raise ApiError('Ngày sinh không hợp lệ.')
        clean.append(dict(SeatID=integer(p, 'SeatID'), FareClassID=integer(p, 'FareClassID'),
                          FullName=text(p, 'FullName', 2), DateOfBirth=dob.isoformat(), DocumentNumber=text(p, 'DocumentNumber', 5, 30)))
    return query('EXEC dbo.sp_CreateBooking @UserID=?,@FlightID=?,@Passengers=?', (uid, flight_id, json.dumps(clean, ensure_ascii=False)), one=True)
