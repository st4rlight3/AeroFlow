"""Xem trước hoặc nạp lịch bay mẫu; chỉ --apply mới ghi vào SQL Server."""
import argparse
from datetime import date, datetime, timedelta
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts.demo_catalog import (AIRLINES, BUNDLES, CABINS, DEMO_MODEL, MAX_DAYS,
                                  TAX_RATE, build_plan, fare_base, local_today, seat_plan)
from scripts.international_catalog import AIRPORTS, MODEL, build_international_plan
from scripts.international_catalog import fare_base as international_fare


def resolve_window(days=None, start_date=None):
    custom = start_date is not None
    start = date.fromisoformat(start_date) if isinstance(start_date, str) else start_date
    start = start or max(date(2026, 12, 1), local_today() + timedelta(days=1))
    if not isinstance(start, date) or isinstance(start, datetime):
        raise ValueError('--start-date cần có dạng YYYY-MM-DD.')
    if days is None:
        days = (date(2027, 1, 31) - start).days + 1 if not custom and start <= date(2027, 1, 31) else 30
    if type(days) is not int or not 1 <= days <= MAX_DAYS:
        raise ValueError(f'--days cần từ 1 đến {MAX_DAYS}.')
    return days, start


def identity(cursor):
    while cursor.description is None:
        if not cursor.nextset():
            raise RuntimeError('Không nhận được mã bản ghi vừa tạo.')
    value = int(cursor.fetchone()[0])
    while cursor.nextset():
        pass
    return value


def drain(cursor):
    while cursor.nextset():
        pass


def import_catalog(days, start):
    if not local_today() < start <= local_today() + timedelta(days=365):
        raise ValueError('Ngày đầu tiên cần nằm từ ngày mai đến 365 ngày tới.')
    from app.db import connection
    from zoneinfo import ZoneInfo
    domestic = build_plan(days, start)
    world = build_international_plan(days, start)
    plan = sorted(domestic + world, key=lambda f: (f.departure, f.number))
    result = dict(created_flights=0, existing_flights=0, created_aircraft=0,
                  created_fare_classes=0, inserted_fares=0, skipped_closed_flights=0)
    with connection() as conn:
        conn.timeout = 180
        conn.execute('SET NOCOUNT ON; SET XACT_ABORT ON;')
        conn.execute('SELECT TOP(0) BookingSegmentID FROM dbo.BookingSegments')
        drain(conn.execute('EXEC dbo.sp_LockInventory'))
        airports = {r[0].strip(): r[1] for r in conn.execute('SELECT Code,AirportID FROM dbo.Airports WHERE IsActive=1')}
        airlines = {r[0].strip(): r[1] for r in conn.execute('SELECT Code,AirlineID FROM dbo.Airlines')}
        missing = sorted({f.origin for f in domestic} | {f.destination for f in domestic})
        if any(code not in airports for code in missing) or any(code not in airlines for code in AIRLINES):
            raise ValueError('Hãy chạy scripts/init_db.py trước khi nạp lịch bay.')
        for code, city, country, name, region, windows, iana, lat, lon in AIRPORTS:
            ZoneInfo(iana)
            row = conn.execute('SELECT AirportID,CountryName,IanaTimeZone,IsActive FROM dbo.Airports WHERE Code=?', code).fetchone()
            if row:
                if tuple(row[1:]) != (name, iana, True):
                    raise ValueError(f'Sân bay {code} có thông tin khác với dữ liệu mẫu.')
                airports[code] = row[0]
            else:
                airports[code] = identity(conn.execute('INSERT dbo.Airports(Code,Name,City,CountryName,IanaTimeZone) OUTPUT inserted.AirportID VALUES(?,?,?,?,?)', code, f'Sân bay {city} ({code})', city, name, iana))
        classes = {}
        for cabin, prefix, label in CABINS:
            for bundle, suffix, bundle_label, refund, change, bag in BUNDLES:
                code = 'U' + prefix + suffix
                row = conn.execute('SELECT FareClassID,Name,Cabin,BaggageKg,RefundPercent FROM dbo.FareClasses WHERE Code=?', code).fetchone()
                expected = (f'{label} {bundle_label}', cabin, bag, refund)
                if row:
                    if tuple(row[1:]) != expected:
                        raise ValueError(f'Hạng vé {code} có chính sách khác với dữ liệu mẫu.')
                    class_id = row[0]
                else:
                    class_id = identity(conn.execute('INSERT dbo.FareClasses(Code,Name,Cabin,BaggageKg,RefundPercent) OUTPUT inserted.FareClassID VALUES(?,?,?,?,?)', code, *expected))
                    result['created_fare_classes'] += 1
                classes[class_id] = (cabin, bundle)
        planes = {}
        layout = list(seat_plan())
        for registration, airline in sorted({(f.registration, f.airline) for f in plan}):
            model = MODEL if registration.startswith('DEMO-INT-') else DEMO_MODEL
            row = conn.execute('SELECT AircraftID,AirlineID,Model,IsActive FROM dbo.Aircraft WHERE Registration=?', registration).fetchone()
            if row:
                actual = [tuple(s) for s in conn.execute('SELECT SeatNumber,RowNumber,ColumnLetter,Cabin,SeatFee,IsPriority FROM dbo.AircraftSeats WHERE AircraftID=? AND IsActive=1 ORDER BY RowNumber,ColumnLetter', row[0])]
                if tuple(row[1:]) != (airlines[airline], model, True) or actual != layout:
                    raise ValueError(f'Máy bay {registration} có sơ đồ ghế khác với dữ liệu mẫu.')
                plane_id = row[0]
            else:
                plane_id = identity(conn.execute('INSERT dbo.Aircraft(AirlineID,Registration,Model) OUTPUT inserted.AircraftID VALUES(?,?,?)', airlines[airline], registration, model))
                cursor = conn.cursor()
                cursor.executemany('INSERT dbo.AircraftSeats(AircraftID,SeatNumber,RowNumber,ColumnLetter,Cabin,SeatFee,IsPriority) VALUES(?,?,?,?,?,?,?)', [(plane_id,) + seat for seat in layout])
                drain(cursor)
                result['created_aircraft'] += 1
            planes[registration] = plane_id
        existing = {(r[0], r[1]): tuple(r[2:]) for r in conn.execute("SELECT f.FlightNumber,f.DepartureTime,f.FlightID,f.AircraftID,f.OriginID,f.DestinationID,f.ArrivalTime,f.Status FROM dbo.Flights f JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID WHERE a.Registration LIKE 'DEMO-%'")}
        fares = {(r[0], r[1]): (r[2], r[3]) for r in conn.execute("SELECT ff.FlightID,ff.FareClassID,ff.BasePrice,ff.TaxRate FROM dbo.FlightFares ff JOIN dbo.Flights f ON f.FlightID=ff.FlightID JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID WHERE a.Registration LIKE 'DEMO-%'")}
        pending = []
        for flight in plan:
            row = existing.get((flight.number, flight.departure))
            expected = (planes[flight.registration], airports[flight.origin], airports[flight.destination], flight.arrival)
            if row:
                if row[1:5] != expected:
                    raise ValueError(f'Lịch {flight.number} ngày {flight.local_date} khác với dữ liệu mẫu.')
                result['existing_flights'] += 1
                if row[5] != 'SCHEDULED':
                    result['skipped_closed_flights'] += 1
                    continue
                flight_id = row[0]
            else:
                flight_id = identity(conn.execute('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?', None, flight.number, *expected[:3], flight.departure, flight.arrival))
                result['created_flights'] += 1
            for class_id, (cabin, bundle) in classes.items():
                base = international_fare(flight, cabin, bundle) if flight.registration.startswith('DEMO-INT-') else fare_base(flight.origin, flight.destination, flight.airline, flight.local_date, cabin, bundle)
                old = fares.get((flight_id, class_id))
                if old is None:
                    pending.append((flight_id, class_id, base, TAX_RATE))
                elif old != (base, TAX_RATE):
                    raise ValueError(f'Giá chuyến {flight.number} đã được sửa. Không ghi đè giá hiện có.')
        if pending:
            cursor = conn.cursor()
            cursor.executemany('EXEC dbo.sp_SaveFare ?,?,?,?', pending)
            drain(cursor)
            result['inserted_fares'] = len(pending)
    return result


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true', help='Nạp dữ liệu vào cơ sở dữ liệu đang cấu hình.')
    mode.add_argument('--preview', action='store_true', help='Chỉ xem số liệu, không kết nối cơ sở dữ liệu.')
    parser.add_argument('--days', type=int, help='Số ngày lịch bay, từ 1 đến 90.')
    parser.add_argument('--start-date', help='Ngày đầu tiên, dạng YYYY-MM-DD.')
    args = parser.parse_args()
    try:
        days, start = resolve_window(args.days, args.start_date)
        domestic, world = build_plan(days, start), build_international_plan(days, start)
        result = dict(mode='APPLIED' if args.apply else 'PREVIEW_ONLY', start_date=start.isoformat(), days=days,
                      airports=42, domestic_flights=len(domestic), international_flights=len(world),
                      generated_flights=len(domestic) + len(world), generated_fares=(len(domestic) + len(world)) * 12,
                      note='Lịch bay và giá vé mẫu, không phải vé đang mở bán của hãng hàng không.')
        if args.apply:
            result['result'] = import_catalog(days, start)
    except (ValueError, RuntimeError) as error:
        parser.error(str(error))
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
