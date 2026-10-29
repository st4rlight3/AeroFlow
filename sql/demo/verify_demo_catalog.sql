-- SSMS: choose the configured database before executing. Read-only checks.
-- The fresh baseline already contains schema 017. This file only inspects data.
USE AeroFlow;
GO
SET NOCOUNT ON;

-- Default presentation preset: 2232 managed flights, 62 days, 9 aircraft, 10 airports.
SELECT COUNT(*) ManagedFlights, COUNT(DISTINCT f.AircraftID) ManagedAircraft,
 MIN(CONVERT(date, DATEADD(hour,7,f.DepartureTime))) FirstVietnamDate,
 MAX(CONVERT(date, DATEADD(hour,7,f.DepartureTime))) LastVietnamDate
FROM dbo.Flights f JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID
WHERE a.Registration IN ('DEMO-AF-HAN','DEMO-AF-SGN','DEMO-AF-DAD',
 'DEMO-LS-HAN','DEMO-LS-SGN','DEMO-LS-DAD','DEMO-BA-HAN','DEMO-BA-SGN','DEMO-BA-DAD');

-- Per-route adult Economy Basic ticket price, tax included; optional extras excluded.
SELECT o.Code Origin,d.Code Destination,COUNT(*) Flights,
 MIN(dbo.fn_CalculateTicketPrice(ff.BasePrice,ff.TaxRate)) LowestAdultTotal,
 MAX(dbo.fn_CalculateTicketPrice(ff.BasePrice,ff.TaxRate)) HighestAdultTotal
FROM dbo.Flights f JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID
JOIN dbo.Airports o ON o.AirportID=f.OriginID JOIN dbo.Airports d ON d.AirportID=f.DestinationID
JOIN dbo.FlightFares ff ON ff.FlightID=f.FlightID
JOIN dbo.FareClasses c ON c.FareClassID=ff.FareClassID
WHERE a.Model=N'AeroFlow demo 150 • 4 khoang' AND c.Code='UEB'
GROUP BY o.Code,d.Code ORDER BY o.Code,d.Code;

-- Expected: no rows. The next flight must start where this aircraft arrived,
-- with at least 60 minutes between flights, including across calendar days.
-- Fresh baseline rotations are also checked; old installations may contain earlier legacy schedules.
WITH Rotation AS (
 SELECT a.Registration,f.FlightNumber,f.DepartureTime,f.OriginID,
 LAG(f.DestinationID) OVER(PARTITION BY f.AircraftID ORDER BY f.DepartureTime) PreviousDestination,
 LAG(f.ArrivalTime) OVER(PARTITION BY f.AircraftID ORDER BY f.DepartureTime) PreviousArrival
 FROM dbo.Flights f JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID
 WHERE a.Model=N'AeroFlow demo 150 • 4 khoang' OR a.Registration IN ('VN-AF1','VN-AF3')
)
SELECT * FROM Rotation WHERE PreviousDestination<>OriginID
 OR DATEDIFF(minute,PreviousArrival,DepartureTime)<60;

-- Expected: no rows. SQL Server also enforces this using a filtered unique index.
SELECT FlightID,SeatID,COUNT(*) ActiveOwners FROM dbo.FlightSeatAssignments
WHERE IsActive=1 GROUP BY FlightID,SeatID HAVING COUNT(*)>1;

-- Expected: no rows for constraint violations.
DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;
GO
