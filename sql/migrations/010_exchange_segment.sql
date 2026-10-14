CREATE OR ALTER PROCEDURE dbo.sp_ExchangeSegment
 @UserID int,@SegmentID int,@NewFlightID int,@FareClassID int,@IdempotencyKey varchar(80),@ExpectedDifference decimal(14,2)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 EXEC dbo.sp_LockFlight 0;
 DECLARE @bid int,@oldFlight int,@order int,@group int,@newSegment int,@status varchar(12),@oldStatus varchar(12);
 SELECT @bid=b.BookingID,@oldFlight=s.FlightID,@order=s.SegmentOrder,@group=s.JourneyGroup,@status=b.Status,@oldStatus=s.Status
 FROM dbo.BookingSegments s JOIN dbo.Bookings b ON b.BookingID=s.BookingID WHERE s.BookingSegmentID=@SegmentID AND b.UserID=@UserID;
 IF @bid IS NULL THROW 51006,N'Không tìm thấy chặng bay.',1;
 IF LEN(@IdempotencyKey)<16 OR @IdempotencyKey IS NULL OR @ExpectedDifference IS NULL THROW 51004,N'Thiếu mã giao dịch hoặc báo giá.',1;
 IF EXISTS(SELECT 1 FROM dbo.BookingChanges WHERE IdempotencyKey=@IdempotencyKey)
 BEGIN
 IF NOT EXISTS(SELECT 1 FROM dbo.BookingChanges c JOIN dbo.BookingSegments s ON s.BookingSegmentID=c.NewSegmentID JOIN dbo.Tickets t ON t.BookingSegmentID=s.BookingSegmentID WHERE c.IdempotencyKey=@IdempotencyKey AND c.BookingID=@bid AND c.OldSegmentID=@SegmentID AND s.FlightID=@NewFlightID AND t.FareClassID=@FareClassID AND c.ChangeFee+c.FareDifference=@ExpectedDifference)
 THROW 51007,N'Mã giao dịch đã dùng cho yêu cầu khác.',1;
 COMMIT; SELECT * FROM dbo.BookingChanges WHERE IdempotencyKey=@IdempotencyKey; RETURN;
 END;
 IF @status<>'CONFIRMED' OR @oldStatus<>'ACTIVE' THROW 51010,N'Chỉ đổi chặng đang có hiệu lực.',1;
 IF EXISTS(SELECT 1 FROM dbo.Tickets t LEFT JOIN dbo.TicketRules r ON r.TicketID=t.TicketID LEFT JOIN dbo.CheckIns ci ON ci.TicketID=t.TicketID WHERE t.BookingSegmentID=@SegmentID AND (t.Status<>'VALID' OR r.ChangeAllowed<>1 OR r.TicketID IS NULL OR ci.Status='ACTIVE'))
 THROW 51017,N'Chặng có vé không được đổi, đã hủy hoặc đã check-in.',1;
 DECLARE @dep datetime2(0),@arr datetime2(0),@origin int,@dest int,@aircraft int,@cabin varchar(12),@base decimal(14,2),@rate decimal(5,4),@refund decimal(5,2);
 SELECT @dep=DepartureTime,@arr=ArrivalTime,@origin=OriginID,@dest=DestinationID,@aircraft=AircraftID FROM dbo.Flights WHERE FlightID=@NewFlightID AND Status='SCHEDULED' AND DepartureTime>DATEADD(hour,24,SYSUTCDATETIME());
 IF @dep IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Flights WHERE FlightID=@oldFlight AND OriginID=@origin AND DestinationID=@dest AND DepartureTime>DATEADD(hour,24,SYSUTCDATETIME()) AND Status='SCHEDULED') THROW 51017,N'Đổi cùng đường bay, trước giờ bay ít nhất 24 giờ.',1;
 IF EXISTS(SELECT 1 FROM dbo.BookingSegments s WHERE s.BookingID=@bid AND s.Status='ACTIVE' AND s.FlightID=@NewFlightID AND s.BookingSegmentID<>@SegmentID) THROW 51004,N'Không lặp chuyến trong hành trình.',1;
 IF EXISTS(SELECT 1 FROM dbo.BookingSegments s JOIN dbo.Flights f ON f.FlightID=s.FlightID WHERE s.BookingID=@bid AND s.Status='ACTIVE' AND s.BookingSegmentID<>@SegmentID AND
 ((s.SegmentOrder<@order AND f.ArrivalTime>DATEADD(minute,-60,@dep)) OR (s.SegmentOrder>@order AND f.DepartureTime<DATEADD(minute,60,@arr)))) THROW 51017,N'Giờ bay mới xung đột với các chặng còn lại.',1;
 IF EXISTS(SELECT 1 FROM dbo.BookingSegments s JOIN dbo.Flights f ON f.FlightID=s.FlightID WHERE s.BookingID=@bid AND s.Status='ACTIVE' AND s.JourneyGroup=@group AND
 ((s.SegmentOrder=@order-1 AND (@dep>DATEADD(hour,8,f.ArrivalTime) OR f.DestinationID<>@origin)) OR (s.SegmentOrder=@order+1 AND (f.DepartureTime>DATEADD(hour,8,@arr) OR @dest<>f.OriginID)))) THROW 51017,N'Thời gian nối chuyến không hợp lệ.',1;
 SELECT @cabin=c.Cabin,@base=ff.BasePrice,@rate=ff.TaxRate,@refund=c.RefundPercent FROM dbo.FlightFares ff JOIN dbo.FareClasses c ON c.FareClassID=ff.FareClassID WHERE ff.FlightID=@NewFlightID AND ff.FareClassID=@FareClassID;
 IF @cabin IS NULL THROW 51004,N'Hạng vé mới chưa mở bán.',1;
 EXEC dbo.sp_ExpireFlightHolds @NewFlightID;
 DECLARE @oldValue decimal(14,2),@fees decimal(14,2),@newValue decimal(14,2),@difference decimal(14,2),@payment int;
 SELECT @oldValue=SUM(dbo.fn_TicketPaidValue(t.TicketID)),@fees=SUM(r.ChangeFee) FROM dbo.Tickets t JOIN dbo.TicketRules r ON r.TicketID=t.TicketID WHERE t.BookingSegmentID=@SegmentID AND t.Status='VALID';
 IF @oldValue IS NULL THROW 51017,N'Chặng không có vé còn hiệu lực.',1;
 DECLARE @old TABLE(N int IDENTITY,TicketID int,BP int,TypeCode varchar(8));
 INSERT @old(TicketID,BP,TypeCode) SELECT TicketID,BookingPassengerID,PassengerType FROM dbo.Tickets WHERE BookingSegmentID=@SegmentID AND Status='VALID' ORDER BY TicketID;
 UPDATE dbo.Tickets SET Status='VOID' WHERE BookingSegmentID=@SegmentID AND Status='VALID';
 UPDATE a SET IsActive=0 FROM dbo.FlightSeatAssignments a JOIN @old t ON t.TicketID IN (SELECT TicketID FROM dbo.Tickets WHERE AssignmentID=a.AssignmentID);
 UPDATE dbo.BookingSegments SET Status='EXCHANGED' WHERE BookingSegmentID=@SegmentID;
 INSERT dbo.BookingSegments(BookingID,SegmentOrder,JourneyGroup,FlightID) VALUES(@bid,@order,@group,@NewFlightID); SET @newSegment=SCOPE_IDENTITY();
 DECLARE @i int=1,@count int=(SELECT COUNT(*) FROM @old),@seat int,@seatFee decimal(14,2),@factor decimal(5,4),@price decimal(14,2),@tax decimal(14,2),@aid int,@tid int,@bp int,@oldTicket int,@type varchar(8);
 WHILE @i<=@count
 BEGIN
 SELECT @bp=o.BP,@oldTicket=o.TicketID,@type=o.TypeCode,@factor=p.PriceFactor FROM @old o JOIN dbo.PassengerTypes p ON p.TypeCode=o.TypeCode WHERE N=@i;
 -- Keep age category valid on the new departure date.
 IF EXISTS(SELECT 1 FROM dbo.BookingPassengers bp JOIN dbo.Passengers p ON p.PassengerID=bp.PassengerID WHERE bp.BookingPassengerID=@bp AND @type<>CASE WHEN p.DateOfBirth>DATEADD(year,-2,CONVERT(date,@dep)) THEN 'INFANT' WHEN p.DateOfBirth>DATEADD(year,-12,CONVERT(date,@dep)) THEN 'CHILD' ELSE 'ADULT' END) THROW 51017,N'Độ tuổi thay đổi: cần tạo hành trình mới.',1;
 SET @seat=NULL;
 SELECT TOP(1) @seat=s.SeatID,@seatFee=s.SeatFee FROM dbo.AircraftSeats s WHERE s.AircraftID=@aircraft AND s.Cabin=@cabin AND s.IsActive=1 AND NOT EXISTS(SELECT 1 FROM dbo.FlightSeatAssignments a WHERE a.FlightID=@NewFlightID AND a.SeatID=s.SeatID AND a.IsActive=1) ORDER BY s.SeatFee,s.RowNumber,s.ColumnLetter;
 IF @seat IS NULL THROW 51005,N'Chặng mới không đủ ghế.',1;
 SET @price=ROUND(@base*@factor,2); SET @tax=ROUND(@price*@rate,2);
 INSERT dbo.FlightSeatAssignments(FlightID,SeatID) VALUES(@NewFlightID,@seat); SET @aid=SCOPE_IDENTITY();
 INSERT dbo.Tickets(AssignmentID,TicketNumber,BookingPassengerID,BookingSegmentID,FareClassID,PassengerType,BaseFare,TaxAmount,SeatFee,BreakdownSource,Amount,RefundPercent,Status)
 VALUES(@aid,CONCAT('AF',RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),16)),@bp,@newSegment,@FareClassID,@type,@price,@tax,@seatFee,'DETAILED',@price+@tax+@seatFee,@refund,'VALID'); SET @tid=SCOPE_IDENTITY();
 INSERT dbo.BookingExtras SELECT @tid,ServiceID,ServiceName,Quantity,UnitPrice,RefundPercent FROM dbo.BookingExtras WHERE TicketID=@oldTicket;
 INSERT dbo.TicketDiscounts SELECT @tid,Amount FROM dbo.TicketDiscounts WHERE TicketID=@oldTicket;
 IF dbo.fn_TicketPaidValue(@tid)<1 THROW 51017,N'Giá mới nhỏ hơn ưu đãi đã dùng; cần chọn hạng khác.',1;
 SET @i+=1;
 END;
 SELECT @newValue=SUM(dbo.fn_TicketPaidValue(TicketID)) FROM dbo.Tickets WHERE BookingSegmentID=@newSegment;
 SET @difference=@newValue-@oldValue+@fees;
 IF @difference<>@ExpectedDifference THROW 51013,N'Chênh lệch đã thay đổi. Kiểm tra báo giá.',1;
 INSERT dbo.Payments(BookingID,IdempotencyKey,Amount,Kind,Status,Purpose) VALUES(@bid,@IdempotencyKey,ABS(@difference),CASE WHEN @difference<0 THEN 'REFUND' ELSE 'CHARGE' END,'SUCCESS','EXCHANGE'); SET @payment=SCOPE_IDENTITY();
 INSERT dbo.BookingChanges(BookingID,OldSegmentID,NewSegmentID,PaymentID,ChangeFee,FareDifference,IdempotencyKey) VALUES(@bid,@SegmentID,@newSegment,@payment,@fees,@newValue-@oldValue,@IdempotencyKey);
 INSERT dbo.AuditLogs(ActorID,Entity,EntityID,Action,Details) VALUES(@UserID,'Bookings',@bid,'EXCHANGE',CONCAT(@SegmentID,' -> ',@newSegment));
 COMMIT;
 SELECT * FROM dbo.BookingChanges WHERE IdempotencyKey=@IdempotencyKey;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
