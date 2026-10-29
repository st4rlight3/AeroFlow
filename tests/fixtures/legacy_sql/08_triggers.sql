USE AeroFlow;
GO
CREATE OR ALTER TRIGGER dbo.tr_Bookings_Audit ON dbo.Bookings AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted b JOIN dbo.BookingPassengers bp ON bp.BookingID=b.BookingID JOIN dbo.Tickets t ON t.BookingPassengerID=bp.BookingPassengerID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID WHERE a.FlightID<>b.FlightID)
  THROW 51004,N'Chuyến bay của đặt chỗ phải khớp với ghế đã cấp.',1;
 INSERT dbo.AuditLogs(ActorID,Entity,EntityID,Action,Details)
 SELECT TRY_CONVERT(int,SESSION_CONTEXT(N'ActorID')),'Bookings',i.BookingID,
 CASE WHEN d.BookingID IS NULL THEN 'CREATE' ELSE 'STATUS_CHANGE' END,
 CONCAT(COALESCE(d.Status,'NEW'),' -> ',i.Status)
 FROM inserted i LEFT JOIN deleted d ON d.BookingID=i.BookingID
 WHERE d.BookingID IS NULL OR d.Status<>i.Status;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_Flights_Audit ON dbo.Flights AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted f JOIN dbo.FlightSeatAssignments a ON a.FlightID=f.FlightID JOIN dbo.AircraftSeats s ON s.SeatID=a.SeatID WHERE s.AircraftID<>f.AircraftID)
  THROW 51011,N'Không được đổi máy bay khi đã cấp ghế.',1;
 INSERT dbo.AuditLogs(ActorID,Entity,EntityID,Action,Details)
 SELECT TRY_CONVERT(int,SESSION_CONTEXT(N'ActorID')),'Flights',i.FlightID,
 CASE WHEN d.FlightID IS NULL THEN 'CREATE' ELSE 'UPDATE' END,
 CONCAT(COALESCE(d.Status,'NEW'),' -> ',i.Status,': ',i.FlightNumber)
 FROM inserted i LEFT JOIN deleted d ON d.FlightID=i.FlightID;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_Assignments_Integrity ON dbo.FlightSeatAssignments AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted a JOIN dbo.Flights f ON f.FlightID=a.FlightID JOIN dbo.AircraftSeats s ON s.SeatID=a.SeatID WHERE s.AircraftID<>f.AircraftID)
  THROW 51004,N'Ghế không thuộc máy bay của chuyến bay.',1;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.AssignmentID=i.AssignmentID WHERE i.FlightID<>d.FlightID OR i.SeatID<>d.SeatID)
  THROW 51011,N'Lịch sử cấp ghế không được thay đổi.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_Tickets_Integrity ON dbo.Tickets AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID
  JOIN dbo.Bookings b ON b.BookingID=bp.BookingID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID
  JOIN dbo.AircraftSeats s ON s.SeatID=a.SeatID JOIN dbo.FareClasses c ON c.FareClassID=bp.FareClassID
  WHERE a.FlightID<>b.FlightID OR s.Cabin<>c.Cabin OR (t.Status='VALID' AND b.Status<>'CONFIRMED'))
  THROW 51004,N'Vé, chuyến bay, ghế và hạng vé không nhất quán.',1;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.TicketID=i.TicketID WHERE i.AssignmentID<>d.AssignmentID OR i.BookingPassengerID<>d.BookingPassengerID OR i.Amount<>d.Amount OR i.RefundPercent<>d.RefundPercent)
  THROW 51011,N'Không sửa liên kết hoặc giá của vé đã tạo.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_Payments_Audit ON dbo.Payments AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.AuditLogs(ActorID,Entity,EntityID,Action,Details)
 SELECT TRY_CONVERT(int,SESSION_CONTEXT(N'ActorID')),'Payments',PaymentID,Kind,CONCAT(Status,': ',Amount) FROM inserted;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_Seats_ImmutableLayout ON dbo.AircraftSeats AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM dbo.Flights f JOIN (SELECT AircraftID FROM inserted UNION SELECT AircraftID FROM deleted) x ON x.AircraftID=f.AircraftID)
  THROW 51011,N'Sơ đồ ghế đã được dùng cho chuyến bay và không thể thay đổi. Tạo máy bay mới để dùng sơ đồ khác.',1;
END;
GO
