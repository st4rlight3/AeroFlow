from datetime import datetime, time, timedelta
from flask import Blueprint, jsonify, request
from ..db import query
from ..errors import ApiError
from ..validation import iso_date, integer

bp = Blueprint('flights', __name__, url_prefix='/api')

# A fare is sellable only when its cabin has enough free seats for the party.
# The reporting view's FromPrice is the minimum of every configured fare, even
# for a full cabin, so it must not be used as a public offer price.
BOOKABLE_FLIGHTS = """
WITH CabinAvailability AS (
 SELECT f.FlightID,s.Cabin,COUNT(*) CabinAvailable
 FROM dbo.Flights f
 JOIN dbo.AircraftSeats s ON s.AircraftID=f.AircraftID AND s.IsActive=1
 WHERE NOT EXISTS (
  SELECT 1 FROM dbo.FlightSeatAssignments a
  JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID
  JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID
  JOIN dbo.Bookings b ON b.BookingID=bp.BookingID
  WHERE a.FlightID=f.FlightID AND a.SeatID=s.SeatID AND a.IsActive=1
   AND (b.Status='CONFIRMED' OR (b.Status='HELD' AND b.ExpiresAt>SYSUTCDATETIME()))
 )
 GROUP BY f.FlightID,s.Cabin
), PricedFares AS (
 SELECT ff.FlightID,c.*,ff.BasePrice,ff.TaxRate,ca.CabinAvailable,
  dbo.fn_CalculateTicketPrice(ff.BasePrice,ff.TaxRate) Price
 FROM dbo.FlightFares ff
 JOIN dbo.FareClasses c ON c.FareClassID=ff.FareClassID
 JOIN CabinAvailability ca ON ca.FlightID=ff.FlightID AND ca.Cabin=c.Cabin
 WHERE ca.CabinAvailable>=?
), PublicFlights AS (
 SELECT f.FlightID,f.FlightNumber,f.AircraftID,f.OriginID,f.DestinationID,
  f.OriginCode,f.OriginCity,f.DestinationCode,f.DestinationCity,
  f.DepartureTime,f.ArrivalTime,f.Status,f.Model,f.AirlineName,f.AirlineCode,
  f.TotalSeats,f.AvailableSeats,f.OriginCountryCode,f.DestinationCountryCode,
  f.OriginCountryName,f.DestinationCountryName,f.DestinationRegion,
  f.OriginTimeZone,f.DestinationTimeZone,f.DepartureDate,f.ArrivalDate,
  (SELECT MIN(p.Price) FROM PricedFares p WHERE p.FlightID=f.FlightID) FromPrice
 FROM dbo.vw_FlightAvailability f
)
"""

@bp.get('/health')
def health():
    query('SELECT 1 Ready')
    return jsonify(status='ok', database='Microsoft SQL Server')

@bp.get('/airports')
def airports():
    return jsonify(items=query('SELECT AirportID,Code,Name,City,CountryCode,CountryName,RegionCode,TimeZoneName,IanaTimeZone FROM dbo.Airports WHERE IsActive=1 ORDER BY City'))

@bp.get('/discovery')
def discovery():
    # The advertised date belongs to the same flight as the advertised price.
    # Lowest price wins, then earliest departure gives a stable tie-breaker.
    return jsonify(items=query(BOOKABLE_FLIGHTS + """
, RankedRoutes AS (
 SELECT *,ROW_NUMBER() OVER(PARTITION BY OriginID,DestinationID
  ORDER BY FromPrice,DepartureTime,FlightID) OfferRank,
  COUNT(*) OVER(PARTITION BY OriginID,DestinationID) FlightCount
 FROM PublicFlights
 WHERE Status='SCHEDULED' AND DepartureTime>DATEADD(hour,2,SYSUTCDATETIME())
  AND FromPrice IS NOT NULL
)
SELECT TOP(120) OriginID,DestinationID,OriginCode,DestinationCode,OriginCity,
 DestinationCity,FromPrice,DepartureTime NextDeparture,FlightCount,DepartureDate,
 OriginCountryCode,DestinationCountryCode,DestinationCountryName,DestinationRegion,OriginTimeZone
FROM RankedRoutes WHERE OfferRank=1
ORDER BY FlightCount DESC,OriginCode,DestinationCode
""", (1,)))

@bp.get('/flights')
def search():
    d = request.args
    origin, dest, count = integer(d, 'origin'), integer(d, 'destination'), integer(d, 'passengers', 1, 9)
    if origin == dest:
        raise ApiError('Điểm đi và điểm đến phải khác nhau.')
    date = iso_date(d.get('date'))
    # Vietnamese civil day converted into UTC half-open interval.
    from ..services.timezones import airport_day_bounds
    start, end = airport_day_bounds(origin, date)
    return jsonify(items=query(BOOKABLE_FLIGHTS + """
SELECT * FROM PublicFlights
WHERE OriginID=? AND DestinationID=? AND DepartureTime>=? AND DepartureTime<?
 AND DepartureTime>DATEADD(hour,2,SYSUTCDATETIME()) AND Status='SCHEDULED'
 AND FromPrice IS NOT NULL
ORDER BY DepartureTime,FlightID
""", (count, origin, dest, start, end)))

@bp.get('/flights/<int:flight_id>')
def details(flight_id):
    count = integer(request.args, 'passengers', 1, 9) if 'passengers' in request.args else 1
    f = query(BOOKABLE_FLIGHTS + 'SELECT * FROM PublicFlights WHERE FlightID=?', (count, flight_id), one=True)
    if not f:
        raise ApiError('Không tìm thấy chuyến bay.', 404)
    fares = query(BOOKABLE_FLIGHTS + 'SELECT * FROM PricedFares WHERE FlightID=? ORDER BY Price,FareClassID', (count, flight_id))
    return jsonify(flight=f, fares=fares)

@bp.get('/flights/calendar')
def price_calendar():
    d=request.args
    origin,dest,count=integer(d,'origin'),integer(d,'destination'),integer(d,'passengers',1,9)
    if origin==dest:raise ApiError('Điểm đi và điểm đến phải khác nhau.')
    day=iso_date(d.get('date'))
    from ..services.timezones import airport_day_bounds
    start,_=airport_day_bounds(origin,day-timedelta(days=3))
    _,end=airport_day_bounds(origin,day+timedelta(days=3))
    return jsonify(items=query(BOOKABLE_FLIGHTS+'''
     SELECT DepartureDate [Date],MIN(FromPrice) FromPrice,COUNT(*) FlightCount
     FROM PublicFlights WHERE OriginID=? AND DestinationID=? AND DepartureTime>=? AND DepartureTime<?
      AND DepartureTime>DATEADD(hour,2,SYSUTCDATETIME()) AND Status='SCHEDULED' AND FromPrice IS NOT NULL
     GROUP BY DepartureDate ORDER BY DepartureDate''',(count,origin,dest,start,end)))

@bp.get('/flights/<int:flight_id>/seats')
def seats(flight_id):
    if not query('SELECT FlightID FROM dbo.Flights WHERE FlightID=?', (flight_id,), one=True):
        raise ApiError('Không tìm thấy chuyến bay.', 404)
    return jsonify(items=query('EXEC dbo.sp_GetAvailableSeats ?', (flight_id,)))
