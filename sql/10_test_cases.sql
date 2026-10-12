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
