"""Preview/import 32 international destinations, without changing old bookings.

Run after migrate.py and seed_ultimate.py. No --apply means no SQL connection.
All imported flights use sp_SaveFlight and all prices use sp_SaveFare.
"""
import argparse
from dataclasses import asdict
from datetime import timedelta
import json
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.demo_catalog import TAX_RATE,local_today,seat_plan
from scripts.international_catalog import AIRPORTS,MODEL,build_international_plan,fare_base,preview
from scripts.seed_ultimate import SeedResult,_catalog,_drain,_identity,resolve_window


def seed_international(days=None,start_date=None):
    from app.db import connection
    days,start_date=resolve_window(days,start_date)
    if not local_today()<start_date<=local_today()+timedelta(days=365):
        raise ValueError('First date must be tomorrow or later, within the next 365 days.')
    plan=build_international_plan(days,start_date);result=SeedResult()
    with connection() as conn:
        conn.timeout=120
        conn.execute('SET NOCOUNT ON; SET XACT_ABORT ON;')
        if conn.execute('SELECT COALESCE(MAX(Version),0) FROM dbo.SchemaMigrations').fetchone()[0]<17:
            raise ValueError('Apply migrations 001–017 before importing international data.')
        lock=conn.execute("DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource='AeroFlow:schedule',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000; SELECT @r;").fetchone()[0]
        if lock<0:raise RuntimeError('Timetable is being updated; retry later.')
        _drain(conn.execute('EXEC dbo.sp_LockFlight 0'))
        airports,classes,_=_catalog(conn,result)
        for code,city,country,name,region,windows,iana,lat,lon in AIRPORTS:
            if code=='YVR':
                windows=next((zone for zone in ('British Columbia Standard Time','Yukon Standard Time') if conn.execute('SELECT 1 FROM sys.time_zone_info WHERE name=?',zone).fetchone()),None)
                if windows is None:raise ValueError('Install the British Columbia or Yukon Windows time zone before importing YVR.')
            if not conn.execute('SELECT 1 FROM sys.time_zone_info WHERE name=?',windows).fetchone():
                raise ValueError(f'Time zone {windows} is not installed on this SQL Server host.')
            row=conn.execute('SELECT AirportID,CountryCode,TimeZoneName,IanaTimeZone,IsActive FROM dbo.Airports WHERE Code=?',code).fetchone()
            if row:
                if (row[1],row[2],row[3],bool(row[4]))!=(country,windows,iana,True):
                    raise ValueError(f'{code} has different metadata or is inactive. Review it in Admin; no overwrite performed.')
                airports[code]=row[0]
            else:
                airports[code]=_identity(conn.execute('INSERT dbo.Airports(Code,Name,City,CountryCode,CountryName,RegionCode,TimeZoneName,IanaTimeZone) OUTPUT inserted.AirportID VALUES(?,?,?,?,?,?,?,?)',code,'Sân bay '+city+' ('+code+')',city,country,name,region,windows,iana))
        airlines={r[0].strip():r[1] for r in conn.execute('SELECT Code,AirlineID FROM dbo.Airlines')}
        planes={}
        for registration,airline in sorted({(f.registration,f.airline) for f in plan}):
            row=conn.execute('SELECT AircraftID,AirlineID,Model,IsActive FROM dbo.Aircraft WHERE Registration=?',registration).fetchone()
            expected=list(seat_plan())
            if row:
                actual=[tuple(r) for r in conn.execute('SELECT SeatNumber,RowNumber,ColumnLetter,Cabin FROM dbo.AircraftSeats WHERE AircraftID=? AND IsActive=1 ORDER BY RowNumber,ColumnLetter',row[0])]
                if (row[1],row[2],bool(row[3]))!=(airlines[airline],MODEL,True) or actual!=[s[:4] for s in expected]:
                    raise ValueError(f'{registration} differs from this managed demo; no overwrite performed.')
                planes[registration]=row[0]
            else:
                pid=_identity(conn.execute('INSERT dbo.Aircraft(AirlineID,Registration,Model) OUTPUT inserted.AircraftID VALUES(?,?,?)',airlines[airline],registration,MODEL))
                cursor=conn.cursor();cursor.executemany('INSERT dbo.AircraftSeats(AircraftID,SeatNumber,RowNumber,ColumnLetter,Cabin,SeatFee,IsPriority) VALUES(?,?,?,?,?,?,?)',[(pid,)+s for s in expected]);_drain(cursor)
                planes[registration]=pid;result.created_aircraft+=1
        old_fares={(r[0],r[1]):(r[2],r[3]) for r in conn.execute("SELECT ff.FlightID,ff.FareClassID,ff.BasePrice,ff.TaxRate FROM dbo.FlightFares ff JOIN dbo.Flights f ON f.FlightID=ff.FlightID JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID WHERE a.Registration LIKE 'DEMO-INT-%'")}
        pending=[]
        for flight in plan:
            row=conn.execute('SELECT FlightID,AircraftID,OriginID,DestinationID,ArrivalTime,Status FROM dbo.Flights WHERE FlightNumber=? AND DepartureTime=?',flight.number,flight.departure).fetchone()
            if row:
                if tuple(row[1:5])!=(planes[flight.registration],airports[flight.origin],airports[flight.destination],flight.arrival):
                    raise ValueError(f'{flight.number} differs from the managed plan. No flight is rescheduled.')
                result.existing+=1
                if row[5]!='SCHEDULED':result.skipped_closed_flights+=1;continue
                fid=row[0]
            else:
                fid=_identity(conn.execute('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?',None,flight.number,planes[flight.registration],airports[flight.origin],airports[flight.destination],flight.departure,flight.arrival))
                result.created+=1
            for cls,(cabin,bundle) in classes.items():
                base=fare_base(flight,cabin,bundle)
                if old_fares.get((fid,cls))!=(base,TAX_RATE):pending.append((fid,cls,base,TAX_RATE))
        if pending:
            cursor=conn.cursor();cursor.executemany('EXEC dbo.sp_SaveFare ?,?,?,?',pending);_drain(cursor)
            result.updated_fares=len(pending)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--days',type=int)
    parser.add_argument('--start-date')
    args=parser.parse_args()
    try:
        days,start=resolve_window(args.days,args.start_date);result=preview(days,start)
        result['mode']='APPLIED' if args.apply else 'PREVIEW_ONLY'
        if args.apply:result['result']=asdict(seed_international(days,start))
    except (ValueError,RuntimeError) as error:parser.error(str(error))
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
