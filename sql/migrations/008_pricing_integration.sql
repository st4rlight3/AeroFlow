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
  IF EXISTS(SELECT 1 FROM dbo.BookingSegments s JOIN dbo.Flights f ON f.FlightID=s.FlightID WHERE s.BookingID=@BookingID AND s.Status='ACTIVE' AND (f.Status<>'SCHEDULED' OR f.DepartureTime<=SYSUTCDATETIME()))
   THROW 51003,N'Chuyến bay không còn cho phép thanh toán.',1;
  DECLARE @amount decimal(14,2);
  SELECT @amount=SUM(dbo.fn_TicketPaidValue(t.TicketID)) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID;
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
   IF EXISTS(SELECT 1 FROM dbo.CheckIns c JOIN dbo.Tickets t ON t.TicketID=c.TicketID JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID WHERE bp.BookingID=@BookingID AND c.Status='ACTIVE') THROW 51009,N'Vé đã check-in không thể hủy.',1;
   IF EXISTS(SELECT 1 FROM dbo.BookingSegments s JOIN dbo.Flights f ON f.FlightID=s.FlightID WHERE s.BookingID=@BookingID AND s.Status='ACTIVE' AND (f.DepartureTime<=DATEADD(hour,24,SYSUTCDATETIME()) OR f.Status<>'SCHEDULED'))
    THROW 51009,N'Chỉ được hủy vé đã thanh toán trước giờ bay ít nhất 24 giờ.',1;
   SELECT @refund=SUM(dbo.fn_TicketRefundValue(t.TicketID)) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=@BookingID AND t.Status='VALID';
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
 SELECT s.SeatID,s.SeatNumber,s.RowNumber,s.ColumnLetter,s.Cabin,s.SeatFee,s.IsPriority,
 CAST(CASE WHEN EXISTS(SELECT 1 FROM dbo.FlightSeatAssignments a WHERE a.FlightID=@FlightID AND a.SeatID=s.SeatID AND a.IsActive=1) THEN 0 ELSE 1 END AS bit) Available
 FROM dbo.AircraftSeats s JOIN dbo.Flights f ON f.AircraftID=s.AircraftID WHERE f.FlightID=@FlightID AND s.IsActive=1 ORDER BY s.RowNumber,s.ColumnLetter;
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
    SELECT b.BookingID,CONCAT('refund-booking-',b.BookingID),SUM(dbo.fn_TicketPaidValue(t.TicketID)),'REFUND','SUCCESS'
    FROM dbo.Bookings b JOIN dbo.BookingPassengers p ON p.BookingID=b.BookingID JOIN dbo.Tickets t ON t.BookingPassengerID=p.BookingPassengerID
    WHERE EXISTS(SELECT 1 FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID AND s.FlightID=@FlightID AND s.Status='ACTIVE') AND b.Status='CONFIRMED' AND t.Status='VALID' GROUP BY b.BookingID;
   DECLARE @closing TABLE(BookingID int PRIMARY KEY);
   UPDATE dbo.Bookings SET Status=CASE WHEN @Status='CANCELLED' THEN 'CANCELLED' ELSE 'EXPIRED' END
    OUTPUT inserted.BookingID INTO @closing WHERE EXISTS(SELECT 1 FROM dbo.BookingSegments s WHERE s.BookingID=dbo.Bookings.BookingID AND s.FlightID=@FlightID AND s.Status='ACTIVE') AND (Status='HELD' OR (@Status='CANCELLED' AND Status='CONFIRMED'));
   UPDATE t SET Status='VOID' FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID JOIN @closing c ON c.BookingID=p.BookingID;
   UPDATE a SET IsActive=0 FROM dbo.FlightSeatAssignments a JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID JOIN @closing c ON c.BookingID=p.BookingID;
  END;
  UPDATE dbo.Flights SET Status=@Status WHERE FlightID=@FlightID;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER VIEW dbo.vw_BookingDetails AS
 SELECT b.BookingID,b.PNR,b.UserID,b.FlightID,b.Status,b.CreatedAt,b.ExpiresAt,b.JourneyType,(SELECT COUNT(*) FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID) SegmentCount,
 u.FullName CustomerName,u.Email,f.FlightNumber,f.OriginCode,f.DestinationCode,f.DepartureTime,f.ArrivalTime,
 COALESCE((SELECT SUM(dbo.fn_TicketPaidValue(t.TicketID)) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=b.BookingID),0) TotalAmount,
 (SELECT COUNT(*) FROM dbo.BookingPassengers p WHERE p.BookingID=b.BookingID) PassengerCount
 FROM dbo.Bookings b JOIN dbo.Users u ON u.UserID=b.UserID JOIN dbo.vw_FlightAvailability f ON f.FlightID=b.FlightID;


GO
CREATE OR ALTER TRIGGER dbo.tr_Seats_ImmutableLayout ON dbo.AircraftSeats AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i FULL JOIN deleted d ON d.SeatID=i.SeatID
 WHERE EXISTS(SELECT 1 FROM dbo.Flights f WHERE f.AircraftID IN (i.AircraftID,d.AircraftID))
 AND (i.SeatID IS NULL OR d.SeatID IS NULL OR i.AircraftID<>d.AircraftID OR i.SeatNumber<>d.SeatNumber OR i.RowNumber<>d.RowNumber OR i.ColumnLetter<>d.ColumnLetter OR i.Cabin<>d.Cabin OR i.IsActive<>d.IsActive))
 THROW 51011,N'Không thay đổi sơ đồ đã có chuyến bay. Phí chọn ghế chỉ áp dụng cho vé mới.',1;
END;
GO
UPDATE dbo.FareClasses SET Bundle=CASE WHEN Code='ECO' THEN 'BASIC' WHEN Code IN ('FLEX','BIZ') THEN 'FLEXIBLE' ELSE Bundle END,ChangeAllowed=CASE WHEN Code='ECO' THEN 0 ELSE ChangeAllowed END;