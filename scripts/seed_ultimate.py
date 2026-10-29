"""Preview or import the December 2026 / January 2027 presentation timetable.

No --apply means no connection or database write. The importer is atomic and
idempotent for overlapping date windows; issued ticket price snapshots are
never updated. Only explicitly owned demo aircraft/flights are repriced.
"""
import argparse
from dataclasses import asdict, dataclass
from datetime import date, datetime, timedelta
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts.demo_catalog import (AIRLINES, BASES, BUNDLES, CABINS, DEMO_MODEL,
                                  TAX_RATE, MAX_DAYS, build_plan, fare_base, local_today,
                                  preview, seat_plan)


PRESENTATION_START = date(2026, 12, 1)
PRESENTATION_END = date(2027, 1, 31)


def resolve_window(days=None, start_date=None):
    """Default to the future part of the presentation window, Vietnam time.

    A custom start date alone retains a 30-day window. After the presentation
    window has ended, no-argument runs use tomorrow + 30 days instead of
    silently importing expired flights.
    """
    custom_start = start_date is not None
    if start_date is None:
        start_date = max(PRESENTATION_START, local_today() + timedelta(days=1))
    if isinstance(start_date, str):
        start_date = date.fromisoformat(start_date)
    if not isinstance(start_date, date) or isinstance(start_date, datetime):
        raise ValueError('--start-date must be an ISO date (YYYY-MM-DD).')
    if days is None:
        days = ((PRESENTATION_END - start_date).days + 1
                if not custom_start and start_date <= PRESENTATION_END else 30)
    if not isinstance(days, int) or isinstance(days, bool) or not 1 <= days <= MAX_DAYS:
        raise ValueError(f'--days must be between 1 and {MAX_DAYS}.')
    return days, start_date


@dataclass
class SeedResult:
    created: int = 0
    existing: int = 0
    created_aircraft: int = 0
    created_fare_classes: int = 0
    updated_fares: int = 0
    legacy_updated_fares: int = 0
    skipped_closed_flights: int = 0


def _identity(cursor):
    while cursor.description is None:
        if not cursor.nextset():
            raise RuntimeError('The database procedure did not return an identifier.')
    value = int(cursor.fetchone()[0])
    while cursor.nextset():
        pass
    return value


def _drain(cursor):
    while cursor.nextset():
        pass


def _catalog(conn, result):
    airports = {r[0].strip(): r[1] for r in conn.execute('SELECT Code,AirportID FROM dbo.Airports WHERE IsActive=1')}
    airlines = {r[0].strip(): r[1] for r in conn.execute('SELECT Code,AirlineID FROM dbo.Airlines')}
    from scripts.demo_catalog import AIRPORT_COORDINATES
    missing = sorted(set(AIRPORT_COORDINATES) - airports.keys()) + sorted(set(AIRLINES) - airlines.keys())
    if missing:
        raise ValueError('Required active demo catalog entries are missing: ' + ', '.join(missing))
    classes = {}
    for cabin, prefix, label in CABINS:
        for bundle, suffix, bundle_label, refund, change, bag in BUNDLES:
            code = 'U' + prefix + suffix
            row = conn.execute('SELECT FareClassID,Cabin,Bundle FROM dbo.FareClasses WHERE Code=?', code).fetchone()
            if row:
                if row[1] != cabin or row[2] != bundle:
                    raise ValueError(f'{code} was modified; this importer will not overwrite its policy.')
                classes[row[0]] = (cabin, bundle)
                continue
            fid = _identity(conn.execute(
                'INSERT dbo.FareClasses(Code,Name,Cabin,BaggageKg,RefundPercent,Bundle,ChangeAllowed,ChangeFee,CabinBaggageKg) '
                'OUTPUT inserted.FareClassID VALUES(?,?,?,?,?,?,?,?,?)',
                code, f'{label} {bundle_label}', cabin, bag, refund, bundle, change,
                200000 if bundle == 'STANDARD' else 0, 7 if cabin == 'ECONOMY' else 12,
            ))
            classes[fid] = (cabin, bundle)
            result.created_fare_classes += 1
    planes = {}
    expected_seats = list(seat_plan())
    for airline in AIRLINES:
        for base in BASES:
            registration = f'DEMO-{airline}-{base}'
            row = conn.execute('SELECT AircraftID,AirlineID,Model,IsActive FROM dbo.Aircraft WHERE Registration=?', registration).fetchone()
            if row:
                if row[1] != airlines[airline] or row[2] != DEMO_MODEL or not row[3]:
                    raise ValueError(f'{registration} is not an active aircraft owned by this demo catalog.')
                actual = list(conn.execute('SELECT SeatNumber,RowNumber,ColumnLetter,Cabin FROM dbo.AircraftSeats WHERE AircraftID=? AND IsActive=1 ORDER BY RowNumber,ColumnLetter', row[0]))
                if [tuple(s) for s in actual] != [s[:4] for s in expected_seats]:
                    raise ValueError(f'{registration} has a changed seat layout; no existing aircraft is rewritten.')
                planes[registration] = row[0]
                continue
            pid = _identity(conn.execute(
                'INSERT dbo.Aircraft(AirlineID,Registration,Model) OUTPUT inserted.AircraftID VALUES(?,?,?)',
                airlines[airline], registration, DEMO_MODEL,
            ))
            cursor = conn.cursor()
            cursor.executemany(
                'INSERT dbo.AircraftSeats(AircraftID,SeatNumber,RowNumber,ColumnLetter,Cabin,SeatFee,IsPriority) VALUES(?,?,?,?,?,?,?)',
                [(pid,) + seat for seat in expected_seats],
            )
            _drain(cursor)
            planes[registration] = pid
            result.created_aircraft += 1
    return airports, classes, planes


def _save_fare(conn, flight_id, class_id, base):
    old = conn.execute('SELECT BasePrice,TaxRate FROM dbo.FlightFares WHERE FlightID=? AND FareClassID=?', flight_id, class_id).fetchone()
    if old and old[0] == base and old[1] == TAX_RATE:
        return 0
    _drain(conn.execute('EXEC dbo.sp_SaveFare ?,?,?,?', flight_id, class_id, base, TAX_RATE))
    return 1


def _reprice_legacy(conn):
    """Bounded allowlist from original seeds; every issued ticket stays unchanged."""
    allowed = {
        ('VN-AF1', 'AF100', 'HAN', 'SGN'), ('VN-AF2', 'AF101', 'HAN', 'SGN'),
        ('VN-AF3', 'AF102', 'HAN', 'DAD'), ('VN-AF4', 'AF103', 'SGN', 'HAN'),
        ('VN-AF1', 'AF101', 'SGN', 'HAN'), ('VN-AF3', 'AF103', 'DAD', 'HAN'),
        ('DEMO-ULT-1', 'UA100', 'HAN', 'SGN'), ('DEMO-ULT-1', 'UA101', 'SGN', 'HAN'),
        ('DEMO-ULT-2', 'UA200', 'HAN', 'DAD'), ('DEMO-ULT-2', 'UA201', 'DAD', 'SGN'),
        ('DEMO-ULT-2', 'UA202', 'SGN', 'DAD'), ('DEMO-ULT-2', 'UA203', 'DAD', 'HAN'),
    }
    rows = conn.execute(
        "SELECT f.FlightID,f.FlightNumber,a.Registration,al.Code,o.Code,d.Code,f.DepartureTime,ff.FareClassID,c.Cabin,c.Bundle "
        "FROM dbo.Flights f JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID "
        "JOIN dbo.Airlines al ON al.AirlineID=a.AirlineID JOIN dbo.Airports o ON o.AirportID=f.OriginID "
        "JOIN dbo.Airports d ON d.AirportID=f.DestinationID JOIN dbo.FlightFares ff ON ff.FlightID=f.FlightID "
        "JOIN dbo.FareClasses c ON c.FareClassID=ff.FareClassID "
        "WHERE f.Status='SCHEDULED' AND f.DepartureTime>DATEADD(hour,2,SYSUTCDATETIME()) "
        "AND a.Registration IN (?,?,?,?,?,?)",
        'VN-AF1', 'VN-AF2', 'VN-AF3', 'VN-AF4', 'DEMO-ULT-1', 'DEMO-ULT-2',
    ).fetchall()
    from scripts.demo_catalog import VIETNAM
    from datetime import timezone
    updated = 0
    for flight_id, number, registration, airline, origin, destination, departure, class_id, cabin, bundle in rows:
        origin, destination = origin.strip(), destination.strip()
        if (registration, number, origin, destination) not in allowed:
            continue
        day = departure.replace(tzinfo=timezone.utc).astimezone(VIETNAM).date()
        base = fare_base(origin, destination, airline.strip(), day, cabin, bundle)
        updated += _save_fare(conn, flight_id, class_id, base)
    return updated


def seed_demo(days=None, start_date=None, *, reprice_legacy=True):
    days, start_date = resolve_window(days, start_date)
    plan = build_plan(days, start_date)
    if min(f.local_date for f in plan) <= local_today():
        raise ValueError('--start-date must be tomorrow or later (Vietnam time).')
    if min(f.local_date for f in plan) > local_today() + timedelta(days=365):
        raise ValueError('--start-date must be within the next 365 days.')
    # Lazy import: --preview and the pure timetable tests need no ODBC package.
    from app.db import connection
    result = SeedResult()
    with connection() as conn:
        conn.timeout = 120
        # connection() owns the ODBC transaction. A second explicit BEGIN
        # nests SQL Server's transaction count and can leave work uncommitted
        # when the driver ends its transaction, causing close() to roll it back.
        conn.execute('SET NOCOUNT ON; SET XACT_ABORT ON;')
        if conn.execute("SELECT COALESCE(MAX(Version),0) FROM dbo.SchemaMigrations").fetchone()[0] < 14:
            raise ValueError('Schema 014 or later is required: install a new database with init_db.py, or upgrade an existing database with migrate.py.')
        lock = conn.execute(
            "DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource=?,@LockMode='Exclusive',"
            "@LockOwner='Transaction',@LockTimeout=10000; SELECT @r;", 'AeroFlow:schedule',
        ).fetchone()[0]
        if lock < 0:
            raise RuntimeError('The flight timetable is being updated; retry this seed later.')
        _drain(conn.execute('EXEC dbo.sp_LockFlight 0'))
        airports, classes, planes = _catalog(conn, result)
        for flight in plan:
            row = conn.execute(
                'SELECT FlightID,AircraftID,OriginID,DestinationID,ArrivalTime,Status FROM dbo.Flights '
                'WHERE FlightNumber=? AND DepartureTime=?', flight.number, flight.departure,
            ).fetchone()
            if row:
                if tuple(row[1:5]) != (planes[flight.registration], airports[flight.origin], airports[flight.destination], flight.arrival):
                    raise ValueError(f'{flight.number} on {flight.local_date} differs from the managed plan; existing flights are never rewritten.')
                result.existing += 1
                if row[5] != 'SCHEDULED':
                    result.skipped_closed_flights += 1
                    continue
                flight_id = row[0]
            else:
                flight_id = _identity(conn.execute(
                    'EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?', None, flight.number,
                    planes[flight.registration], airports[flight.origin], airports[flight.destination],
                    flight.departure, flight.arrival,
                ))
                result.created += 1
            for class_id, (cabin, bundle) in classes.items():
                result.updated_fares += _save_fare(
                    conn, flight_id, class_id,
                    fare_base(flight.origin, flight.destination, flight.airline, flight.local_date, cabin, bundle),
                )
        if reprice_legacy:
            result.legacy_updated_fares = _reprice_legacy(conn)
    return result


def seed(days=None, start_date=None):
    """Compatibility entry point: return the number of newly created flights."""
    return seed_demo(days, start_date).created


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true', help='Atomically import into the configured SQL Server database.')
    mode.add_argument('--preview', action='store_true', help='Show the proposed records without connecting to SQL Server (default).')
    parser.add_argument('--days', type=int, help='Override calendar days, 1–90; default presentation window has 62 days.')
    parser.add_argument('--start-date', type=date.fromisoformat, help='Custom first Vietnam date, YYYY-MM-DD; defaults to the future part of Dec 2026 / Jan 2027.')
    args = parser.parse_args()
    try:
        days, start_date = resolve_window(args.days, args.start_date)
        summary = preview(days, start_date)
        if args.apply:
            summary.update(mode='APPLIED', result=asdict(seed_demo(days, start_date)))
    except (ValueError, RuntimeError) as error:
        parser.error(str(error))
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
