CREATE OR ALTER PROCEDURE dbo.sp_ConfirmPayment @UserID int,@BookingID int,@IdempotencyKey varchar(80),@Success bit,@Method varchar(8)='MOCK',@ExpectedAmount decimal(14,2)=NULL AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @flight int;
 SELECT @flight=FlightID FROM dbo.Bookings WHERE BookingID=@BookingID AND UserID=@UserID;
 IF @flight IS NULL THROW 51006,N'Không tìm thấy đơn đặt vé.',1;
 EXEC dbo.sp_ExpireFlightHolds @flight;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockFlight @flight;
  IF @Method NOT IN ('MOCK','CREDIT') OR @Method IS NULL THROW 51004,N'Phương thức không hợp lệ.',1;
  IF LEN(@IdempotencyKey)<16 OR @IdempotencyKey IS NULL OR @Success IS NULL THROW 51004,N'Mã thanh toán không hợp lệ.',1;
  IF EXISTS(SELECT 1 FROM dbo.Payments WHERE IdempotencyKey=@IdempotencyKey)
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Payments WHERE IdempotencyKey=@IdempotencyKey AND BookingID=@BookingID AND Kind='CHARGE' AND Purpose='BOOKING' AND Settlement=@Method AND Status=CASE WHEN @Success=1 THEN 'SUCCESS' ELSE 'FAILED' END)
    THROW 51007,N'Mã thanh toán đã được dùng cho yêu cầu khác.',1;
   COMMIT;
   SELECT * FROM dbo.Payments WHERE IdempotencyKey=@IdempotencyKey;
   RETURN;
  END;
  IF NOT EXISTS(SELECT 1 FROM dbo.Bookings WHERE BookingID=@BookingID AND Status='HELD' AND ExpiresAt>SYSUTCDATETIME())
   THROW 51008,N'Đơn đã thanh toán, đã hủy hoặc hết hạn giữ ghế.',1;
  IF EXISTS(SELECT 1 FROM dbo.BookingSegments s JOIN dbo.Flights f ON f.FlightID=s.FlightID WHERE s.BookingID=@BookingID AND s.Status='ACTIVE' AND (f.Status<>'SCHEDULED' OR f.DepartureTime<=SYSUTCDATETIME()))
   THROW 51003,N'Chuyến bay không còn cho phép thanh toán.',1;
  DECLARE @amount decimal(14,2);
  SELECT @amount=SUM(dbo.fn_TicketPaidValue(t.TicketID)) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID;
  IF @ExpectedAmount IS NOT NULL AND @ExpectedAmount<>@amount THROW 51013,N'Tổng tiền đã thay đổi. Tải lại đặt chỗ.',1;
  IF @Success=1 AND @Method='CREDIT' AND @amount>COALESCE((SELECT SUM(Amount) FROM dbo.TravelCreditLedger WHERE UserID=@UserID),0) THROW 51016,N'Tín dụng du lịch không đủ.',1;
  INSERT dbo.Payments(BookingID,IdempotencyKey,Amount,Kind,Status,Settlement) VALUES(@BookingID,@IdempotencyKey,@amount,'CHARGE',CASE WHEN @Success=1 THEN 'SUCCESS' ELSE 'FAILED' END,@Method);
  DECLARE @paymentID int=SCOPE_IDENTITY();
  IF @Success=1 AND @Method='CREDIT' INSERT dbo.TravelCreditLedger(UserID,PaymentID,Amount) VALUES(@UserID,@paymentID,-@amount);
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
   IF EXISTS(SELECT 1 FROM dbo.BookingSegments WHERE FlightID=@FlightID) THROW 51011,N'Chuyến đã có lịch sử đặt vé. Hãy hủy chuyến và tạo chuyến mới nếu cần thay đổi lịch hoặc máy bay.',1;
  END;
  IF @OriginID=@DestinationID OR @ArrivalTime<=@DepartureTime OR @DepartureTime<=SYSUTCDATETIME() THROW 51004,N'Lịch bay không hợp lệ.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Aircraft WHERE AircraftID=@AircraftID AND IsActive=1) OR
    (SELECT COUNT(*) FROM dbo.Airports WHERE AirportID IN (@OriginID,@DestinationID) AND IsActive=1)<>2 THROW 51004,N'Máy bay hoặc sân bay không hoạt động.',1;
  IF EXISTS(SELECT 1 FROM dbo.Flights WITH(UPDLOCK,HOLDLOCK) WHERE AircraftID=@AircraftID AND Status<>'CANCELLED' AND FlightID<>COALESCE(@FlightID,0) AND DepartureTime<DATEADD(minute,45,@ArrivalTime) AND ArrivalTime>DATEADD(minute,-45,@DepartureTime))
   THROW 51012,N'Máy bay có lịch trùng hoặc chưa đủ 45 phút quay đầu.',1;
  IF EXISTS(SELECT 1 FROM dbo.Routes WHERE OriginID=@OriginID AND DestinationID=@DestinationID AND IsActive=0) THROW 51003,N'Đường bay đang tạm ngừng khai thác mới.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Routes WHERE OriginID=@OriginID AND DestinationID=@DestinationID) INSERT dbo.Routes(OriginID,DestinationID) VALUES(@OriginID,@DestinationID);
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