-- Additive foundation. The runner owns the transaction and migration ledger.
IF OBJECT_ID('dbo.Bookings') IS NULL THROW 51100, 'Initialize the original AeroFlow schema first.', 1;
ALTER TABLE dbo.Bookings ADD JourneyType varchar(12) NOT NULL
 CONSTRAINT DF_Bookings_Journey DEFAULT 'ONE_WAY'
 CONSTRAINT CK_Bookings_Journey CHECK(JourneyType IN ('ONE_WAY','ROUND_TRIP','MULTI_CITY'));
CREATE TABLE dbo.BookingSegments (
 BookingSegmentID int IDENTITY CONSTRAINT PK_BookingSegments PRIMARY KEY,
 BookingID int NOT NULL CONSTRAINT FK_Segments_Booking REFERENCES dbo.Bookings,
 SegmentOrder int NOT NULL CONSTRAINT CK_Segments_Order CHECK(SegmentOrder BETWEEN 1 AND 12),
 JourneyGroup int NOT NULL CONSTRAINT DF_Segments_Group DEFAULT 1 CONSTRAINT CK_Segments_Group CHECK(JourneyGroup BETWEEN 1 AND 6),
 FlightID int NOT NULL CONSTRAINT FK_Segments_Flight REFERENCES dbo.Flights,
 Status varchar(12) NOT NULL CONSTRAINT DF_Segments_Status DEFAULT 'ACTIVE'
 CONSTRAINT CK_Segments_Status CHECK(Status IN ('ACTIVE','CANCELLED','EXCHANGED')),
 CONSTRAINT UQ_Segments_Order UNIQUE(BookingID,SegmentOrder),
 CONSTRAINT UQ_Segments_BookingKey UNIQUE(BookingSegmentID,BookingID)
);
CREATE INDEX IX_Segments_Flight ON dbo.BookingSegments(FlightID,Status) INCLUDE(BookingID);
INSERT dbo.BookingSegments(BookingID,SegmentOrder,JourneyGroup,FlightID,Status)
 SELECT BookingID,1,1,FlightID,CASE WHEN Status IN ('CANCELLED','EXPIRED') THEN 'CANCELLED' ELSE 'ACTIVE' END FROM dbo.Bookings;
GO
-- Compatibility bridge: original procedure inserts still get an atomic segment row.
CREATE OR ALTER TRIGGER dbo.tr_Bookings_Segments ON dbo.Bookings AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.BookingSegments(BookingID,SegmentOrder,JourneyGroup,FlightID,Status)
 SELECT i.BookingID,1,1,i.FlightID,CASE WHEN i.Status IN ('CANCELLED','EXPIRED') THEN 'CANCELLED' ELSE 'ACTIVE' END
 FROM inserted i WHERE NOT EXISTS(SELECT 1 FROM dbo.BookingSegments s WHERE s.BookingID=i.BookingID);
 UPDATE s SET Status='CANCELLED' FROM dbo.BookingSegments s JOIN inserted i ON i.BookingID=s.BookingID
 WHERE i.Status IN ('CANCELLED','EXPIRED') AND s.Status='ACTIVE';
END;
GO
CREATE OR ALTER VIEW dbo.vw_ItinerarySegments AS
 SELECT s.BookingSegmentID,s.BookingID,s.SegmentOrder,s.JourneyGroup,s.Status SegmentStatus,
 f.FlightID,f.FlightNumber,f.OriginCode,f.DestinationCode,f.OriginCity,f.DestinationCity,
 f.DepartureTime,f.ArrivalTime,f.Status FlightStatus,f.AirlineName,f.AircraftID
 FROM dbo.BookingSegments s JOIN dbo.vw_FlightAvailability f ON f.FlightID=s.FlightID;
