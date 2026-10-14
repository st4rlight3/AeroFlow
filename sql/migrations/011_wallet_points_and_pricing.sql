CREATE OR ALTER PROCEDURE dbo.sp_ConfirmPayment @UserID int,@BookingID int,@IdempotencyKey varchar(80),@Success bit,@Method varchar(8)='MOCK' AS
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
    SELECT b.BookingID,CONCAT('refund-booking-',b.BookingID),(SELECT SUM(CASE WHEN px.Kind='CHARGE' THEN px.Amount ELSE -px.Amount END) FROM dbo.Payments px WHERE px.BookingID=b.BookingID AND px.Status='SUCCESS'),'REFUND','SUCCESS'
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
CREATE OR ALTER PROCEDURE dbo.sp_SetBookingOptions @UserID int,@BookingID int,@Extras nvarchar(max)=N'[]',@Code varchar(30)=NULL,@Points int=0 AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 EXEC dbo.sp_LockFlight 0;
 IF NOT EXISTS(SELECT 1 FROM dbo.Bookings WHERE BookingID=@BookingID AND UserID=@UserID) THROW 51006,N'Không tìm thấy đặt chỗ.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Bookings WHERE BookingID=@BookingID AND Status='HELD' AND ExpiresAt>SYSUTCDATETIME()) THROW 51008,N'Chỉ sửa dịch vụ khi còn giữ ghế.',1;
 IF ISJSON(@Extras)<>1 OR LEFT(LTRIM(@Extras),1)<>'[' THROW 51004,N'Danh sách dịch vụ không hợp lệ.',1;
 IF @Points IS NULL OR @Points<0 OR (NULLIF(TRIM(@Code),'') IS NOT NULL AND @Points>0) THROW 51004,N'Chọn mã ưu đãi hoặc điểm, không cộng dồn.',1;
 DELETE dbo.LoyaltySpends WHERE BookingID=@BookingID;
 DECLARE @available int=(SELECT AvailablePoints FROM dbo.vw_LoyaltySummary WHERE UserID=@UserID);
 IF @Points>@available THROW 51016,N'Không đủ điểm thưởng.',1;
 DECLARE @x TABLE(TicketID int,ServiceID int,Quantity int,PRIMARY KEY(TicketID,ServiceID));
 INSERT @x SELECT TicketID,ServiceID,Quantity FROM OPENJSON(@Extras) WITH(TicketID int,ServiceID int,Quantity int);
 IF (SELECT COUNT(*) FROM @x)>540 OR EXISTS(SELECT 1 FROM @x x LEFT JOIN dbo.Tickets t ON t.TicketID=x.TicketID LEFT JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID LEFT JOIN dbo.Services s ON s.ServiceID=x.ServiceID WHERE bp.BookingID IS NULL OR bp.BookingID<>@BookingID OR t.Status<>'PENDING' OR s.ServiceID IS NULL OR s.IsActive<>1 OR x.Quantity IS NULL OR x.Quantity<1 OR x.Quantity>s.MaxQuantity)
 THROW 51004,N'Vé hoặc dịch vụ không hợp lệ.',1;
 IF EXISTS(SELECT 1 FROM @x x JOIN dbo.Services s ON s.ServiceID=x.ServiceID WHERE s.Category='MEAL' GROUP BY x.TicketID HAVING COUNT(*)>1) THROW 51004,N'Chỉ chọn một loại suất ăn cho mỗi vé.',1;
 DELETE d FROM dbo.TicketDiscounts d JOIN dbo.Tickets t ON t.TicketID=d.TicketID JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID WHERE bp.BookingID=@BookingID;
 DELETE e FROM dbo.BookingExtras e JOIN dbo.Tickets t ON t.TicketID=e.TicketID JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID WHERE bp.BookingID=@BookingID;
 DELETE dbo.BookingDiscounts WHERE BookingID=@BookingID;
 INSERT dbo.BookingExtras SELECT x.TicketID,x.ServiceID,s.Name,x.Quantity,s.UnitPrice,s.RefundPercent FROM @x x JOIN dbo.Services s ON s.ServiceID=x.ServiceID;
 DECLARE @gross decimal(14,2),@discount decimal(14,2)=0,@codeid int,@method varchar(8),@value decimal(14,2),@max decimal(14,2),@min decimal(14,2),@uses int;
 SELECT @gross=SUM(dbo.fn_TicketPaidValue(t.TicketID)) FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID WHERE bp.BookingID=@BookingID;
 IF NULLIF(TRIM(@Code),'') IS NOT NULL
 BEGIN
 SELECT @codeid=DiscountCodeID,@method=Method,@value=Value,@max=MaxDiscount,@min=MinimumSpend,@uses=MaxUses FROM dbo.DiscountCodes WHERE Code=@Code AND IsActive=1 AND ValidFrom<=SYSUTCDATETIME() AND ValidTo>SYSUTCDATETIME();
 IF @codeid IS NULL OR @gross<@min THROW 51015,N'Mã giảm giá không hợp lệ hoặc chưa đủ giá trị tối thiểu.',1;
 IF (SELECT COUNT(*) FROM dbo.BookingDiscounts d JOIN dbo.Bookings b ON b.BookingID=d.BookingID WHERE d.DiscountCodeID=@codeid AND (b.Status='CONFIRMED' OR (b.Status='HELD' AND b.ExpiresAt>SYSUTCDATETIME())))>=@uses THROW 51015,N'Mã giảm giá đã hết lượt.',1;
 SET @discount=ROUND(CASE WHEN @method='PERCENT' THEN @gross*@value/100 ELSE @value END,2);
 IF @discount>@max SET @discount=@max;
 IF @discount>@gross-1 SET @discount=@gross-1;
 INSERT dbo.BookingDiscounts VALUES(@BookingID,@codeid,UPPER(@Code),@discount);
 END;
 IF @Points>0
 BEGIN
 SET @discount=CONVERT(decimal(14,2),@Points)*1000;
 IF @discount>@gross/2 THROW 51016,N'Điểm chỉ giảm tối đa 50 phần trăm đơn.',1;
 INSERT dbo.LoyaltySpends VALUES(@BookingID,@UserID,@Points,@discount);
 END;
 IF @discount>0
 BEGIN
 -- Allocate discount across tickets with an exact remainder on the last row.
 DECLARE @last int=(SELECT MAX(t.TicketID) FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID WHERE bp.BookingID=@BookingID);
 INSERT dbo.TicketDiscounts SELECT t.TicketID,FLOOR(dbo.fn_TicketPaidValue(t.TicketID)*@discount/@gross*100)/100 FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID WHERE bp.BookingID=@BookingID AND t.TicketID<>@last;
 INSERT dbo.TicketDiscounts SELECT @last,@discount-COALESCE(SUM(d.Amount),0) FROM dbo.TicketDiscounts d JOIN dbo.Tickets t ON t.TicketID=d.TicketID JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID WHERE bp.BookingID=@BookingID;
 END;
 INSERT dbo.AuditLogs(ActorID,Entity,EntityID,Action,Details) VALUES(@UserID,'Bookings',@BookingID,'OPTIONS_SAVED',CONCAT('Discount=',@discount));
 COMMIT;
 SELECT @gross GrossAmount,@discount DiscountAmount,@gross-@discount TotalAmount;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_CancelTicket @UserID int,@TicketID int,@ToCredit bit=0 AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 EXEC dbo.sp_LockFlight 0;
 DECLARE @booking int,@status varchar(12),@bookingStatus varchar(12),@departure datetime2(0),@flightStatus varchar(12),@refund decimal(14,2),@payment int;
 SELECT @booking=b.BookingID,@status=t.Status,@bookingStatus=b.Status,@departure=f.DepartureTime,@flightStatus=f.Status
 FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Bookings b ON b.BookingID=bp.BookingID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID JOIN dbo.Flights f ON f.FlightID=a.FlightID WHERE t.TicketID=@TicketID AND b.UserID=@UserID;
 IF @booking IS NULL THROW 51006,N'Không tìm thấy vé.',1;
 IF @ToCredit IS NULL THROW 51004,N'Chọn cách hoàn tiền.',1;
 IF EXISTS(SELECT 1 FROM dbo.TicketRefunds WHERE TicketID=@TicketID) BEGIN
 IF EXISTS(SELECT 1 FROM dbo.TicketRefunds r JOIN dbo.Payments p ON p.PaymentID=r.PaymentID WHERE r.TicketID=@TicketID AND p.Settlement<>CASE WHEN @ToCredit=1 THEN 'CREDIT' ELSE 'MOCK' END) THROW 51007,N'Vé đã hoàn bằng phương thức khác.',1;
 COMMIT; SELECT * FROM dbo.TicketRefunds WHERE TicketID=@TicketID; RETURN; END;
 IF @status<>'VALID' OR @bookingStatus<>'CONFIRMED' THROW 51010,N'Chỉ hủy riêng vé đã thanh toán còn hiệu lực.',1;
 IF @departure<=DATEADD(hour,24,SYSUTCDATETIME()) OR @flightStatus<>'SCHEDULED' OR EXISTS(SELECT 1 FROM dbo.CheckIns WHERE TicketID=@TicketID AND Status='ACTIVE') THROW 51009,N'Chỉ hủy vé trước giờ bay ít nhất 24 giờ.',1;
 SET @refund=dbo.fn_TicketRefundValue(@TicketID);
 INSERT dbo.Payments(BookingID,IdempotencyKey,Amount,Kind,Status,Settlement) VALUES(@booking,CONCAT('refund-ticket-',@TicketID),@refund,'REFUND','SUCCESS',CASE WHEN @ToCredit=1 THEN 'CREDIT' ELSE 'MOCK' END); SET @payment=SCOPE_IDENTITY();
 IF @ToCredit=1 INSERT dbo.TravelCreditLedger(UserID,PaymentID,Amount) VALUES(@UserID,@payment,@refund);
 INSERT dbo.TicketRefunds(TicketID,PaymentID,Amount) VALUES(@TicketID,@payment,@refund);
 UPDATE dbo.Tickets SET Status='VOID' WHERE TicketID=@TicketID;
 UPDATE a SET IsActive=0 FROM dbo.FlightSeatAssignments a JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID WHERE t.TicketID=@TicketID;
 UPDATE s SET Status='CANCELLED' FROM dbo.BookingSegments s WHERE s.BookingID=@booking AND s.Status='ACTIVE' AND NOT EXISTS(SELECT 1 FROM dbo.Tickets t WHERE t.BookingSegmentID=s.BookingSegmentID AND t.Status='VALID');
 IF NOT EXISTS(SELECT 1 FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID WHERE bp.BookingID=@booking AND t.Status='VALID') UPDATE dbo.Bookings SET Status='CANCELLED' WHERE BookingID=@booking;
 INSERT dbo.AuditLogs(ActorID,Entity,EntityID,Action,Details) VALUES(@UserID,'Tickets',@TicketID,'PARTIAL_CANCEL',CONCAT('Refund=',@refund));
 COMMIT;
 SELECT * FROM dbo.TicketRefunds WHERE TicketID=@TicketID;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;

GO
CREATE OR ALTER VIEW dbo.vw_BookingDetails AS
 SELECT b.BookingID,b.PNR,b.UserID,b.FlightID,b.Status,b.CreatedAt,b.ExpiresAt,b.JourneyType,(SELECT COUNT(*) FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID) SegmentCount,
 u.FullName CustomerName,u.Email,f.FlightNumber,f.OriginCode,f.DestinationCode,f.DepartureTime,f.ArrivalTime,
 CASE WHEN b.Status IN ('HELD','EXPIRED') OR NOT EXISTS(SELECT 1 FROM dbo.Payments px WHERE px.BookingID=b.BookingID AND px.Kind='CHARGE' AND px.Status='SUCCESS') THEN COALESCE((SELECT SUM(dbo.fn_TicketPaidValue(t.TicketID)) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=b.BookingID),0) ELSE COALESCE((SELECT SUM(Amount) FROM dbo.Payments WHERE BookingID=b.BookingID AND Kind='CHARGE' AND Status='SUCCESS'),0) END TotalAmount,
 (SELECT COUNT(*) FROM dbo.BookingPassengers p WHERE p.BookingID=b.BookingID) PassengerCount
 FROM dbo.Bookings b JOIN dbo.Users u ON u.UserID=b.UserID JOIN dbo.vw_FlightAvailability f ON f.FlightID=b.FlightID;


GO
CREATE OR ALTER PROCEDURE dbo.sp_CreateBooking @UserID int,@FlightID int,@Passengers nvarchar(max) AS
BEGIN
 SET NOCOUNT ON;
 IF ISJSON(@Passengers)<>1 OR LEFT(LTRIM(@Passengers),1)<>'[' THROW 51004,N'Danh sách hành khách không hợp lệ.',1;
 DECLARE @segments nvarchar(max),@people nvarchar(max),@choices nvarchar(max),@fare int,@day date=(SELECT CONVERT(date,DepartureTime) FROM dbo.Flights WHERE FlightID=@FlightID);
 SELECT TOP(1) @fare=FareClassID FROM OPENJSON(@Passengers) WITH(FareClassID int);
 -- Legacy API has one common cabin/fare. Mixed fares are rejected instead of silently repriced.
 IF EXISTS(SELECT 1 FROM OPENJSON(@Passengers) WITH(FareClassID int) WHERE FareClassID<>@fare OR FareClassID IS NULL) THROW 51004,N'Luồng một chặng cần cùng hạng vé.',1;
 SET @segments=(SELECT @FlightID FlightID,@fare FareClassID,1 JourneyGroup FOR JSON PATH);
 SET @people=(SELECT x.FullName,x.DateOfBirth,x.DocumentNumber,CASE WHEN TRY_CONVERT(date,x.DateOfBirth)>DATEADD(year,-2,@day) THEN 'INFANT' WHEN TRY_CONVERT(date,x.DateOfBirth)>DATEADD(year,-12,@day) THEN 'CHILD' ELSE 'ADULT' END TypeCode FROM OPENJSON(@Passengers) j CROSS APPLY OPENJSON(j.value) WITH(FullName nvarchar(120),DateOfBirth nvarchar(20),DocumentNumber nvarchar(30)) x ORDER BY CONVERT(int,j.[key]) FOR JSON PATH);
 SET @choices=(SELECT CONVERT(int,j.[key]) PassengerIndex,0 SegmentIndex,x.SeatID FROM OPENJSON(@Passengers) j CROSS APPLY OPENJSON(j.value) WITH(SeatID int) x ORDER BY CONVERT(int,j.[key]) FOR JSON PATH);
 EXEC dbo.sp_CreateItinerary @UserID,'ONE_WAY',@segments,@people,@choices;
END;