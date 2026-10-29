USE AeroFlow;
GO
-- 05_views - Final definitions, including all historical dynamic patches.
-- Complete schema. Install into a new, empty database.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- dbo.vw_FlightAvailability
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vw_FlightAvailability AS
 SELECT f.FlightID,f.FlightNumber,f.AircraftID,f.OriginID,f.DestinationID,
 o.Code OriginCode,o.City OriginCity,d.Code DestinationCode,d.City DestinationCity,
 o.CountryCode OriginCountryCode,o.CountryName OriginCountryName,d.CountryCode DestinationCountryCode,d.CountryName DestinationCountryName,
 d.RegionCode DestinationRegion,o.IanaTimeZone OriginTimeZone,d.IanaTimeZone DestinationTimeZone,
 CONVERT(date,(f.DepartureTime AT TIME ZONE 'UTC') AT TIME ZONE o.TimeZoneName) DepartureDate,
 CONVERT(date,(f.ArrivalTime AT TIME ZONE 'UTC') AT TIME ZONE d.TimeZoneName) ArrivalDate,
 f.DepartureTime,f.ArrivalTime,f.Status,a.Model,l.Name AirlineName,l.Code AirlineCode,
 (SELECT COUNT(*) FROM dbo.AircraftSeats s WHERE s.AircraftID=f.AircraftID AND s.IsActive=1) TotalSeats,
 (SELECT COUNT(*) FROM dbo.AircraftSeats s WHERE s.AircraftID=f.AircraftID AND s.IsActive=1)
 - (SELECT COUNT(*) FROM dbo.FlightSeatAssignments x JOIN dbo.Tickets t ON t.AssignmentID=x.AssignmentID JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Bookings b ON b.BookingID=bp.BookingID
     WHERE x.FlightID=f.FlightID AND x.IsActive=1 AND (b.Status='CONFIRMED' OR (b.Status='HELD' AND b.ExpiresAt>SYSUTCDATETIME()))) AvailableSeats,
 (SELECT MIN(ROUND(BasePrice*(1+TaxRate),2)) FROM dbo.FlightFares ff WHERE ff.FlightID=f.FlightID) FromPrice
 FROM dbo.Flights f JOIN dbo.Airports o ON o.AirportID=f.OriginID
 JOIN dbo.Airports d ON d.AirportID=f.DestinationID JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID
 JOIN dbo.Airlines l ON l.AirlineID=a.AirlineID;
GO

-- dbo.vw_LoyaltySummary
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vw_LoyaltySummary AS
SELECT u.UserID,CONVERT(int,COALESCE(l.Points,0)) Points,
 CONVERT(int,CASE WHEN COALESCE(l.Points,0)-COALESCE(s.Points,0)<0 THEN 0 ELSE COALESCE(l.Points,0)-COALESCE(s.Points,0) END) AvailablePoints,t.TierCode,t.Name TierName
FROM dbo.Users u OUTER APPLY(SELECT SUM(Points) Points FROM dbo.LoyaltyLedger WHERE UserID=u.UserID) l
OUTER APPLY(SELECT SUM(x.Points) Points FROM dbo.LoyaltySpends x JOIN dbo.Bookings b ON b.BookingID=x.BookingID WHERE x.UserID=u.UserID AND (b.Status='CONFIRMED' OR (b.Status='HELD' AND b.ExpiresAt>SYSUTCDATETIME()))) s
CROSS APPLY(SELECT TOP(1) * FROM dbo.LoyaltyTiers WHERE MinimumPoints<=CASE WHEN COALESCE(l.Points,0)<0 THEN 0 ELSE COALESCE(l.Points,0) END ORDER BY MinimumPoints DESC) t;
GO

-- dbo.vw_MonthlyRevenue
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vw_MonthlyRevenue AS
 SELECT YEAR(CreatedAt) [Year],MONTH(CreatedAt) [Month],
 SUM(CASE WHEN Kind='CHARGE' THEN Amount ELSE 0 END) GrossRevenue,
 SUM(CASE WHEN Kind='REFUND' THEN Amount ELSE 0 END) Refunds,
 SUM(CASE WHEN Kind='CHARGE' THEN Amount ELSE -Amount END) NetRevenue,
 SUM(CASE WHEN Kind='CHARGE' THEN 1 ELSE 0 END) PaidBookings
 FROM dbo.Payments WHERE Status='SUCCESS' GROUP BY YEAR(CreatedAt),MONTH(CreatedAt);
GO

-- dbo.vw_BookingDetails
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- Keep the original Bookings.FlightID as history; present the first current segment.
CREATE OR ALTER VIEW dbo.vw_BookingDetails AS
 SELECT b.BookingID,b.PNR,b.UserID,COALESCE(currentLeg.FlightID,b.FlightID) FlightID,b.Status,b.CreatedAt,b.ExpiresAt,b.JourneyType,
 (SELECT COUNT(*) FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID AND s.Status<>'EXCHANGED') SegmentCount,
 u.FullName CustomerName,u.Email,f.FlightNumber,f.OriginCode,f.DestinationCode,f.DepartureTime,f.ArrivalTime,
 CASE WHEN b.Status IN ('HELD','EXPIRED') OR NOT EXISTS(SELECT 1 FROM dbo.Payments px WHERE px.BookingID=b.BookingID AND px.Kind='CHARGE' AND px.Status='SUCCESS')
 THEN COALESCE((SELECT SUM(dbo.fn_TicketPaidValue(t.TicketID)) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=b.BookingID),0)
 ELSE COALESCE((SELECT SUM(Amount) FROM dbo.Payments WHERE BookingID=b.BookingID AND Kind='CHARGE' AND Status='SUCCESS'),0) END TotalAmount,
 (SELECT COUNT(*) FROM dbo.BookingPassengers p WHERE p.BookingID=b.BookingID) PassengerCount
 FROM dbo.Bookings b JOIN dbo.Users u ON u.UserID=b.UserID
 OUTER APPLY(SELECT TOP(1) s.FlightID FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID AND s.Status<>'EXCHANGED' ORDER BY s.SegmentOrder) currentLeg
 JOIN dbo.vw_FlightAvailability f ON f.FlightID=COALESCE(currentLeg.FlightID,b.FlightID);
GO

-- dbo.vw_FlightOccupancy
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vw_FlightOccupancy AS
 SELECT f.FlightID,f.FlightNumber,f.DepartureTime,f.TotalSeats,
 (SELECT COUNT(*) FROM dbo.FlightSeatAssignments x JOIN dbo.Tickets t ON t.AssignmentID=x.AssignmentID WHERE x.FlightID=f.FlightID AND x.IsActive=1 AND t.Status='VALID') SoldSeats
 FROM dbo.vw_FlightAvailability f;
GO

-- dbo.vw_ItinerarySegments
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vw_ItinerarySegments AS
 SELECT s.BookingSegmentID,s.BookingID,s.SegmentOrder,s.JourneyGroup,s.Status SegmentStatus,
 f.FlightID,f.FlightNumber,f.OriginCode,f.DestinationCode,f.OriginCity,f.DestinationCity,
 f.DepartureTime,f.ArrivalTime,f.Status FlightStatus,f.AirlineName,f.AircraftID
 FROM dbo.BookingSegments s JOIN dbo.vw_FlightAvailability f ON f.FlightID=s.FlightID;
GO
