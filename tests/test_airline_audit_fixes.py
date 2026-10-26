"""Regression checks for the concrete audit failures, on isolated SQL Server."""
from datetime import datetime, timedelta, timezone
import uuid
import pytest
from app.db import query
from conftest import send, sign_in

pytestmark=pytest.mark.integration


def test_operations_partial_update_preserves_fields_and_rejects_stale_write(app,users,flight):
    admin=sign_in(app,users[2]); customer=sign_in(app,users[0]); path=f"/api/admin/flights/{flight['FlightID']}/operations"
    assert customer.get(path).status_code==403
    estimated=(flight['DepartureTime']+timedelta(minutes=30)).isoformat()+'Z'
    assert send(admin,path,dict(Gate='B12',EstimatedDeparture=estimated,OperationNote='Ban đầu'),method='PUT').status_code==200
    original=admin.get(path).json['flight']
    assert send(admin,path,dict(OperationNote='Ghi chú mới'),method='PUT').status_code==200
    after=admin.get(path).json['flight']
    assert after['Gate']=='B12' and after['EstimatedDeparture']==original['EstimatedDeparture']
    assert after['OperationNote']=='Ghi chú mới'
    assert send(admin,path,dict(OperationNote='Ghi đè cũ',Original=original),method='PUT').status_code==409
    assert admin.get(path).json['flight']['OperationNote']=='Ghi chú mới'
    assert send(admin,path,dict(Gate=None),method='PUT').status_code==200
    cleared=admin.get(path).json['flight']
    assert cleared['Gate'] is None and cleared['EstimatedDeparture']==original['EstimatedDeparture']


@pytest.mark.parametrize(('boundary','expected'),[(2,'CHILD'),(12,'ADULT')])
def test_age_boundary_uses_vietnam_departure_day_in_quote_create_and_legacy(app,users,flight,boundary,expected):
    client=sign_in(app,users[0])
    local_day=(datetime.now(timezone.utc)+timedelta(days=10)).date()
    utc_departure=datetime.combine(local_day,datetime.min.time())-timedelta(hours=6,minutes=30)
    query('UPDATE dbo.Flights SET DepartureTime=?,ArrivalTime=? WHERE FlightID=?',
          (utc_departure,utc_departure+timedelta(hours=2),flight['FlightID']))
    birth=local_day.replace(year=local_day.year-boundary).isoformat()
    passengers=[dict(FullName='Người lớn demo',DateOfBirth='1990-01-01',DocumentNumber='D-'+uuid.uuid4().hex[:10],TypeCode='ADULT'),
                dict(FullName='Khách đúng ngày sinh',DateOfBirth=birth,DocumentNumber='D-'+uuid.uuid4().hex[:10],TypeCode=expected)]
    data=dict(JourneyType='ONE_WAY',Segments=[dict(FlightID=flight['FlightID'],FareClassID=flight['FareClassID'],JourneyGroup=1)],Passengers=passengers,Selections=[])
    priced=send(client,'/api/itineraries/quote',data)
    assert priced.status_code==200,priced.json
    data.update(ExpectedTotal=priced.json['Total'],Selections=priced.json['Selections'])
    created=send(client,'/api/itineraries',data)
    assert created.status_code==201,created.json
    legacy=[]
    for i,p in enumerate(passengers):
        legacy.append(dict(FullName=p['FullName'],DateOfBirth=p['DateOfBirth'],DocumentNumber='L-'+uuid.uuid4().hex[:10],SeatID=flight['Seats'][i+4]['SeatID'],FareClassID=flight['FareClassID']))
    r=send(client,'/api/bookings',dict(FlightID=flight['FlightID'],Passengers=legacy))
    assert r.status_code==201,r.json


def test_new_aircraft_business_rows_are_at_front_without_rewriting_existing(app,users):
    admin=sign_in(app,users[2]); airline=query('SELECT TOP(1) AirlineID ID FROM dbo.Airlines',one=True)['ID']
    r=send(admin,'/api/admin/catalog/aircraft',dict(AirlineID=airline,Registration='QA-'+uuid.uuid4().hex[:10],Model='Cabin test',IsActive=True,Rows=4,BusinessRows=1))
    assert r.status_code==200,r.json
    seats=query('SELECT RowNumber,Cabin FROM dbo.AircraftSeats WHERE AircraftID=?',(r.json['id'],))
    assert len(seats)==24
    assert all(s['Cabin']==('BUSINESS' if s['RowNumber']==1 else 'ECONOMY') for s in seats)


def test_aircraft_must_be_at_previous_destination_before_next_flight(app,users,flight):
    admin=sign_in(app,users[2]); dad=query("SELECT AirportID ID FROM dbo.Airports WHERE Code='DAD'",one=True)['ID']
    departure=flight['DepartureTime']+timedelta(hours=4)
    def create(origin,dest,dep):
        return send(admin,'/api/admin/flights',dict(FlightNumber='P'+uuid.uuid4().hex[:7],AircraftID=flight['AircraftID'],OriginID=origin,DestinationID=dest,DepartureTime=dep.isoformat()+'Z',ArrivalTime=(dep+timedelta(hours=1)).isoformat()+'Z'))
    bad=create(dad,flight['OriginID'],departure)
    assert bad.status_code==409 and bad.json['error']['code']=='SQL_51018',bad.json
    assert query('SELECT COUNT(*) N FROM dbo.Flights WHERE AircraftID=?',(flight['AircraftID'],),one=True)['N']==1
    # An unpriced SGN-DAD flight can serve as an explicit positioning leg.
    positioning=create(flight['DestinationID'],dad,departure)
    assert positioning.status_code==201,positioning.json
    returning=create(dad,flight['OriginID'],departure+timedelta(hours=3))
    assert returning.status_code==201,returning.json


def test_admin_can_read_configured_fare_even_when_cabin_is_full(app,users,flight):
    customer=sign_in(app,users[0]); admin=sign_in(app,users[2])
    for indices in (range(9),range(9,12)):
        people=[dict(FullName='Khách demo',DateOfBirth='1990-01-01',DocumentNumber='T-'+uuid.uuid4().hex[:10],SeatID=flight['Seats'][i]['SeatID'],FareClassID=flight['FareClassID']) for i in indices]
        response=send(customer,'/api/bookings',dict(FlightID=flight['FlightID'],Passengers=people))
        assert response.status_code==201,response.json
    assert customer.get(f"/api/flights/{flight['FlightID']}").json['fares']==[]
    path=f"/api/admin/flights/{flight['FlightID']}/fares"
    assert customer.get(path).status_code==403
    configured=admin.get(path)
    assert configured.status_code==200 and len(configured.json['items'])==1
    assert float(configured.json['items'][0]['BasePrice'])==1000000
