"""Add 4-cabin demo aircraft/fares/timetable without rewriting old records."""
import argparse
from datetime import datetime,timedelta,timezone
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app.db import connection
from scripts.migrate import drain

def seed():
    with connection() as conn:
        conn.execute('EXEC dbo.sp_LockFlight 0')
        airline=conn.execute('SELECT TOP(1) AirlineID FROM dbo.Airlines ORDER BY AirlineID').fetchone()[0]
        fares=[]
        for cabin,prefix,label,mult in [('ECONOMY','E','Phổ thông',1),('PREMIUM','P','Phổ thông đặc biệt',2),('BUSINESS','B','Thương gia',3),('FIRST','F','Hạng nhất',5)]:
            for bundle,suffix,refund,change,bag,premium in [('BASIC','B',0,0,7,0),('STANDARD','S',50,1,20,300000),('FLEXIBLE','F',90,1,30,600000)]:
                code='U'+prefix+suffix
                row=conn.execute('SELECT FareClassID FROM dbo.FareClasses WHERE Code=?',code).fetchone()
                if not row:
                    row=conn.execute('INSERT dbo.FareClasses(Code,Name,Cabin,BaggageKg,RefundPercent,Bundle,ChangeAllowed,ChangeFee,CabinBaggageKg) OUTPUT inserted.FareClassID VALUES(?,?,?,?,?,?,?,?,?)',code,label+' '+bundle.title(),cabin,bag,refund,bundle,change,200000 if bundle=='STANDARD' else 0,7 if cabin=='ECONOMY' else 12).fetchone()
                fares.append((row[0],900000*mult+premium))
        planes=[]
        for index in (1,2):
            registration='DEMO-ULT-'+str(index); row=conn.execute('SELECT AircraftID FROM dbo.Aircraft WHERE Registration=?',registration).fetchone()
            if not row:
                row=conn.execute('INSERT dbo.Aircraft(AirlineID,Registration,Model) OUTPUT inserted.AircraftID VALUES(?,?,?)',airline,registration,'AeroFlow demo 4 cabins').fetchone()
                for number in range(1,13):
                    cabin='FIRST' if number==1 else 'BUSINESS' if number<=3 else 'PREMIUM' if number<=5 else 'ECONOMY'
                    for col in 'ABCDEF':
                        conn.execute('INSERT dbo.AircraftSeats(AircraftID,SeatNumber,RowNumber,ColumnLetter,Cabin,SeatFee,IsPriority) VALUES(?,?,?,?,?,?,?)',row[0],f'{col}{number}',number,col,cabin,80000 if number==6 else 0,number==6)
            planes.append(row[0])
        airports={row[0]:row[1] for row in conn.execute("SELECT Code,AirportID FROM dbo.Airports WHERE Code IN ('HAN','SGN','DAD')")}
        start=datetime.now(timezone.utc).replace(tzinfo=None,hour=0,minute=0,second=0,microsecond=0)+timedelta(days=2)
        created=0
        for offset in range(14):
            # UTC schedule; connections HAN-DAD-SGN have a 90-minute layover.
            for number,plane,origin,dest,hour,duration in [('UA100',planes[0],'HAN','SGN',2,125),('UA101',planes[0],'SGN','HAN',9,125),('UA200',planes[1],'HAN','DAD',1,90),('UA201',planes[1],'DAD','SGN',4,90),('UA202',planes[1],'SGN','DAD',8,90),('UA203',planes[1],'DAD','HAN',11,90)]:
                departure=start+timedelta(days=offset,hours=hour)
                row=conn.execute('SELECT FlightID FROM dbo.Flights WHERE FlightNumber=? AND DepartureTime=?',number,departure).fetchone()
                if row: continue
                cur=conn.execute('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?',None,number,plane,airports[origin],airports[dest],departure,departure+timedelta(minutes=duration))
                while cur.description is None: cur.nextset()
                fid=cur.fetchone()[0];drain(cur)
                for fare,base in fares: drain(conn.execute('EXEC dbo.sp_SaveFare ?,?,?,?',fid,fare,base,.1))
                created+=1
    return created

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--apply',action='store_true');a=p.parse_args()
    if not a.apply: p.error('Use --apply to add labelled demo data to the configured database.')
    print('Created demo flights:',seed())
