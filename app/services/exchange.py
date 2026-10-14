from decimal import Decimal,ROUND_HALF_UP
from ..db import query
from ..errors import ApiError

def quote_exchange(segment_id,flight_id,fare_id,user):
    segment=query("SELECT s.*,b.UserID,b.Status BookingStatus FROM dbo.BookingSegments s JOIN dbo.Bookings b ON b.BookingID=s.BookingID WHERE s.BookingSegmentID=? AND b.UserID=?",(segment_id,user['UserID']),one=True)
    if not segment: raise ApiError('Không tìm thấy chặng.',404)
    if segment['BookingStatus']!='CONFIRMED' or segment['Status']!='ACTIVE': raise ApiError('Chặng không thể đổi.',409)
    tickets=query('SELECT t.TicketID,t.Status,t.PassengerType,r.ChangeAllowed,r.ChangeFee,pt.PriceFactor,dbo.fn_TicketPaidValue(t.TicketID) PaidValue,COALESCE(d.Amount,0) DiscountAmount,COALESCE(e.Amount,0) ExtraAmount FROM dbo.Tickets t JOIN dbo.TicketRules r ON r.TicketID=t.TicketID JOIN dbo.PassengerTypes pt ON pt.TypeCode=t.PassengerType LEFT JOIN dbo.TicketDiscounts d ON d.TicketID=t.TicketID OUTER APPLY(SELECT SUM(Quantity*UnitPrice) Amount FROM dbo.BookingExtras WHERE TicketID=t.TicketID) e WHERE t.BookingSegmentID=? ORDER BY t.TicketID',(segment_id,))
    if not tickets or any(t['Status']!='VALID' or not t['ChangeAllowed'] for t in tickets): raise ApiError('Chặng chứa vé không được đổi.',409)
    fare=query("SELECT ff.BasePrice,ff.TaxRate,fc.Cabin,fc.Name,f.FlightNumber,f.DepartureTime FROM dbo.FlightFares ff JOIN dbo.FareClasses fc ON fc.FareClassID=ff.FareClassID JOIN dbo.Flights f ON f.FlightID=ff.FlightID WHERE ff.FlightID=? AND ff.FareClassID=? AND f.Status='SCHEDULED' AND f.DepartureTime>DATEADD(hour,24,SYSUTCDATETIME())",(flight_id,fare_id),one=True)
    if not fare: raise ApiError('Chuyến/hạng mới không còn đủ điều kiện đổi.',409)
    query('EXEC dbo.sp_ExpireFlightHolds ?',(flight_id,))
    seats=query('SELECT s.SeatID,s.SeatNumber,s.SeatFee FROM dbo.AircraftSeats s JOIN dbo.Flights f ON f.AircraftID=s.AircraftID WHERE f.FlightID=? AND s.Cabin=? AND s.IsActive=1 AND NOT EXISTS(SELECT 1 FROM dbo.FlightSeatAssignments a WHERE a.FlightID=f.FlightID AND a.SeatID=s.SeatID AND a.IsActive=1 AND NOT EXISTS(SELECT 1 FROM dbo.Tickets t WHERE t.AssignmentID=a.AssignmentID AND t.BookingSegmentID=?)) ORDER BY s.SeatFee,s.RowNumber,s.ColumnLetter',(flight_id,fare['Cabin'],segment_id))
    if len(seats)<len(tickets): raise ApiError('Không đủ ghế cho toàn bộ hành khách của chặng.',409)
    money=lambda v:v.quantize(Decimal('.01'),rounding=ROUND_HALF_UP)
    old=sum(t['PaidValue'] for t in tickets); fees=sum(t['ChangeFee'] for t in tickets); new=Decimal(0)
    for t,s in zip(tickets,seats):
        base=money(fare['BasePrice']*t['PriceFactor']);new+=base+money(base*fare['TaxRate'])+s['SeatFee']+t['ExtraAmount']-t['DiscountAmount']
    return dict(BookingID=segment['BookingID'],SegmentID=segment_id,FlightID=flight_id,FareClassID=fare_id,OldValue=old,NewValue=new,ChangeFee=fees,Difference=new-old+fees,FlightNumber=fare['FlightNumber'],DepartureTime=fare['DepartureTime'],Notice='Đổi toàn bộ hành khách của chặng; tự xếp ghế. Số dương thu thêm, số âm hoàn mô phỏng. Hệ thống kiểm tra lại điều kiện nối chuyến và giá khi xác nhận.')
