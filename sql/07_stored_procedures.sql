USE AeroFlow;
GO
-- 07_stored_procedures - Final definitions, including all historical dynamic patches.
-- Consolidated schema through migration 017. For a NEW database only.
-- Existing installations use scripts/migrate.py and the unchanged sql/migrations history.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- dbo.sp_GetRevenueReport
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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

-- dbo.sp_LockFlight
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_LockFlight @FlightID int AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @r int,@resource nvarchar(255)=N'AeroFlow:inventory';
 EXEC @r=sys.sp_getapplock @Resource=@resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @r<0 THROW 51001,N'Chuyến bay đang được cập nhật. Vui lòng thử lại.',1;
END;
GO

-- dbo.sp_BoardPassenger
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_BoardPassenger @UserID int,@CheckInID int AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 EXEC dbo.sp_LockFlight 0;
 IF NOT EXISTS(SELECT 1 FROM dbo.Users u JOIN dbo.Roles r ON r.RoleID=u.RoleID WHERE u.UserID=@UserID AND u.IsActive=1 AND r.Name='ADMIN') THROW 51006,N'Không có quyền khai thác.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.CheckIns c JOIN dbo.Tickets t ON t.TicketID=c.TicketID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID JOIN dbo.Flights f ON f.FlightID=a.FlightID WHERE c.CheckInID=@CheckInID AND c.Status='ACTIVE' AND t.Status='VALID' AND a.IsActive=1 AND f.Status='BOARDING') THROW 51010,N'Chưa đủ điều kiện lên máy bay.',1;
 UPDATE dbo.CheckIns SET BoardedAt=SYSUTCDATETIME() WHERE CheckInID=@CheckInID AND BoardedAt IS NULL;
 IF @@ROWCOUNT>0 INSERT dbo.AuditLogs(ActorID,Entity,EntityID,Action) VALUES(@UserID,'CheckIns',@CheckInID,'BOARDED');
 COMMIT;SELECT * FROM dbo.CheckIns WHERE CheckInID=@CheckInID;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH
END;
GO

-- dbo.sp_CancelTicket
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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

-- dbo.sp_CheckIn
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_CheckIn @UserID int,@TicketID int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 EXEC dbo.sp_LockFlight 0;
 DECLARE @bid int,@departure datetime2(0),@flightStatus varchar(12),@ticketStatus varchar(12),@bookingStatus varchar(12),@active bit;
 SELECT @bid=b.BookingID,@departure=COALESCE(f.EstimatedDeparture,f.DepartureTime),@flightStatus=f.Status,@ticketStatus=t.Status,@bookingStatus=b.Status,@active=a.IsActive
 FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Bookings b ON b.BookingID=bp.BookingID
 JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID JOIN dbo.Flights f ON f.FlightID=a.FlightID
 WHERE t.TicketID=@TicketID AND b.UserID=@UserID;
 IF @bid IS NULL THROW 51006,N'Không tìm thấy vé.',1;
 IF @ticketStatus<>'VALID' OR @bookingStatus<>'CONFIRMED' OR @active<>1 OR @flightStatus NOT IN ('SCHEDULED','BOARDING') THROW 51014,N'Vé không đủ điều kiện check-in.',1;
 IF SYSUTCDATETIME()<DATEADD(hour,-24,@departure) OR SYSUTCDATETIME()>=DATEADD(hour,-1,@departure) THROW 51014,N'Check-in mở từ 24 giờ đến 1 giờ trước giờ bay dự kiến.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.CheckIns WHERE TicketID=@TicketID)
 BEGIN
 INSERT dbo.CheckIns(TicketID) VALUES(@TicketID);
 INSERT dbo.AuditLogs(ActorID,Entity,EntityID,Action) VALUES(@UserID,'Tickets',@TicketID,'CHECK_IN');
 INSERT dbo.Notifications(UserID,BookingID,Title,Message,EventKey) VALUES(@UserID,@bid,N'Check-in thành công',N'Thẻ lên máy bay mô phỏng đã sẵn sàng. Không có giá trị vận chuyển.',CONCAT('checkin:',@TicketID));
 END;
 COMMIT;
 SELECT * FROM dbo.CheckIns WHERE TicketID=@TicketID;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO

-- dbo.sp_ExpireFlightHolds
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ExpireFlightHolds @FlightID int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockFlight @FlightID;
  DECLARE @expired TABLE(BookingID int PRIMARY KEY);
  UPDATE dbo.Bookings SET Status='EXPIRED' OUTPUT inserted.BookingID INTO @expired
   WHERE EXISTS(SELECT 1 FROM dbo.BookingSegments s WHERE s.BookingID=dbo.Bookings.BookingID AND s.FlightID=@FlightID) AND Status='HELD' AND ExpiresAt<=SYSUTCDATETIME();
  UPDATE t SET Status='VOID' FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID JOIN @expired e ON e.BookingID=p.BookingID;
  UPDATE a SET IsActive=0 FROM dbo.FlightSeatAssignments a JOIN dbo.Tickets t ON t.AssignmentID=a.AssignmentID JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID JOIN @expired e ON e.BookingID=p.BookingID;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO

-- dbo.sp_GenerateReminders
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_GenerateReminders AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 EXEC dbo.sp_LockFlight 0;
 INSERT dbo.Notifications(UserID,BookingID,Title,Message,EventKey)
 SELECT DISTINCT b.UserID,b.BookingID,N'Sắp đến giờ bay',CONCAT(f.FlightNumber,N' đã mở cửa sổ check-in. Xem hành trình để làm thủ tục.'),CONCAT('reminder:',b.BookingID,':',f.FlightID)
 FROM dbo.Bookings b JOIN dbo.BookingSegments s ON s.BookingID=b.BookingID JOIN dbo.Flights f ON f.FlightID=s.FlightID
 LEFT JOIN dbo.UserPreferences p ON p.UserID=b.UserID
 WHERE b.Status='CONFIRMED' AND s.Status='ACTIVE' AND f.Status IN ('SCHEDULED','BOARDING') AND COALESCE(p.Reminders,1)=1
 AND COALESCE(f.EstimatedDeparture,f.DepartureTime)>DATEADD(hour,1,SYSUTCDATETIME()) AND COALESCE(f.EstimatedDeparture,f.DepartureTime)<=DATEADD(hour,24,SYSUTCDATETIME())
 AND NOT EXISTS(SELECT 1 FROM dbo.Notifications n WHERE n.EventKey=CONCAT('reminder:',b.BookingID,':',f.FlightID));
 SELECT @@ROWCOUNT Created;
 COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO

-- dbo.sp_SaveFare
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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

-- dbo.sp_SaveFlight
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_SaveFlight @FlightID int=NULL,@FlightNumber varchar(8),@AircraftID int,@OriginID int,@DestinationID int,@DepartureTime datetime2(0),@ArrivalTime datetime2(0) AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @r int,@PreviousAircraftID int;
  SELECT @PreviousAircraftID=AircraftID FROM dbo.Flights WHERE FlightID=@FlightID;
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
  -- Validate the complete aircraft chain after the proposed insert/update.
  -- Unpriced flights may represent positioning legs and remain outside public search.
  IF EXISTS(SELECT 1 FROM (
   SELECT OriginID,LAG(DestinationID) OVER(PARTITION BY AircraftID ORDER BY DepartureTime,FlightID) PreviousDestination
   FROM dbo.Flights WHERE AircraftID IN (@AircraftID,@PreviousAircraftID) AND Status<>'CANCELLED'
  ) chain WHERE PreviousDestination<>OriginID)
   THROW 51018,N'Lịch máy bay không liên tục giữa các sân bay. Cần bổ sung chặng định vị phù hợp.',1;
  COMMIT;
  SELECT @FlightID FlightID;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO

-- dbo.sp_SetBookingOptions
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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

-- dbo.sp_UpdateFlightStatus
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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

-- dbo.sp_CancelBooking
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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

-- dbo.sp_ConfirmPayment
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
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

-- dbo.sp_CreateItinerary
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_CreateItinerary
 @UserID int,@JourneyType varchar(12),@Segments nvarchar(max),@Passengers nvarchar(max),@Selections nvarchar(max)=N'[]',@ExpectedTotal decimal(14,2)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockFlight 0;
  IF NOT EXISTS(SELECT 1 FROM dbo.Users WHERE UserID=@UserID AND IsActive=1) THROW 51002,N'Tài khoản không hoạt động.',1;
  IF @JourneyType NOT IN ('ONE_WAY','ROUND_TRIP','MULTI_CITY') OR @JourneyType IS NULL THROW 51004,N'Loại hành trình không hợp lệ.',1;
  IF ISJSON(@Segments)<>1 OR ISJSON(@Passengers)<>1 OR ISJSON(@Selections)<>1
   OR LEFT(LTRIM(@Segments),1)<>'[' OR LEFT(LTRIM(@Passengers),1)<>'[' OR LEFT(LTRIM(@Selections),1)<>'['
   THROW 51004,N'Dữ liệu hành trình không hợp lệ.',1;
  DECLARE @s TABLE(N int PRIMARY KEY,FlightID int,GroupID int,FareClassID int,OriginID int,DestinationID int,DepartureTime datetime2(0),ArrivalTime datetime2(0));
  INSERT @s SELECT CONVERT(int,j.[key])+1,x.FlightID,x.JourneyGroup,x.FareClassID,f.OriginID,f.DestinationID,f.DepartureTime,f.ArrivalTime
   FROM OPENJSON(@Segments) j CROSS APPLY OPENJSON(j.value) WITH(FlightID int,JourneyGroup int,FareClassID int) x LEFT JOIN dbo.Flights f ON f.FlightID=x.FlightID;
  DECLARE @count int=(SELECT COUNT(*) FROM @s);
  IF @count NOT BETWEEN 1 AND 12 OR EXISTS(SELECT 1 FROM @s WHERE OriginID IS NULL OR GroupID IS NULL OR FareClassID IS NULL OR GroupID NOT BETWEEN 1 AND 6)
   OR (SELECT COUNT(DISTINCT FlightID) FROM @s)<>@count THROW 51004,N'Cần từ 1 đến 12 chặng bay hợp lệ, không lặp chuyến.',1;
  IF (SELECT GroupID FROM @s WHERE N=1)<>1 OR EXISTS(SELECT 1 FROM @s a JOIN @s b ON b.N=a.N+1 WHERE b.GroupID<a.GroupID OR b.GroupID>a.GroupID+1)
   THROW 51004,N'Thứ tự nhóm hành trình không hợp lệ.',1;
  IF (@JourneyType='ONE_WAY' AND (SELECT MAX(GroupID) FROM @s)<>1) OR (@JourneyType='ROUND_TRIP' AND (SELECT MAX(GroupID) FROM @s)<>2)
   OR (@JourneyType='MULTI_CITY' AND (SELECT MAX(GroupID) FROM @s)<2) THROW 51004,N'Số điểm dừng không khớp loại hành trình.',1;
  IF EXISTS(SELECT 1 FROM @s a JOIN @s b ON b.N=a.N+1 WHERE b.DepartureTime<DATEADD(minute,60,a.ArrivalTime)
   OR (a.GroupID=b.GroupID AND (a.DestinationID<>b.OriginID OR b.DepartureTime>DATEADD(hour,8,a.ArrivalTime))))
   THROW 51004,N'Chặng nối chuyến cần cùng sân bay, thời gian nối từ 60 phút đến 8 giờ. Các chặng phải theo thời gian.',1;
  IF @JourneyType='ROUND_TRIP' AND ((SELECT OriginID FROM @s WHERE N=1)<>(SELECT DestinationID FROM @s WHERE N=@count)
   OR (SELECT TOP(1) DestinationID FROM @s WHERE GroupID=1 ORDER BY N DESC)<>(SELECT TOP(1) OriginID FROM @s WHERE GroupID=2 ORDER BY N))
   THROW 51004,N'Hành trình khứ hồi phải quay về sân bay xuất phát.',1;
  IF EXISTS(SELECT 1 FROM @s s JOIN dbo.Flights f ON f.FlightID=s.FlightID WHERE f.Status<>'SCHEDULED' OR f.DepartureTime<=DATEADD(hour,2,SYSUTCDATETIME()))
   THROW 51003,N'Một chặng đã đóng bán.',1;
  DECLARE @p TABLE(N int PRIMARY KEY,FullName nvarchar(120),DateOfBirth date,DocumentNumber nvarchar(30),TypeCode varchar(8),Assistance varchar(12),BP int);
  INSERT @p(N,FullName,DateOfBirth,DocumentNumber,TypeCode,Assistance)
   SELECT CONVERT(int,j.[key])+1,x.FullName,TRY_CONVERT(date,x.DateOfBirth),x.DocumentNumber,x.TypeCode,COALESCE(x.Assistance,'NONE')
   FROM OPENJSON(@Passengers) j CROSS APPLY OPENJSON(j.value) WITH(FullName nvarchar(120),DateOfBirth nvarchar(20),DocumentNumber nvarchar(30),TypeCode varchar(8),Assistance varchar(12)) x;
  DECLARE @pcount int=(SELECT COUNT(*) FROM @p),@date date=(SELECT dbo.fn_FlightLocalDate(FlightID) FROM @s WHERE N=1);
  IF @pcount NOT BETWEEN 1 AND 9 OR EXISTS(SELECT 1 FROM @p WHERE Assistance NOT IN ('NONE','WHEELCHAIR','HEARING','VISION') OR FullName IS NULL OR LEN(TRIM(FullName))<2 OR DateOfBirth IS NULL OR DateOfBirth<'19000101' OR DateOfBirth>CONVERT(date,SYSUTCDATETIME()) OR DocumentNumber IS NULL OR LEN(TRIM(DocumentNumber))<5)
   OR (SELECT COUNT(DISTINCT DocumentNumber) FROM @p)<>@pcount THROW 51004,N'Thông tin hành khách thiếu, trùng hoặc sai ngày sinh.',1;
  IF EXISTS(SELECT 1 FROM @p WHERE TypeCode IS NULL OR TypeCode<>CASE WHEN DateOfBirth>DATEADD(year,-2,@date) THEN 'INFANT' WHEN DateOfBirth>DATEADD(year,-12,@date) THEN 'CHILD' ELSE 'ADULT' END)
   OR NOT EXISTS(SELECT 1 FROM @p WHERE TypeCode='ADULT')
   OR (SELECT COUNT(*) FROM @p WHERE TypeCode='INFANT')>(SELECT COUNT(*) FROM @p WHERE TypeCode='ADULT')
   THROW 51004,N'Loại hành khách phải khớp tuổi ngày bay; cần người lớn đi cùng, mỗi người lớn tối đa một em bé.',1;
  DECLARE @x TABLE(P int,S int,SeatID int,PRIMARY KEY(P,S));
  INSERT @x SELECT PassengerIndex+1,SegmentIndex+1,SeatID FROM OPENJSON(@Selections) WITH(PassengerIndex int,SegmentIndex int,SeatID int);
  IF EXISTS(SELECT 1 FROM @x WHERE P NOT BETWEEN 1 AND @pcount OR S NOT BETWEEN 1 AND @count OR SeatID<1) THROW 51004,N'Lựa chọn ghế không hợp lệ.',1;
  DECLARE @i int=1,@f int;
  WHILE @i<=@count BEGIN SELECT @f=FlightID FROM @s WHERE N=@i; EXEC dbo.sp_ExpireFlightHolds @f; SET @i+=1; END;
  DECLARE @pnr char(8)=UPPER(LEFT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),8)),@booking int;
  WHILE EXISTS(SELECT 1 FROM dbo.Bookings WHERE PNR=@pnr) SET @pnr=UPPER(LEFT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),8));
  INSERT dbo.Bookings(PNR,UserID,FlightID,ExpiresAt,JourneyType) SELECT @pnr,@UserID,FlightID,DATEADD(minute,10,SYSUTCDATETIME()),@JourneyType FROM @s WHERE N=1;
  SET @booking=SCOPE_IDENTITY();
  INSERT dbo.BookingSegments(BookingID,SegmentOrder,JourneyGroup,FlightID) SELECT @booking,N,GroupID,FlightID FROM @s WHERE N>1;
  DECLARE @j int=1,@passenger int,@bp int;
  WHILE @j<=@pcount
  BEGIN
   INSERT dbo.Passengers(FullName,DateOfBirth,DocumentNumber,Assistance) SELECT TRIM(FullName),DateOfBirth,TRIM(DocumentNumber),Assistance FROM @p WHERE N=@j;
   SET @passenger=SCOPE_IDENTITY();
   INSERT dbo.BookingPassengers(BookingID,PassengerID,FareClassID) SELECT @booking,@passenger,FareClassID FROM @s WHERE N=1;
   SET @bp=SCOPE_IDENTITY(); UPDATE @p SET BP=@bp WHERE N=@j; SET @j+=1;
  END;
  SET @i=1;
  DECLARE @fare int,@aircraft int,@segment int,@seat int,@cabin varchar(12),@assignment int,@factor decimal(5,4),@type varchar(8),@base decimal(14,2),@tax decimal(14,2),@fee decimal(14,2),@refund decimal(5,2);
  WHILE @i<=@count
  BEGIN
   SELECT @f=s.FlightID,@fare=s.FareClassID,@aircraft=f.AircraftID FROM @s s JOIN dbo.Flights f ON f.FlightID=s.FlightID WHERE s.N=@i;
   SELECT @segment=BookingSegmentID FROM dbo.BookingSegments WHERE BookingID=@booking AND SegmentOrder=@i;
   SET @cabin=NULL; SELECT @cabin=c.Cabin,@refund=c.RefundPercent FROM dbo.FareClasses c JOIN dbo.FlightFares ff ON ff.FareClassID=c.FareClassID AND ff.FlightID=@f WHERE c.FareClassID=@fare;
   IF @cabin IS NULL THROW 51004,N'Hạng vé chưa được mở bán cho chặng.',1;
   SET @j=1;
   WHILE @j<=@pcount
   BEGIN
    SELECT @bp=p.BP,@type=p.TypeCode,@factor=t.PriceFactor FROM @p p JOIN dbo.PassengerTypes t ON t.TypeCode=p.TypeCode WHERE p.N=@j;
    SET @seat=NULL; SELECT @seat=SeatID FROM @x WHERE P=@j AND S=@i;
    IF @seat IS NULL
     SELECT TOP(1) @seat=SeatID FROM dbo.AircraftSeats s WHERE AircraftID=@aircraft AND Cabin=@cabin AND IsActive=1
      AND NOT EXISTS(SELECT 1 FROM dbo.FlightSeatAssignments a WHERE a.FlightID=@f AND a.SeatID=s.SeatID AND a.IsActive=1) AND NOT EXISTS(SELECT 1 FROM @x x WHERE x.S=@i AND x.P<>@j AND x.SeatID=s.SeatID) ORDER BY SeatFee,RowNumber,ColumnLetter;
    IF @seat IS NULL THROW 51005,N'Không còn đủ ghế cho tất cả hành khách.',1;
    IF NOT EXISTS(SELECT 1 FROM dbo.AircraftSeats WHERE SeatID=@seat AND AircraftID=@aircraft AND Cabin=@cabin AND IsActive=1) THROW 51004,N'Ghế không thuộc máy bay hoặc khoang đã chọn.',1;
    IF EXISTS(SELECT 1 FROM dbo.FlightSeatAssignments WHERE FlightID=@f AND SeatID=@seat AND IsActive=1) THROW 51005,N'Ghế vừa được người khác giữ.',1;
    SELECT @base=ROUND(BasePrice*@factor,2),@tax=ROUND(ROUND(BasePrice*@factor,2)*TaxRate,2) FROM dbo.FlightFares WHERE FlightID=@f AND FareClassID=@fare;
    SELECT @fee=SeatFee FROM dbo.AircraftSeats WHERE SeatID=@seat;
    INSERT dbo.FlightSeatAssignments(FlightID,SeatID) VALUES(@f,@seat); SET @assignment=SCOPE_IDENTITY();
    INSERT dbo.Tickets(AssignmentID,TicketNumber,BookingPassengerID,BookingSegmentID,FareClassID,PassengerType,BaseFare,TaxAmount,SeatFee,BreakdownSource,Amount,RefundPercent)
     VALUES(@assignment,CONCAT('AF',RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),16)),@bp,@segment,@fare,@type,@base,@tax,@fee,'DETAILED',@base+@tax+@fee,@refund);
    SET @j+=1;
   END;
   SET @i+=1;
  END;
  DECLARE @total decimal(14,2)=(SELECT SUM(t.Amount) FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID WHERE bp.BookingID=@booking);
  IF @ExpectedTotal IS NOT NULL AND @ExpectedTotal<>@total THROW 51013,N'Giá hoặc ghế đã thay đổi. Vui lòng kiểm tra lại báo giá.',1;
  COMMIT;
  SELECT * FROM dbo.vw_BookingDetails WHERE BookingID=@booking;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO

-- dbo.sp_ExchangeSegment
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
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
 IF EXISTS(SELECT 1 FROM dbo.BookingPassengers bp JOIN dbo.Passengers p ON p.PassengerID=bp.PassengerID WHERE bp.BookingPassengerID=@bp AND @type<>CASE WHEN p.DateOfBirth>DATEADD(year,-2,dbo.fn_FlightLocalDate(@NewFlightID)) THEN 'INFANT' WHEN p.DateOfBirth>DATEADD(year,-12,dbo.fn_FlightLocalDate(@NewFlightID)) THEN 'CHILD' ELSE 'ADULT' END) THROW 51017,N'Độ tuổi thay đổi: cần tạo hành trình mới.',1;
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
GO

-- dbo.sp_GetAvailableSeats
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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

-- dbo.sp_CreateBooking
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_CreateBooking @UserID int,@FlightID int,@Passengers nvarchar(max) AS
BEGIN
 SET NOCOUNT ON;
 IF ISJSON(@Passengers)<>1 OR LEFT(LTRIM(@Passengers),1)<>'[' THROW 51004,N'Danh sách hành khách không hợp lệ.',1;
 DECLARE @segments nvarchar(max),@people nvarchar(max),@choices nvarchar(max),@fare int,@day date=(SELECT dbo.fn_FlightLocalDate(FlightID) FROM dbo.Flights WHERE FlightID=@FlightID);
 SELECT TOP(1) @fare=FareClassID FROM OPENJSON(@Passengers) WITH(FareClassID int);
 -- Legacy API has one common cabin/fare. Mixed fares are rejected instead of silently repriced.
 IF EXISTS(SELECT 1 FROM OPENJSON(@Passengers) WITH(FareClassID int) WHERE FareClassID<>@fare OR FareClassID IS NULL) THROW 51004,N'Luồng một chặng cần cùng hạng vé.',1;
 SET @segments=(SELECT @FlightID FlightID,@fare FareClassID,1 JourneyGroup FOR JSON PATH);
 SET @people=(SELECT x.FullName,x.DateOfBirth,x.DocumentNumber,CASE WHEN TRY_CONVERT(date,x.DateOfBirth)>DATEADD(year,-2,@day) THEN 'INFANT' WHEN TRY_CONVERT(date,x.DateOfBirth)>DATEADD(year,-12,@day) THEN 'CHILD' ELSE 'ADULT' END TypeCode FROM OPENJSON(@Passengers) j CROSS APPLY OPENJSON(j.value) WITH(FullName nvarchar(120),DateOfBirth nvarchar(20),DocumentNumber nvarchar(30)) x ORDER BY CONVERT(int,j.[key]) FOR JSON PATH);
 SET @choices=(SELECT CONVERT(int,j.[key]) PassengerIndex,0 SegmentIndex,x.SeatID FROM OPENJSON(@Passengers) j CROSS APPLY OPENJSON(j.value) WITH(SeatID int) x ORDER BY CONVERT(int,j.[key]) FOR JSON PATH);
 EXEC dbo.sp_CreateItinerary @UserID,'ONE_WAY',@segments,@people,@choices;
END;
GO
