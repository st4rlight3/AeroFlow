ALTER TABLE dbo.CheckIns ADD BoardedAt datetime2(0) NULL;
ALTER TABLE dbo.UserPreferences ADD EmailNotifications bit NOT NULL CONSTRAINT DF_EmailPreference DEFAULT 0;
ALTER TABLE dbo.LoyaltyTiers ADD LoyaltyTierID int IDENTITY;
CREATE UNIQUE INDEX UX_LoyaltyTierID ON dbo.LoyaltyTiers(LoyaltyTierID);
CREATE TABLE dbo.Routes(
 RouteID int IDENTITY CONSTRAINT PK_Routes PRIMARY KEY,
 OriginID int NOT NULL REFERENCES dbo.Airports(AirportID),DestinationID int NOT NULL REFERENCES dbo.Airports(AirportID),
 IsActive bit NOT NULL DEFAULT 1,CONSTRAINT UQ_Route UNIQUE(OriginID,DestinationID),CONSTRAINT CK_Route CHECK(OriginID<>DestinationID));
INSERT dbo.Routes(OriginID,DestinationID) SELECT DISTINCT OriginID,DestinationID FROM dbo.Flights;
CREATE TABLE dbo.NotificationDeliveries(
 NotificationID bigint CONSTRAINT PK_NotificationDelivery PRIMARY KEY REFERENCES dbo.Notifications,
 SentAt datetime2(0) NULL,Attempts int NOT NULL DEFAULT 0,LastError varchar(80) NULL);
GO
CREATE OR ALTER TRIGGER dbo.tr_Booking_Notifications ON dbo.Bookings AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Notifications(UserID,BookingID,Title,Message)
 SELECT i.UserID,i.BookingID,N'Trạng thái đặt chỗ',CONCAT(N'Đặt chỗ ',i.PNR,N': ',i.Status,N'. Xem chi tiết trong Chuyến đi của tôi.')
 FROM inserted i LEFT JOIN deleted d ON d.BookingID=i.BookingID WHERE d.BookingID IS NULL OR i.Status<>d.Status;
END;
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
