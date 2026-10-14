-- Additive operations. Existing passenger/payment records are not rewritten.
CREATE TABLE dbo.SavedTravellers(
 TravellerID int IDENTITY CONSTRAINT PK_SavedTravellers PRIMARY KEY,
 UserID int NOT NULL REFERENCES dbo.Users,FullName nvarchar(120) NOT NULL,
 DateOfBirth date NOT NULL,DocumentNumber nvarchar(30) NOT NULL,
 Assistance varchar(12) NOT NULL DEFAULT 'NONE',
 CONSTRAINT UQ_SavedTraveller UNIQUE(UserID,DocumentNumber),
 CONSTRAINT CK_SavedTraveller CHECK(LEN(FullName)>=2 AND LEN(DocumentNumber)>=5 AND Assistance IN ('NONE','WHEELCHAIR','HEARING','VISION')));
CREATE TABLE dbo.UserPreferences(
 UserID int CONSTRAINT PK_UserPreferences PRIMARY KEY REFERENCES dbo.Users,
 PreferredCabin varchar(12) NOT NULL DEFAULT 'ECONOMY',SeatPreference varchar(8) NOT NULL DEFAULT 'ANY',
 Reminders bit NOT NULL DEFAULT 1,
 CONSTRAINT CK_UserPreferences CHECK(PreferredCabin IN ('ECONOMY','PREMIUM','BUSINESS','FIRST') AND SeatPreference IN ('ANY','WINDOW','AISLE')));
CREATE TABLE dbo.PasswordResetTokens(
 TokenHash char(64) CONSTRAINT PK_ResetTokens PRIMARY KEY,UserID int NOT NULL REFERENCES dbo.Users,
 ExpiresAt datetime2(0) NOT NULL,UsedAt datetime2(0) NULL,CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME());
CREATE INDEX IX_ResetTokens_User ON dbo.PasswordResetTokens(UserID,ExpiresAt);
CREATE TABLE dbo.Notifications(
 NotificationID bigint IDENTITY CONSTRAINT PK_Notifications PRIMARY KEY,
 UserID int NOT NULL REFERENCES dbo.Users,BookingID int NULL REFERENCES dbo.Bookings,
 Title nvarchar(120) NOT NULL,Message nvarchar(1000) NOT NULL,IsRead bit NOT NULL DEFAULT 0,
 EventKey varchar(100) NULL,CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME());
CREATE INDEX IX_Notifications_User ON dbo.Notifications(UserID,NotificationID DESC);
CREATE UNIQUE INDEX UX_Notifications_Event ON dbo.Notifications(EventKey) WHERE EventKey IS NOT NULL;
CREATE TABLE dbo.LoyaltyLedger(
 LoyaltyID bigint IDENTITY CONSTRAINT PK_LoyaltyLedger PRIMARY KEY,UserID int NOT NULL REFERENCES dbo.Users,
 PaymentID int NOT NULL CONSTRAINT UQ_Loyalty_Payment UNIQUE REFERENCES dbo.Payments,
 Points int NOT NULL,Reason nvarchar(120) NOT NULL,CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME());
CREATE INDEX IX_Loyalty_User ON dbo.LoyaltyLedger(UserID,LoyaltyID);
CREATE TABLE dbo.LoyaltyTiers(
 TierCode varchar(10) CONSTRAINT PK_LoyaltyTiers PRIMARY KEY,Name nvarchar(50) NOT NULL,
 MinimumPoints int NOT NULL CONSTRAINT UQ_Loyalty_Minimum UNIQUE CHECK(MinimumPoints>=0));
INSERT dbo.LoyaltyTiers VALUES('BLUE',N'Blue',0),('SILVER',N'Silver',1000),('GOLD',N'Gold',5000);
ALTER TABLE dbo.Flights ADD Gate nvarchar(12) NULL,EstimatedDeparture datetime2(0) NULL,OperationNote nvarchar(300) NULL;
CREATE TABLE dbo.CheckIns(
 CheckInID int IDENTITY CONSTRAINT PK_CheckIns PRIMARY KEY,TicketID int NOT NULL CONSTRAINT UQ_CheckIn_Ticket UNIQUE REFERENCES dbo.Tickets,
 Reference uniqueidentifier NOT NULL DEFAULT NEWID() CONSTRAINT UQ_CheckIn_Reference UNIQUE,
 Status varchar(8) NOT NULL DEFAULT 'ACTIVE' CHECK(Status IN ('ACTIVE','REVOKED')),
 CheckedInAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),RevokedAt datetime2(0) NULL);
GO
CREATE OR ALTER VIEW dbo.vw_LoyaltySummary AS
SELECT u.UserID,CONVERT(int,COALESCE(l.Points,0)) Points,t.TierCode,t.Name TierName
FROM dbo.Users u OUTER APPLY(SELECT SUM(Points) Points FROM dbo.LoyaltyLedger WHERE UserID=u.UserID) l
CROSS APPLY(SELECT TOP(1) * FROM dbo.LoyaltyTiers WHERE MinimumPoints<=COALESCE(l.Points,0) ORDER BY MinimumPoints DESC) t;
GO
CREATE OR ALTER TRIGGER dbo.tr_Payment_CustomerEvents ON dbo.Payments AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Notifications(UserID,BookingID,Title,Message,EventKey)
 SELECT b.UserID,i.BookingID,N'Giao dịch đặt chỗ',CONCAT(N'Mã ',b.PNR,N': ',i.Kind,N' / ',i.Status,N' — ',i.Amount,N' VND. Thanh toán mô phỏng.'),CONCAT('payment:',i.PaymentID)
 FROM inserted i JOIN dbo.Bookings b ON b.BookingID=i.BookingID;
 -- New successful charges earn 1 point / 10,000 VND. Refunds reverse at most
 -- points already awarded for that booking; legacy payments get no retroactive award.
 INSERT dbo.LoyaltyLedger(UserID,PaymentID,Points,Reason)
 SELECT b.UserID,i.PaymentID,CASE WHEN i.Kind='CHARGE' THEN CONVERT(int,FLOOR(i.Amount/10000))
 ELSE -CONVERT(int,CASE WHEN COALESCE(l.Points,0)<CEILING(i.Amount/10000) THEN COALESCE(l.Points,0) ELSE CEILING(i.Amount/10000) END) END,
 CASE WHEN i.Kind='CHARGE' THEN N'Tích điểm thanh toán' ELSE N'Điều chỉnh hoàn tiền' END
 FROM inserted i JOIN dbo.Bookings b ON b.BookingID=i.BookingID
 OUTER APPLY(SELECT SUM(ll.Points) Points FROM dbo.LoyaltyLedger ll JOIN dbo.Payments p ON p.PaymentID=ll.PaymentID WHERE p.BookingID=i.BookingID) l
 WHERE i.Status='SUCCESS';
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_Flight_CustomerEvents ON dbo.Flights AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Notifications(UserID,BookingID,Title,Message)
 SELECT DISTINCT b.UserID,b.BookingID,N'Cập nhật chuyến bay',CONCAT(i.FlightNumber,N': ',i.Status,N'; cửa ',COALESCE(i.Gate,N'chưa công bố'),N'; ',COALESCE(i.OperationNote,N''))
 FROM inserted i JOIN deleted d ON d.FlightID=i.FlightID JOIN dbo.BookingSegments s ON s.FlightID=i.FlightID
 JOIN dbo.Bookings b ON b.BookingID=s.BookingID
 WHERE b.Status IN ('HELD','CONFIRMED') AND
 (i.Status<>d.Status OR ISNULL(i.Gate,'')<>ISNULL(d.Gate,'') OR ISNULL(i.EstimatedDeparture,'19000101')<>ISNULL(d.EstimatedDeparture,'19000101') OR ISNULL(i.OperationNote,'')<>ISNULL(d.OperationNote,''));
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_Ticket_RevokeCheckIn ON dbo.Tickets AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 UPDATE c SET Status='REVOKED',RevokedAt=SYSUTCDATETIME() FROM dbo.CheckIns c JOIN inserted t ON t.TicketID=c.TicketID WHERE t.Status<>'VALID' AND c.Status='ACTIVE';
 -- Snapshot values are immutable, including direct SQL updates.
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.TicketID=i.TicketID WHERE i.BaseFare<>d.BaseFare OR i.TaxAmount<>d.TaxAmount OR i.SeatFee<>d.SeatFee OR i.PassengerType<>d.PassengerType OR i.BreakdownSource<>d.BreakdownSource)
 THROW 51011,N'Không sửa ảnh chụp giá vé.',1;
END;
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
