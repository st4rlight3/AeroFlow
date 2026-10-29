USE AeroFlow;
GO
-- 08_triggers - Final definitions, including all historical dynamic patches.
-- Consolidated schema through migration 017. For a NEW database only.
-- Existing installations use scripts/migrate.py and the unchanged sql/migrations history.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- dbo.tr_Assignments_Integrity
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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

-- dbo.tr_Booking_Notifications
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER TRIGGER dbo.tr_Booking_Notifications ON dbo.Bookings AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Notifications(UserID,BookingID,Title,Message)
 SELECT i.UserID,i.BookingID,N'Trạng thái đặt chỗ',CONCAT(N'Đặt chỗ ',i.PNR,N': ',i.Status,N'. Xem chi tiết trong Chuyến đi của tôi.')
 FROM inserted i LEFT JOIN deleted d ON d.BookingID=i.BookingID WHERE d.BookingID IS NULL OR i.Status<>d.Status;
END;
GO

-- dbo.tr_Bookings_Audit
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER TRIGGER dbo.tr_Bookings_Audit ON dbo.Bookings AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted b JOIN dbo.BookingPassengers bp ON bp.BookingID=b.BookingID JOIN dbo.Tickets t ON t.BookingPassengerID=bp.BookingPassengerID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID LEFT JOIN dbo.BookingSegments seg ON seg.BookingSegmentID=t.BookingSegmentID WHERE a.FlightID<>COALESCE(seg.FlightID,b.FlightID))
  THROW 51004,N'Chuyến bay của đặt chỗ phải khớp với ghế đã cấp.',1;
 INSERT dbo.AuditLogs(ActorID,Entity,EntityID,Action,Details)
 SELECT TRY_CONVERT(int,SESSION_CONTEXT(N'ActorID')),'Bookings',i.BookingID,
 CASE WHEN d.BookingID IS NULL THEN 'CREATE' ELSE 'STATUS_CHANGE' END,
 CONCAT(COALESCE(d.Status,'NEW'),' -> ',i.Status)
 FROM inserted i LEFT JOIN deleted d ON d.BookingID=i.BookingID
 WHERE d.BookingID IS NULL OR d.Status<>i.Status;
END;
GO

-- dbo.tr_Bookings_Segments
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER TRIGGER dbo.tr_Bookings_Segments ON dbo.Bookings AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.BookingSegments(BookingID,SegmentOrder,JourneyGroup,FlightID,Status)
 SELECT i.BookingID,1,1,i.FlightID,CASE WHEN i.Status IN ('CANCELLED','EXPIRED') THEN 'CANCELLED' ELSE 'ACTIVE' END
 FROM inserted i WHERE NOT EXISTS(SELECT 1 FROM dbo.BookingSegments s WHERE s.BookingID=i.BookingID);
 UPDATE s SET Status='CANCELLED' FROM dbo.BookingSegments s JOIN inserted i ON i.BookingID=s.BookingID
 WHERE i.Status IN ('CANCELLED','EXPIRED') AND s.Status='ACTIVE';
END;
GO

-- dbo.tr_Flight_CustomerEvents
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER TRIGGER dbo.tr_Flight_CustomerEvents ON dbo.Flights AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Notifications(UserID,BookingID,Title,Message)
 SELECT DISTINCT b.UserID,b.BookingID,N'Cập nhật chuyến bay',CONCAT(i.FlightNumber,N': ',i.Status,N'; cửa ',COALESCE(i.Gate,N'chưa công bố'),N'; ',COALESCE(i.OperationNote,N''))
 FROM inserted i JOIN deleted d ON d.FlightID=i.FlightID JOIN dbo.BookingSegments s ON s.FlightID=i.FlightID
 JOIN dbo.Bookings b ON b.BookingID=s.BookingID
 WHERE b.Status IN ('HELD','CONFIRMED') AND
 (i.Status<>d.Status OR ISNULL(i.Gate,'')<>ISNULL(d.Gate,'') OR ISNULL(i.EstimatedDeparture,'19000101')<>ISNULL(d.EstimatedDeparture,'19000101') OR ISNULL(i.OperationNote,'')<>ISNULL(d.OperationNote,''));
END;
GO

-- dbo.tr_Flights_Audit
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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

-- dbo.tr_Payment_CustomerEvents
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER TRIGGER dbo.tr_Payment_CustomerEvents ON dbo.Payments AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Notifications(UserID,BookingID,Title,Message,EventKey)
 SELECT b.UserID,i.BookingID,N'Giao dịch đặt chỗ',CONCAT(N'Mã ',b.PNR,N': ',i.Kind,N' / ',i.Status,N' — ',i.Amount,N' VND. Thanh toán mô phỏng.'),CONCAT('payment:',i.PaymentID)
 FROM inserted i JOIN dbo.Bookings b ON b.BookingID=i.BookingID;
 -- New successful charges earn 1 point / 10,000 VND. Refunds reverse at most
 -- points already awarded for that booking; legacy payments get no retroactive award.
 INSERT dbo.LoyaltyLedger(UserID,PaymentID,Points,Reason)
 SELECT b.UserID,i.PaymentID,CASE WHEN i.Kind='CHARGE' THEN CONVERT(int,FLOOR(i.Amount/10000))
 ELSE -CONVERT(int,CASE WHEN COALESCE(l.Points,0)<CEILING(i.Amount/10000) THEN COALESCE(l.Points,0) ELSE CEILING(i.Amount/10000) END) END,
 CASE WHEN i.Kind='CHARGE' THEN N'Tích điểm thanh toán' ELSE N'Điều chỉnh hoàn tiền' END
 FROM inserted i JOIN dbo.Bookings b ON b.BookingID=i.BookingID
 OUTER APPLY(SELECT SUM(ll.Points) Points FROM dbo.LoyaltyLedger ll JOIN dbo.Payments p ON p.PaymentID=ll.PaymentID WHERE p.BookingID=i.BookingID) l
 WHERE i.Status='SUCCESS';
END;
GO

-- dbo.tr_Payments_Audit
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER TRIGGER dbo.tr_Payments_Audit ON dbo.Payments AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.AuditLogs(ActorID,Entity,EntityID,Action,Details)
 SELECT TRY_CONVERT(int,SESSION_CONTEXT(N'ActorID')),'Payments',PaymentID,Kind,CONCAT(Status,': ',Amount) FROM inserted;
END;
GO

-- dbo.tr_Seats_ImmutableLayout
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER TRIGGER dbo.tr_Seats_ImmutableLayout ON dbo.AircraftSeats AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i FULL JOIN deleted d ON d.SeatID=i.SeatID
 WHERE EXISTS(SELECT 1 FROM dbo.Flights f WHERE f.AircraftID IN (i.AircraftID,d.AircraftID))
 AND (i.SeatID IS NULL OR d.SeatID IS NULL OR i.AircraftID<>d.AircraftID OR i.SeatNumber<>d.SeatNumber OR i.RowNumber<>d.RowNumber OR i.ColumnLetter<>d.ColumnLetter OR i.Cabin<>d.Cabin OR i.IsActive<>d.IsActive))
 THROW 51011,N'Không thay đổi sơ đồ đã có chuyến bay. Phí chọn ghế chỉ áp dụng cho vé mới.',1;
END;
GO

-- dbo.tr_Ticket_RevokeCheckIn
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER TRIGGER dbo.tr_Ticket_RevokeCheckIn ON dbo.Tickets AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 UPDATE c SET Status='REVOKED',RevokedAt=SYSUTCDATETIME() FROM dbo.CheckIns c JOIN inserted t ON t.TicketID=c.TicketID WHERE t.Status<>'VALID' AND c.Status='ACTIVE';
 -- Snapshot values are immutable, including direct SQL updates.
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.TicketID=i.TicketID WHERE i.BaseFare<>d.BaseFare OR i.TaxAmount<>d.TaxAmount OR i.SeatFee<>d.SeatFee OR i.PassengerType<>d.PassengerType OR i.BreakdownSource<>d.BreakdownSource)
 THROW 51011,N'Không sửa ảnh chụp giá vé.',1;
END;
GO

-- dbo.tr_Ticket_RulesSnapshot
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER TRIGGER dbo.tr_Ticket_RulesSnapshot ON dbo.Tickets AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.TicketRules
 SELECT i.TicketID,c.ChangeAllowed,c.ChangeFee,c.BaggageKg,c.CabinBaggageKg,'ISSUED_SNAPSHOT'
 FROM inserted i JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=i.BookingPassengerID JOIN dbo.FareClasses c ON c.FareClassID=COALESCE(i.FareClassID,bp.FareClassID);
END;
GO

-- dbo.tr_Tickets_Integrity
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER TRIGGER dbo.tr_Tickets_Integrity ON dbo.Tickets AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID
  JOIN dbo.Bookings b ON b.BookingID=bp.BookingID JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID
  JOIN dbo.AircraftSeats s ON s.SeatID=a.SeatID LEFT JOIN dbo.BookingSegments seg ON seg.BookingSegmentID=t.BookingSegmentID JOIN dbo.FareClasses c ON c.FareClassID=COALESCE(t.FareClassID,bp.FareClassID)
  WHERE a.FlightID<>COALESCE(seg.FlightID,b.FlightID) OR (seg.BookingID IS NOT NULL AND seg.BookingID<>bp.BookingID) OR s.Cabin<>c.Cabin OR (t.Status='VALID' AND b.Status<>'CONFIRMED'))
  THROW 51004,N'Vé, chuyến bay, ghế và hạng vé không nhất quán.',1;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.TicketID=i.TicketID WHERE i.AssignmentID<>d.AssignmentID OR i.BookingPassengerID<>d.BookingPassengerID OR i.Amount<>d.Amount OR i.RefundPercent<>d.RefundPercent OR (d.BookingSegmentID IS NOT NULL AND i.BookingSegmentID<>d.BookingSegmentID) OR (d.FareClassID IS NOT NULL AND i.FareClassID<>d.FareClassID))
  THROW 51011,N'Không sửa liên kết hoặc giá của vé đã tạo.',1;
 UPDATE t SET BookingSegmentID=COALESCE(t.BookingSegmentID,seg.BookingSegmentID),FareClassID=COALESCE(t.FareClassID,bp.FareClassID)
 FROM dbo.Tickets t JOIN inserted i ON i.TicketID=t.TicketID JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID
 JOIN dbo.BookingSegments seg ON seg.BookingID=bp.BookingID AND seg.SegmentOrder=1
 WHERE t.BookingSegmentID IS NULL OR t.FareClassID IS NULL;
END;
GO
