CREATE TABLE dbo.Services(
 ServiceID int IDENTITY CONSTRAINT PK_Services PRIMARY KEY,Code varchar(20) NOT NULL CONSTRAINT UQ_ServiceCode UNIQUE,
 Name nvarchar(100) NOT NULL,Category varchar(12) NOT NULL CHECK(Category IN ('BAGGAGE','MEAL','PRIORITY','LOUNGE')),
 UnitPrice decimal(14,2) NOT NULL CHECK(UnitPrice BETWEEN 0 AND 10000000),MaxQuantity int NOT NULL DEFAULT 1 CHECK(MaxQuantity BETWEEN 1 AND 5),
 RefundPercent decimal(5,2) NOT NULL DEFAULT 0 CHECK(RefundPercent BETWEEN 0 AND 100),IsActive bit NOT NULL DEFAULT 1);
INSERT dbo.Services(Code,Name,Category,UnitPrice,MaxQuantity,RefundPercent) VALUES
 ('BAG10',N'Thêm 10 kg hành lý ký gửi','BAGGAGE',250000,3,80),('MEAL',N'Suất ăn tiêu chuẩn','MEAL',120000,1,0),
 ('VEGMEAL',N'Suất ăn chay','MEAL',120000,1,0),('PRIORITY',N'Ưu tiên lên máy bay','PRIORITY',150000,1,100),('LOUNGE',N'Phòng chờ mô phỏng','LOUNGE',400000,1,100);
CREATE TABLE dbo.DiscountCodes(
 DiscountCodeID int IDENTITY CONSTRAINT PK_DiscountCodes PRIMARY KEY,Code varchar(30) NOT NULL CONSTRAINT UQ_DiscountCode UNIQUE,
 Kind varchar(8) NOT NULL CHECK(Kind IN ('PROMO','VOUCHER')),Method varchar(8) NOT NULL CHECK(Method IN ('PERCENT','FIXED')),
 Value decimal(14,2) NOT NULL CHECK(Value>0),MaxDiscount decimal(14,2) NOT NULL CHECK(MaxDiscount>0),MinimumSpend decimal(14,2) NOT NULL DEFAULT 0 CHECK(MinimumSpend>=0),
 ValidFrom datetime2(0) NOT NULL,ValidTo datetime2(0) NOT NULL,MaxUses int NOT NULL CHECK(MaxUses>0),IsActive bit NOT NULL DEFAULT 1,
 CONSTRAINT CK_DiscountTerms CHECK(ValidTo>ValidFrom AND (Method<>'PERCENT' OR Value<=50)));
INSERT dbo.DiscountCodes(Code,Kind,Method,Value,MaxDiscount,MinimumSpend,ValidFrom,ValidTo,MaxUses) VALUES
 ('ULTIMATE10','PROMO','PERCENT',10,200000,1000000,SYSUTCDATETIME(),DATEADD(year,1,SYSUTCDATETIME()),10000),
 ('DEMO100K','VOUCHER','FIXED',100000,100000,500000,SYSUTCDATETIME(),DATEADD(year,1,SYSUTCDATETIME()),10000);
CREATE TABLE dbo.BookingExtras(
 TicketID int NOT NULL REFERENCES dbo.Tickets,ServiceID int NOT NULL REFERENCES dbo.Services,
 ServiceName nvarchar(100) NOT NULL,Quantity int NOT NULL CHECK(Quantity BETWEEN 1 AND 5),UnitPrice decimal(14,2) NOT NULL CHECK(UnitPrice>=0),RefundPercent decimal(5,2) NOT NULL CHECK(RefundPercent BETWEEN 0 AND 100),
 CONSTRAINT PK_BookingExtras PRIMARY KEY(TicketID,ServiceID));
CREATE TABLE dbo.BookingDiscounts(
 BookingID int CONSTRAINT PK_BookingDiscounts PRIMARY KEY REFERENCES dbo.Bookings,
 DiscountCodeID int NOT NULL REFERENCES dbo.DiscountCodes,Code varchar(30) NOT NULL,Amount decimal(14,2) NOT NULL CHECK(Amount>=0));
CREATE INDEX IX_BookingDiscount_Code ON dbo.BookingDiscounts(DiscountCodeID,BookingID);
CREATE TABLE dbo.TicketDiscounts(TicketID int CONSTRAINT PK_TicketDiscounts PRIMARY KEY REFERENCES dbo.Tickets,Amount decimal(14,2) NOT NULL CHECK(Amount>=0));
CREATE TABLE dbo.TicketRefunds(
 TicketID int CONSTRAINT PK_TicketRefunds PRIMARY KEY REFERENCES dbo.Tickets,PaymentID int NOT NULL REFERENCES dbo.Payments,
 Amount decimal(14,2) NOT NULL CHECK(Amount>=0),CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME());
-- Multiple refunds are now supported; idempotency keys plus transaction locks still enforce exactly-once effects.
DROP INDEX UX_Payments_Refund ON dbo.Payments;
GO
CREATE OR ALTER FUNCTION dbo.fn_TicketPaidValue(@TicketID int) RETURNS decimal(14,2) AS
BEGIN
 DECLARE @amount decimal(14,2);
 SELECT @amount=t.Amount+COALESCE((SELECT SUM(e.Quantity*e.UnitPrice) FROM dbo.BookingExtras e WHERE e.TicketID=t.TicketID),0)-COALESCE(d.Amount,0)
 FROM dbo.Tickets t LEFT JOIN dbo.TicketDiscounts d ON d.TicketID=t.TicketID WHERE t.TicketID=@TicketID;
 RETURN @amount;
END;
GO
CREATE OR ALTER FUNCTION dbo.fn_TicketRefundValue(@TicketID int) RETURNS decimal(14,2) AS
BEGIN
 DECLARE @refund decimal(14,2);
 SELECT @refund=ROUND((t.Amount*t.RefundPercent/100+COALESCE(e.Refundable,0))*(t.Amount+COALESCE(e.Total,0)-COALESCE(d.Amount,0))/(t.Amount+COALESCE(e.Total,0)),2)
 FROM dbo.Tickets t LEFT JOIN dbo.TicketDiscounts d ON d.TicketID=t.TicketID
 OUTER APPLY(SELECT SUM(Quantity*UnitPrice) Total,SUM(Quantity*UnitPrice*RefundPercent/100) Refundable FROM dbo.BookingExtras WHERE TicketID=t.TicketID) e WHERE t.TicketID=@TicketID;
 RETURN @refund;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_SetBookingOptions @UserID int,@BookingID int,@Extras nvarchar(max)=N'[]',@Code varchar(30)=NULL AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 EXEC dbo.sp_LockFlight 0;
 IF NOT EXISTS(SELECT 1 FROM dbo.Bookings WHERE BookingID=@BookingID AND UserID=@UserID) THROW 51006,N'Không tìm thấy đặt chỗ.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Bookings WHERE BookingID=@BookingID AND Status='HELD' AND ExpiresAt>SYSUTCDATETIME()) THROW 51008,N'Chỉ sửa dịch vụ khi còn giữ ghế.',1;
 IF ISJSON(@Extras)<>1 OR LEFT(LTRIM(@Extras),1)<>'[' THROW 51004,N'Danh sách dịch vụ không hợp lệ.',1;
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
CREATE OR ALTER PROCEDURE dbo.sp_CancelTicket @UserID int,@TicketID int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 EXEC dbo.sp_LockFlight 0;
 DECLARE @booking int,@status varchar(12),@bookingStatus varchar(12),@departure datetime2(0),@flightStatus varchar(12),@refund decimal(14,2),@payment int;
 SELECT @booking=b.BookingID,@status=t.Status,@bookingStatus=b.Status,@departure=f.DepartureTime,@flightStatus=f.Status
 FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Bookings b ON b.BookingID=bp.BookingID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID JOIN dbo.Flights f ON f.FlightID=a.FlightID WHERE t.TicketID=@TicketID AND b.UserID=@UserID;
 IF @booking IS NULL THROW 51006,N'Không tìm thấy vé.',1;
 IF EXISTS(SELECT 1 FROM dbo.TicketRefunds WHERE TicketID=@TicketID) BEGIN COMMIT; SELECT * FROM dbo.TicketRefunds WHERE TicketID=@TicketID; RETURN; END;
 IF @status<>'VALID' OR @bookingStatus<>'CONFIRMED' THROW 51010,N'Chỉ hủy riêng vé đã thanh toán còn hiệu lực.',1;
 IF @departure<=DATEADD(hour,24,SYSUTCDATETIME()) OR @flightStatus<>'SCHEDULED' OR EXISTS(SELECT 1 FROM dbo.CheckIns WHERE TicketID=@TicketID AND Status='ACTIVE') THROW 51009,N'Chỉ hủy vé trước giờ bay ít nhất 24 giờ.',1;
 SET @refund=dbo.fn_TicketRefundValue(@TicketID);
 INSERT dbo.Payments(BookingID,IdempotencyKey,Amount,Kind,Status) VALUES(@booking,CONCAT('refund-ticket-',@TicketID),@refund,'REFUND','SUCCESS'); SET @payment=SCOPE_IDENTITY();
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
