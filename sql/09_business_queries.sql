USE AeroFlow;
GO
-- Q01 SELECT *: catalog of Vietnamese airports.
SELECT * FROM dbo.Airports ORDER BY Code;
-- Q02 INNER JOIN: flight routes and aircraft.
SELECT f.FlightNumber,o.City Origin,d.City Destination,a.Registration FROM dbo.Flights f
INNER JOIN dbo.Airports o ON o.AirportID=f.OriginID INNER JOIN dbo.Airports d ON d.AirportID=f.DestinationID
INNER JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID;
-- Q03 LEFT JOIN: include customers with zero bookings.
SELECT u.UserID,u.FullName,COUNT(b.BookingID) BookingCount FROM dbo.Users u LEFT JOIN dbo.Bookings b ON b.UserID=u.UserID GROUP BY u.UserID,u.FullName;
-- Q04 RIGHT JOIN: include airports without departures.
SELECT a.Code,COUNT(f.FlightID) Departures FROM dbo.Flights f RIGHT JOIN dbo.Airports a ON a.AirportID=f.OriginID GROUP BY a.Code;
-- Q05 FULL OUTER JOIN: reconcile arrival/departure totals by airport.
WITH departures AS(SELECT OriginID AirportID,COUNT(*) N FROM dbo.Flights GROUP BY OriginID),
arrivals AS(SELECT DestinationID AirportID,COUNT(*) N FROM dbo.Flights GROUP BY DestinationID)
SELECT COALESCE(d.AirportID,a.AirportID) AirportID,COALESCE(d.N,0) Departures,COALESCE(a.N,0) Arrivals
FROM departures d FULL OUTER JOIN arrivals a ON a.AirportID=d.AirportID;
-- Q06 GROUP BY + HAVING: routes with at least ten flights.
SELECT OriginID,DestinationID,COUNT(*) Flights FROM dbo.Flights GROUP BY OriginID,DestinationID HAVING COUNT(*)>=10;
-- Q07 Scalar subquery: fares above average.
SELECT * FROM dbo.FlightFares WHERE BasePrice>(SELECT AVG(BasePrice) FROM dbo.FlightFares);
-- Q08 Table subquery: repeat customers including subquery grouped result.
SELECT u.FullName,s.N FROM dbo.Users u JOIN(SELECT UserID,COUNT(*) N FROM dbo.Bookings GROUP BY UserID) s ON s.UserID=u.UserID WHERE s.N>=1;
-- Q09 UNION: all airports served.
SELECT OriginID AirportID FROM dbo.Flights UNION SELECT DestinationID FROM dbo.Flights;
-- Q10 INTERSECT: airports that both receive and depart.
SELECT OriginID AirportID FROM dbo.Flights INTERSECT SELECT DestinationID FROM dbo.Flights;
-- Q11 EXCEPT: airports with no outbound service.
SELECT AirportID FROM dbo.Airports EXCEPT SELECT OriginID FROM dbo.Flights;
-- Q12 LIKE: customer lookup by Vietnamese name.
SELECT UserID,FullName,Email FROM dbo.Users WHERE FullName LIKE N'%mẫu%';
-- Q13 BETWEEN: inclusive price range, exact decimal amounts.
SELECT * FROM dbo.FlightFares WHERE BasePrice BETWEEN 1000000 AND 2000000;
-- Q14 TOP / PERCENT: highest priced decile (ties deliberately included).
SELECT TOP(10) PERCENT WITH TIES * FROM dbo.FlightFares ORDER BY BasePrice DESC;
-- Q15 Real dashboard view: cash-basis revenue net of successful refunds.
SELECT * FROM dbo.vw_MonthlyRevenue ORDER BY [Year],[Month];
-- Q16 Both user-defined functions in useful queries.
SELECT FlightID,FareClassID,dbo.fn_CalculateTicketPrice(BasePrice,TaxRate) TotalPrice FROM dbo.FlightFares;
SELECT TOP(10) FlightID,FlightNumber,dbo.fn_GetFlightOccupancyRate(FlightID) OccupancyPercent FROM dbo.Flights ORDER BY FlightID;
-- Q17 Parameterized procedure example, calendar dates interpreted as UTC report days.
DECLARE @start date=DATEADD(day,-30,CONVERT(date,SYSUTCDATETIME())),@end date=CONVERT(date,SYSUTCDATETIME());
EXEC dbo.sp_GetRevenueReport @start,@end;
-- Q18 Correlated NOT EXISTS: unassigned seats of a selected flight.
DECLARE @flight int=(SELECT MIN(FlightID) FROM dbo.Flights);
SELECT s.SeatNumber FROM dbo.AircraftSeats s JOIN dbo.Flights f ON f.AircraftID=s.AircraftID
WHERE f.FlightID=@flight AND NOT EXISTS(SELECT 1 FROM dbo.FlightSeatAssignments a WHERE a.FlightID=f.FlightID AND a.SeatID=s.SeatID AND a.IsActive=1);
GO
