import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from threading import Barrier
import pytest
from app.db import query
from conftest import sign_in, send, pay


def another(flight,origin,destination,departure):
    old=query('SELECT AirlineID FROM dbo.Aircraft WHERE AircraftID=?',(flight['AircraftID'],),one=True)
    aircraft=query('SET NOCOUNT ON; INSERT dbo.Aircraft(AirlineID,Registration,Model) VALUES(?,?,?); SELECT CONVERT(int,SCOPE_IDENTITY()) ID',(old['AirlineID'],'U-'+uuid.uuid4().hex[:12],'Ultimate test'),one=True)['ID']
    query('INSERT dbo.AircraftSeats(AircraftID,SeatNumber,RowNumber,ColumnLetter,Cabin) SELECT ?,SeatNumber,RowNumber,ColumnLetter,Cabin FROM dbo.AircraftSeats WHERE AircraftID=?',(aircraft,flight['AircraftID']))
    fid=query('EXEC dbo.sp_SaveFlight ?,?,?,?,?,?,?',(None,'U'+uuid.uuid4().hex[:7],aircraft,origin,destination,departure,departure+timedelta(hours=2)),one=True)['FlightID']
    query('EXEC dbo.sp_SaveFare ?,?,?,?',(fid,flight['FareClassID'],1000000,.1))
    return dict(FlightID=fid,FareClassID=flight['FareClassID'],Seats=query('EXEC dbo.sp_GetAvailableSeats ?',(fid,)))


def payload(flights,kind='ONE_WAY',groups=None):
    return dict(JourneyType=kind,Segments=[dict(FlightID=f['FlightID'],FareClassID=f['FareClassID'],JourneyGroup=(groups or [1]*len(flights))[i]) for i,f in enumerate(flights)],Passengers=[dict(FullName='Khách Ultimate Demo',DateOfBirth='1990-01-01',DocumentNumber='ULT-'+uuid.uuid4().hex[:10],TypeCode='ADULT')],Selections=[])


@pytest.fixture
def legs(flight):
    mid=query("SELECT AirportID FROM dbo.Airports WHERE Code='DAD'",one=True)['AirportID']
    outbound=another(flight,flight['DestinationID'],mid,flight['DepartureTime']+timedelta(hours=3,minutes=30))
    home=another(flight,mid,flight['OriginID'],flight['DepartureTime']+timedelta(days=2))
    return [flight,outbound,home]


@pytest.mark.parametrize('kind,groups', [('ONE_WAY',[1,1]),('ROUND_TRIP',[1,1,2]),('MULTI_CITY',[1,2,3])])
def test_unified_itinerary_quote_book_pay_cancel(app,users,legs,kind,groups):
    client=sign_in(app,users[0]); data=payload(legs[:len(groups)],kind,groups)
    priced=send(client,'/api/itineraries/quote',data)
    assert priced.status_code==200,priced.get_json()
    q=priced.get_json();data.update(Selections=q['Selections'],ExpectedTotal=q['Total'])
    created=send(client,'/api/itineraries',data)
    assert created.status_code==201,created.get_json()
    bid=created.get_json()['booking']['BookingID']
    details=client.get(f'/api/itineraries/{bid}').get_json()
    assert len(details['segments'])==len(groups)==len(details['tickets'])
    assert pay(client,bid).status_code==200
    assert all(t['Status']=='VALID' for t in client.get(f'/api/itineraries/{bid}').get_json()['tickets'])
    assert send(client,f'/api/bookings/{bid}/cancel').status_code==200
    assert all(t['Status']=='VOID' for t in client.get(f'/api/itineraries/{bid}').get_json()['tickets'])
    assert query("SELECT COUNT(*) N FROM dbo.FlightSeatAssignments a JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=? AND a.IsActive=1",(bid,),one=True)['N']==0


def test_new_oneway_automatic_assignment_and_price_guard(app,users,flight):
    client=sign_in(app,users[0]);data=payload([flight]);data['ExpectedTotal']='1'
    r=send(client,'/api/itineraries',data)
    assert r.status_code==409,r.get_json()
    assert query('SELECT COUNT(*) N FROM dbo.Bookings WHERE UserID=?',(users[0]['UserID'],),one=True)['N']==0
    data.pop('ExpectedTotal')
    assert send(client,'/api/itineraries',data).status_code==201


def test_invalid_connection_and_roundtrip_rejected(app,users,legs):
    c=sign_in(app,users[0]);d=payload([legs[0],legs[2]])
    assert send(c,'/api/itineraries',d).status_code==400
    d=payload(legs[:2],'ROUND_TRIP',[1,2])
    assert send(c,'/api/itineraries',d).status_code==400


def test_second_segment_expiration_releases_entire_hold(app,users,legs):
    c=sign_in(app,users[0]);r=send(c,'/api/itineraries',payload(legs[:2]));assert r.status_code==201,r.get_json()
    bid=r.get_json()['booking']['BookingID']
    query('UPDATE dbo.Bookings SET CreatedAt=DATEADD(minute,-20,SYSUTCDATETIME()),ExpiresAt=DATEADD(minute,-1,SYSUTCDATETIME()) WHERE BookingID=?',(bid,))
    c.get(f"/api/flights/{legs[1]['FlightID']}/seats")
    details=c.get(f'/api/itineraries/{bid}').get_json()
    assert details['booking']['Status']=='EXPIRED'
    assert all(t['Status']=='VOID' for t in details['tickets'])


def test_shared_second_segment_concurrency_rolls_back_first_segment(app,users,legs):
    clients=[sign_in(app,u) for u in users[:2]];barrier=Barrier(2)
    def run(i):
        d=payload(legs[:2]);d['Selections']=[dict(PassengerIndex=0,SegmentIndex=0,SeatID=legs[0]['Seats'][i]['SeatID']),dict(PassengerIndex=0,SegmentIndex=1,SeatID=legs[1]['Seats'][0]['SeatID'])]
        barrier.wait();return send(clients[i],'/api/itineraries',d).status_code
    with ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(run,[0,1]))
    assert sorted(results)==[201,409]
    assert query('SELECT COUNT(*) N FROM dbo.Bookings WHERE UserID IN (?,?)',(users[0]['UserID'],users[1]['UserID']),one=True)['N']==1
    assert query('SELECT COUNT(*) N FROM dbo.FlightSeatAssignments WHERE FlightID=? AND IsActive=1',(legs[0]['FlightID'],),one=True)['N']==1


def test_cancel_second_flight_refunds_whole_itinerary(app,users,legs):
    c=sign_in(app,users[0]);admin=sign_in(app,users[2]);r=send(c,'/api/itineraries',payload(legs[:2]));assert r.status_code==201,r.get_json()
    bid=r.get_json()['booking']['BookingID'];assert pay(c,bid).status_code==200
    assert send(admin,f"/api/admin/flights/{legs[1]['FlightID']}/status",{'Status':'CANCELLED'},'PUT').status_code==200
    assert c.get(f'/api/itineraries/{bid}').get_json()['booking']['Status']=='CANCELLED'
    refund=query("SELECT Amount FROM dbo.Payments WHERE BookingID=? AND Kind='REFUND'",(bid,),one=True)
    assert str(refund['Amount'])=='2200000.00'


def test_itinerary_ownership_and_child_validation(app,users,flight):
    c=sign_in(app,users[0]);other=sign_in(app,users[1]);d=payload([flight])
    d['Passengers'][0]['TypeCode']='CHILD';assert send(c,'/api/itineraries',d).status_code==400
    d['Passengers'][0]['TypeCode']='ADULT';r=send(c,'/api/itineraries',d);assert r.status_code==201
    assert other.get('/api/itineraries/'+str(r.get_json()['booking']['BookingID'])).status_code==404


def test_search_returns_direct_and_connecting_options(app,users,legs):
    c=sign_in(app,users[0]);f=legs[0];dest=query('SELECT DestinationID FROM dbo.Flights WHERE FlightID=?',(legs[1]['FlightID'],),one=True)['DestinationID']
    day=(f['DepartureTime']+timedelta(hours=7)).date().isoformat()
    r=c.get(f"/api/itineraries/search?OriginID={f['OriginID']}&DestinationID={dest}&Date={day}&Passengers=1&Cabin=ECONOMY")
    assert r.status_code==200,r.get_json()
    assert any([x['FlightID'] for x in o['Flights']]==[legs[0]['FlightID'],legs[1]['FlightID']] for o in r.get_json()['items'])
