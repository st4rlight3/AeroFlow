from collections import defaultdict
from datetime import date,datetime,timedelta,timezone
from decimal import Decimal
import pytest

from scripts.demo_catalog import CABINS,BUNDLES,VIETNAM,TAX_RATE
from scripts.international_catalog import AIRPORTS,build_international_plan,fare_base,preview

START=date(2026,12,1)


def test_international_coverage_and_exact_presentation_dates():
    plan=build_international_plan(62,START)
    assert len(plan)==3936
    assert len(AIRPORTS)==32 and len({a[2] for a in AIRPORTS})==20
    assert len({f.registration for f in plan})==64
    assert {f.destination for f in plan if f.origin in ('HAN','SGN')}=={a[0] for a in AIRPORTS}
    for f in plan:
        assert START<=f.departure.replace(tzinfo=timezone.utc).astimezone(VIETNAM).date()<=date(2027,1,31)
        assert f.arrival.replace(tzinfo=timezone.utc).astimezone(VIETNAM).date()<=date(2027,1,31)
        assert timedelta(hours=1)<=f.arrival-f.departure<=timedelta(hours=20)


def test_every_international_aircraft_returns_before_next_departure():
    planes=defaultdict(list)
    for f in build_international_plan(62,START):planes[f.registration].append(f)
    for flights in planes.values():
        flights.sort(key=lambda f:f.departure)
        for a,b in zip(flights,flights[1:]):
            assert a.destination==b.origin
            assert b.departure-a.arrival>=timedelta(minutes=90)


def test_overlapping_import_windows_keep_identity_and_prices():
    whole={(f.number,f.departure):f for f in build_international_plan(62,START)}
    assert len(whole)==3936
    for f in build_international_plan(7,START+timedelta(days=20)):
        assert whole[(f.number,f.departure)]==f
        assert fare_base(whole[(f.number,f.departure)])==fare_base(f)


def test_international_fares_and_art_are_valid_for_all_destinations():
    from pathlib import Path
    for f in build_international_plan(4,START):
        for cabin,_,_ in CABINS:
            prices=[fare_base(f,cabin,b[0]) for b in BUNDLES]
            assert prices==sorted(prices)
            assert all(Decimal(0)<p<=Decimal(100000000) for p in prices)
    folder=Path(__file__).resolve().parents[1]/'app/static/images/destinations'
    covers=[(folder/(a[0]+'.svg')).read_bytes() for a in AIRPORTS]
    assert len(set(covers))==32


@pytest.fixture(scope='module')
def international_sql():
    import os
    if os.getenv('RUN_SQL_TESTS')!='1':pytest.skip('SQL integration not enabled.')
    assert os.environ['SQL_DATABASE'].startswith('AeroFlow_Test_')
    from scripts.seed_international import seed_international
    from app.db import query
    history={name:query('SELECT * FROM dbo.'+name+' ORDER BY 1') for name in ('Bookings','Tickets','Payments')}
    first=seed_international(4,START)
    assert history=={name:query('SELECT * FROM dbo.'+name+' ORDER BY 1') for name in history}
    second=seed_international(4,START)
    assert second.created==0 and second.updated_fares==0
    assert first.created+first.existing==len(build_international_plan(4,START))
    return second


@pytest.mark.integration
def test_international_seed_is_idempotent_and_searchable(app,international_sql):
    from app.db import query
    client=app.test_client()
    airports=client.get('/api/airports').json['items']
    assert {a[0] for a in AIRPORTS}<={a['Code'] for a in airports}
    f=query("SELECT TOP(1) f.* FROM dbo.vw_FlightAvailability f JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID WHERE a.Registration LIKE 'DEMO-INT-%' AND f.OriginCountryCode<>'VN' ORDER BY f.DepartureTime",one=True)
    args=dict(origin=f['OriginID'],destination=f['DestinationID'],date=f['DepartureDate'].isoformat(),passengers=1)
    found=client.get('/api/flights',query_string=args)
    assert found.status_code==200,found.json
    assert f['FlightID'] in {x['FlightID'] for x in found.json['items']}
    calendar=client.get('/api/flights/calendar',query_string=args)
    assert calendar.status_code==200,calendar.json
    price=next(x for x in calendar.json['items'] if x['Date']==args['date'])
    assert Decimal(price['FromPrice'])==min(Decimal(x['FromPrice']) for x in found.json['items'])
    itinerary=client.get('/api/itineraries/search',query_string=dict(OriginID=f['OriginID'],DestinationID=f['DestinationID'],Date=args['date'],Passengers=1,Cabin='ECONOMY',Connections='false'))
    assert itinerary.status_code==200,itinerary.json
    assert any(f['FlightID']==x['Flights'][0]['FlightID'] for x in itinerary.json['items'])


@pytest.mark.integration
@pytest.mark.parametrize('code,day,hours',[('SYD',date(2027,4,4),25),('SYD',date(2026,10,4),23),('JFK',date(2026,11,1),25),('JFK',date(2027,3,14),23),('DEL',date(2026,12,1),24),('YVR',date(2026,12,1),24),('YVR',date(2027,1,1),24)])
def test_civil_days_follow_dst_and_half_hour_zones(international_sql,code,day,hours):
    from app.db import query
    from app.services.timezones import airport_day_bounds
    aid=query('SELECT AirportID FROM dbo.Airports WHERE Code=?',(code,),one=True)['AirportID']
    start,end=airport_day_bounds(aid,day)
    assert end-start==timedelta(hours=hours)
    if code=='DEL':assert start==datetime(2026,11,30,18,30)
    if code=='YVR':assert start==datetime.combine(day,datetime.min.time())+timedelta(hours=7)


@pytest.mark.integration
def test_japan_birthday_age_uses_origin_local_day(app,users,flight,international_sql):
    import uuid
    from app.db import query
    from conftest import sign_in,send
    nrt=query("SELECT AirportID FROM dbo.Airports WHERE Code='NRT'",one=True)['AirportID']
    dep=datetime(2026,12,8,16,30) # Dec 9 in Tokyo; still Dec 8 in Vietnam.
    query('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?',(flight['FlightID'],'J'+uuid.uuid4().hex[:7],flight['AircraftID'],nrt,flight['OriginID'],dep,dep+timedelta(hours=5)))
    data=dict(JourneyType='ONE_WAY',Segments=[dict(FlightID=flight['FlightID'],FareClassID=flight['FareClassID'],JourneyGroup=1)],Passengers=[dict(FullName='Tokyo Birthday Demo',DateOfBirth='2014-12-09',DocumentNumber='DEMO-'+uuid.uuid4().hex[:12],TypeCode='ADULT')],Selections=[])
    c=sign_in(app,users[0]);q=send(c,'/api/itineraries/quote',data)
    assert q.status_code==200,q.json
    result=send(c,'/api/itineraries',{**data,'ExpectedTotal':q.json['Total']})
    assert result.status_code==201,result.json
    bid=result.json['booking']['BookingID']
    assert query('SELECT PassengerType FROM dbo.Tickets WHERE BookingSegmentID IN (SELECT BookingSegmentID FROM dbo.BookingSegments WHERE BookingID=?)',(bid,),one=True)['PassengerType']=='ADULT'
    assert send(c,f'/api/bookings/{bid}/payments',dict(Success=True,IdempotencyKey=uuid.uuid4().hex)).status_code==200
    ticket=c.get(f'/api/bookings/{bid}').json['tickets'][0]
    pdf=c.get(f"/api/tickets/{ticket['TicketID']}/pdf")
    assert pdf.status_code==200 and pdf.data.startswith(b'%PDF'),pdf.data[:150]
