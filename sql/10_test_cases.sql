USE AeroFlow;
GO
SET NOCOUNT ON;
-- Each test must fail with the expected SQL Server constraint error and leave no rows behind.
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.Airports(Code,Name,City) SELECT TOP(1) Code,N'Duplicate',N'Test' FROM dbo.Airports;
 ROLLBACK;
 THROW 52000,'FAIL UNIQUE: invalid insert accepted',1;
END TRY BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 IF ERROR_NUMBER() NOT IN (2601,2627) THROW;
 PRINT 'PASS UNIQUE';
END CATCH;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.Aircraft(AirlineID,Registration,Model) VALUES(-1,'TEST-FK','Invalid');
 ROLLBACK;
 THROW 52000,'FAIL FK: invalid insert accepted',1;
END TRY BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 IF ERROR_NUMBER()<>547 THROW;
 PRINT 'PASS FOREIGN KEY';
END CATCH;
BEGIN TRY
 BEGIN TRAN;
 UPDATE dbo.FlightFares SET BasePrice=-1 WHERE FlightID=(SELECT MIN(FlightID) FROM dbo.Flights);
 ROLLBACK;
 THROW 52000,'FAIL CHECK: invalid update accepted',1;
END TRY BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 IF ERROR_NUMBER()<>547 THROW;
 PRINT 'PASS CHECK';
END CATCH;
DECLARE @before int=(SELECT COUNT(*) FROM dbo.Airports);
BEGIN TRAN;
INSERT dbo.Airports(Code,Name,City) VALUES('ZZZ',N'Rollback',N'Test');
ROLLBACK;
IF (SELECT COUNT(*) FROM dbo.Airports)<>@before THROW 52000,'FAIL ROLLBACK',1;
PRINT 'PASS ROLLBACK';
IF EXISTS(SELECT FlightID,SeatID FROM dbo.FlightSeatAssignments WHERE IsActive=1 GROUP BY FlightID,SeatID HAVING COUNT(*)>1)
 THROW 52000,'FAIL double booking invariant',1;
IF EXISTS(SELECT 1 FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Bookings b ON b.BookingID=bp.BookingID
 LEFT JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID
 WHERE (t.Status='VALID' AND (b.Status<>'CONFIRMED' OR a.IsActive<>1 OR a.AssignmentID IS NULL)) OR (b.Status IN ('EXPIRED','CANCELLED') AND (t.Status<>'VOID' OR a.IsActive<>0)))
 THROW 52000,'FAIL booking-ticket-seat consistency',1;
DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;
PRINT 'PASS business invariants. Run pytest integration suite for concurrent clients and failure injection.';
GO

-- Aircraft rotation checks. Expected: no rows. The next flight must start where this aircraft arrived,
-- with at least 60 minutes between flights, including across calendar days.
-- Check the sample aircraft and the two aircraft used by the initial seed.
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

-- International rotation checks. Expected: no rows for managed international aircraft.
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
GO
