-- SSMS: choose your AeroFlow database before running this read-only script.
SELECT CountryName,CountryCode,COUNT(*) Airports
FROM dbo.Airports WHERE IsActive=1 GROUP BY CountryName,CountryCode ORDER BY CountryName;

SELECT a.Code,a.City,a.CountryName,a.TimeZoneName,a.IanaTimeZone,
 COUNT(f.FlightID) Departures
FROM dbo.Airports a LEFT JOIN dbo.Flights f ON f.OriginID=a.AirportID
GROUP BY a.Code,a.City,a.CountryName,a.TimeZoneName,a.IanaTimeZone ORDER BY a.CountryName,a.City;

SELECT TOP(100) f.FlightNumber,f.OriginCode,f.DestinationCode,f.OriginTimeZone,f.DestinationTimeZone,
 f.DepartureTime DepartureUTC,f.ArrivalTime ArrivalUTC,f.DepartureDate,f.ArrivalDate,
 DATEDIFF(minute,f.DepartureTime,f.ArrivalTime) DurationMinutes,f.FromPrice
FROM dbo.vw_FlightAvailability f JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID
WHERE a.Registration LIKE 'DEMO-INT-%' ORDER BY f.DepartureTime,f.FlightID;

-- Both checks must return zero rows for managed international aircraft.
WITH Rotation AS (
 SELECT a.Registration,f.FlightNumber,f.OriginID,f.DepartureTime,
  LAG(f.DestinationID) OVER(PARTITION BY f.AircraftID ORDER BY f.DepartureTime,f.FlightID) PreviousDestination,
  LAG(f.ArrivalTime) OVER(PARTITION BY f.AircraftID ORDER BY f.DepartureTime,f.FlightID) PreviousArrival
 FROM dbo.Flights f JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID
 WHERE a.Registration LIKE 'DEMO-INT-%' AND f.Status<>'CANCELLED'
)
SELECT * FROM Rotation WHERE PreviousDestination<>OriginID OR DATEDIFF(minute,PreviousArrival,DepartureTime)<90;

SELECT FlightID,SeatID,COUNT(*) ActiveOwners FROM dbo.FlightSeatAssignments
WHERE IsActive=1 GROUP BY FlightID,SeatID HAVING COUNT(*)>1;
