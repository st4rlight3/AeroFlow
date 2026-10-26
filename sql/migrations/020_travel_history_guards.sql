-- History is a snapshot: editing tomorrow's catalogue must not rewrite a paid receipt.
ALTER TABLE dbo.TravelBookings ADD CONSTRAINT CK_TravelBooking_HoldWindow CHECK(ExpiresAt<=DATEADD(minute,10,CreatedAt));
GO
CREATE OR ALTER TRIGGER dbo.tr_TravelBooking_Snapshot ON dbo.TravelBookings AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.BookingID=i.BookingID
 WHERE EXISTS(SELECT 1 FROM dbo.TravelBookingItems x WHERE x.BookingID=i.BookingID)
 AND EXISTS(SELECT i.UserID,i.ProductID,i.PackageID,i.StartDate,i.EndDate,i.SlotCode,i.Quantity,i.GuestCount,i.ServiceStartsAt,i.ServiceEndsAt,
 i.ProductTitle,i.PackageName,i.UnitLabel,i.Subtotal,i.DiscountAmount,i.Total,i.RefundPercent,i.CancelCutoffHours,i.ChangeAllowed,i.ChangeFee,i.IdempotencyKey,i.RequestHash
 EXCEPT SELECT d.UserID,d.ProductID,d.PackageID,d.StartDate,d.EndDate,d.SlotCode,d.Quantity,d.GuestCount,d.ServiceStartsAt,d.ServiceEndsAt,
 d.ProductTitle,d.PackageName,d.UnitLabel,d.Subtotal,d.DiscountAmount,d.Total,d.RefundPercent,d.CancelCutoffHours,d.ChangeAllowed,d.ChangeFee,d.IdempotencyKey,d.RequestHash))
 THROW 52012,N'Booking snapshot is immutable.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_TravelItems_PaidHistory ON dbo.TravelBookingItems AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted d JOIN dbo.TravelBookings b ON b.BookingID=d.BookingID WHERE b.Status<>'HELD')
 THROW 52012,N'Paid or closed booking items are immutable.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_TravelReviews_Verified ON dbo.TravelReviews AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted r JOIN dbo.TravelBookings b ON b.BookingID=r.BookingID WHERE b.Status<>'CONFIRMED' OR b.ServiceEndsAt>SYSUTCDATETIME())
 THROW 52010,N'Only a completed confirmed booking can be reviewed.',1;
END;
GO
CREATE TABLE dbo.TravelFulfillments(
 BookingID int NOT NULL CONSTRAINT PK_TravelFulfillment PRIMARY KEY CONSTRAINT FK_TravelFulfillment_Booking REFERENCES dbo.TravelBookings,
 Kind varchar(12) NOT NULL,PayloadJson nvarchar(max) NOT NULL,
 CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_TravelFulfillment_Json CHECK(ISJSON(PayloadJson)=1 AND Kind IN ('ESIM','VOUCHER'))
);
GO
CREATE OR ALTER TRIGGER dbo.tr_TravelVoucher_Fulfillment ON dbo.TravelVouchers AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i JOIN dbo.TravelBookings b ON b.BookingID=i.BookingID WHERE b.Status<>'CONFIRMED')
 THROW 52010,N'Voucher requires a confirmed booking.',1;
 INSERT dbo.TravelFulfillments(BookingID,Kind,PayloadJson)
 SELECT b.BookingID,CASE WHEN p.CategoryCode='esim' THEN 'ESIM' ELSE 'VOUCHER' END,
 (SELECT CAST(1 AS bit) Simulated,b.Reference BookingReference,b.ProductTitle ProductTitle,b.PackageName PackageName,
 CASE WHEN p.CategoryCode='esim' THEN CONCAT('DEMO-NOT-ACTIVE-',i.Code) END ActivationCode,
 CASE WHEN p.CategoryCode='esim' THEN N'Không cài vào điện thoại. Mã không kết nối được nhà mạng.' ELSE N'Xuất trình mã QR trong kịch bản kiểm thử AeroFlow.' END Instructions
 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
 FROM inserted i JOIN dbo.TravelBookings b ON b.BookingID=i.BookingID JOIN dbo.TravelProducts p ON p.ProductID=b.ProductID;
END;
