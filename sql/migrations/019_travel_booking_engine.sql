-- All stock writers take a transaction-owned product lock before reading capacity.
CREATE OR ALTER PROCEDURE dbo.sp_TravelLock @ProductID int AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @r int,@resource nvarchar(255)=CONCAT(N'AeroFlow:travel:product:',@ProductID);
 EXEC @r=sys.sp_getapplock @Resource=@resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @r<0 THROW 52001,N'Travel stock is busy.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_TravelQuote
 @PackageID int,@StartDate date,@EndDate date,@SlotCode varchar(20),@Quantity int,@GuestCount int,
 @VoucherCode varchar(40)=NULL,@UserID int=NULL,@Result nvarchar(max) OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @product int,@unit varchar(12),@max int,@category varchar(20),@days int,@subtotal decimal(14,2),@discount decimal(14,2)=0,
 @coupon int=NULL,@kind varchar(8),@amount decimal(14,2),@cap decimal(14,2),@min decimal(14,2),@limit int,@per int;
 SELECT @product=p.ProductID,@unit=k.UnitCode,@max=k.MaxGuests,@category=p.CategoryCode
 FROM dbo.TravelPackages k JOIN dbo.TravelProducts p ON p.ProductID=k.ProductID JOIN dbo.TravelProviders pr ON pr.ProviderID=p.ProviderID
 WHERE k.PackageID=@PackageID AND k.IsActive=1 AND p.IsPublished=1 AND pr.Status='ACTIVE';
 IF @product IS NULL THROW 52002,N'Package unavailable.',1;
 IF @Quantity NOT BETWEEN 1 AND 99 OR @GuestCount NOT BETWEEN 1 AND @Quantity*@max OR @StartDate IS NULL OR @EndDate IS NULL
  OR @EndDate<@StartDate OR DATEDIFF(day,@StartDate,@EndDate)>30 OR (@unit IN ('NIGHT','DAY') AND @EndDate=@StartDate)
  OR (@unit NOT IN ('NIGHT','DAY') AND @EndDate<>@StartDate) THROW 52003,N'Invalid dates or quantity.',1;
 SET @days=CASE WHEN @unit IN ('NIGHT','DAY') THEN DATEDIFF(day,@StartDate,@EndDate) ELSE 1 END;
 DECLARE @lines TABLE(InventoryID int,ServiceDate date,SlotCode varchar(20),StartsAt datetime2(0),EndsAt datetime2(0),UnitPrice decimal(14,2),AvailableQuantity int);
 INSERT @lines SELECT InventoryID,ServiceDate,SlotCode,StartsAt,EndsAt,UnitPrice,AvailableQuantity
 FROM dbo.vw_TravelAvailability WHERE PackageID=@PackageID AND SlotCode=@SlotCode AND IsClosed=0 AND StartsAt>SYSUTCDATETIME()
 AND ServiceDate>=@StartDate AND ServiceDate<CASE WHEN @unit IN ('NIGHT','DAY') THEN @EndDate ELSE DATEADD(day,1,@StartDate) END;
 IF (SELECT COUNT(*) FROM @lines)<>@days OR EXISTS(SELECT 1 FROM @lines WHERE AvailableQuantity<@Quantity)
  THROW 52004,N'Insufficient inventory for every selected date.',1;
 SELECT @subtotal=SUM(UnitPrice*@Quantity) FROM @lines;
 IF NULLIF(@VoucherCode,'') IS NOT NULL
 BEGIN
  SELECT @coupon=CouponID,@kind=Kind,@amount=Amount,@cap=MaxDiscount,@min=MinSubtotal,@limit=UsageLimit,@per=PerUserLimit
  FROM dbo.TravelCoupons WHERE Code=@VoucherCode AND IsActive=1 AND SYSUTCDATETIME() BETWEEN ValidFrom AND ValidUntil AND (CategoryCode IS NULL OR CategoryCode=@category);
  IF @coupon IS NULL OR @subtotal<@min THROW 52005,N'Invalid coupon.',1;
  -- A successful charge consumes the coupon even if later refunded. Only live holds reserve it temporarily.
  IF (SELECT COUNT(*) FROM dbo.TravelCouponReservations cr JOIN dbo.TravelBookings b ON b.BookingID=cr.BookingID WHERE cr.CouponID=@coupon
    AND (EXISTS(SELECT 1 FROM dbo.TravelPayments py WHERE py.BookingID=b.BookingID AND py.Kind='CHARGE' AND py.Status='SUCCESS') OR (b.Status='HELD' AND b.ExpiresAt>SYSUTCDATETIME())))>=@limit
   OR (@UserID IS NOT NULL AND (SELECT COUNT(*) FROM dbo.TravelCouponReservations cr JOIN dbo.TravelBookings b ON b.BookingID=cr.BookingID WHERE cr.CouponID=@coupon AND b.UserID=@UserID
    AND (EXISTS(SELECT 1 FROM dbo.TravelPayments py WHERE py.BookingID=b.BookingID AND py.Kind='CHARGE' AND py.Status='SUCCESS') OR (b.Status='HELD' AND b.ExpiresAt>SYSUTCDATETIME())))>=@per)
   THROW 52005,N'Coupon quota exhausted.',1;
  SET @discount=CASE WHEN @kind='PERCENT' THEN ROUND(@subtotal*@amount/100,0) ELSE @amount END;
  IF @cap IS NOT NULL AND @discount>@cap SET @discount=@cap;
  IF @discount>@subtotal SET @discount=@subtotal;
 END;
 SELECT @Result=(SELECT @product ProductID,@PackageID PackageID,@StartDate StartDate,@EndDate EndDate,@SlotCode SlotCode,@Quantity Quantity,@GuestCount GuestCount,
  @subtotal Subtotal,@discount DiscountAmount,@subtotal-@discount Total,'VND' Currency,@coupon CouponID,@days Units,
  (SELECT MIN(AvailableQuantity) FROM @lines) AvailableQuantity,(SELECT MIN(StartsAt) FROM @lines) ServiceStartsAt,(SELECT MAX(EndsAt) FROM @lines) ServiceEndsAt,
  k.UnitLabel,k.RefundPercent,k.CancelCutoffHours,k.ChangeAllowed,k.ChangeFee,
  JSON_QUERY((SELECT * FROM @lines ORDER BY ServiceDate FOR JSON PATH)) Lines
  FROM dbo.TravelPackages k WHERE k.PackageID=@PackageID FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_TravelCreateBooking
 @UserID int,@PackageID int,@StartDate date,@EndDate date,@SlotCode varchar(20),@Quantity int,@GuestCount int,
 @VoucherCode varchar(40),@ContactName nvarchar(120),@ContactEmail nvarchar(254),@ContactPhone varchar(24),@Notes nvarchar(1000),
 @IdempotencyKey varchar(80),@RequestHash char(64),@ExpectedTotal decimal(14,2)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 IF NOT EXISTS(SELECT 1 FROM dbo.Users WHERE UserID=@UserID AND IsActive=1) THROW 52006,N'Inactive account.',1;
 DECLARE @product int=(SELECT ProductID FROM dbo.TravelPackages WHERE PackageID=@PackageID),@result nvarchar(max),@id int,@resource nvarchar(255),@r int;
 SET @resource=CONCAT(N'AeroFlow:travel:request:',@UserID,':',@IdempotencyKey);
 EXEC @r=sys.sp_getapplock @Resource=@resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @r<0 THROW 52001,N'Request busy.',1;
 SELECT @id=BookingID FROM dbo.TravelBookings WHERE UserID=@UserID AND IdempotencyKey=@IdempotencyKey;
 IF @id IS NOT NULL
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM dbo.TravelBookings WHERE BookingID=@id AND RequestHash=@RequestHash) THROW 52007,N'Idempotency conflict.',1;
  COMMIT; SELECT * FROM dbo.TravelBookings WHERE BookingID=@id; RETURN;
 END;
 EXEC dbo.sp_TravelLock @product;
 UPDATE dbo.TravelBookings SET Status='EXPIRED' WHERE ProductID=@product AND Status='HELD' AND ExpiresAt<=SYSUTCDATETIME();
 IF NULLIF(@VoucherCode,'') IS NOT NULL
 BEGIN
  SET @resource=CONCAT(N'AeroFlow:travel:coupon:',@VoucherCode);
  EXEC @r=sys.sp_getapplock @Resource=@resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @r<0 THROW 52001,N'Coupon busy.',1;
 END;
 EXEC dbo.sp_TravelQuote @PackageID,@StartDate,@EndDate,@SlotCode,@Quantity,@GuestCount,@VoucherCode,@UserID,@result OUTPUT;
 IF @ExpectedTotal IS NULL OR @ExpectedTotal<>CONVERT(decimal(14,2),JSON_VALUE(@result,'$.Total')) THROW 52008,N'Price changed.',1;
 IF LEN(TRIM(@ContactName))<2 OR LEN(TRIM(@ContactEmail))<5 OR LEN(@ContactPhone)<6 THROW 52003,N'Invalid contact.',1;
 INSERT dbo.TravelBookings(Reference,UserID,ProductID,PackageID,StartDate,EndDate,SlotCode,Quantity,GuestCount,ServiceStartsAt,ServiceEndsAt,
 ProductTitle,PackageName,UnitLabel,Subtotal,DiscountAmount,Total,RefundPercent,CancelCutoffHours,ChangeAllowed,ChangeFee,ContactName,ContactEmail,ContactPhone,Notes,ExpiresAt,IdempotencyKey,RequestHash)
 SELECT UPPER(LEFT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12)),@UserID,@product,@PackageID,@StartDate,@EndDate,@SlotCode,@Quantity,@GuestCount,
 JSON_VALUE(@result,'$.ServiceStartsAt'),JSON_VALUE(@result,'$.ServiceEndsAt'),p.Title,k.Name,k.UnitLabel,
 JSON_VALUE(@result,'$.Subtotal'),JSON_VALUE(@result,'$.DiscountAmount'),@ExpectedTotal,k.RefundPercent,k.CancelCutoffHours,k.ChangeAllowed,k.ChangeFee,
 @ContactName,@ContactEmail,@ContactPhone,@Notes,DATEADD(minute,10,SYSUTCDATETIME()),@IdempotencyKey,@RequestHash
 FROM dbo.TravelPackages k JOIN dbo.TravelProducts p ON p.ProductID=k.ProductID WHERE k.PackageID=@PackageID;
 SET @id=SCOPE_IDENTITY();
 INSERT dbo.TravelBookingItems(BookingID,PackageID,InventoryID,Quantity,UnitPrice)
 SELECT @id,@PackageID,InventoryID,@Quantity,UnitPrice FROM OPENJSON(@result,'$.Lines') WITH(InventoryID int,UnitPrice decimal(14,2));
 IF JSON_VALUE(@result,'$.CouponID') IS NOT NULL INSERT dbo.TravelCouponReservations VALUES(@id,JSON_VALUE(@result,'$.CouponID'),JSON_VALUE(@result,'$.DiscountAmount'));
 INSERT dbo.TravelAuditLog(ActorID,Entity,EntityID,Action) VALUES(@UserID,'BOOKING',@id,'HOLD');
 COMMIT; SELECT * FROM dbo.TravelBookings WHERE BookingID=@id;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_TravelPay @UserID int,@BookingID int,@IdempotencyKey varchar(80),@Success bit,@ExpectedAmount decimal(14,2) AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 DECLARE @product int,@status varchar(12),@expires datetime2(0),@total decimal(14,2),@r int,@res nvarchar(255)=CONCAT(N'AeroFlow:travel:payment:',@IdempotencyKey);
 SELECT @product=ProductID FROM dbo.TravelBookings WHERE BookingID=@BookingID AND UserID=@UserID;
 IF @product IS NULL THROW 52009,N'Booking not found.',1;
 EXEC dbo.sp_TravelLock @product;
 EXEC @r=sys.sp_getapplock @Resource=@res,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @r<0 THROW 52001,N'Payment busy.',1;
 IF EXISTS(SELECT 1 FROM dbo.TravelPayments WHERE IdempotencyKey=@IdempotencyKey)
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM dbo.TravelPayments WHERE IdempotencyKey=@IdempotencyKey AND BookingID=@BookingID AND Kind='CHARGE' AND Amount=@ExpectedAmount AND Status=CASE WHEN @Success=1 THEN 'SUCCESS' ELSE 'FAILED' END) THROW 52007,N'Payment key conflict.',1;
  COMMIT; SELECT * FROM dbo.TravelPayments WHERE IdempotencyKey=@IdempotencyKey; RETURN;
 END;
 SELECT @status=Status,@expires=ExpiresAt,@total=Total FROM dbo.TravelBookings WHERE BookingID=@BookingID;
 IF @status<>'HELD' OR @expires<=SYSUTCDATETIME() THROW 52010,N'Hold expired or booking no longer payable.',1;
 IF @ExpectedAmount<>@total OR @ExpectedAmount IS NULL THROW 52008,N'Amount changed.',1;
 INSERT dbo.TravelPayments(BookingID,Kind,Status,Amount,IdempotencyKey) VALUES(@BookingID,'CHARGE',CASE WHEN @Success=1 THEN 'SUCCESS' ELSE 'FAILED' END,@total,@IdempotencyKey);
 IF @Success=1
 BEGIN
  UPDATE dbo.TravelBookings SET Status='CONFIRMED' WHERE BookingID=@BookingID;
  INSERT dbo.TravelVouchers(BookingID,Code) VALUES(@BookingID,UPPER(REPLACE(CONVERT(varchar(36),NEWID()),'-','')));
 END;
 INSERT dbo.TravelAuditLog(ActorID,Entity,EntityID,Action,Details) VALUES(@UserID,'BOOKING',@BookingID,'PAYMENT',CASE WHEN @Success=1 THEN N'SUCCESS' ELSE N'FAILED' END);
 COMMIT; SELECT * FROM dbo.TravelPayments WHERE IdempotencyKey=@IdempotencyKey;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_TravelCancel @UserID int,@BookingID int,@IdempotencyKey varchar(80) AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 DECLARE @product int,@status varchar(12),@start datetime2(0),@cutoff int,@refund decimal(14,2),@r int,@res nvarchar(255)=CONCAT(N'AeroFlow:travel:payment:',@IdempotencyKey);
 SELECT @product=ProductID FROM dbo.TravelBookings WHERE BookingID=@BookingID AND UserID=@UserID;
 IF @product IS NULL THROW 52009,N'Booking not found.',1;
 EXEC dbo.sp_TravelLock @product;
 EXEC @r=sys.sp_getapplock @Resource=@res,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @r<0 THROW 52001,N'Refund busy.',1;
 IF EXISTS(SELECT 1 FROM dbo.TravelPayments WHERE IdempotencyKey=@IdempotencyKey AND (BookingID<>@BookingID OR Kind<>'REFUND')) THROW 52007,N'Refund key conflict.',1;
 SELECT @status=Status,@start=ServiceStartsAt,@cutoff=CancelCutoffHours,@refund=ROUND(Total*RefundPercent/100,0) FROM dbo.TravelBookings WHERE BookingID=@BookingID;
 IF @status='CANCELLED' BEGIN COMMIT; SELECT * FROM dbo.TravelBookings WHERE BookingID=@BookingID; RETURN; END;
 IF @status NOT IN ('HELD','CONFIRMED') THROW 52010,N'Booking not cancellable.',1;
 IF @status='CONFIRMED' AND (DATEADD(hour,-@cutoff,@start)<=SYSUTCDATETIME() OR EXISTS(SELECT 1 FROM dbo.TravelVouchers WHERE BookingID=@BookingID AND Status='REDEEMED')) THROW 52011,N'Cancellation deadline passed or voucher used.',1;
 IF @status='CONFIRMED' INSERT dbo.TravelPayments(BookingID,Kind,Status,Amount,IdempotencyKey) VALUES(@BookingID,'REFUND','SUCCESS',@refund,@IdempotencyKey);
 UPDATE dbo.TravelBookings SET Status='CANCELLED',CancelledAt=SYSUTCDATETIME() WHERE BookingID=@BookingID;
 UPDATE dbo.TravelVouchers SET Status='VOID' WHERE BookingID=@BookingID;
 INSERT dbo.TravelAuditLog(ActorID,Entity,EntityID,Action) VALUES(@UserID,'BOOKING',@BookingID,'CANCEL');
 COMMIT; SELECT * FROM dbo.TravelBookings WHERE BookingID=@BookingID;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
-- Protect pooled inventory even when it is modified through SSMS instead of the API.
CREATE OR ALTER TRIGGER dbo.tr_TravelItems_Capacity ON dbo.TravelBookingItems AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @p int;
 DECLARE locks CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT b.ProductID FROM dbo.TravelBookings b JOIN(SELECT BookingID FROM inserted UNION SELECT BookingID FROM deleted) x ON x.BookingID=b.BookingID ORDER BY b.ProductID;
 OPEN locks; FETCH NEXT FROM locks INTO @p;
 WHILE @@FETCH_STATUS=0 BEGIN EXEC dbo.sp_TravelLock @p; FETCH NEXT FROM locks INTO @p; END;
 CLOSE locks; DEALLOCATE locks;
 IF EXISTS(SELECT 1 FROM inserted x JOIN dbo.TravelBookings b ON b.BookingID=x.BookingID JOIN dbo.TravelInventory i ON i.InventoryID=x.InventoryID
 WHERE x.Quantity<>b.Quantity OR i.ServiceDate<b.StartDate OR i.ServiceDate>CASE WHEN b.EndDate=b.StartDate THEN b.StartDate ELSE DATEADD(day,-1,b.EndDate) END)
 THROW 52003,N'Inventory does not match booking.',1;
 IF EXISTS(SELECT 1 FROM dbo.vw_TravelAvailability a JOIN(SELECT InventoryID FROM inserted UNION SELECT InventoryID FROM deleted) x ON x.InventoryID=a.InventoryID WHERE a.AvailableQuantity<0)
 THROW 52004,N'Inventory capacity exceeded.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_TravelBooking_State ON dbo.TravelBookings AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @p int;
 DECLARE locks CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT ProductID FROM inserted ORDER BY ProductID;
 OPEN locks; FETCH NEXT FROM locks INTO @p;
 WHILE @@FETCH_STATUS=0 BEGIN EXEC dbo.sp_TravelLock @p; FETCH NEXT FROM locks INTO @p; END;
 CLOSE locks; DEALLOCATE locks;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.BookingID=i.BookingID WHERE
 (d.Status IN ('CANCELLED','EXPIRED') AND i.Status<>d.Status) OR (d.Status='CONFIRMED' AND i.Status NOT IN ('CONFIRMED','CANCELLED')))
 THROW 52010,N'Invalid booking transition.',1;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.BookingID=i.BookingID WHERE d.Status<>i.Status AND i.Status='CONFIRMED' AND
 (NOT EXISTS(SELECT 1 FROM dbo.TravelPayments p WHERE p.BookingID=i.BookingID AND p.Kind='CHARGE' AND p.Status='SUCCESS' AND p.Amount=i.Total)
 OR i.ExpiresAt<=SYSUTCDATETIME() OR (SELECT COUNT(*) FROM dbo.TravelBookingItems bi WHERE bi.BookingID=i.BookingID)<>CASE WHEN i.StartDate=i.EndDate THEN 1 ELSE DATEDIFF(day,i.StartDate,i.EndDate) END))
 THROW 52010,N'Confirmation requires valid stock and payment.',1;
 IF EXISTS(SELECT 1 FROM dbo.vw_TravelAvailability a JOIN inserted i ON i.ProductID=a.ProductID WHERE a.AvailableQuantity<0) THROW 52004,N'Inventory capacity exceeded.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_TravelInventory_Capacity ON dbo.TravelInventory AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @p int;
 DECLARE locks CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT pk.ProductID FROM inserted i JOIN dbo.TravelPackages pk ON pk.PackageID=i.PackageID ORDER BY pk.ProductID;
 OPEN locks; FETCH NEXT FROM locks INTO @p;
 WHILE @@FETCH_STATUS=0 BEGIN EXEC dbo.sp_TravelLock @p; FETCH NEXT FROM locks INTO @p; END;
 CLOSE locks; DEALLOCATE locks;
 IF EXISTS(SELECT 1 FROM dbo.vw_TravelAvailability a JOIN inserted i ON i.InventoryID=a.InventoryID WHERE a.AvailableQuantity<0) THROW 52004,N'Capacity below active bookings.',1;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.InventoryID=i.InventoryID WHERE
 (i.PackageID<>d.PackageID OR i.ServiceDate<>d.ServiceDate OR i.SlotCode<>d.SlotCode OR i.StartsAt<>d.StartsAt OR i.EndsAt<>d.EndsAt)
 AND EXISTS(SELECT 1 FROM dbo.TravelBookingItems bi WHERE bi.InventoryID=i.InventoryID)) THROW 52012,N'Used inventory schedule is immutable.',1;
END;
