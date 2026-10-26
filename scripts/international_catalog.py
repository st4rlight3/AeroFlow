"""Original fictional international routes; prices are VND teaching estimates.

Aircraft fly out and back to their assigned Vietnamese base every 48 hours.
Each destination has a daily outbound service, alternating HAN and SGN. The
absolute calendar ordinal fixes identities across overlapping seed windows.
"""
from datetime import datetime, time, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from math import asin, ceil, cos, radians, sin, sqrt

from scripts.demo_catalog import PlannedFlight, VIETNAM, CABIN_MULTIPLIER, BUNDLE_PREMIUM, TAX_RATE

# Code, city, country code/name, region, Windows/IANA zones, latitude/longitude.
AIRPORTS = (
 ('SIN','Singapore','SG','Singapore','ASIA','Singapore Standard Time','Asia/Singapore',1.364,103.992),
 ('BKK','Bangkok','TH','Thái Lan','ASIA','SE Asia Standard Time','Asia/Bangkok',13.690,100.750),
 ('HKT','Phuket','TH','Thái Lan','ASIA','SE Asia Standard Time','Asia/Bangkok',8.113,98.317),
 ('CNX','Chiang Mai','TH','Thái Lan','ASIA','SE Asia Standard Time','Asia/Bangkok',18.767,98.963),
 ('KUL','Kuala Lumpur','MY','Malaysia','ASIA','Singapore Standard Time','Asia/Kuala_Lumpur',2.746,101.710),
 ('PEN','Penang','MY','Malaysia','ASIA','Singapore Standard Time','Asia/Kuala_Lumpur',5.297,100.277),
 ('DPS','Bali','ID','Indonesia','ASIA','Singapore Standard Time','Asia/Makassar',-8.748,115.167),
 ('CGK','Jakarta','ID','Indonesia','ASIA','SE Asia Standard Time','Asia/Jakarta',-6.126,106.656),
 ('MNL','Manila','PH','Philippines','ASIA','Singapore Standard Time','Asia/Manila',14.509,121.020),
 ('CEB','Cebu','PH','Philippines','ASIA','Singapore Standard Time','Asia/Manila',10.308,123.979),
 ('HKG','Hồng Kông','HK','Hồng Kông','ASIA','China Standard Time','Asia/Hong_Kong',22.308,113.918),
 ('TPE','Đài Bắc','TW','Đài Loan','ASIA','Taipei Standard Time','Asia/Taipei',25.080,121.234),
 ('ICN','Seoul','KR','Hàn Quốc','ASIA','Korea Standard Time','Asia/Seoul',37.460,126.441),
 ('PUS','Busan','KR','Hàn Quốc','ASIA','Korea Standard Time','Asia/Seoul',35.180,128.938),
 ('NRT','Tokyo','JP','Nhật Bản','ASIA','Tokyo Standard Time','Asia/Tokyo',35.765,140.386),
 ('KIX','Osaka','JP','Nhật Bản','ASIA','Tokyo Standard Time','Asia/Tokyo',34.435,135.244),
 ('PEK','Bắc Kinh','CN','Trung Quốc','ASIA','China Standard Time','Asia/Shanghai',40.080,116.584),
 ('PVG','Thượng Hải','CN','Trung Quốc','ASIA','China Standard Time','Asia/Shanghai',31.144,121.808),
 ('DEL','New Delhi','IN','Ấn Độ','ASIA','India Standard Time','Asia/Kolkata',28.556,77.100),
 ('BOM','Mumbai','IN','Ấn Độ','ASIA','India Standard Time','Asia/Kolkata',19.089,72.868),
 ('DXB','Dubai','AE','Các Tiểu vương quốc Ả Rập Thống nhất','MIDDLE_EAST','Arabian Standard Time','Asia/Dubai',25.253,55.366),
 ('DOH','Doha','QA','Qatar','MIDDLE_EAST','Arab Standard Time','Asia/Qatar',25.273,51.608),
 ('IST','Istanbul','TR','Thổ Nhĩ Kỳ','EUROPE','Turkey Standard Time','Europe/Istanbul',41.275,28.752),
 ('CDG','Paris','FR','Pháp','EUROPE','Romance Standard Time','Europe/Paris',49.010,2.548),
 ('LHR','London','GB','Vương quốc Anh','EUROPE','GMT Standard Time','Europe/London',51.470,-0.454),
 ('FRA','Frankfurt','DE','Đức','EUROPE','W. Europe Standard Time','Europe/Berlin',50.037,8.562),
 ('SYD','Sydney','AU','Úc','OCEANIA','AUS Eastern Standard Time','Australia/Sydney',-33.946,151.177),
 ('MEL','Melbourne','AU','Úc','OCEANIA','AUS Eastern Standard Time','Australia/Melbourne',-37.669,144.841),
 ('LAX','Los Angeles','US','Hoa Kỳ','AMERICAS','Pacific Standard Time','America/Los_Angeles',33.942,-118.408),
 ('SFO','San Francisco','US','Hoa Kỳ','AMERICAS','Pacific Standard Time','America/Los_Angeles',37.621,-122.379),
 ('JFK','New York','US','Hoa Kỳ','AMERICAS','Eastern Standard Time','America/New_York',40.641,-73.778),
 ('YVR','Vancouver','CA','Canada','AMERICAS','British Columbia Standard Time','America/Vancouver',49.195,-123.178),
)
LOOKUP = {a[0]: a for a in AIRPORTS}
MODEL = 'AeroFlow demo long range 150'


def distance(origin, destination):
    from scripts.demo_catalog import AIRPORT_COORDINATES
    coords = {**AIRPORT_COORDINATES, **{a[0]:a[-2:] for a in AIRPORTS}}
    a,b=coords[origin],coords[destination]
    p,q=map(radians,(a[0],b[0])); dp=q-p;dl=radians(b[1]-a[1])
    return round(12742*asin(min(1,sqrt(sin(dp/2)**2+cos(p)*cos(q)*sin(dl/2)**2))))


def minutes(origin,destination):
    return max(70,ceil((40+distance(origin,destination)/13)/5)*5)


def build_international_plan(days, start_date):
    from scripts.demo_catalog import build_plan
    # Reuse strict date/window validation without mixing domestic records.
    build_plan(days,start_date)
    from datetime import date
    if isinstance(start_date,str):start_date=date.fromisoformat(start_date)
    end=datetime.combine(start_date+timedelta(days=days),time.min,VIETNAM).astimezone(timezone.utc).replace(tzinfo=None)
    plan=[]
    for offset in range(days):
        day=start_date+timedelta(days=offset)
        for i,airport in enumerate(AIRPORTS):
            dest=airport[0];bi=(day.toordinal()+i)%2;base=('HAN','SGN')[bi]
            airline=('AF','LS','BA')[i%3]
            departure=(datetime.combine(day,time(7+i%5,15*(i%4)),VIETNAM)
                       .astimezone(timezone.utc).replace(tzinfo=None))
            arrival=departure+timedelta(minutes=minutes(base,dest))
            back=arrival+timedelta(hours=3)
            home=back+timedelta(minutes=minutes(base,dest))
            # A complete rotation stays inside the requested presentation window.
            if home>=end:continue
            registration=f'DEMO-INT-{base}-{dest}'
            plan.extend((PlannedFlight(registration,airline,f'IX{i:02}{bi}1',base,dest,departure,arrival),
                         PlannedFlight(registration,airline,f'IX{i:02}{bi}2',dest,base,back,home)))
    return sorted(plan,key=lambda f:(f.departure,f.number))


def fare_base(flight,cabin='ECONOMY',bundle='BASIC'):
    day=flight.local_date
    target=(Decimal(1800000+distance(flight.origin,flight.destination)*850)
            * (Decimal('1.08') if day.weekday() in (4,5,6) else Decimal(1))
            * (Decimal(1)+Decimal(day.toordinal()%5)*Decimal('.02'))
            * CABIN_MULTIPLIER[cabin]+BUNDLE_PREMIUM[bundle]*CABIN_MULTIPLIER[cabin])
    return (target/(1+TAX_RATE)/1000).quantize(Decimal(1),rounding=ROUND_HALF_UP)*Decimal('1000.00')


def preview(days,start_date):
    plan=build_international_plan(days,start_date)
    return dict(planned_international_flights=len(plan),international_airports=len(AIRPORTS),
                countries_and_territories=len({a[2] for a in AIRPORTS}),
                international_aircraft=len({f.registration for f in plan}),
                planned_fare_rows=len(plan)*12,
                note='Fictional timetable and VND demo prices; not real airline inventory.')
