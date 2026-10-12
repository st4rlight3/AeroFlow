from datetime import datetime, time, timedelta
from flask import Blueprint, jsonify, request
from ..db import query
from ..errors import ApiError
from ..validation import iso_date, integer

bp = Blueprint('flights', __name__, url_prefix='/api')

@bp.get('/health')
def health():
    query('SELECT 1 Ready')
    return jsonify(status='ok', database='Microsoft SQL Server')

@bp.get('/airports')
def airports():
    return jsonify(items=query('SELECT AirportID,Code,Name,City FROM dbo.Airports WHERE IsActive=1 ORDER BY City'))

@bp.get('/discovery')
def discovery():
    return jsonify(items=query("SELECT TOP(6) OriginID,DestinationID,OriginCode,DestinationCode,OriginCity,DestinationCity,MIN(FromPrice) FromPrice,MIN(DepartureTime) NextDeparture,COUNT(*) FlightCount FROM dbo.vw_FlightAvailability WHERE Status='SCHEDULED' AND DepartureTime>DATEADD(hour,2,SYSUTCDATETIME()) AND AvailableSeats>0 AND FromPrice IS NOT NULL GROUP BY OriginID,DestinationID,OriginCode,DestinationCode,OriginCity,DestinationCity ORDER BY COUNT(*) DESC,OriginCode,DestinationCode"))

@bp.get('/flights')
def search():
    d = request.args
    origin, dest, count = integer(d, 'origin'), integer(d, 'destination'), integer(d, 'passengers', 1, 9)
    if origin == dest:
        raise ApiError('Điểm đi và điểm đến phải khác nhau.')
    date = iso_date(d.get('date'))
    # Vietnamese civil day converted into UTC half-open interval.
    start = datetime.combine(date, time.min) - timedelta(hours=7)
    return jsonify(items=query("SELECT * FROM dbo.vw_FlightAvailability WHERE OriginID=? AND DestinationID=? AND DepartureTime>=? AND DepartureTime<? AND DepartureTime>DATEADD(hour,2,SYSUTCDATETIME()) AND Status='SCHEDULED' AND AvailableSeats>=? ORDER BY DepartureTime", (origin, dest, start, start+timedelta(days=1), count)))

@bp.get('/flights/<int:flight_id>')
def details(flight_id):
    f = query('SELECT * FROM dbo.vw_FlightAvailability WHERE FlightID=?', (flight_id,), one=True)
    if not f:
        raise ApiError('Không tìm thấy chuyến bay.', 404)
    fares = query('SELECT c.*,ff.BasePrice,ff.TaxRate,dbo.fn_CalculateTicketPrice(ff.BasePrice,ff.TaxRate) Price FROM dbo.FlightFares ff JOIN dbo.FareClasses c ON c.FareClassID=ff.FareClassID WHERE ff.FlightID=? ORDER BY Price', (flight_id,))
    return jsonify(flight=f, fares=fares)

@bp.get('/flights/<int:flight_id>/seats')
def seats(flight_id):
    if not query('SELECT FlightID FROM dbo.Flights WHERE FlightID=?', (flight_id,), one=True):
        raise ApiError('Không tìm thấy chuyến bay.', 404)
    return jsonify(items=query('EXEC dbo.sp_GetAvailableSeats ?', (flight_id,)))
