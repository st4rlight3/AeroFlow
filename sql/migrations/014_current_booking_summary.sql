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
