ALTER TABLE dbo.Payments ADD Purpose varchar(12) NOT NULL CONSTRAINT DF_PaymentPurpose DEFAULT 'BOOKING' CONSTRAINT CK_PaymentPurpose CHECK(Purpose IN ('BOOKING','EXCHANGE')),
 Settlement varchar(8) NOT NULL CONSTRAINT DF_PaymentSettlement DEFAULT 'MOCK' CONSTRAINT CK_PaymentSettlement CHECK(Settlement IN ('MOCK','CREDIT'));
GO
DROP INDEX UX_Payments_SuccessCharge ON dbo.Payments;
CREATE UNIQUE INDEX UX_Payments_SuccessCharge ON dbo.Payments(BookingID) WHERE Kind='CHARGE' AND Status='SUCCESS' AND Purpose='BOOKING';
ALTER TABLE dbo.BookingSegments DROP CONSTRAINT UQ_Segments_Order;
CREATE UNIQUE INDEX UX_Segments_ActiveOrder ON dbo.BookingSegments(BookingID,SegmentOrder) WHERE Status='ACTIVE';
CREATE TABLE dbo.TicketRules(
 TicketID int CONSTRAINT PK_TicketRules PRIMARY KEY REFERENCES dbo.Tickets,
 ChangeAllowed bit NOT NULL,ChangeFee decimal(14,2) NOT NULL CHECK(ChangeFee>=0),
 BaggageKg int NOT NULL,CabinBaggageKg int NOT NULL,
 Source varchar(16) NOT NULL CHECK(Source IN ('LEGACY_CURRENT','ISSUED_SNAPSHOT')));
INSERT dbo.TicketRules SELECT t.TicketID,c.ChangeAllowed,c.ChangeFee,c.BaggageKg,c.CabinBaggageKg,'LEGACY_CURRENT' FROM dbo.Tickets t JOIN dbo.FareClasses c ON c.FareClassID=t.FareClassID;
CREATE TABLE dbo.BookingChanges(
 ChangeID int IDENTITY CONSTRAINT PK_BookingChanges PRIMARY KEY,BookingID int NOT NULL REFERENCES dbo.Bookings,
 OldSegmentID int NOT NULL CONSTRAINT UQ_ChangeOldSegment UNIQUE REFERENCES dbo.BookingSegments,
 NewSegmentID int NOT NULL CONSTRAINT UQ_ChangeNewSegment UNIQUE REFERENCES dbo.BookingSegments,
 PaymentID int NOT NULL CONSTRAINT UQ_ChangePayment UNIQUE REFERENCES dbo.Payments,
 ChangeFee decimal(14,2) NOT NULL CHECK(ChangeFee>=0),FareDifference decimal(14,2) NOT NULL,
 IdempotencyKey varchar(80) NOT NULL CONSTRAINT UQ_ChangeKey UNIQUE,CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME());
CREATE TABLE dbo.TravelCreditLedger(
 CreditID bigint IDENTITY CONSTRAINT PK_TravelCredits PRIMARY KEY,UserID int NOT NULL REFERENCES dbo.Users,
 PaymentID int NOT NULL CONSTRAINT UQ_CreditPayment UNIQUE REFERENCES dbo.Payments,
 Amount decimal(14,2) NOT NULL,CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME());
CREATE INDEX IX_Credit_User ON dbo.TravelCreditLedger(UserID,CreditID);
CREATE TABLE dbo.LoyaltySpends(
 BookingID int CONSTRAINT PK_LoyaltySpends PRIMARY KEY REFERENCES dbo.Bookings,UserID int NOT NULL REFERENCES dbo.Users,
 Points int NOT NULL CHECK(Points>0),Amount decimal(14,2) NOT NULL CHECK(Amount>0));
GO
CREATE OR ALTER TRIGGER dbo.tr_Ticket_RulesSnapshot ON dbo.Tickets AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.TicketRules
 SELECT i.TicketID,c.ChangeAllowed,c.ChangeFee,c.BaggageKg,c.CabinBaggageKg,'ISSUED_SNAPSHOT'
 FROM inserted i JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=i.BookingPassengerID JOIN dbo.FareClasses c ON c.FareClassID=COALESCE(i.FareClassID,bp.FareClassID);
END;
GO
CREATE OR ALTER VIEW dbo.vw_LoyaltySummary AS
SELECT u.UserID,CONVERT(int,COALESCE(l.Points,0)) Points,
 CONVERT(int,CASE WHEN COALESCE(l.Points,0)-COALESCE(s.Points,0)<0 THEN 0 ELSE COALESCE(l.Points,0)-COALESCE(s.Points,0) END) AvailablePoints,t.TierCode,t.Name TierName
FROM dbo.Users u OUTER APPLY(SELECT SUM(Points) Points FROM dbo.LoyaltyLedger WHERE UserID=u.UserID) l
OUTER APPLY(SELECT SUM(x.Points) Points FROM dbo.LoyaltySpends x JOIN dbo.Bookings b ON b.BookingID=x.BookingID WHERE x.UserID=u.UserID AND (b.Status='CONFIRMED' OR (b.Status='HELD' AND b.ExpiresAt>SYSUTCDATETIME()))) s
CROSS APPLY(SELECT TOP(1) * FROM dbo.LoyaltyTiers WHERE MinimumPoints<=CASE WHEN COALESCE(l.Points,0)<0 THEN 0 ELSE COALESCE(l.Points,0) END ORDER BY MinimumPoints DESC) t;
