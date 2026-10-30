USE AeroFlow;
GO
SET NOCOUNT ON;
-- Thao tác sai phải bị từ chối; dữ liệu thử được hoàn tác.
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.Airports(Code,Name,City) SELECT TOP(1) Code,N'Trùng mã',N'Kiểm thử' FROM dbo.Airports;
 ROLLBACK; THROW 52000,N'UNIQUE không chặn mã sân bay trùng.',1;
END TRY BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 IF ERROR_NUMBER() NOT IN (2601,2627) THROW;
 PRINT 'PASS UNIQUE';
END CATCH;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.Aircraft(AirlineID,Registration,Model) VALUES(-1,'TEST-FK',N'Kiểm thử');
 ROLLBACK; THROW 52000,N'FOREIGN KEY không chặn hãng không tồn tại.',1;
END TRY BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 IF ERROR_NUMBER()<>547 THROW;
 PRINT 'PASS FOREIGN KEY';
END CATCH;
BEGIN TRY
 BEGIN TRAN;
 UPDATE dbo.FlightFares SET BasePrice=-1 WHERE FlightID=(SELECT MIN(FlightID) FROM dbo.Flights);
 ROLLBACK; THROW 52000,N'CHECK không chặn giá âm.',1;
END TRY BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 IF ERROR_NUMBER()<>547 THROW;
 PRINT 'PASS CHECK';
END CATCH;
DECLARE @before int=(SELECT COUNT(*) FROM dbo.Airports);
BEGIN TRAN;
INSERT dbo.Airports(Code,Name,City) VALUES('ZZZ',N'Hoàn tác',N'Kiểm thử');
ROLLBACK;
IF (SELECT COUNT(*) FROM dbo.Airports)<>@before THROW 52000,N'ROLLBACK không khôi phục dữ liệu.',1;
PRINT 'PASS ROLLBACK';

IF EXISTS(SELECT FlightID,SeatID FROM dbo.FlightSeatAssignments WHERE IsActive=1 GROUP BY FlightID,SeatID HAVING COUNT(*)>1)
 THROW 52000,N'Một ghế đang được cấp cho nhiều vé trên cùng chuyến.',1;
IF EXISTS(SELECT 1 FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID
 JOIN dbo.Bookings b ON b.BookingID=p.BookingID JOIN dbo.BookingSegments s ON s.BookingSegmentID=t.BookingSegmentID
 JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID
 JOIN dbo.AircraftSeats seat ON seat.SeatID=a.SeatID JOIN dbo.Flights f ON f.FlightID=a.FlightID
 JOIN dbo.FareClasses c ON c.FareClassID=t.FareClassID
 WHERE s.BookingID<>p.BookingID OR s.FlightID<>a.FlightID OR seat.AircraftID<>f.AircraftID OR seat.Cabin<>c.Cabin
  OR t.Amount<>t.BaseFare+t.TaxAmount+t.SeatFee
  OR (t.Status='VALID' AND (b.Status<>'CONFIRMED' OR a.IsActive<>1))
  OR (b.Status IN ('EXPIRED','CANCELLED') AND (t.Status<>'VOID' OR a.IsActive<>0)))
 THROW 52000,N'Vé, hành trình, giá hoặc quyền giữ ghế không nhất quán.',1;
IF EXISTS(SELECT 1 FROM dbo.Bookings b WHERE
 (SELECT COUNT(*) FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID) NOT BETWEEN 1 AND 2
 OR NOT EXISTS(SELECT 1 FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID AND s.SegmentOrder=1)
 OR (SELECT COUNT(*) FROM dbo.Tickets t JOIN dbo.BookingPassengers p ON p.BookingPassengerID=t.BookingPassengerID WHERE p.BookingID=b.BookingID)
  <>(SELECT COUNT(*) FROM dbo.BookingPassengers p WHERE p.BookingID=b.BookingID)*(SELECT COUNT(*) FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID))
 THROW 52000,N'Đơn thiếu chặng hoặc thiếu vé của hành khách.',1;
IF EXISTS(SELECT 1 FROM dbo.BookingSegments a JOIN dbo.BookingSegments b ON b.BookingID=a.BookingID AND b.SegmentOrder=2
 JOIN dbo.Flights f ON f.FlightID=a.FlightID JOIN dbo.Flights r ON r.FlightID=b.FlightID
 WHERE a.SegmentOrder=1 AND (f.OriginID<>r.DestinationID OR f.DestinationID<>r.OriginID OR r.DepartureTime<DATEADD(minute,60,f.ArrivalTime)))
 THROW 52000,N'Hành trình khứ hồi không đúng tuyến hoặc thời gian.',1;
IF EXISTS(SELECT 1 FROM dbo.Payments p WHERE p.Status='SUCCESS' AND
 ((p.Kind='CHARGE' AND p.Amount<>(SELECT SUM(t.Amount) FROM dbo.Tickets t JOIN dbo.BookingPassengers x ON x.BookingPassengerID=t.BookingPassengerID WHERE x.BookingID=p.BookingID))
 OR (p.Kind='REFUND' AND p.Amount>COALESCE((SELECT SUM(c.Amount) FROM dbo.Payments c WHERE c.BookingID=p.BookingID AND c.Kind='CHARGE' AND c.Status='SUCCESS'),0))))
 THROW 52000,N'Số tiền thu hoặc hoàn không hợp lệ.',1;
IF EXISTS(SELECT 1 FROM (SELECT AircraftID,DepartureTime,OriginID,
 LAG(ArrivalTime) OVER(PARTITION BY AircraftID ORDER BY DepartureTime) PreviousArrival,
 LAG(DestinationID) OVER(PARTITION BY AircraftID ORDER BY DepartureTime) PreviousDestination
 FROM dbo.Flights WHERE Status<>'CANCELLED') x
 WHERE DepartureTime<DATEADD(minute,45,PreviousArrival) OR OriginID<>PreviousDestination)
 THROW 52000,N'Máy bay trùng lịch hoặc sai sân bay quay đầu.',1;
DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;
PRINT 'PASS tính nhất quán đặt chỗ, khứ hồi, vé, giá, thu hoàn và lịch máy bay.';
GO
