USE AeroFlow;
GO
-- One transaction lock protects seat inventory across both directions.
CREATE OR ALTER PROCEDURE dbo.sp_LockInventory AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @result int;
 EXEC @result=sys.sp_getapplock @Resource='AeroFlow:inventory',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @result<0 THROW 51001,N'Đặt chỗ đang được xử lý. Vui lòng thử lại.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ExpireFlightHolds @FlightID int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockInventory;
  DECLARE @expired TABLE(BookingID int PRIMARY KEY);
  UPDATE b SET Status='EXPIRED' OUTPUT inserted.BookingID INTO @expired
  FROM dbo.Bookings b WHERE b.Status='HELD' AND b.ExpiresAt<=SYSUTCDATETIME()
    AND EXISTS(SELECT 1 FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID AND s.FlightID=@FlightID);
  UPDATE t SET Status='VOID' FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID JOIN @expired e ON e.BookingID=p.BookingID;
  UPDATE a SET IsActive=0 FROM dbo.FlightSeatAssignments a JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID
  JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID JOIN @expired e ON e.BookingID=p.BookingID;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_CreateBooking
 @UserID int,@FlightID int,@Passengers nvarchar(max),@BookingID int=NULL OUTPUT,
 @ReturnFlightID int=NULL,@ExpectedTotal decimal(14,2)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockInventory;
  EXEC dbo.sp_ExpireFlightHolds @FlightID;
  IF @ReturnFlightID IS NOT NULL EXEC dbo.sp_ExpireFlightHolds @ReturnFlightID;
  IF NOT EXISTS(SELECT 1 FROM dbo.Users WHERE UserID=@UserID AND IsActive=1)
   THROW 51002,N'Tài khoản không hoạt động.',1;
  DECLARE @legs TABLE(SegmentOrder tinyint PRIMARY KEY,FlightID int,AircraftID int,SegmentID int);
  INSERT @legs(SegmentOrder,FlightID) VALUES(1,@FlightID);
  IF @ReturnFlightID IS NOT NULL INSERT @legs(SegmentOrder,FlightID) VALUES(2,@ReturnFlightID);
  UPDATE l SET AircraftID=f.AircraftID FROM @legs l JOIN dbo.Flights f WITH(UPDLOCK,HOLDLOCK) ON f.FlightID=l.FlightID
   JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID AND a.IsActive=1
   JOIN dbo.Airports o ON o.AirportID=f.OriginID AND o.IsActive=1 JOIN dbo.Airports d ON d.AirportID=f.DestinationID AND d.IsActive=1
   WHERE f.Status='SCHEDULED' AND f.DepartureTime>DATEADD(hour,2,SYSUTCDATETIME());
  IF EXISTS(SELECT 1 FROM @legs WHERE AircraftID IS NULL) THROW 51003,N'Chuyến bay không còn mở bán.',1;
  IF @ReturnFlightID IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM dbo.Flights f JOIN dbo.Flights r ON r.FlightID=@ReturnFlightID
   WHERE f.FlightID=@FlightID AND r.OriginID=f.DestinationID AND r.DestinationID=f.OriginID
     AND r.DepartureTime>=DATEADD(minute,60,f.ArrivalTime))
   THROW 51004,N'Chiều về phải ngược chiều đi và cách giờ đến ít nhất 60 phút.',1;
  IF @Passengers IS NULL OR ISJSON(@Passengers)<>1 OR LEFT(LTRIM(@Passengers),1)<>'['
   THROW 51004,N'Danh sách hành khách không hợp lệ.',1;
  DECLARE @p TABLE(RowID int IDENTITY,SeatID int,FareClassID int,ReturnSeatID int,ReturnFareClassID int,
   FullName nvarchar(120),DateOfBirth date,DocumentNumber nvarchar(30),BookingPassengerID int);
  INSERT @p(SeatID,FareClassID,ReturnSeatID,ReturnFareClassID,FullName,DateOfBirth,DocumentNumber)
  SELECT SeatID,FareClassID,ReturnSeatID,ReturnFareClassID,TRIM(FullName),TRY_CONVERT(date,DateOfBirth),TRIM(DocumentNumber)
  FROM OPENJSON(@Passengers) WITH(SeatID int,FareClassID int,ReturnSeatID int,ReturnFareClassID int,
   FullName nvarchar(120),DateOfBirth nvarchar(30),DocumentNumber nvarchar(30));
  DECLARE @count int=(SELECT COUNT(*) FROM @p);
  IF @count NOT BETWEEN 1 AND 9 THROW 51004,N'Cần từ 1 đến 9 hành khách.',1;
  IF EXISTS(SELECT 1 FROM @p WHERE FullName IS NULL OR LEN(FullName)<2 OR DateOfBirth IS NULL
   OR DateOfBirth>CONVERT(date,SYSUTCDATETIME()) OR DateOfBirth<'19000101' OR DocumentNumber IS NULL OR LEN(DocumentNumber)<5)
   THROW 51004,N'Thông tin hành khách chưa đầy đủ.',1;
  IF (SELECT COUNT(DISTINCT DocumentNumber) FROM @p)<>@count
   THROW 51004,N'Giấy tờ hành khách trong một đơn không được trùng.',1;
  DECLARE @items TABLE(RowID int,SegmentOrder tinyint,FlightID int,SeatID int,FareClassID int,
   BaseFare decimal(14,2),TaxAmount decimal(14,2),SeatFee decimal(14,2),BaggageKg int,RefundPercent decimal(5,2));
  INSERT @items(RowID,SegmentOrder,FlightID,SeatID,FareClassID)
  SELECT p.RowID,l.SegmentOrder,l.FlightID,CASE l.SegmentOrder WHEN 1 THEN p.SeatID ELSE p.ReturnSeatID END,
   CASE l.SegmentOrder WHEN 1 THEN p.FareClassID ELSE p.ReturnFareClassID END FROM @p p CROSS JOIN @legs l;
  IF EXISTS(SELECT 1 FROM @items GROUP BY FlightID,SeatID HAVING COUNT(*)>1)
   THROW 51004,N'Mỗi hành khách phải chọn một ghế khác nhau.',1;
  UPDATE i SET BaseFare=f.BasePrice,TaxAmount=ROUND(f.BasePrice*f.TaxRate,2),SeatFee=s.SeatFee,
   BaggageKg=c.BaggageKg,RefundPercent=c.RefundPercent
  FROM @items i JOIN @legs l ON l.SegmentOrder=i.SegmentOrder
  JOIN dbo.AircraftSeats s ON s.SeatID=i.SeatID AND s.AircraftID=l.AircraftID AND s.IsActive=1
  JOIN dbo.FareClasses c ON c.FareClassID=i.FareClassID AND c.Cabin=s.Cabin
  JOIN dbo.FlightFares f ON f.FlightID=i.FlightID AND f.FareClassID=i.FareClassID;
  IF EXISTS(SELECT 1 FROM @items WHERE BaseFare IS NULL)
   THROW 51004,N'Ghế hoặc hạng vé không phù hợp với chuyến bay.',1;
  IF EXISTS(SELECT 1 FROM @items i JOIN dbo.FlightSeatAssignments a WITH(UPDLOCK,HOLDLOCK)
   ON a.FlightID=i.FlightID AND a.SeatID=i.SeatID AND a.IsActive=1)
   THROW 51005,N'Ghế vừa được người khác giữ. Vui lòng chọn ghế khác.',1;
  IF @ExpectedTotal IS NOT NULL AND @ExpectedTotal<>(SELECT SUM(BaseFare+TaxAmount+SeatFee) FROM @items)
   THROW 51013,N'Giá vé đã thay đổi. Vui lòng kiểm tra lại trước khi đặt.',1;
  DECLARE @pnr char(8)=UPPER(LEFT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),8));
  WHILE EXISTS(SELECT 1 FROM dbo.Bookings WHERE PNR=@pnr)
   SET @pnr=UPPER(LEFT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),8));
  INSERT dbo.Bookings(PNR,UserID,ExpiresAt) VALUES(@pnr,@UserID,DATEADD(minute,10,SYSUTCDATETIME()));
  SET @BookingID=SCOPE_IDENTITY();
  INSERT dbo.BookingSegments(BookingID,FlightID,SegmentOrder) SELECT @BookingID,FlightID,SegmentOrder FROM @legs;
  UPDATE l SET SegmentID=s.BookingSegmentID FROM @legs l JOIN dbo.BookingSegments s ON s.BookingID=@BookingID AND s.SegmentOrder=l.SegmentOrder;
  DECLARE @i int=1,@passenger int,@bp int,@assignment int,@leg tinyint;
  WHILE @i<=@count
  BEGIN
   INSERT dbo.Passengers(FullName,DateOfBirth,DocumentNumber) SELECT FullName,DateOfBirth,DocumentNumber FROM @p WHERE RowID=@i;
   SET @passenger=SCOPE_IDENTITY();
   INSERT dbo.BookingPassengers(BookingID,PassengerID) VALUES(@BookingID,@passenger);
   SET @bp=SCOPE_IDENTITY(); SET @leg=1;
   WHILE @leg<=(SELECT COUNT(*) FROM @legs)
   BEGIN
    INSERT dbo.FlightSeatAssignments(FlightID,SeatID) SELECT FlightID,SeatID FROM @items WHERE RowID=@i AND SegmentOrder=@leg;
    SET @assignment=SCOPE_IDENTITY();
    INSERT dbo.Tickets(TicketNumber,BookingPassengerID,BookingSegmentID,FareClassID,AssignmentID,
     BaseFare,TaxAmount,SeatFee,BaggageKg,Amount,RefundPercent)
    SELECT CONCAT('AF',RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),16)),@bp,l.SegmentID,i.FareClassID,@assignment,
     i.BaseFare,i.TaxAmount,i.SeatFee,i.BaggageKg,i.BaseFare+i.TaxAmount+i.SeatFee,i.RefundPercent
    FROM @items i JOIN @legs l ON l.SegmentOrder=i.SegmentOrder WHERE i.RowID=@i AND i.SegmentOrder=@leg;
    SET @leg+=1;
   END;
   SET @i+=1;
  END;
  COMMIT;
  SELECT * FROM dbo.vw_BookingDetails WHERE BookingID=@BookingID;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ConfirmPayment @UserID int,@BookingID int,@IdempotencyKey varchar(80),@Success bit AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @flight int=(SELECT MIN(s.FlightID) FROM dbo.BookingSegments s JOIN dbo.Bookings b ON b.BookingID=s.BookingID WHERE b.BookingID=@BookingID AND b.UserID=@UserID);
 IF @flight IS NULL THROW 51006,N'Không tìm thấy đơn đặt vé.',1;
 EXEC dbo.sp_ExpireFlightHolds @flight;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockInventory;
  IF @IdempotencyKey IS NULL OR LEN(TRIM(@IdempotencyKey))<16 OR @Success IS NULL THROW 51004,N'Mã thanh toán không hợp lệ.',1;
  IF EXISTS(SELECT 1 FROM dbo.Payments WHERE IdempotencyKey=@IdempotencyKey)
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Payments WHERE IdempotencyKey=@IdempotencyKey AND BookingID=@BookingID AND Kind='CHARGE'
    AND Status=CASE WHEN @Success=1 THEN 'SUCCESS' ELSE 'FAILED' END)
    THROW 51007,N'Mã thanh toán đã được dùng cho yêu cầu khác.',1;
   COMMIT;
   SELECT * FROM dbo.Payments WHERE IdempotencyKey=@IdempotencyKey; RETURN;
  END;
  IF NOT EXISTS(SELECT 1 FROM dbo.Bookings WHERE BookingID=@BookingID AND Status='HELD' AND ExpiresAt>SYSUTCDATETIME())
   THROW 51008,N'Đơn đã thanh toán, đã hủy hoặc hết hạn giữ ghế.',1;
  IF EXISTS(SELECT 1 FROM dbo.BookingSegments s JOIN dbo.Flights f ON f.FlightID=s.FlightID
   WHERE s.BookingID=@BookingID AND (f.Status<>'SCHEDULED' OR f.DepartureTime<=DATEADD(hour,2,SYSUTCDATETIME())))
   THROW 51003,N'Chuyến bay không còn cho phép thanh toán.',1;
  DECLARE @amount decimal(14,2)=(SELECT SUM(t.Amount) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID);
  INSERT dbo.Payments(BookingID,IdempotencyKey,Amount,Kind,Status)
   VALUES(@BookingID,@IdempotencyKey,@amount,'CHARGE',CASE WHEN @Success=1 THEN 'SUCCESS' ELSE 'FAILED' END);
  IF @Success=1
  BEGIN
   UPDATE dbo.Bookings SET Status='CONFIRMED' WHERE BookingID=@BookingID;
   UPDATE t SET Status='VALID' FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID;
  END;
  COMMIT;
  SELECT * FROM dbo.Payments WHERE IdempotencyKey=@IdempotencyKey;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_CancelBooking @UserID int,@BookingID int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @flight int,@status varchar(12),@refund decimal(14,2)=0;
 SELECT @flight=MIN(s.FlightID) FROM dbo.Bookings b JOIN dbo.BookingSegments s ON s.BookingID=b.BookingID
 WHERE b.BookingID=@BookingID AND (b.UserID=@UserID OR EXISTS(SELECT 1 FROM dbo.Users u JOIN dbo.Roles r ON r.RoleID=u.RoleID WHERE u.UserID=@UserID AND u.IsActive=1 AND r.Name='ADMIN'));
 IF @flight IS NULL THROW 51006,N'Không tìm thấy đơn đặt vé.',1;
 EXEC dbo.sp_ExpireFlightHolds @flight;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockInventory;
  SELECT @status=Status FROM dbo.Bookings WHERE BookingID=@BookingID;
  IF @status='CANCELLED' BEGIN COMMIT; SELECT CAST(1 AS bit) Cancelled,CAST(0 AS decimal(14,2)) RefundAmount; RETURN; END;
  IF @status='EXPIRED' THROW 51008,N'Đơn đã hết hạn giữ ghế.',1;
  IF @status='CONFIRMED'
  BEGIN
   IF EXISTS(SELECT 1 FROM dbo.BookingSegments s JOIN dbo.Flights f ON f.FlightID=s.FlightID WHERE s.BookingID=@BookingID
    AND (f.DepartureTime<=DATEADD(hour,24,SYSUTCDATETIME()) OR f.Status<>'SCHEDULED'))
    THROW 51009,N'Chỉ được hủy cả hành trình trước giờ bay ít nhất 24 giờ.',1;
   SELECT @refund=SUM(ROUND(t.Amount*t.RefundPercent/100,2)) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID AND t.Status='VALID';
   INSERT dbo.Payments(BookingID,IdempotencyKey,Amount,Kind,Status) VALUES(@BookingID,CONCAT('refund-booking-',@BookingID),@refund,'REFUND','SUCCESS');
  END;
  UPDATE t SET Status='VOID' FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID;
  UPDATE a SET IsActive=0 FROM dbo.FlightSeatAssignments a JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID;
  UPDATE dbo.Bookings SET Status='CANCELLED' WHERE BookingID=@BookingID;
  COMMIT;
  SELECT CAST(1 AS bit) Cancelled,@refund RefundAmount;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_GetAvailableSeats @FlightID int AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ExpireFlightHolds @FlightID;
 SELECT s.SeatID,s.SeatNumber,s.RowNumber,s.ColumnLetter,s.Cabin,s.SeatFee,s.IsPriority,
 CAST(CASE WHEN a.AssignmentID IS NULL THEN 1 ELSE 0 END AS bit) Available,
 CAST(CASE WHEN a.AssignmentID IS NULL THEN 1 ELSE 0 END AS bit) IsAvailable
 FROM dbo.AircraftSeats s JOIN dbo.Flights f ON f.AircraftID=s.AircraftID
 LEFT JOIN dbo.FlightSeatAssignments a ON a.FlightID=f.FlightID AND a.SeatID=s.SeatID AND a.IsActive=1
 WHERE f.FlightID=@FlightID AND s.IsActive=1 ORDER BY s.RowNumber,s.ColumnLetter;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_GetRevenueReport @From date,@To date AS
BEGIN
 SET NOCOUNT ON;
 IF @From IS NULL OR @To IS NULL OR @From>@To OR @To='99991231' THROW 51004,N'Khoảng ngày không hợp lệ.',1;
 SELECT CONVERT(date,CreatedAt) [Date],
 SUM(CASE WHEN Kind='CHARGE' THEN Amount ELSE 0 END) GrossRevenue,
 SUM(CASE WHEN Kind='REFUND' THEN Amount ELSE 0 END) Refunds,
 SUM(CASE WHEN Kind='CHARGE' THEN Amount ELSE -Amount END) NetRevenue
 FROM dbo.Payments WHERE Status='SUCCESS' AND CreatedAt>=@From AND CreatedAt<DATEADD(day,1,@To)
 GROUP BY CONVERT(date,CreatedAt) ORDER BY [Date];
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_UpdateFlightStatus @FlightID int,@Status varchar(12) AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockInventory;
  DECLARE @old varchar(12)=(SELECT Status FROM dbo.Flights WHERE FlightID=@FlightID);
  IF @old IS NULL THROW 51006,N'Không tìm thấy chuyến bay.',1;
  IF @old=@Status BEGIN COMMIT; RETURN; END;
  IF @Status IS NULL OR NOT ((@old='SCHEDULED' AND @Status IN ('BOARDING','CANCELLED'))
   OR (@old='BOARDING' AND @Status IN ('DEPARTED','CANCELLED')) OR (@old='DEPARTED' AND @Status='ARRIVED'))
   THROW 51010,N'Chuyển trạng thái chuyến bay không hợp lệ.',1;
  DECLARE @affected TABLE(BookingID int PRIMARY KEY);
  IF @Status IN ('CANCELLED','BOARDING')
  BEGIN
   INSERT @affected SELECT b.BookingID FROM dbo.Bookings b WHERE b.Status='HELD'
    AND EXISTS(SELECT 1 FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID AND s.FlightID=@FlightID);
   IF @Status='CANCELLED'
   BEGIN
    INSERT @affected SELECT b.BookingID FROM dbo.Bookings b WHERE b.Status='CONFIRMED'
     AND EXISTS(SELECT 1 FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID AND s.FlightID=@FlightID);
    INSERT dbo.Payments(BookingID,IdempotencyKey,Amount,Kind,Status)
    SELECT b.BookingID,CONCAT('refund-booking-',b.BookingID),SUM(t.Amount),'REFUND','SUCCESS'
    FROM @affected x JOIN dbo.Bookings b ON b.BookingID=x.BookingID
    JOIN dbo.BookingPassengers p ON p.BookingID=b.BookingID JOIN dbo.Tickets t ON t.BookingPassengerID=p.BookingPassengerID
    JOIN dbo.BookingSegments s ON s.BookingSegmentID=t.BookingSegmentID JOIN dbo.Flights f ON f.FlightID=s.FlightID
    WHERE b.Status='CONFIRMED' AND t.Status='VALID' AND f.Status IN ('SCHEDULED','BOARDING')
    GROUP BY b.BookingID;
   END;
   UPDATE t SET Status='VOID' FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID
   JOIN dbo.Bookings b ON b.BookingID=p.BookingID JOIN @affected x ON x.BookingID=b.BookingID
   JOIN dbo.BookingSegments s ON s.BookingSegmentID=t.BookingSegmentID JOIN dbo.Flights f ON f.FlightID=s.FlightID
   WHERE b.Status='HELD' OR (@Status='CANCELLED' AND f.Status IN ('SCHEDULED','BOARDING'));
   UPDATE a SET IsActive=0 FROM dbo.FlightSeatAssignments a JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID
   JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID JOIN @affected x ON x.BookingID=p.BookingID WHERE t.Status='VOID';
   UPDATE b SET Status=CASE WHEN @Status='BOARDING' THEN 'EXPIRED' ELSE 'CANCELLED' END
   FROM dbo.Bookings b JOIN @affected x ON x.BookingID=b.BookingID
   WHERE NOT EXISTS(SELECT 1 FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=b.BookingID AND t.Status='VALID');
  END;
  UPDATE dbo.Flights SET Status=@Status WHERE FlightID=@FlightID;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_SaveFlight @FlightID int=NULL,@FlightNumber varchar(8),@AircraftID int,
 @OriginID int,@DestinationID int,@DepartureTime datetime2(0),@ArrivalTime datetime2(0) AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockInventory;
  IF @FlightID IS NOT NULL
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Flights WHERE FlightID=@FlightID AND Status='SCHEDULED') THROW 51010,N'Chỉ sửa chuyến đang mở bán.',1;
   IF EXISTS(SELECT 1 FROM dbo.BookingSegments WHERE FlightID=@FlightID) THROW 51011,N'Chuyến đã có lịch sử đặt vé. Hãy tạo chuyến mới nếu cần đổi lịch hoặc máy bay.',1;
  END;
  IF @OriginID=@DestinationID OR @ArrivalTime<=@DepartureTime OR @DepartureTime<=SYSUTCDATETIME()
   OR NULLIF(TRIM(@FlightNumber),'') IS NULL THROW 51004,N'Lịch bay không hợp lệ.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Aircraft WHERE AircraftID=@AircraftID AND IsActive=1)
   OR (SELECT COUNT(*) FROM dbo.Airports WHERE AirportID IN (@OriginID,@DestinationID) AND IsActive=1)<>2
   THROW 51004,N'Máy bay hoặc sân bay không hoạt động.',1;
  IF EXISTS(SELECT 1 FROM dbo.Flights WHERE AircraftID=@AircraftID AND Status<>'CANCELLED' AND FlightID<>COALESCE(@FlightID,0)
   AND DepartureTime<DATEADD(minute,45,@ArrivalTime) AND ArrivalTime>DATEADD(minute,-45,@DepartureTime))
   THROW 51012,N'Máy bay có lịch trùng hoặc chưa đủ 45 phút quay đầu.',1;
  IF EXISTS(SELECT 1 FROM dbo.Flights f WHERE f.FlightID=(SELECT TOP(1) FlightID FROM dbo.Flights
   WHERE AircraftID=@AircraftID AND Status<>'CANCELLED' AND FlightID<>COALESCE(@FlightID,0) AND ArrivalTime<=@DepartureTime ORDER BY ArrivalTime DESC)
   AND f.DestinationID<>@OriginID)
   OR EXISTS(SELECT 1 FROM dbo.Flights f WHERE f.FlightID=(SELECT TOP(1) FlightID FROM dbo.Flights
   WHERE AircraftID=@AircraftID AND Status<>'CANCELLED' AND FlightID<>COALESCE(@FlightID,0) AND DepartureTime>=@ArrivalTime ORDER BY DepartureTime)
   AND f.OriginID<>@DestinationID)
   THROW 51012,N'Máy bay không ở đúng sân bay trước hoặc sau chuyến này.',1;
  IF @FlightID IS NULL
  BEGIN
   INSERT dbo.Flights(FlightNumber,AircraftID,OriginID,DestinationID,DepartureTime,ArrivalTime)
    VALUES(@FlightNumber,@AircraftID,@OriginID,@DestinationID,@DepartureTime,@ArrivalTime);
   SET @FlightID=SCOPE_IDENTITY();
  END
  ELSE UPDATE dbo.Flights SET FlightNumber=@FlightNumber,AircraftID=@AircraftID,OriginID=@OriginID,
   DestinationID=@DestinationID,DepartureTime=@DepartureTime,ArrivalTime=@ArrivalTime WHERE FlightID=@FlightID;
  COMMIT;
  SELECT @FlightID FlightID;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_SaveFare @FlightID int,@FareClassID int,@BasePrice decimal(14,2),@TaxRate decimal(5,4) AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockInventory;
  IF NOT EXISTS(SELECT 1 FROM dbo.Flights WHERE FlightID=@FlightID AND Status='SCHEDULED') THROW 51010,N'Chỉ sửa giá chuyến đang mở bán.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Flights f JOIN dbo.AircraftSeats s ON s.AircraftID=f.AircraftID AND s.IsActive=1
   JOIN dbo.FareClasses c ON c.Cabin=s.Cabin WHERE f.FlightID=@FlightID AND c.FareClassID=@FareClassID)
   THROW 51004,N'Máy bay không có ghế thuộc khoang của hạng vé này.',1;
  UPDATE dbo.FlightFares SET BasePrice=@BasePrice,TaxRate=@TaxRate WHERE FlightID=@FlightID AND FareClassID=@FareClassID;
  IF @@ROWCOUNT=0 INSERT dbo.FlightFares(FlightID,FareClassID,BasePrice,TaxRate) VALUES(@FlightID,@FareClassID,@BasePrice,@TaxRate);
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
