"""Shared itinerary validation, SQL-backed search and server-side quotation."""
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from flask import g,has_request_context
from ..db import query
from ..errors import ApiError
from ..validation import integer, text, iso_date

CABINS = ('ECONOMY', 'PREMIUM', 'BUSINESS', 'FIRST')


def parse(data):
    kind=text(data,'JourneyType',1,12)
    if kind not in ('ONE_WAY','ROUND_TRIP','MULTI_CITY'):
        raise ApiError('Loại hành trình không hợp lệ.')
    segments=data.get('Segments'); passengers=data.get('Passengers'); choices=data.get('Selections',[])
    if not isinstance(segments,list) or not 1<=len(segments)<=12:
        raise ApiError('Cần từ 1 đến 12 chặng bay.')
    if not isinstance(passengers,list) or not 1<=len(passengers)<=9:
        raise ApiError('Cần từ 1 đến 9 hành khách.')
    if not isinstance(choices,list) or len(choices)>len(segments)*len(passengers):
        raise ApiError('Danh sách chọn ghế không hợp lệ.')
    if any(not isinstance(x,dict) for x in segments+passengers+choices):
        raise ApiError('Mỗi phần tử cần là một đối tượng.')
    ss=[dict(FlightID=integer(s,'FlightID'),FareClassID=integer(s,'FareClassID'),JourneyGroup=integer(s,'JourneyGroup',1,6)) for s in segments]
    pp=[]
    for p in passengers:
        dob=iso_date(p.get('DateOfBirth'))
        if not date(1900,1,1)<=dob<=date.today():
            raise ApiError('Ngày sinh không hợp lệ.')
        code=text(p,'TypeCode',1,8)
        if code not in ('ADULT','CHILD','INFANT'):
            raise ApiError('Loại hành khách không hợp lệ.')
        assistance=p.get('Assistance','NONE')
        if assistance not in ('NONE','WHEELCHAIR','HEARING','VISION'):
            raise ApiError('Yêu cầu hỗ trợ không hợp lệ.')
        pp.append(dict(FullName=text(p,'FullName',2,120),DateOfBirth=dob.isoformat(),DocumentNumber=text(p,'DocumentNumber',5,30),TypeCode=code,Assistance=assistance))
    cc=[dict(PassengerIndex=integer(c,'PassengerIndex',0,len(pp)-1),SegmentIndex=integer(c,'SegmentIndex',0,len(ss)-1),SeatID=integer(c,'SeatID')) for c in choices]
    if len({(c['PassengerIndex'],c['SegmentIndex']) for c in cc})!=len(cc):
        raise ApiError('Mỗi hành khách chỉ chọn một ghế cho mỗi chặng.')
    if len({p['DocumentNumber'] for p in pp})!=len(pp) or len({s['FlightID'] for s in ss})!=len(ss):
        raise ApiError('Không lặp giấy tờ hành khách hoặc chuyến bay.')
    return kind,ss,pp,cc


def validate_route(kind,segments,flights):
    groups=[s['JourneyGroup'] for s in segments]
    if groups[0]!=1 or any(b<a or b>a+1 for a,b in zip(groups,groups[1:])):
        raise ApiError('Nhóm hành trình phải liên tiếp từ 1.')
    if (kind=='ONE_WAY' and max(groups)!=1) or (kind=='ROUND_TRIP' and max(groups)!=2) or (kind=='MULTI_CITY' and max(groups)<2):
        raise ApiError('Số nhóm chặng không khớp loại hành trình.')
    for i,(a,b) in enumerate(zip(flights,flights[1:])):
        gap=(b['DepartureTime']-a['ArrivalTime']).total_seconds()/60
        if gap<60 or (groups[i]==groups[i+1] and (a['DestinationID']!=b['OriginID'] or gap>480)):
            raise ApiError('Nối chuyến cần cùng sân bay và từ 60 phút đến 8 giờ; các chặng phải theo thứ tự thời gian.')
    if kind=='ROUND_TRIP':
        turnaround=groups.index(2)
        if flights[0]['OriginID']!=flights[-1]['DestinationID'] or flights[turnaround-1]['DestinationID']!=flights[turnaround]['OriginID']:
            raise ApiError('Khứ hồi phải quay về sân bay xuất phát.')


def quote(data):
    kind,segments,passengers,selections=parse(data)
    flights=[]; fares=[]
    for s in segments:
        f=query("SELECT * FROM dbo.vw_FlightAvailability WHERE FlightID=? AND Status='SCHEDULED' AND DepartureTime>DATEADD(hour,2,SYSUTCDATETIME())",(s['FlightID'],),one=True)
        fare=query('SELECT c.*,ff.BasePrice,ff.TaxRate FROM dbo.FareClasses c JOIN dbo.FlightFares ff ON ff.FareClassID=c.FareClassID WHERE ff.FlightID=? AND ff.FareClassID=?',(s['FlightID'],s['FareClassID']),one=True)
        if not f or not fare:
            raise ApiError('Chuyến hoặc hạng vé không còn mở bán.',409)
        flights.append(f);fares.append(fare)
    validate_route(kind,segments,flights)
    fly_day=flights[0]['DepartureDate']
    types=[]
    for p in passengers:
        birth=date.fromisoformat(p['DateOfBirth'])
        age=fly_day.year-birth.year-((fly_day.month,fly_day.day)<(birth.month,birth.day))
        expected='INFANT' if age<2 else ('CHILD' if age<12 else 'ADULT')
        if p['TypeCode']!=expected:
            raise ApiError('Loại hành khách không khớp tuổi tại ngày bay.')
        types.append(expected)
    if 'ADULT' not in types or types.count('INFANT')>types.count('ADULT'):
        raise ApiError('Cần người lớn đi cùng; mỗi người lớn tối đa một em bé.')
    factors={x['TypeCode']:x['PriceFactor'] for x in query('SELECT TypeCode,PriceFactor FROM dbo.PassengerTypes')}
    money=lambda n:n.quantize(Decimal('.01'),rounding=ROUND_HALF_UP)
    requested={(c['PassengerIndex'],c['SegmentIndex']):c['SeatID'] for c in selections}
    preference='ANY'
    if has_request_context() and getattr(g,'user',None):
        pref=query('SELECT SeatPreference FROM dbo.UserPreferences WHERE UserID=?',(g.user['UserID'],),one=True)
        if pref: preference=pref['SeatPreference']
    lines=[];resolved=[]
    for si,(segment,fare) in enumerate(zip(segments,fares)):
        query('EXEC dbo.sp_ExpireFlightHolds ?',(segment['FlightID'],))
        seats=query('SELECT s.* FROM dbo.AircraftSeats s JOIN dbo.Flights f ON f.AircraftID=s.AircraftID WHERE f.FlightID=? AND s.IsActive=1 AND s.Cabin=? AND NOT EXISTS(SELECT 1 FROM dbo.FlightSeatAssignments a WHERE a.FlightID=f.FlightID AND a.SeatID=s.SeatID AND a.IsActive=1) ORDER BY s.SeatFee,s.RowNumber,s.ColumnLetter',(segment['FlightID'],fare['Cabin']))
        preferred={'WINDOW':'AF','AISLE':'CD'}.get(preference,'ABCDEF')
        seats.sort(key=lambda s:(s['SeatFee'],s['ColumnLetter'] not in preferred,s['RowNumber'],s['ColumnLetter']))
        available={s['SeatID']:s for s in seats}
        # Reserve explicitly requested seats before suggesting seats for other passengers.
        explicit=[v for (pi,sj),v in requested.items() if sj==si]
        if len(explicit)!=len(set(explicit)) or any(v not in available for v in explicit):
            raise ApiError('Ghế đã được giữ hoặc không phù hợp hạng vé.',409)
        for pi,p in enumerate(passengers):
            sid=requested.get((pi,si))
            if sid is None:
                sid=next((s['SeatID'] for s in seats if s['SeatID'] in available and s['SeatID'] not in explicit),None)
            if sid is None or sid not in available:
                raise ApiError('Không còn đủ ghế.',409)
            seat=available.pop(sid);base=money(fare['BasePrice']*factors[p['TypeCode']]);tax=money(base*fare['TaxRate']);fee=seat['SeatFee']
            resolved.append(dict(PassengerIndex=pi,SegmentIndex=si,SeatID=sid))
            lines.append(dict(PassengerIndex=pi,SegmentIndex=si,FullName=p['FullName'],TypeCode=p['TypeCode'],FlightNumber=flights[si]['FlightNumber'],SeatID=sid,SeatNumber=seat['SeatNumber'],FareClassID=segment['FareClassID'],FareName=fare['Name'],BaseFare=base,TaxAmount=tax,SeatFee=fee,Amount=base+tax+fee,RefundPercent=fare['RefundPercent']))
    return dict(JourneyType=kind,Segments=segments,Passengers=passengers,Selections=resolved,Flights=flights,Lines=lines,Total=sum(x['Amount'] for x in lines),Notice='Báo giá chưa giữ ghế. Em bé có ghế riêng trong mô phỏng này.')


def search(args):
    origin=integer(args,'OriginID');dest=integer(args,'DestinationID');day=iso_date(args.get('Date'))
    if origin==dest:
        raise ApiError('Điểm đi và điểm đến phải khác nhau.')
    count=integer(args,'Passengers',1,9);cabin=args.get('Cabin','ECONOMY')
    if cabin not in CABINS:
        raise ApiError('Khoang không hợp lệ.')
    from .timezones import airport_day_bounds
    start,_=airport_day_bounds(origin,day-timedelta(days=3))
    _,end=airport_day_bounds(origin,day+timedelta(days=5))
    rows=query("""SELECT f.*,c.FareClassID,c.Name FareName,c.Cabin,c.Bundle,c.BaggageKg,c.CabinBaggageKg,c.RefundPercent,c.ChangeAllowed,c.ChangeFee,ff.BasePrice,ff.TaxRate,
     dbo.fn_CalculateTicketPrice(ff.BasePrice,ff.TaxRate) Price,
     (SELECT COUNT(*) FROM dbo.AircraftSeats s WHERE s.AircraftID=f.AircraftID AND s.Cabin=c.Cabin AND s.IsActive=1 AND NOT EXISTS
      (SELECT 1 FROM dbo.FlightSeatAssignments a JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Bookings b ON b.BookingID=bp.BookingID
       WHERE a.FlightID=f.FlightID AND a.SeatID=s.SeatID AND a.IsActive=1 AND (b.Status='CONFIRMED' OR (b.Status='HELD' AND b.ExpiresAt>SYSUTCDATETIME())))) CabinAvailable
     FROM dbo.vw_FlightAvailability f JOIN dbo.FlightFares ff ON ff.FlightID=f.FlightID JOIN dbo.FareClasses c ON c.FareClassID=ff.FareClassID
     WHERE f.Status='SCHEDULED' AND f.DepartureTime>DATEADD(hour,2,SYSUTCDATETIME()) AND f.DepartureTime>=? AND f.DepartureTime<? AND c.Cabin=? AND (f.OriginID=? OR f.DestinationID=?) ORDER BY f.DepartureTime,Price""",(start,end,cabin,origin,dest))
    flights={}
    for row in rows:
        if row['CabinAvailable']<count:
            continue
        flight=flights.setdefault(row['FlightID'],{k:row[k] for k in ('FlightID','FlightNumber','OriginID','DestinationID','OriginCode','DestinationCode','OriginCity','DestinationCity','DepartureTime','ArrivalTime','AirlineName','AirlineCode','AircraftID','OriginTimeZone','DestinationTimeZone','DepartureDate','ArrivalDate')})
        flight.setdefault('Fares',[]).append({k:row[k] for k in ('FareClassID','FareName','Cabin','Bundle','BaggageKg','CabinBaggageKg','RefundPercent','ChangeAllowed','ChangeFee','Price','CabinAvailable')})
    options=[];calendar={}
    def add(parts):
        local_day=parts[0]['DepartureDate']
        if abs((local_day-day).days)>3:
            return
        price=sum(p['Fares'][0]['Price'] for p in parts)*count
        calendar[local_day]=min(calendar.get(local_day,price),price)
        if local_day==day:
            options.append(dict(Key='-'.join(str(p['FlightID']) for p in parts),Flights=parts,FromPrice=price,Stops=len(parts)-1,DurationMinutes=int((parts[-1]['ArrivalTime']-parts[0]['DepartureTime']).total_seconds()/60)))
    all_flights=list(flights.values())
    for first in all_flights:
        if first['OriginID']!=origin:
            continue
        if first['DestinationID']==dest:
            add([first])
        elif args.get('Connections','true')!='false':
            for second in all_flights:
                gap=(second['DepartureTime']-first['ArrivalTime']).total_seconds()/60
                if second['OriginID']==first['DestinationID'] and second['DestinationID']==dest and 60<=gap<=480:
                    add([first,second])
    options.sort(key=lambda x:x['FromPrice'])
    return dict(items=options,calendar=[dict(Date=d,FromPrice=p) for d,p in sorted(calendar.items())],PriceNote='Giá tham khảo cho người lớn; báo giá cuối tính theo tuổi, ghế và dịch vụ đã chọn.')
