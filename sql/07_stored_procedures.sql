USE AeroFlow;
GO
CREATE OR ALTER PROCEDURE dbo.sp_LockFlight @FlightID int AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @r int,@resource nvarchar(255)=CONCAT('AeroFlow:flight:',@FlightID);
 EXEC @r=sys.sp_getapplock @Resource=@resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @r<0 THROW 51001,N'Chuyến bay đang được cập nhật. Vui lòng thử lại.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ExpireFlightHolds @FlightID int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockFlight @FlightID;
  DECLARE @expired TABLE(BookingID int PRIMARY KEY);
  UPDATE dbo.Bookings SET Status='EXPIRED' OUTPUT inserted.BookingID INTO @expired
   WHERE FlightID=@FlightID AND Status='HELD' AND ExpiresAt<=SYSUTCDATETIME();
  UPDATE t SET Status='VOID' FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID JOIN @expired e ON e.BookingID=p.BookingID;
  UPDATE a SET IsActive=0 FROM dbo.FlightSeatAssignments a JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID JOIN @expired e ON e.BookingID=p.BookingID;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_CreateBooking
 @UserID int,@FlightID int,@Passengers nvarchar(max),@BookingID int=NULL OUTPUT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockFlight @FlightID;
  EXEC dbo.sp_ExpireFlightHolds @FlightID;
  IF NOT EXISTS(SELECT 1 FROM dbo.Users WHERE UserID=@UserID AND IsActive=1)
    THROW 51002,N'Tài khoản không hoạt động.',1;
  DECLARE @aircraft int,@departure datetime2(0);
  SELECT @aircraft=AircraftID,@departure=DepartureTime FROM dbo.Flights WITH(UPDLOCK,HOLDLOCK)
   WHERE FlightID=@FlightID AND Status='SCHEDULED' AND DepartureTime>DATEADD(hour,2,SYSUTCDATETIME());
  IF @aircraft IS NULL THROW 51003,N'Chuyến bay không còn mở bán.',1;
  IF ISJSON(@Passengers)<>1 OR LEFT(LTRIM(@Passengers),1)<>'[' THROW 51004,N'Danh sách hành khách không hợp lệ.',1;
  DECLARE @p TABLE(RowID int IDENTITY,SeatID int,FareClassID int,FullName nvarchar(120),DateOfBirth date,DocumentNumber nvarchar(30));
  INSERT @p(SeatID,FareClassID,FullName,DateOfBirth,DocumentNumber)
   SELECT SeatID,FareClassID,FullName,TRY_CONVERT(date,DateOfBirth),DocumentNumber
   FROM OPENJSON(@Passengers) WITH(SeatID int,FareClassID int,FullName nvarchar(120),DateOfBirth nvarchar(30),DocumentNumber nvarchar(30));
  IF (SELECT COUNT(*) FROM @p) NOT BETWEEN 1 AND 9 THROW 51004,N'Cần từ 1 đến 9 hành khách.',1;
  IF EXISTS(SELECT 1 FROM @p WHERE LEN(TRIM(FullName))<2 OR FullName IS NULL OR DateOfBirth IS NULL OR DateOfBirth>CONVERT(date,SYSUTCDATETIME()) OR DateOfBirth<'1900-01-01' OR LEN(TRIM(DocumentNumber))<5 OR DocumentNumber IS NULL)
    THROW 51004,N'Thông tin hành khách chưa đầy đủ.',1;
  IF (SELECT COUNT(DISTINCT SeatID) FROM @p)<>(SELECT COUNT(*) FROM @p)
    THROW 51004,N'Mỗi hành khách phải chọn một ghế khác nhau.',1;
  IF (SELECT COUNT(DISTINCT DocumentNumber) FROM @p)<>(SELECT COUNT(*) FROM @p)
    THROW 51004,N'Giấy tờ hành khách trong một đơn không được trùng.',1;
  IF EXISTS(SELECT 1 FROM @p p LEFT JOIN dbo.AircraftSeats s ON s.SeatID=p.SeatID AND s.AircraftID=@aircraft AND s.IsActive=1
   LEFT JOIN dbo.FareClasses c ON c.FareClassID=p.FareClassID AND c.Cabin=s.Cabin
   LEFT JOIN dbo.FlightFares f ON f.FlightID=@FlightID AND f.FareClassID=c.FareClassID
   WHERE s.SeatID IS NULL OR c.FareClassID IS NULL OR f.FlightID IS NULL)
    THROW 51004,N'Ghế hoặc hạng vé không phù hợp với chuyến bay.',1;
  IF EXISTS(SELECT 1 FROM @p p JOIN dbo.FlightSeatAssignments a WITH(UPDLOCK,HOLDLOCK) ON a.SeatID=p.SeatID AND a.FlightID=@FlightID AND a.IsActive=1)
    THROW 51005,N'Ghế vừa được người khác giữ. Vui lòng chọn ghế khác.',1;
  DECLARE @pnr char(8)=UPPER(LEFT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),8));
  WHILE EXISTS(SELECT 1 FROM dbo.Bookings WHERE PNR=@pnr)
    SET @pnr=UPPER(LEFT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),8));
  INSERT dbo.Bookings(PNR,UserID,FlightID,ExpiresAt) VALUES(@pnr,@UserID,@FlightID,DATEADD(minute,10,SYSUTCDATETIME()));
  SET @BookingID=SCOPE_IDENTITY();
  DECLARE @i int=1,@passenger int,@bp int,@assignment int;
  WHILE @i<=(SELECT COUNT(*) FROM @p)
  BEGIN
   INSERT dbo.Passengers(FullName,DateOfBirth,DocumentNumber) SELECT TRIM(FullName),DateOfBirth,TRIM(DocumentNumber) FROM @p WHERE RowID=@i;
   SET @passenger=SCOPE_IDENTITY();
   INSERT dbo.BookingPassengers(BookingID,PassengerID,FareClassID) SELECT @BookingID,@passenger,FareClassID FROM @p WHERE RowID=@i;
   SET @bp=SCOPE_IDENTITY();
   INSERT dbo.FlightSeatAssignments(FlightID,SeatID) SELECT @FlightID,SeatID FROM @p WHERE RowID=@i;
   SET @assignment=SCOPE_IDENTITY();
   INSERT dbo.Tickets(TicketNumber,BookingPassengerID,AssignmentID,Amount,RefundPercent)
    SELECT CONCAT('AF',RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),16)),@bp,@assignment,dbo.fn_CalculateTicketPrice(f.BasePrice,f.TaxRate),c.RefundPercent
    FROM @p p JOIN dbo.FlightFares f ON f.FlightID=@FlightID AND f.FareClassID=p.FareClassID JOIN dbo.FareClasses c ON c.FareClassID=f.FareClassID WHERE p.RowID=@i;
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
 DECLARE @flight int;
 SELECT @flight=FlightID FROM dbo.Bookings WHERE BookingID=@BookingID AND UserID=@UserID;
 IF @flight IS NULL THROW 51006,N'Không tìm thấy đơn đặt vé.',1;
 EXEC dbo.sp_ExpireFlightHolds @flight;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockFlight @flight;
  IF LEN(@IdempotencyKey)<16 OR @IdempotencyKey IS NULL OR @Success IS NULL THROW 51004,N'Mã thanh toán không hợp lệ.',1;
  IF EXISTS(SELECT 1 FROM dbo.Payments WHERE IdempotencyKey=@IdempotencyKey)
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Payments WHERE IdempotencyKey=@IdempotencyKey AND BookingID=@BookingID AND Kind='CHARGE' AND Status=CASE WHEN @Success=1 THEN 'SUCCESS' ELSE 'FAILED' END)
    THROW 51007,N'Mã thanh toán đã được dùng cho yêu cầu khác.',1;
   COMMIT;
   SELECT * FROM dbo.Payments WHERE IdempotencyKey=@IdempotencyKey;
   RETURN;
  END;
  IF NOT EXISTS(SELECT 1 FROM dbo.Bookings WHERE BookingID=@BookingID AND Status='HELD' AND ExpiresAt>SYSUTCDATETIME())
   THROW 51008,N'Đơn đã thanh toán, đã hủy hoặc hết hạn giữ ghế.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Flights WHERE FlightID=@flight AND Status='SCHEDULED' AND DepartureTime>SYSUTCDATETIME())
   THROW 51003,N'Chuyến bay không còn cho phép thanh toán.',1;
  DECLARE @amount decimal(14,2);
  SELECT @amount=SUM(t.Amount) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID;
  INSERT dbo.Payments(BookingID,IdempotencyKey,Amount,Kind,Status) VALUES(@BookingID,@IdempotencyKey,@amount,'CHARGE',CASE WHEN @Success=1 THEN 'SUCCESS' ELSE 'FAILED' END);
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
 DECLARE @flight int,@status varchar(12),@refund decimal(14,2);
 SELECT @flight=FlightID FROM dbo.Bookings WHERE BookingID=@BookingID AND (UserID=@UserID OR EXISTS(SELECT 1 FROM dbo.Users u JOIN dbo.Roles r ON r.RoleID=u.RoleID WHERE u.UserID=@UserID AND u.IsActive=1 AND r.Name='ADMIN'));
 IF @flight IS NULL THROW 51006,N'Không tìm thấy đơn đặt vé.',1;
 EXEC dbo.sp_ExpireFlightHolds @flight;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockFlight @flight;
  SELECT @status=Status FROM dbo.Bookings WHERE BookingID=@BookingID;
  IF @status='CANCELLED' BEGIN COMMIT; SELECT CAST(1 AS bit) Cancelled; RETURN; END;
  IF @status='EXPIRED' THROW 51008,N'Đơn đã hết hạn giữ ghế.',1;
  IF @status='CONFIRMED'
  BEGIN
   IF EXISTS(SELECT 1 FROM dbo.Flights WHERE FlightID=@flight AND (DepartureTime<=DATEADD(hour,24,SYSUTCDATETIME()) OR Status NOT IN ('SCHEDULED')))
    THROW 51009,N'Chỉ được hủy vé đã thanh toán trước giờ bay ít nhất 24 giờ.',1;
   SELECT @refund=SUM(ROUND(t.Amount*t.RefundPercent/100,2)) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID;
   INSERT dbo.Payments(BookingID,IdempotencyKey,Amount,Kind,Status) VALUES(@BookingID,CONCAT('refund-booking-',@BookingID),@refund,'REFUND','SUCCESS');
  END;
  UPDATE dbo.Bookings SET Status='CANCELLED' WHERE BookingID=@BookingID;
  UPDATE t SET Status='VOID' FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID;
  UPDATE a SET IsActive=0 FROM dbo.FlightSeatAssignments a JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID;
  COMMIT;
  SELECT CAST(1 AS bit) Cancelled,COALESCE(@refund,0) RefundAmount;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_GetAvailableSeats @FlightID int AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ExpireFlightHolds @FlightID;
 SELECT s.SeatID,s.SeatNumber,s.RowNumber,s.ColumnLetter,s.Cabin,
 CAST(CASE WHEN EXISTS(SELECT 1 FROM dbo.FlightSeatAssignments a WHERE a.FlightID=@FlightID AND a.SeatID=s.SeatID AND a.IsActive=1) THEN 0 ELSE 1 END AS bit) Available
 FROM dbo.AircraftSeats s JOIN dbo.Flights f ON f.AircraftID=s.AircraftID WHERE f.FlightID=@FlightID AND s.IsActive=1 ORDER BY s.RowNumber,s.ColumnLetter;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_GetRevenueReport @From date,@To date AS
BEGIN
 SET NOCOUNT ON;
 IF @From>@To THROW 51004,N'Khoảng ngày không hợp lệ.',1;
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
  EXEC dbo.sp_LockFlight @FlightID;
  DECLARE @old varchar(12);
  SELECT @old=Status FROM dbo.Flights WHERE FlightID=@FlightID;
  IF @old IS NULL THROW 51006,N'Không tìm thấy chuyến bay.',1;
  IF @old=@Status BEGIN COMMIT; RETURN; END;
  IF NOT ((@old='SCHEDULED' AND @Status IN ('BOARDING','CANCELLED')) OR (@old='BOARDING' AND @Status IN ('DEPARTED','CANCELLED')) OR (@old='DEPARTED' AND @Status='ARRIVED'))
   THROW 51010,N'Chuyển trạng thái chuyến bay không hợp lệ.',1;
  IF @Status IN ('CANCELLED','BOARDING')
  BEGIN
   -- Closing sales invalidates every unpaid hold. Airline cancellation refunds paid tickets in full.
   IF @Status='CANCELLED'
    INSERT dbo.Payments(BookingID,IdempotencyKey,Amount,Kind,Status)
    SELECT b.BookingID,CONCAT('refund-booking-',b.BookingID),SUM(t.Amount),'REFUND','SUCCESS'
    FROM dbo.Bookings b JOIN dbo.BookingPassengers p ON p.BookingID=b.BookingID JOIN dbo.Tickets t ON t.BookingPassengerID=p.BookingPassengerID
    WHERE b.FlightID=@FlightID AND b.Status='CONFIRMED' GROUP BY b.BookingID;
   DECLARE @closing TABLE(BookingID int PRIMARY KEY);
   UPDATE dbo.Bookings SET Status=CASE WHEN @Status='CANCELLED' THEN 'CANCELLED' ELSE 'EXPIRED' END
    OUTPUT inserted.BookingID INTO @closing WHERE FlightID=@FlightID AND (Status='HELD' OR (@Status='CANCELLED' AND Status='CONFIRMED'));
   UPDATE t SET Status='VOID' FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID JOIN @closing c ON c.BookingID=p.BookingID;
   UPDATE a SET IsActive=0 FROM dbo.FlightSeatAssignments a JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID JOIN @closing c ON c.BookingID=p.BookingID;
  END;
  UPDATE dbo.Flights SET Status=@Status WHERE FlightID=@FlightID;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_SaveFlight @FlightID int=NULL,@FlightNumber varchar(8),@AircraftID int,@OriginID int,@DestinationID int,@DepartureTime datetime2(0),@ArrivalTime datetime2(0) AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @r int;
  EXEC @r=sys.sp_getapplock @Resource='AeroFlow:schedule',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @r<0 THROW 51001,N'Lịch bay đang được cập nhật.',1;
  IF @FlightID IS NOT NULL
  BEGIN
   EXEC dbo.sp_LockFlight @FlightID;
   IF NOT EXISTS(SELECT 1 FROM dbo.Flights WHERE FlightID=@FlightID AND Status='SCHEDULED') THROW 51010,N'Chỉ sửa chuyến đang mở bán.',1;
   IF EXISTS(SELECT 1 FROM dbo.Bookings WHERE FlightID=@FlightID) THROW 51011,N'Chuyến đã có lịch sử đặt vé. Hãy hủy chuyến và tạo chuyến mới nếu cần thay đổi lịch hoặc máy bay.',1;
  END;
  IF @OriginID=@DestinationID OR @ArrivalTime<=@DepartureTime OR @DepartureTime<=SYSUTCDATETIME() THROW 51004,N'Lịch bay không hợp lệ.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Aircraft WHERE AircraftID=@AircraftID AND IsActive=1) OR
    (SELECT COUNT(*) FROM dbo.Airports WHERE AirportID IN (@OriginID,@DestinationID) AND IsActive=1)<>2 THROW 51004,N'Máy bay hoặc sân bay không hoạt động.',1;
  IF EXISTS(SELECT 1 FROM dbo.Flights WITH(UPDLOCK,HOLDLOCK) WHERE AircraftID=@AircraftID AND Status<>'CANCELLED' AND FlightID<>COALESCE(@FlightID,0) AND DepartureTime<DATEADD(minute,45,@ArrivalTime) AND ArrivalTime>DATEADD(minute,-45,@DepartureTime))
   THROW 51012,N'Máy bay có lịch trùng hoặc chưa đủ 45 phút quay đầu.',1;
  IF @FlightID IS NULL
  BEGIN
   INSERT dbo.Flights(FlightNumber,AircraftID,OriginID,DestinationID,DepartureTime,ArrivalTime) VALUES(@FlightNumber,@AircraftID,@OriginID,@DestinationID,@DepartureTime,@ArrivalTime);
   SET @FlightID=SCOPE_IDENTITY();
  END
  ELSE UPDATE dbo.Flights SET FlightNumber=@FlightNumber,AircraftID=@AircraftID,OriginID=@OriginID,DestinationID=@DestinationID,DepartureTime=@DepartureTime,ArrivalTime=@ArrivalTime WHERE FlightID=@FlightID;
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
  EXEC dbo.sp_LockFlight @FlightID;
  IF NOT EXISTS(SELECT 1 FROM dbo.Flights WHERE FlightID=@FlightID AND Status='SCHEDULED') THROW 51010,N'Chỉ sửa giá chuyến đang mở bán.',1;
  UPDATE dbo.FlightFares SET BasePrice=@BasePrice,TaxRate=@TaxRate WHERE FlightID=@FlightID AND FareClassID=@FareClassID;
  IF @@ROWCOUNT=0 INSERT dbo.FlightFares(FlightID,FareClassID,BasePrice,TaxRate) VALUES(@FlightID,@FareClassID,@BasePrice,@TaxRate);
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
