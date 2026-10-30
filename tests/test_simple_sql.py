"""SQL-backed checks for one booking containing two direct flights."""
import json
import uuid
from datetime import timedelta
from decimal import Decimal

import pyodbc
import pytest
from app.db import query


@pytest.fixture
def roundtrip(flight):
    departure = flight['DepartureTime'] + timedelta(days=3)
    result = query('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?',
                   (None, 'R'+uuid.uuid4().hex[:7], flight['AircraftID'],
                    flight['DestinationID'], flight['OriginID'], departure,
                    departure+timedelta(hours=2)), one=True)
    query('EXEC dbo.sp_SaveFare ?,?,?,?', (result['FlightID'], flight['FareClassID'], 1000000, .1))
    return dict(flight, ReturnFlightID=result['FlightID'])


def reserve(user, route, *, return_seat=None, expected=None):
    passenger = dict(FullName='Nguyễn Kiểm Thử', DateOfBirth='1995-04-20',
                     DocumentNumber='DOC-'+uuid.uuid4().hex[:12],
                     SeatID=route['Seats'][0]['SeatID'], FareClassID=route['FareClassID'],
                     ReturnSeatID=return_seat or route['Seats'][0]['SeatID'],
                     ReturnFareClassID=route['FareClassID'])
    return query('EXEC dbo.sp_CreateBooking @UserID=?,@FlightID=?,@Passengers=?,@ReturnFlightID=?,@ExpectedTotal=?',
                 (user['UserID'], route['FlightID'], json.dumps([passenger]), route['ReturnFlightID'], expected), one=True)


def ticket_rows(booking):
    return query('SELECT t.*,a.IsActive,s.FlightID FROM dbo.Tickets t '
                 'JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID '
                 'JOIN dbo.BookingSegments s ON s.BookingSegmentID=t.BookingSegmentID '
                 'JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID WHERE p.BookingID=?',
                 (booking['BookingID'],))


def payment(user, booking, key=None, success=True):
    return query('EXEC dbo.sp_ConfirmPayment ?,?,?,?',
                 (user['UserID'], booking['BookingID'], key or uuid.uuid4().hex, success), one=True)


def test_roundtrip_one_charge_and_immutable_prices(users, roundtrip):
    booking = reserve(users[0], roundtrip, expected=2200000)
    assert booking['SegmentCount'] == 2 and booking['PassengerCount'] == 1
    assert booking['TotalAmount'] == Decimal('2200000.00')
    query('EXEC dbo.sp_SaveFare ?,?,?,?', (roundtrip['ReturnFlightID'], roundtrip['FareClassID'], 2000000, .1))
    key = uuid.uuid4().hex
    first = payment(users[0], booking, key)
    second = payment(users[0], booking, key)
    assert first['PaymentID'] == second['PaymentID'] and first['Amount'] == Decimal('2200000.00')
    assert all(t['Status'] == 'VALID' and t['Amount'] == Decimal('1100000.00') for t in ticket_rows(booking))
    with pytest.raises(pyodbc.Error, match='51011|51004'):
        query('UPDATE dbo.Tickets SET BaseFare=BaseFare+1,Amount=Amount+1 WHERE TicketID=?',
              (ticket_rows(booking)[0]['TicketID'],))
    with pytest.raises(pyodbc.Error, match='51007'):
        payment(users[0], booking, key, success=False)


def test_second_direction_conflict_rolls_back_everything(users, roundtrip):
    outbound = dict(roundtrip, FlightID=roundtrip['ReturnFlightID'], ReturnFlightID=None)
    reserve(users[1], outbound)
    before = {table: query('SELECT COUNT(*) N FROM dbo.'+table, one=True)['N']
              for table in ('Bookings', 'BookingSegments', 'Passengers', 'Tickets', 'FlightSeatAssignments')}
    with pytest.raises(pyodbc.Error, match='51005'):
        reserve(users[0], roundtrip)
    assert before == {table: query('SELECT COUNT(*) N FROM dbo.'+table, one=True)['N'] for table in before}
    assert query('SELECT COUNT(*) N FROM dbo.FlightSeatAssignments WHERE FlightID=? AND IsActive=1',
                 (roundtrip['FlightID'],), one=True)['N'] == 0


def test_changed_quote_and_invalid_return_leave_no_booking(users, roundtrip):
    before = query('SELECT COUNT(*) N FROM dbo.Bookings', one=True)['N']
    with pytest.raises(pyodbc.Error, match='51013'):
        reserve(users[0], roundtrip, expected=1)
    with pytest.raises(pyodbc.Error, match='51004'):
        reserve(users[0], dict(roundtrip, ReturnFlightID=roundtrip['FlightID']))
    assert query('SELECT COUNT(*) N FROM dbo.Bookings', one=True)['N'] == before


def test_expiry_on_return_releases_both_directions(users, roundtrip):
    booking = reserve(users[0], roundtrip)
    query('UPDATE dbo.Bookings SET CreatedAt=DATEADD(minute,-20,SYSUTCDATETIME()),'
          'ExpiresAt=DATEADD(minute,-1,SYSUTCDATETIME()) WHERE BookingID=?', (booking['BookingID'],))
    query('EXEC dbo.sp_GetAvailableSeats ?', (roundtrip['ReturnFlightID'],))
    assert query('SELECT Status FROM dbo.Bookings WHERE BookingID=?', (booking['BookingID'],), one=True)['Status'] == 'EXPIRED'
    assert all(t['Status'] == 'VOID' and not t['IsActive'] for t in ticket_rows(booking))
    with pytest.raises(pyodbc.Error, match='51008'):
        payment(users[0], booking)


def test_customer_cancellation_refunds_both_and_is_idempotent(users, roundtrip):
    booking = reserve(users[0], roundtrip)
    payment(users[0], booking)
    result = query('EXEC dbo.sp_CancelBooking ?,?', (users[0]['UserID'], booking['BookingID']), one=True)
    assert result['RefundAmount'] == Decimal('1760000.00')
    query('EXEC dbo.sp_CancelBooking ?,?', (users[0]['UserID'], booking['BookingID']))
    assert query("SELECT COUNT(*) N FROM dbo.Payments WHERE BookingID=? AND Kind='REFUND'",
                 (booking['BookingID'],), one=True)['N'] == 1
    assert all(t['Status'] == 'VOID' and not t['IsActive'] for t in ticket_rows(booking))


def test_airline_cancellation_before_travel_refunds_entire_trip(users, roundtrip):
    booking = reserve(users[0], roundtrip)
    payment(users[0], booking)
    query("EXEC dbo.sp_UpdateFlightStatus ?,'CANCELLED'", (roundtrip['ReturnFlightID'],))
    assert query("SELECT Amount FROM dbo.Payments WHERE BookingID=? AND Kind='REFUND'",
                 (booking['BookingID'],), one=True)['Amount'] == Decimal('2200000.00')
    assert all(t['Status'] == 'VOID' and not t['IsActive'] for t in ticket_rows(booking))


def test_airline_cancellation_keeps_used_leg_and_refunds_unused(users, roundtrip):
    booking = reserve(users[0], roundtrip)
    payment(users[0], booking)
    # Flight status is authoritative for used travel; do not rewrite the issued timetable.
    for status in ('BOARDING', 'DEPARTED', 'ARRIVED'):
        query('EXEC dbo.sp_UpdateFlightStatus ?,?', (roundtrip['FlightID'], status))
    query("EXEC dbo.sp_UpdateFlightStatus ?,'CANCELLED'", (roundtrip['ReturnFlightID'],))
    refund = query("SELECT Amount FROM dbo.Payments WHERE BookingID=? AND Kind='REFUND'",
                   (booking['BookingID'],), one=True)
    assert refund['Amount'] == Decimal('1100000.00')
    rows = {t['FlightID']: t for t in ticket_rows(booking)}
    assert rows[roundtrip['FlightID']]['Status'] == 'VALID'
    assert rows[roundtrip['ReturnFlightID']]['Status'] == 'VOID'
    assert query('SELECT Status FROM dbo.Bookings WHERE BookingID=?', (booking['BookingID'],), one=True)['Status'] == 'CONFIRMED'
