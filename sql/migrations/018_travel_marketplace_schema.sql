-- Marketplace domain shares Users/Roles; airline bookings and payments stay intact.
CREATE TABLE dbo.TravelCategories(
 Code varchar(20) NOT NULL CONSTRAINT PK_TravelCategories PRIMARY KEY,
 Name nvarchar(80) NOT NULL, Icon varchar(24) NOT NULL, SortOrder int NOT NULL DEFAULT 0
);
CREATE TABLE dbo.TravelDestinations(
 DestinationID int IDENTITY CONSTRAINT PK_TravelDestinations PRIMARY KEY,
 Slug varchar(100) NOT NULL CONSTRAINT UQ_TravelDestinations_Slug UNIQUE,
 Name nvarchar(100) NOT NULL,CountryCode char(2) NOT NULL,CountryName nvarchar(80) NOT NULL,
 RegionCode varchar(20) NOT NULL,TimeZoneName nvarchar(64) NOT NULL,IanaTimeZone nvarchar(64) NOT NULL,
 Latitude decimal(9,6) NOT NULL,Longitude decimal(9,6) NOT NULL,ImagePath nvarchar(250) NOT NULL,
 CONSTRAINT CK_TravelDestination_Coordinates CHECK(Latitude BETWEEN -90 AND 90 AND Longitude BETWEEN -180 AND 180)
);
CREATE TABLE dbo.TravelProviders(
 ProviderID int IDENTITY CONSTRAINT PK_TravelProviders PRIMARY KEY,
 OwnerUserID int NULL CONSTRAINT FK_TravelProvider_User REFERENCES dbo.Users,
 Name nvarchar(150) NOT NULL,Description nvarchar(1000) NOT NULL DEFAULT N'',
 Status varchar(12) NOT NULL DEFAULT 'ACTIVE',IsDemo bit NOT NULL DEFAULT 1,
 CONSTRAINT CK_TravelProvider_Status CHECK(Status IN ('PENDING','ACTIVE','SUSPENDED'))
);
CREATE TABLE dbo.TravelProducts(
 ProductID int IDENTITY CONSTRAINT PK_TravelProducts PRIMARY KEY,
 CategoryCode varchar(20) NOT NULL CONSTRAINT FK_TravelProduct_Category REFERENCES dbo.TravelCategories,
 DestinationID int NOT NULL CONSTRAINT FK_TravelProduct_Destination REFERENCES dbo.TravelDestinations,
 ProviderID int NOT NULL CONSTRAINT FK_TravelProduct_Provider REFERENCES dbo.TravelProviders,
 Slug varchar(150) NOT NULL CONSTRAINT UQ_TravelProducts_Slug UNIQUE,
 Title nvarchar(200) NOT NULL,Summary nvarchar(500) NOT NULL,Description nvarchar(max) NOT NULL,
 Address nvarchar(250) NOT NULL,Latitude decimal(9,6) NOT NULL,Longitude decimal(9,6) NOT NULL,
 DurationMinutes int NOT NULL DEFAULT 0,StarRating tinyint NOT NULL DEFAULT 0,
 FeaturesJson nvarchar(max) NOT NULL DEFAULT N'{}',IsPublished bit NOT NULL DEFAULT 0,
 CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),UpdatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_TravelProduct_Details CHECK(ISJSON(FeaturesJson)=1 AND LEN(Title)>=3 AND StarRating BETWEEN 0 AND 5 AND DurationMinutes BETWEEN 0 AND 100000),
 CONSTRAINT CK_TravelProduct_Coordinates CHECK(Latitude BETWEEN -90 AND 90 AND Longitude BETWEEN -180 AND 180)
);
CREATE TABLE dbo.TravelProductImages(
 ImageID int IDENTITY CONSTRAINT PK_TravelImages PRIMARY KEY,
 ProductID int NOT NULL CONSTRAINT FK_TravelImage_Product REFERENCES dbo.TravelProducts,
 ImagePath nvarchar(250) NOT NULL,Caption nvarchar(200) NOT NULL,SortOrder int NOT NULL,
 CONSTRAINT UQ_TravelImage_Order UNIQUE(ProductID,SortOrder)
);
CREATE TABLE dbo.TravelAmenities(
 AmenityID int IDENTITY CONSTRAINT PK_TravelAmenities PRIMARY KEY,
 Code varchar(30) NOT NULL CONSTRAINT UQ_TravelAmenities_Code UNIQUE,Name nvarchar(100) NOT NULL
);
CREATE TABLE dbo.TravelProductAmenities(
 ProductID int NOT NULL CONSTRAINT FK_TravelPA_Product REFERENCES dbo.TravelProducts,
 AmenityID int NOT NULL CONSTRAINT FK_TravelPA_Amenity REFERENCES dbo.TravelAmenities,
 CONSTRAINT PK_TravelProductAmenities PRIMARY KEY(ProductID,AmenityID)
);
CREATE TABLE dbo.TravelPackages(
 PackageID int IDENTITY CONSTRAINT PK_TravelPackages PRIMARY KEY,
 ProductID int NOT NULL CONSTRAINT FK_TravelPackage_Product REFERENCES dbo.TravelProducts,
 Name nvarchar(150) NOT NULL,Description nvarchar(1000) NOT NULL,
 UnitCode varchar(12) NOT NULL,UnitLabel nvarchar(30) NOT NULL,MaxGuests int NOT NULL DEFAULT 1,
 RefundPercent decimal(5,2) NOT NULL DEFAULT 0,CancelCutoffHours int NOT NULL DEFAULT 24,
 ChangeAllowed bit NOT NULL DEFAULT 0,ChangeFee decimal(14,2) NOT NULL DEFAULT 0,
 IsActive bit NOT NULL DEFAULT 1,
 CONSTRAINT UQ_TravelPackage_Product UNIQUE(PackageID,ProductID),
 CONSTRAINT CK_TravelPackage_Unit CHECK(UnitCode IN ('NIGHT','DAY','PERSON','BOOKING')),
 CONSTRAINT CK_TravelPackage_Policy CHECK(MaxGuests BETWEEN 1 AND 50 AND RefundPercent BETWEEN 0 AND 100 AND CancelCutoffHours BETWEEN 0 AND 720 AND ChangeFee BETWEEN 0 AND 100000000)
);
CREATE TABLE dbo.TravelInventory(
 InventoryID int IDENTITY CONSTRAINT PK_TravelInventory PRIMARY KEY,
 PackageID int NOT NULL CONSTRAINT FK_TravelInventory_Package REFERENCES dbo.TravelPackages,
 ServiceDate date NOT NULL,SlotCode varchar(20) NOT NULL DEFAULT 'ALL_DAY',
 StartsAt datetime2(0) NOT NULL,EndsAt datetime2(0) NOT NULL,
 Capacity int NOT NULL,UnitPrice decimal(14,2) NOT NULL,IsClosed bit NOT NULL DEFAULT 0,
 CONSTRAINT UQ_TravelInventory_Date UNIQUE(PackageID,ServiceDate,SlotCode),
 CONSTRAINT UQ_TravelInventory_Package UNIQUE(InventoryID,PackageID),
 CONSTRAINT CK_TravelInventory_Values CHECK(Capacity BETWEEN 0 AND 5000 AND UnitPrice>0 AND UnitPrice<=100000000 AND EndsAt>StartsAt)
);
CREATE TABLE dbo.TravelCoupons(
 CouponID int IDENTITY CONSTRAINT PK_TravelCoupons PRIMARY KEY,
 Code varchar(30) NOT NULL CONSTRAINT UQ_TravelCoupon_Code UNIQUE,Title nvarchar(150) NOT NULL,
 Kind varchar(8) NOT NULL,Amount decimal(14,2) NOT NULL,MaxDiscount decimal(14,2) NOT NULL,
 MinSubtotal decimal(14,2) NOT NULL DEFAULT 0,UsageLimit int NOT NULL,PerUserLimit int NOT NULL DEFAULT 1,
 ValidFrom datetime2(0) NOT NULL,ValidUntil datetime2(0) NOT NULL,
 CategoryCode varchar(20) NULL CONSTRAINT FK_TravelCoupon_Category REFERENCES dbo.TravelCategories,
 IsActive bit NOT NULL DEFAULT 1,
 CONSTRAINT CK_TravelCoupon_Values CHECK(Kind IN ('FIXED','PERCENT') AND Amount>0 AND (Kind<>'PERCENT' OR Amount<=100) AND MaxDiscount>0 AND MinSubtotal>=0 AND UsageLimit>0 AND PerUserLimit>0 AND ValidUntil>ValidFrom)
);
CREATE TABLE dbo.TravelBookings(
 BookingID int IDENTITY CONSTRAINT PK_TravelBookings PRIMARY KEY,
 Reference char(12) NOT NULL CONSTRAINT UQ_TravelBookings_Reference UNIQUE,
 UserID int NOT NULL CONSTRAINT FK_TravelBooking_User REFERENCES dbo.Users,
 ProductID int NOT NULL CONSTRAINT FK_TravelBooking_Product REFERENCES dbo.TravelProducts,
 PackageID int NOT NULL,StartDate date NOT NULL,EndDate date NOT NULL,SlotCode varchar(20) NOT NULL,
 Quantity int NOT NULL,GuestCount int NOT NULL,ServiceStartsAt datetime2(0) NOT NULL,ServiceEndsAt datetime2(0) NOT NULL,
 ProductTitle nvarchar(200) NOT NULL,PackageName nvarchar(150) NOT NULL,UnitLabel nvarchar(30) NOT NULL,
 Subtotal decimal(14,2) NOT NULL,DiscountAmount decimal(14,2) NOT NULL DEFAULT 0,Total decimal(14,2) NOT NULL,
 RefundPercent decimal(5,2) NOT NULL,CancelCutoffHours int NOT NULL,ChangeAllowed bit NOT NULL,ChangeFee decimal(14,2) NOT NULL,
 ContactName nvarchar(120) NOT NULL,ContactEmail nvarchar(254) NOT NULL,ContactPhone varchar(24) NOT NULL,Notes nvarchar(1000) NULL,
 Status varchar(12) NOT NULL DEFAULT 'HELD',CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 ExpiresAt datetime2(0) NOT NULL,CancelledAt datetime2(0) NULL,
 IdempotencyKey varchar(80) NOT NULL,RequestHash char(64) NOT NULL,
 CONSTRAINT FK_TravelBooking_Package FOREIGN KEY(PackageID,ProductID) REFERENCES dbo.TravelPackages(PackageID,ProductID),
 CONSTRAINT UQ_TravelBooking_Request UNIQUE(UserID,IdempotencyKey),
 CONSTRAINT UQ_TravelBooking_Package UNIQUE(BookingID,PackageID),
 CONSTRAINT UQ_TravelBooking_ReviewOwner UNIQUE(BookingID,UserID,ProductID),
 CONSTRAINT CK_TravelBooking_Status CHECK(Status IN ('HELD','CONFIRMED','CANCELLED','EXPIRED')),
 CONSTRAINT CK_TravelBooking_Values CHECK(Quantity BETWEEN 1 AND 99 AND GuestCount BETWEEN 1 AND 4950 AND EndDate>=StartDate AND ServiceEndsAt>ServiceStartsAt AND ExpiresAt>CreatedAt AND Subtotal>0 AND DiscountAmount BETWEEN 0 AND Subtotal AND Total=Subtotal-DiscountAmount AND RefundPercent BETWEEN 0 AND 100 AND CancelCutoffHours BETWEEN 0 AND 720 AND ChangeFee>=0)
);
CREATE TABLE dbo.TravelBookingItems(
 ItemID int IDENTITY CONSTRAINT PK_TravelBookingItems PRIMARY KEY,
 BookingID int NOT NULL,InventoryID int NOT NULL,PackageID int NOT NULL,
 Quantity int NOT NULL,UnitPrice decimal(14,2) NOT NULL,
 CONSTRAINT FK_TravelItem_Booking FOREIGN KEY(BookingID,PackageID) REFERENCES dbo.TravelBookings(BookingID,PackageID),
 CONSTRAINT FK_TravelItem_Inventory FOREIGN KEY(InventoryID,PackageID) REFERENCES dbo.TravelInventory(InventoryID,PackageID),
 CONSTRAINT UQ_TravelItem_Inventory UNIQUE(BookingID,InventoryID),
 CONSTRAINT CK_TravelItem_Values CHECK(Quantity BETWEEN 1 AND 99 AND UnitPrice>0)
);
CREATE TABLE dbo.TravelCouponReservations(
 BookingID int NOT NULL CONSTRAINT PK_TravelCouponReservations PRIMARY KEY CONSTRAINT FK_TravelCR_Booking REFERENCES dbo.TravelBookings,
 CouponID int NOT NULL CONSTRAINT FK_TravelCR_Coupon REFERENCES dbo.TravelCoupons,
 DiscountAmount decimal(14,2) NOT NULL CONSTRAINT CK_TravelCR_Discount CHECK(DiscountAmount>=0)
);
CREATE TABLE dbo.TravelPayments(
 PaymentID int IDENTITY CONSTRAINT PK_TravelPayments PRIMARY KEY,
 BookingID int NOT NULL CONSTRAINT FK_TravelPayment_Booking REFERENCES dbo.TravelBookings,
 Kind varchar(8) NOT NULL,Status varchar(8) NOT NULL,Amount decimal(14,2) NOT NULL,
 IdempotencyKey varchar(80) NOT NULL CONSTRAINT UQ_TravelPayment_Request UNIQUE,
 CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_TravelPayment_Values CHECK(Kind IN ('CHARGE','REFUND','ADJUST') AND Status IN ('SUCCESS','FAILED') AND Amount>=0)
);
CREATE UNIQUE INDEX UX_TravelPayment_Charge ON dbo.TravelPayments(BookingID) WHERE Kind='CHARGE' AND Status='SUCCESS';
CREATE UNIQUE INDEX UX_TravelPayment_Refund ON dbo.TravelPayments(BookingID) WHERE Kind='REFUND';
CREATE TABLE dbo.TravelVouchers(
 VoucherID int IDENTITY CONSTRAINT PK_TravelVouchers PRIMARY KEY,
 BookingID int NOT NULL CONSTRAINT UQ_TravelVoucher_Booking UNIQUE CONSTRAINT FK_TravelVoucher_Booking REFERENCES dbo.TravelBookings,
 Code char(32) NOT NULL CONSTRAINT UQ_TravelVoucher_Code UNIQUE,
 Status varchar(12) NOT NULL DEFAULT 'ACTIVE',RedeemedAt datetime2(0) NULL,
 RedeemedBy int NULL CONSTRAINT FK_TravelVoucher_Actor REFERENCES dbo.Users,
 CONSTRAINT CK_TravelVoucher_State CHECK(Status IN ('ACTIVE','REDEEMED','VOID'))
);
CREATE TABLE dbo.TravelWishlists(
 UserID int NOT NULL CONSTRAINT FK_TravelWishlist_User REFERENCES dbo.Users,
 ProductID int NOT NULL CONSTRAINT FK_TravelWishlist_Product REFERENCES dbo.TravelProducts,
 CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),CONSTRAINT PK_TravelWishlists PRIMARY KEY(UserID,ProductID)
);
CREATE TABLE dbo.TravelCart(
 CartID int IDENTITY CONSTRAINT PK_TravelCart PRIMARY KEY,UserID int NOT NULL CONSTRAINT FK_TravelCart_User REFERENCES dbo.Users,
 PackageID int NOT NULL CONSTRAINT FK_TravelCart_Package REFERENCES dbo.TravelPackages,
 StartDate date NOT NULL,EndDate date NOT NULL,SlotCode varchar(20) NOT NULL,
 Quantity int NOT NULL,GuestCount int NOT NULL,
 CONSTRAINT CK_TravelCart_Values CHECK(EndDate>=StartDate AND Quantity BETWEEN 1 AND 99 AND GuestCount BETWEEN 1 AND 4950)
);
CREATE TABLE dbo.TravelReviews(
 ReviewID int IDENTITY CONSTRAINT PK_TravelReviews PRIMARY KEY,
 BookingID int NOT NULL CONSTRAINT UQ_TravelReview_Booking UNIQUE,UserID int NOT NULL,ProductID int NOT NULL,
 Rating tinyint NOT NULL CONSTRAINT CK_TravelReview_Rating CHECK(Rating BETWEEN 1 AND 5),
 Title nvarchar(150) NOT NULL,Comment nvarchar(2000) NOT NULL,IsVisible bit NOT NULL DEFAULT 1,
 CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT FK_TravelReview_Booking FOREIGN KEY(BookingID,UserID,ProductID) REFERENCES dbo.TravelBookings(BookingID,UserID,ProductID)
);
CREATE TABLE dbo.TravelAuditLog(
 AuditID bigint IDENTITY CONSTRAINT PK_TravelAudit PRIMARY KEY,
 ActorID int NULL CONSTRAINT FK_TravelAudit_Actor REFERENCES dbo.Users,
 Entity varchar(40) NOT NULL,EntityID int NOT NULL,Action varchar(40) NOT NULL,
 Details nvarchar(max) NULL,CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE TABLE dbo.TravelTrips(
 TripID int IDENTITY CONSTRAINT PK_TravelTrips PRIMARY KEY,UserID int NOT NULL CONSTRAINT FK_TravelTrip_User REFERENCES dbo.Users,
 Name nvarchar(150) NOT NULL,StartDate date NOT NULL,EndDate date NOT NULL,
 CONSTRAINT CK_TravelTrip_Dates CHECK(EndDate>=StartDate AND DATEDIFF(day,StartDate,EndDate)<=60)
);
CREATE TABLE dbo.TravelTripStops(
 StopID int IDENTITY CONSTRAINT PK_TravelTripStops PRIMARY KEY,TripID int NOT NULL CONSTRAINT FK_TravelStop_Trip REFERENCES dbo.TravelTrips,
 VisitDate date NOT NULL,SortOrder int NOT NULL,ProductID int NULL CONSTRAINT FK_TravelStop_Product REFERENCES dbo.TravelProducts,
 Name nvarchar(200) NOT NULL,Notes nvarchar(1000) NOT NULL DEFAULT N'',
 CONSTRAINT UQ_TravelStop_Order UNIQUE(TripID,VisitDate,SortOrder)
);
CREATE TABLE dbo.TravelSupportTickets(
 TicketID int IDENTITY CONSTRAINT PK_TravelSupport PRIMARY KEY,UserID int NOT NULL CONSTRAINT FK_TravelSupport_User REFERENCES dbo.Users,
 BookingID int NULL CONSTRAINT FK_TravelSupport_Booking REFERENCES dbo.TravelBookings,
 Subject nvarchar(150) NOT NULL,Status varchar(12) NOT NULL DEFAULT 'OPEN',CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_TravelSupport_Status CHECK(Status IN ('OPEN','ANSWERED','CLOSED'))
);
CREATE TABLE dbo.TravelSupportMessages(
 MessageID int IDENTITY CONSTRAINT PK_TravelMessages PRIMARY KEY,TicketID int NOT NULL CONSTRAINT FK_TravelMessage_Ticket REFERENCES dbo.TravelSupportTickets,
 SenderID int NOT NULL CONSTRAINT FK_TravelMessage_User REFERENCES dbo.Users,Message nvarchar(2000) NOT NULL,CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE TABLE dbo.TravelArticles(
 ArticleID int IDENTITY CONSTRAINT PK_TravelArticles PRIMARY KEY,Slug varchar(120) NOT NULL CONSTRAINT UQ_TravelArticle_Slug UNIQUE,
 Title nvarchar(200) NOT NULL,Summary nvarchar(500) NOT NULL,Content nvarchar(max) NOT NULL,ImagePath nvarchar(250) NOT NULL,
 IsPublished bit NOT NULL DEFAULT 1,CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE INDEX IX_TravelProduct_Search ON dbo.TravelProducts(CategoryCode,DestinationID,IsPublished) INCLUDE(Title,ProviderID,StarRating);
CREATE INDEX IX_TravelInventory_Dates ON dbo.TravelInventory(ServiceDate,PackageID) INCLUDE(Capacity,UnitPrice,SlotCode,StartsAt,EndsAt,IsClosed);
CREATE INDEX IX_TravelItems_Capacity ON dbo.TravelBookingItems(InventoryID) INCLUDE(BookingID,Quantity);
CREATE INDEX IX_TravelBooking_User ON dbo.TravelBookings(UserID,CreatedAt DESC);
CREATE INDEX IX_TravelBooking_Expiry ON dbo.TravelBookings(ProductID,Status,ExpiresAt);
CREATE INDEX IX_TravelReview_Product ON dbo.TravelReviews(ProductID,IsVisible) INCLUDE(Rating);
GO
CREATE OR ALTER VIEW dbo.vw_TravelAvailability AS
 SELECT i.*,p.ProductID,
 i.Capacity-COALESCE((SELECT SUM(bi.Quantity) FROM dbo.TravelBookingItems bi JOIN dbo.TravelBookings b ON b.BookingID=bi.BookingID
 WHERE bi.InventoryID=i.InventoryID AND (b.Status='CONFIRMED' OR (b.Status='HELD' AND b.ExpiresAt>SYSUTCDATETIME()))),0) AvailableQuantity
 FROM dbo.TravelInventory i JOIN dbo.TravelPackages p ON p.PackageID=i.PackageID;
GO
CREATE OR ALTER VIEW dbo.vw_TravelProducts AS
 SELECT p.*,c.Name CategoryName,d.Name DestinationName,d.CountryName,d.RegionCode,d.IanaTimeZone,d.TimeZoneName,
 pr.Name ProviderName,pr.Status ProviderStatus,
 (SELECT TOP(1) ImagePath FROM dbo.TravelProductImages im WHERE im.ProductID=p.ProductID ORDER BY SortOrder,ImageID) ImagePath,
 (SELECT MIN(i.UnitPrice) FROM dbo.vw_TravelAvailability i JOIN dbo.TravelPackages pk ON pk.PackageID=i.PackageID WHERE pk.ProductID=p.ProductID AND pk.IsActive=1 AND i.IsClosed=0 AND i.StartsAt>SYSUTCDATETIME() AND i.AvailableQuantity>0) FromPrice,
 (SELECT CONVERT(decimal(3,2),AVG(CONVERT(decimal(5,2),r.Rating))) FROM dbo.TravelReviews r WHERE r.ProductID=p.ProductID AND r.IsVisible=1) Rating,
 (SELECT COUNT(*) FROM dbo.TravelReviews r WHERE r.ProductID=p.ProductID AND r.IsVisible=1) ReviewCount
 FROM dbo.TravelProducts p JOIN dbo.TravelCategories c ON c.Code=p.CategoryCode JOIN dbo.TravelDestinations d ON d.DestinationID=p.DestinationID JOIN dbo.TravelProviders pr ON pr.ProviderID=p.ProviderID;
GO
CREATE OR ALTER VIEW dbo.vw_TravelRevenue AS
 SELECT CONVERT(date,CreatedAt) RevenueDate,
 SUM(CASE WHEN Kind IN ('CHARGE','ADJUST') THEN Amount ELSE -Amount END) NetRevenue,
 SUM(CASE WHEN Kind='REFUND' THEN Amount ELSE 0 END) Refunds,
 SUM(CASE WHEN Kind='CHARGE' THEN 1 ELSE 0 END) PaidBookings
 FROM dbo.TravelPayments WHERE Status='SUCCESS' GROUP BY CONVERT(date,CreatedAt);
