"""Exercise the real SQL importer, preserving issued records and atomicity.

Only run against the disposable AeroFlow_Test_* database guarded by sql_ready.
These tests clean up their own future timetable, so rerunning is supported.
"""

from datetime import timedelta
from decimal import Decimal
import uuid

import pytest

from app.db import connection, query
from scripts.demo_catalog import build_plan, local_today
from scripts.seed_ultimate import seed_demo


pytestmark = pytest.mark.integration


def issued_rows():
    return {
        table: query(f'SELECT * FROM dbo.{table} ORDER BY {key}')
        for table, key in (('Bookings', 'BookingID'), ('Tickets', 'TicketID'), ('Payments', 'PaymentID'))
    }


def table_counts():
    with connection() as conn:
        tables = [row[0] for row in conn.execute(
            "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='dbo' AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME"
        ).fetchall()]
        # Identifiers originate exclusively from SQL Server metadata.
        return {table: conn.execute('SELECT COUNT_BIG(*) FROM dbo.[' + table.replace(']', ']]') + ']').fetchone()[0]
                for table in tables}


def ids(table, key):
    return {row[key] for row in query(f'SELECT {key} FROM dbo.{table}')}


def delete_ids(conn, table, key, values):
    if values:
        marks = ','.join('?' for _ in values)
        conn.execute(f'DELETE dbo.{table} WHERE {key} IN ({marks})', tuple(values))


@pytest.fixture
def import_window(sql_ready):
    start = local_today() + timedelta(days=60)
    # The second window is for a collision on day two, after 36 prior flights.
    plans = build_plan(2, start) + build_plan(2, start + timedelta(days=4))
    identity = {(flight.number, flight.departure) for flight in plans}
    old_flights = ids('Flights', 'FlightID')
    old_aircraft = ids('Aircraft', 'AircraftID')
    old_classes = ids('FareClasses', 'FareClassID')
    old_routes = ids('Routes', 'RouteID')
    assert not any((row['FlightNumber'], row['DepartureTime']) in identity
                   for row in query('SELECT FlightNumber,DepartureTime FROM dbo.Flights')), \
        'The dedicated seed-test windows already contain flights; use a clean disposable test database.'
    try:
        yield start
    finally:
        # Remove only records introduced in this test's reserved windows.
        own_flights = {row['FlightID'] for row in query('SELECT FlightID,FlightNumber,DepartureTime FROM dbo.Flights')
                       if row['FlightID'] not in old_flights
                       and (row['FlightNumber'], row['DepartureTime']) in identity}
        own_aircraft = ids('Aircraft', 'AircraftID') - old_aircraft
        own_classes = ids('FareClasses', 'FareClassID') - old_classes
        own_routes = ids('Routes', 'RouteID') - old_routes
        with connection() as conn:
            delete_ids(conn, 'FlightFares', 'FlightID', own_flights)
            delete_ids(conn, 'Flights', 'FlightID', own_flights)
            delete_ids(conn, 'AircraftSeats', 'AircraftID', own_aircraft)
            delete_ids(conn, 'Aircraft', 'AircraftID', own_aircraft)
            delete_ids(conn, 'FareClasses', 'FareClassID', own_classes)
            delete_ids(conn, 'Routes', 'RouteID', own_routes)


def test_sql_demo_seed_creates_72_flights_and_864_fares_idempotently(sql_ready, flight, import_window):
    # An ordinary administrator-created cheap fare is outside the importer's
    # ownership allowlist and must never be silently repriced.
    query('EXEC dbo.sp_SaveFare ?,?,?,?', (flight['FlightID'], flight['FareClassID'], Decimal('100000'), Decimal('.1')))
    unmanaged_before = query('SELECT * FROM dbo.FlightFares WHERE FlightID=? ORDER BY FareClassID', (flight['FlightID'],))
    issued_before = issued_rows()
    assert all(issued_before.values()), 'Seeded booking, ticket and payment records must exist for the preservation check.'

    result = seed_demo(days=2, start_date=import_window)
    assert result.created == 72
    assert result.existing == 0
    assert result.updated_fares == 864
    managed = query("""SELECT f.FlightID,f.FlightNumber,f.DepartureTime,ff.FareClassID,ff.BasePrice,ff.TaxRate
        FROM dbo.Flights f JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID
        JOIN dbo.FlightFares ff ON ff.FlightID=f.FlightID
        WHERE a.Registration LIKE 'DEMO-%' AND f.DepartureTime>=? AND f.DepartureTime<?
        ORDER BY f.FlightID,ff.FareClassID""",
        (min(f.departure for f in build_plan(2, import_window)),
         max(f.departure for f in build_plan(2, import_window)) + timedelta(seconds=1)))
    assert len(managed) == 864, 'Importer output must remain visible from a new database connection.'
    assert len({row['FlightID'] for row in managed}) == 72
    assert issued_rows() == issued_before
    assert query('SELECT * FROM dbo.FlightFares WHERE FlightID=? ORDER BY FareClassID',
                 (flight['FlightID'],)) == unmanaged_before

    counts_after_first = table_counts()
    fares_after_first = query('SELECT * FROM dbo.FlightFares ORDER BY FlightID,FareClassID')
    result = seed_demo(days=2, start_date=import_window)
    assert result.created == 0
    assert result.existing == 72
    assert result.created_aircraft == 0
    assert result.created_fare_classes == 0
    assert result.updated_fares == 0
    assert result.legacy_updated_fares == 0
    assert table_counts() == counts_after_first
    assert query('SELECT * FROM dbo.FlightFares ORDER BY FlightID,FareClassID') == fares_after_first
    assert issued_rows() == issued_before
    assert query('SELECT * FROM dbo.FlightFares WHERE FlightID=? ORDER BY FareClassID',
                 (flight['FlightID'],)) == unmanaged_before


def test_sql_demo_seed_collision_mid_plan_rolls_back_every_table(sql_ready, import_window):
    start = import_window + timedelta(days=4)
    plan = build_plan(2, start)
    collision = plan[36]
    airline = query("SELECT AirlineID FROM dbo.Airlines WHERE Code='AF'", one=True)['AirlineID']
    aircraft = query('SET NOCOUNT ON; INSERT dbo.Aircraft(AirlineID,Registration,Model) VALUES(?,?,?); SELECT CONVERT(int,SCOPE_IDENTITY()) ID;',
                     (airline, 'C-' + uuid.uuid4().hex[:14], 'Intentional seed collision'), one=True)['ID']
    query('INSERT dbo.AircraftSeats(AircraftID,SeatNumber,RowNumber,ColumnLetter,Cabin) VALUES(?,?,?,?,?)',
          (aircraft, 'A1', 1, 'A', 'ECONOMY'))
    airports = {row['Code'].strip(): row['AirportID'] for row in query('SELECT Code,AirportID FROM dbo.Airports')}
    collision_id = query('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?', (
        None, collision.number, aircraft, airports[collision.origin], airports[collision.destination],
        collision.departure, collision.arrival,
    ), one=True)['FlightID']
    counts_before = table_counts()
    issued_before = issued_rows()

    with pytest.raises(ValueError, match='differs from the managed plan'):
        seed_demo(days=2, start_date=start)

    assert table_counts() == counts_before
    assert issued_rows() == issued_before
    first = plan[0]
    assert not query('SELECT FlightID FROM dbo.Flights WHERE FlightNumber=? AND DepartureTime=?',
                     (first.number, first.departure))
    # The pre-existing conflicting record remains untouched; only attempted
    # importer work (including the first 36 flights/fare rows) is rolled back.
    assert query('SELECT AircraftID FROM dbo.Flights WHERE FlightID=?',
                 (collision_id,), one=True)['AircraftID'] == aircraft
