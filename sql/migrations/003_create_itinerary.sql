CREATE OR ALTER PROCEDURE dbo.sp_CreateItinerary
 @UserID int,@JourneyType varchar(12),@Segments nvarchar(max),@Passengers nvarchar(max),@Selections nvarchar(max)=N'[]',@ExpectedTotal decimal(14,2)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.sp_LockFlight 0;
  IF NOT EXISTS(SELECT 1 FROM dbo.Users WHERE UserID=@UserID AND IsActive=1) THROW 51002,N'Tài khoản không hoạt động.',1;
  IF @JourneyType NOT IN ('ONE_WAY','ROUND_TRIP','MULTI_CITY') OR @JourneyType IS NULL THROW 51004,N'Loại hành trình không hợp lệ.',1;
  IF ISJSON(@Segments)<>1 OR ISJSON(@Passengers)<>1 OR ISJSON(@Selections)<>1
   OR LEFT(LTRIM(@Segments),1)<>'[' OR LEFT(LTRIM(@Passengers),1)<>'[' OR LEFT(LTRIM(@Selections),1)<>'['
   THROW 51004,N'Dữ liệu hành trình không hợp lệ.',1;
  DECLARE @s TABLE(N int PRIMARY KEY,FlightID int,GroupID int,FareClassID int,OriginID int,DestinationID int,DepartureTime datetime2(0),ArrivalTime datetime2(0));
  INSERT @s SELECT CONVERT(int,j.[key])+1,x.FlightID,x.JourneyGroup,x.FareClassID,f.OriginID,f.DestinationID,f.DepartureTime,f.ArrivalTime
   FROM OPENJSON(@Segments) j CROSS APPLY OPENJSON(j.value) WITH(FlightID int,JourneyGroup int,FareClassID int) x LEFT JOIN dbo.Flights f ON f.FlightID=x.FlightID;
  DECLARE @count int=(SELECT COUNT(*) FROM @s);
  IF @count NOT BETWEEN 1 AND 12 OR EXISTS(SELECT 1 FROM @s WHERE OriginID IS NULL OR GroupID IS NULL OR FareClassID IS NULL OR GroupID NOT BETWEEN 1 AND 6)
   OR (SELECT COUNT(DISTINCT FlightID) FROM @s)<>@count THROW 51004,N'Cần từ 1 đến 12 chặng bay hợp lệ, không lặp chuyến.',1;
  IF (SELECT GroupID FROM @s WHERE N=1)<>1 OR EXISTS(SELECT 1 FROM @s a JOIN @s b ON b.N=a.N+1 WHERE b.GroupID<a.GroupID OR b.GroupID>a.GroupID+1)
   THROW 51004,N'Thứ tự nhóm hành trình không hợp lệ.',1;
  IF (@JourneyType='ONE_WAY' AND (SELECT MAX(GroupID) FROM @s)<>1) OR (@JourneyType='ROUND_TRIP' AND (SELECT MAX(GroupID) FROM @s)<>2)
   OR (@JourneyType='MULTI_CITY' AND (SELECT MAX(GroupID) FROM @s)<2) THROW 51004,N'Số điểm dừng không khớp loại hành trình.',1;
  IF EXISTS(SELECT 1 FROM @s a JOIN @s b ON b.N=a.N+1 WHERE b.DepartureTime<DATEADD(minute,60,a.ArrivalTime)
   OR (a.GroupID=b.GroupID AND (a.DestinationID<>b.OriginID OR b.DepartureTime>DATEADD(hour,8,a.ArrivalTime))))
   THROW 51004,N'Chặng nối chuyến cần cùng sân bay, thời gian nối từ 60 phút đến 8 giờ. Các chặng phải theo thời gian.',1;
  IF @JourneyType='ROUND_TRIP' AND ((SELECT OriginID FROM @s WHERE N=1)<>(SELECT DestinationID FROM @s WHERE N=@count)
   OR (SELECT TOP(1) DestinationID FROM @s WHERE GroupID=1 ORDER BY N DESC)<>(SELECT TOP(1) OriginID FROM @s WHERE GroupID=2 ORDER BY N))
   THROW 51004,N'Hành trình khứ hồi phải quay về sân bay xuất phát.',1;
  IF EXISTS(SELECT 1 FROM @s s JOIN dbo.Flights f ON f.FlightID=s.FlightID WHERE f.Status<>'SCHEDULED' OR f.DepartureTime<=DATEADD(hour,2,SYSUTCDATETIME()))
   THROW 51003,N'Một chặng đã đóng bán.',1;
  DECLARE @p TABLE(N int PRIMARY KEY,FullName nvarchar(120),DateOfBirth date,DocumentNumber nvarchar(30),TypeCode varchar(8),BP int);
  INSERT @p(N,FullName,DateOfBirth,DocumentNumber,TypeCode)
   SELECT CONVERT(int,j.[key])+1,x.FullName,TRY_CONVERT(date,x.DateOfBirth),x.DocumentNumber,x.TypeCode
   FROM OPENJSON(@Passengers) j CROSS APPLY OPENJSON(j.value) WITH(FullName nvarchar(120),DateOfBirth nvarchar(20),DocumentNumber nvarchar(30),TypeCode varchar(8)) x;
  DECLARE @pcount int=(SELECT COUNT(*) FROM @p),@date date=(SELECT CONVERT(date,DepartureTime) FROM @s WHERE N=1);
  IF @pcount NOT BETWEEN 1 AND 9 OR EXISTS(SELECT 1 FROM @p WHERE FullName IS NULL OR LEN(TRIM(FullName))<2 OR DateOfBirth IS NULL OR DateOfBirth<'19000101' OR DateOfBirth>CONVERT(date,SYSUTCDATETIME()) OR DocumentNumber IS NULL OR LEN(TRIM(DocumentNumber))<5)
   OR (SELECT COUNT(DISTINCT DocumentNumber) FROM @p)<>@pcount THROW 51004,N'Thông tin hành khách thiếu, trùng hoặc sai ngày sinh.',1;
  IF EXISTS(SELECT 1 FROM @p WHERE TypeCode IS NULL OR TypeCode<>CASE WHEN DateOfBirth>DATEADD(year,-2,@date) THEN 'INFANT' WHEN DateOfBirth>DATEADD(year,-12,@date) THEN 'CHILD' ELSE 'ADULT' END)
   OR NOT EXISTS(SELECT 1 FROM @p WHERE TypeCode='ADULT')
   OR (SELECT COUNT(*) FROM @p WHERE TypeCode='INFANT')>(SELECT COUNT(*) FROM @p WHERE TypeCode='ADULT')
   THROW 51004,N'Loại hành khách phải khớp tuổi ngày bay; cần người lớn đi cùng, mỗi người lớn tối đa một em bé.',1;
  DECLARE @x TABLE(P int,S int,SeatID int,PRIMARY KEY(P,S));
  INSERT @x SELECT PassengerIndex+1,SegmentIndex+1,SeatID FROM OPENJSON(@Selections) WITH(PassengerIndex int,SegmentIndex int,SeatID int);
  IF EXISTS(SELECT 1 FROM @x WHERE P NOT BETWEEN 1 AND @pcount OR S NOT BETWEEN 1 AND @count OR SeatID<1) THROW 51004,N'Lựa chọn ghế không hợp lệ.',1;
  DECLARE @i int=1,@f int;
  WHILE @i<=@count BEGIN SELECT @f=FlightID FROM @s WHERE N=@i; EXEC dbo.sp_ExpireFlightHolds @f; SET @i+=1; END;
  DECLARE @pnr char(8)=UPPER(LEFT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),8)),@booking int;
  WHILE EXISTS(SELECT 1 FROM dbo.Bookings WHERE PNR=@pnr) SET @pnr=UPPER(LEFT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),8));
  INSERT dbo.Bookings(PNR,UserID,FlightID,ExpiresAt,JourneyType) SELECT @pnr,@UserID,FlightID,DATEADD(minute,10,SYSUTCDATETIME()),@JourneyType FROM @s WHERE N=1;
  SET @booking=SCOPE_IDENTITY();
  INSERT dbo.BookingSegments(BookingID,SegmentOrder,JourneyGroup,FlightID) SELECT @booking,N,GroupID,FlightID FROM @s WHERE N>1;
  DECLARE @j int=1,@passenger int,@bp int;
  WHILE @j<=@pcount
  BEGIN
   INSERT dbo.Passengers(FullName,DateOfBirth,DocumentNumber) SELECT TRIM(FullName),DateOfBirth,TRIM(DocumentNumber) FROM @p WHERE N=@j;
   SET @passenger=SCOPE_IDENTITY();
   INSERT dbo.BookingPassengers(BookingID,PassengerID,FareClassID) SELECT @booking,@passenger,FareClassID FROM @s WHERE N=1;
   SET @bp=SCOPE_IDENTITY(); UPDATE @p SET BP=@bp WHERE N=@j; SET @j+=1;
  END;
  SET @i=1;
  DECLARE @fare int,@aircraft int,@segment int,@seat int,@cabin varchar(12),@assignment int,@factor decimal(5,4),@type varchar(8),@base decimal(14,2),@tax decimal(14,2),@fee decimal(14,2),@refund decimal(5,2);
  WHILE @i<=@count
  BEGIN
   SELECT @f=s.FlightID,@fare=s.FareClassID,@aircraft=f.AircraftID FROM @s s JOIN dbo.Flights f ON f.FlightID=s.FlightID WHERE s.N=@i;
   SELECT @segment=BookingSegmentID FROM dbo.BookingSegments WHERE BookingID=@booking AND SegmentOrder=@i;
   SET @cabin=NULL; SELECT @cabin=c.Cabin,@refund=c.RefundPercent FROM dbo.FareClasses c JOIN dbo.FlightFares ff ON ff.FareClassID=c.FareClassID AND ff.FlightID=@f WHERE c.FareClassID=@fare;
   IF @cabin IS NULL THROW 51004,N'Hạng vé chưa được mở bán cho chặng.',1;
   SET @j=1;
   WHILE @j<=@pcount
   BEGIN
    SELECT @bp=p.BP,@type=p.TypeCode,@factor=t.PriceFactor FROM @p p JOIN dbo.PassengerTypes t ON t.TypeCode=p.TypeCode WHERE p.N=@j;
    SET @seat=NULL; SELECT @seat=SeatID FROM @x WHERE P=@j AND S=@i;
    IF @seat IS NULL
     SELECT TOP(1) @seat=SeatID FROM dbo.AircraftSeats s WHERE AircraftID=@aircraft AND Cabin=@cabin AND IsActive=1
      AND NOT EXISTS(SELECT 1 FROM dbo.FlightSeatAssignments a WHERE a.FlightID=@f AND a.SeatID=s.SeatID AND a.IsActive=1) ORDER BY SeatFee,RowNumber,ColumnLetter;
    IF @seat IS NULL THROW 51005,N'Không còn đủ ghế cho tất cả hành khách.',1;
    IF NOT EXISTS(SELECT 1 FROM dbo.AircraftSeats WHERE SeatID=@seat AND AircraftID=@aircraft AND Cabin=@cabin AND IsActive=1) THROW 51004,N'Ghế không thuộc máy bay hoặc khoang đã chọn.',1;
    IF EXISTS(SELECT 1 FROM dbo.FlightSeatAssignments WHERE FlightID=@f AND SeatID=@seat AND IsActive=1) THROW 51005,N'Ghế vừa được người khác giữ.',1;
    SELECT @base=ROUND(BasePrice*@factor,2),@tax=ROUND(ROUND(BasePrice*@factor,2)*TaxRate,2) FROM dbo.FlightFares WHERE FlightID=@f AND FareClassID=@fare;
    SELECT @fee=SeatFee FROM dbo.AircraftSeats WHERE SeatID=@seat;
    INSERT dbo.FlightSeatAssignments(FlightID,SeatID) VALUES(@f,@seat); SET @assignment=SCOPE_IDENTITY();
    INSERT dbo.Tickets(AssignmentID,TicketNumber,BookingPassengerID,BookingSegmentID,FareClassID,PassengerType,BaseFare,TaxAmount,SeatFee,BreakdownSource,Amount,RefundPercent)
     VALUES(@assignment,CONCAT('AF',RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),16)),@bp,@segment,@fare,@type,@base,@tax,@fee,'DETAILED',@base+@tax+@fee,@refund);
    SET @j+=1;
   END;
   SET @i+=1;
  END;
  DECLARE @total decimal(14,2)=(SELECT SUM(t.Amount) FROM dbo.Tickets t JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID WHERE bp.BookingID=@booking);
  IF @ExpectedTotal IS NOT NULL AND @ExpectedTotal<>@total THROW 51013,N'Giá hoặc ghế đã thay đổi. Vui lòng kiểm tra lại báo giá.',1;
  COMMIT;
  SELECT * FROM dbo.vw_BookingDetails WHERE BookingID=@booking;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
