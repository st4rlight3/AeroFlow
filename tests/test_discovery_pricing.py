"""Public offers must match a fare and a cabin the customer can actually book."""

from datetime import timedelta
from decimal import Decimal
import uuid

import pytest

from app.db import query
from conftest import book, sign_in


pytestmark = pytest.mark.integration


def search(client, flight, passengers=1):
    day = (flight['DepartureTime'] + timedelta(hours=7)).date().isoformat()
    response = client.get('/api/flights', query_string={
        'origin': flight['OriginID'], 'destination': flight['DestinationID'],
        'date': day, 'passengers': passengers,
    })
    assert response.status_code == 200, response.get_json()
    return {item['FlightID']: item for item in response.get_json()['items']}


def mixed_cabin_flight(flight):
    # Create the layout before scheduling, as existing aircraft layouts are
    # protected by SQL once a flight uses them.
    airline = query('SELECT AirlineID FROM dbo.Aircraft WHERE AircraftID=?',
                    (flight['AircraftID'],), one=True)['AirlineID']
    aircraft = query('SET NOCOUNT ON; INSERT dbo.Aircraft(AirlineID,Registration,Model) VALUES(?,?,?); SELECT CONVERT(int,SCOPE_IDENTITY()) ID;',
                     (airline, 'P-' + uuid.uuid4().hex[:14], 'Cabin price test'), one=True)['ID']
    for column, row, cabin in (('A', 1, 'ECONOMY'), ('A', 2, 'BUSINESS'), ('B', 2, 'BUSINESS')):
        query('INSERT dbo.AircraftSeats(AircraftID,SeatNumber,RowNumber,ColumnLetter,Cabin) VALUES(?,?,?,?,?)',
              (aircraft, f'{column}{row}', row, column, cabin))
    flight_id = query('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?', (
        None, 'P' + uuid.uuid4().hex[:7], aircraft, flight['OriginID'],
        flight['DestinationID'], flight['DepartureTime'],
        flight['DepartureTime'] + timedelta(hours=2),
    ), one=True)['FlightID']
    fare_id = query("SELECT FareClassID FROM dbo.FareClasses WHERE Code='BIZ'", one=True)['FareClassID']
    query('EXEC dbo.sp_SaveFare ?,?,?,?', (flight_id, flight['FareClassID'], 1000000, '.1'))
    query('EXEC dbo.sp_SaveFare ?,?,?,?', (flight_id, fare_id, 2000000, '.1'))
    return dict(flight, FlightID=flight_id, AircraftID=aircraft,
                Seats=query('EXEC dbo.sp_GetAvailableSeats ?', (flight_id,))), fare_id


def test_search_omits_flight_without_fares(app, flight):
    query('DELETE dbo.FlightFares WHERE FlightID=?', (flight['FlightID'],))
    client = app.test_client()
    assert flight['FlightID'] not in search(client, flight)
    detail = client.get(f"/api/flights/{flight['FlightID']}")
    assert detail.status_code == 200
    assert detail.get_json()['flight']['FromPrice'] is None
    assert detail.get_json()['fares'] == []


def test_sold_out_cheap_cabin_does_not_set_offer_price(app, users, flight):
    flight, business_fare = mixed_cabin_flight(flight)
    customer = sign_in(app, users[0])
    booking = book(customer, flight)
    advertised = search(customer, flight)[flight['FlightID']]
    assert advertised['FromPrice'] == '2200000.00'
    detail = customer.get(f"/api/flights/{flight['FlightID']}").get_json()
    assert detail['flight']['FromPrice'] == '2200000.00'
    assert [fare['FareClassID'] for fare in detail['fares']] == [business_fare]

    # A stale active assignment must cease blocking the price when its hold
    # expires, even before the next write/seat refresh cleans it up.
    query('UPDATE dbo.Bookings SET CreatedAt=DATEADD(minute,-20,SYSUTCDATETIME()),ExpiresAt=DATEADD(minute,-1,SYSUTCDATETIME()) WHERE BookingID=?',
          (booking['BookingID'],))
    assert search(customer, flight)[flight['FlightID']]['FromPrice'] == '1100000.00'


def test_party_price_requires_enough_seats_in_one_priced_cabin(app, flight):
    flight, business_fare = mixed_cabin_flight(flight)
    client = app.test_client()
    assert search(client, flight, 1)[flight['FlightID']]['FromPrice'] == '1100000.00'
    assert search(client, flight, 2)[flight['FlightID']]['FromPrice'] == '2200000.00'
    detail = client.get(f"/api/flights/{flight['FlightID']}?passengers=2").get_json()
    assert detail['flight']['FromPrice'] == '2200000.00'
    assert [fare['FareClassID'] for fare in detail['fares']] == [business_fare]
    # Total free seats = 3, but no single fare/cabin can hold all three people.
    assert flight['FlightID'] not in search(client, flight, 3)


def test_discovery_price_and_date_belong_to_the_same_bookable_flight(app, flight):
    client = app.test_client()
    before = client.get('/api/discovery')
    assert before.status_code == 200, before.get_json()
    # Add our offers to the most represented public route, so the route remains
    # in discovery's TOP(6) even when the demo seed contains hundreds of flights.
    route = before.get_json()['items'][0]
    query('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?', (
        flight['FlightID'], 'D' + uuid.uuid4().hex[:7], flight['AircraftID'],
        route['OriginID'], route['DestinationID'], flight['DepartureTime'],
        flight['DepartureTime'] + timedelta(hours=2),
    ))
    first_base = (Decimal(route['FromPrice']) / Decimal('2.2')).quantize(Decimal('.01'))
    later_base = (first_base / 2).quantize(Decimal('.01'))
    assert later_base > 0
    query('EXEC dbo.sp_SaveFare ?,?,?,?', (flight['FlightID'], flight['FareClassID'], first_base, '.1'))

    airline = query('SELECT AirlineID FROM dbo.Aircraft WHERE AircraftID=?',
                    (flight['AircraftID'],), one=True)['AirlineID']
    aircraft = query('SET NOCOUNT ON; INSERT dbo.Aircraft(AirlineID,Registration,Model) VALUES(?,?,?); SELECT CONVERT(int,SCOPE_IDENTITY()) ID;',
                     (airline, 'D-' + uuid.uuid4().hex[:14], 'Discovery price test'), one=True)['ID']
    query('INSERT dbo.AircraftSeats(AircraftID,SeatNumber,RowNumber,ColumnLetter,Cabin) VALUES(?,?,?,?,?)',
          (aircraft, 'A1', 1, 'A', 'ECONOMY'))
    later_departure = flight['DepartureTime'] + timedelta(days=1)
    later_flight = query('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?', (
        None, 'D' + uuid.uuid4().hex[:7], aircraft, route['OriginID'],
        route['DestinationID'], later_departure, later_departure + timedelta(hours=2),
    ), one=True)['FlightID']
    query('EXEC dbo.sp_SaveFare ?,?,?,?', (later_flight, flight['FareClassID'], later_base, '.1'))
    expected = query('SELECT dbo.fn_CalculateTicketPrice(?,?) Price', (later_base, '.1'), one=True)['Price']

    try:
        response = client.get('/api/discovery')
        assert response.status_code == 200, response.get_json()
        offers = response.get_json()['items']
        actual = next(item for item in offers if item['OriginID'] == route['OriginID']
                      and item['DestinationID'] == route['DestinationID'])
        assert Decimal(actual['FromPrice']) == expected
        assert actual['NextDeparture'] == later_departure.replace(tzinfo=None).isoformat() + '+00:00'
        # Following the offer's actual date must surface its displayed fare.
        offered_flight = dict(flight, OriginID=route['OriginID'], DestinationID=route['DestinationID'],
                              DepartureTime=later_departure)
        assert search(client, offered_flight)[later_flight]['FromPrice'] == actual['FromPrice']
    finally:
        query('DELETE dbo.FlightFares WHERE FlightID=?', (later_flight,))
        query('DELETE dbo.Flights WHERE FlightID=?', (later_flight,))
        query('DELETE dbo.AircraftSeats WHERE AircraftID=?', (aircraft,))
        query('DELETE dbo.Aircraft WHERE AircraftID=?', (aircraft,))
        query('EXEC dbo.sp_SaveFare ?,?,?,?', (flight['FlightID'], flight['FareClassID'], 1000000, '.1'))
