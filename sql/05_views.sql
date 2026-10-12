USE AeroFlow;
GO
CREATE OR ALTER VIEW dbo.vw_FlightAvailability AS
 SELECT f.FlightID,f.FlightNumber,f.AircraftID,f.OriginID,f.DestinationID,
 o.Code OriginCode,o.City OriginCity,d.Code DestinationCode,d.City DestinationCity,
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
CREATE OR ALTER VIEW dbo.vw_BookingDetails AS
 SELECT b.BookingID,b.PNR,b.UserID,b.FlightID,b.Status,b.CreatedAt,b.ExpiresAt,
 u.FullName CustomerName,u.Email,f.FlightNumber,f.OriginCode,f.DestinationCode,f.DepartureTime,f.ArrivalTime,
 COALESCE((SELECT SUM(t.Amount) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=b.BookingID),0) TotalAmount,
 (SELECT COUNT(*) FROM dbo.BookingPassengers p WHERE p.BookingID=b.BookingID) PassengerCount
 FROM dbo.Bookings b JOIN dbo.Users u ON u.UserID=b.UserID JOIN dbo.vw_FlightAvailability f ON f.FlightID=b.FlightID;
GO
CREATE OR ALTER VIEW dbo.vw_MonthlyRevenue AS
 SELECT YEAR(CreatedAt) [Year],MONTH(CreatedAt) [Month],
 SUM(CASE WHEN Kind='CHARGE' THEN Amount ELSE 0 END) GrossRevenue,
 SUM(CASE WHEN Kind='REFUND' THEN Amount ELSE 0 END) Refunds,
 SUM(CASE WHEN Kind='CHARGE' THEN Amount ELSE -Amount END) NetRevenue,
 SUM(CASE WHEN Kind='CHARGE' THEN 1 ELSE 0 END) PaidBookings
 FROM dbo.Payments WHERE Status='SUCCESS' GROUP BY YEAR(CreatedAt),MONTH(CreatedAt);
GO
CREATE OR ALTER VIEW dbo.vw_FlightOccupancy AS
 SELECT f.FlightID,f.FlightNumber,f.DepartureTime,f.TotalSeats,
 (SELECT COUNT(*) FROM dbo.FlightSeatAssignments x JOIN dbo.Tickets t ON t.AssignmentID=x.AssignmentID WHERE x.FlightID=f.FlightID AND x.IsActive=1 AND t.Status='VALID') SoldSeats
 FROM dbo.vw_FlightAvailability f;
GO
