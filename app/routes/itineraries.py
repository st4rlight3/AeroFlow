import json
from flask import Blueprint, g, jsonify, request
from ..db import query
from ..security import authenticated
from ..validation import body, decimal_value
from ..services.itineraries import parse, quote, search
from ..services.booking_service import owned_booking

bp=Blueprint('itineraries',__name__,url_prefix='/api/itineraries')


@bp.get('/search')
def find():
    return jsonify(search(request.args))


@bp.post('/quote')
@authenticated()
def price():
    return jsonify(quote(body()))


@bp.post('')
@authenticated()
def create():
    data=body()
    kind,segments,passengers,selections=parse(data)
    expected=decimal_value(data,'ExpectedTotal',0,10000000000) if 'ExpectedTotal' in data else None
    result=query('EXEC dbo.sp_CreateItinerary ?,?,?,?,?,?',(g.user['UserID'],kind,json.dumps(segments),json.dumps(passengers,ensure_ascii=False),json.dumps(selections),expected),one=True)
    return jsonify(booking=result),201


@bp.get('/<int:booking_id>')
@authenticated()
def detail(booking_id):
    booking=owned_booking(booking_id,g.user)
    segments=query('SELECT s.*,f.OriginTimeZone,f.DestinationTimeZone,f.DepartureDate,f.ArrivalDate FROM dbo.vw_ItinerarySegments s JOIN dbo.vw_FlightAvailability f ON f.FlightID=s.FlightID WHERE s.BookingID=? ORDER BY s.SegmentOrder',(booking_id,))
    tickets=query('SELECT t.*,p.FullName,RIGHT(p.DocumentNumber,4) DocumentLast4,s.SeatNumber,c.Name FareName,c.Cabin,c.BaggageKg,c.CabinBaggageKg FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Passengers p ON p.PassengerID=bp.PassengerID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID JOIN dbo.AircraftSeats s ON s.SeatID=a.SeatID JOIN dbo.FareClasses c ON c.FareClassID=t.FareClassID WHERE bp.BookingID=? ORDER BY t.BookingSegmentID,t.TicketID',(booking_id,))
    return jsonify(booking=booking,segments=segments,tickets=tickets)
