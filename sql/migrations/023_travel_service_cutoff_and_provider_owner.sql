-- Keep historical confirmations unchanged. Resolve duplicate ownership explicitly before upgrading.
-- The migration runner wraps all GO batches below in one transaction.
IF EXISTS(SELECT OwnerUserID FROM dbo.TravelProviders WHERE OwnerUserID IS NOT NULL GROUP BY OwnerUserID HAVING COUNT(*)>1)
 THROW 52013,N'Duplicate TravelProviders.OwnerUserID exists. Review the affected provider records and their products before retrying migration 023; no records have been removed or reassigned.',1;
CREATE UNIQUE INDEX UX_TravelProvider_Owner ON dbo.TravelProviders(OwnerUserID) WHERE OwnerUserID IS NOT NULL;
GO
-- Only open holds are normalized; receipts, payments and paid booking snapshots are preserved.
UPDATE dbo.TravelBookings
SET ExpiresAt=CASE WHEN ExpiresAt>ServiceStartsAt THEN ServiceStartsAt ELSE ExpiresAt END,
 Status=CASE WHEN ExpiresAt<=SYSUTCDATETIME() OR ServiceStartsAt<=SYSUTCDATETIME() THEN 'EXPIRED' ELSE 'HELD' END
WHERE Status='HELD' AND (ExpiresAt>ServiceStartsAt OR ExpiresAt<=SYSUTCDATETIME() OR ServiceStartsAt<=SYSUTCDATETIME());
ALTER TABLE dbo.TravelBookings WITH CHECK ADD CONSTRAINT CK_TravelBooking_ServiceHold
 CHECK(Status<>'HELD' OR ExpiresAt<=ServiceStartsAt);
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
 DECLARE @created datetime2(0)=SYSUTCDATETIME(),@serviceStart datetime2(0)=CONVERT(datetime2(0),JSON_VALUE(@result,'$.ServiceStartsAt')),@holdUntil datetime2(0);
 IF @serviceStart<=@created OR @serviceStart<=SYSUTCDATETIME() THROW 52010,N'The service has already started.',1;
 SET @holdUntil=CASE WHEN DATEADD(minute,10,@created)<@serviceStart THEN DATEADD(minute,10,@created) ELSE @serviceStart END;
 INSERT dbo.TravelBookings(Reference,UserID,ProductID,PackageID,StartDate,EndDate,SlotCode,Quantity,GuestCount,ServiceStartsAt,ServiceEndsAt,
 ProductTitle,PackageName,UnitLabel,Subtotal,DiscountAmount,Total,RefundPercent,CancelCutoffHours,ChangeAllowed,ChangeFee,ContactName,ContactEmail,ContactPhone,Notes,CreatedAt,ExpiresAt,IdempotencyKey,RequestHash)
 SELECT UPPER(LEFT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12)),@UserID,@product,@PackageID,@StartDate,@EndDate,@SlotCode,@Quantity,@GuestCount,
 JSON_VALUE(@result,'$.ServiceStartsAt'),JSON_VALUE(@result,'$.ServiceEndsAt'),p.Title,k.Name,k.UnitLabel,
 JSON_VALUE(@result,'$.Subtotal'),JSON_VALUE(@result,'$.DiscountAmount'),@ExpectedTotal,k.RefundPercent,k.CancelCutoffHours,k.ChangeAllowed,k.ChangeFee,
 @ContactName,@ContactEmail,@ContactPhone,@Notes,@created,@holdUntil,@IdempotencyKey,@RequestHash
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
 DECLARE @product int,@status varchar(12),@expires datetime2(0),@starts datetime2(0),@total decimal(14,2),@r int,@res nvarchar(255)=CONCAT(N'AeroFlow:travel:payment:',@IdempotencyKey);
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
 SELECT @status=Status,@expires=ExpiresAt,@starts=ServiceStartsAt,@total=Total FROM dbo.TravelBookings WHERE BookingID=@BookingID;
 IF @status<>'HELD' OR @expires<=SYSUTCDATETIME() OR @starts<=SYSUTCDATETIME() THROW 52010,N'Hold expired or service already started.',1;
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
 OR i.ExpiresAt<=SYSUTCDATETIME() OR i.ServiceStartsAt<=SYSUTCDATETIME() OR (SELECT COUNT(*) FROM dbo.TravelBookingItems bi WHERE bi.BookingID=i.BookingID)<>CASE WHEN i.StartDate=i.EndDate THEN 1 ELSE DATEDIFF(day,i.StartDate,i.EndDate) END))
 THROW 52010,N'Confirmation requires valid stock and payment.',1;
 IF EXISTS(SELECT 1 FROM dbo.vw_TravelAvailability a JOIN inserted i ON i.ProductID=a.ProductID WHERE a.AvailableQuantity<0) THROW 52004,N'Inventory capacity exceeded.',1;
END;
GO
