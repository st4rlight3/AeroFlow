-- Correct local departure age without editing the released migrations 001-014.
-- No historical tickets, bookings or schedules are rewritten.

DECLARE @definition nvarchar(max)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_CreateItinerary'));
IF @definition IS NULL OR CHARINDEX(N'CONVERT(date,DepartureTime) FROM @s WHERE N=1',@definition)=0
 THROW 51004,N'Unexpected procedure version for sp_CreateItinerary; migration stopped.',1;
SET @definition=REPLACE(@definition,N'CONVERT(date,DepartureTime) FROM @s WHERE N=1',N'CONVERT(date,DATEADD(hour,7,DepartureTime)) FROM @s WHERE N=1');
-- SQL Server may normalize CREATE OR ALTER to CREATE with extra whitespace.
SET @definition=N'ALTER '+SUBSTRING(@definition,CHARINDEX(N'PROCEDURE',UPPER(@definition)),LEN(@definition));
EXEC sys.sp_executesql @definition;
GO

DECLARE @definition nvarchar(max)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_CreateBooking'));
IF @definition IS NULL OR CHARINDEX(N'CONVERT(date,DepartureTime) FROM dbo.Flights WHERE FlightID=@FlightID',@definition)=0
 THROW 51004,N'Unexpected procedure version for sp_CreateBooking; migration stopped.',1;
SET @definition=REPLACE(@definition,N'CONVERT(date,DepartureTime) FROM dbo.Flights WHERE FlightID=@FlightID',N'CONVERT(date,DATEADD(hour,7,DepartureTime)) FROM dbo.Flights WHERE FlightID=@FlightID');
-- SQL Server may normalize CREATE OR ALTER to CREATE with extra whitespace.
SET @definition=N'ALTER '+SUBSTRING(@definition,CHARINDEX(N'PROCEDURE',UPPER(@definition)),LEN(@definition));
EXEC sys.sp_executesql @definition;
GO

DECLARE @definition nvarchar(max)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_ExchangeSegment'));
IF @definition IS NULL OR CHARINDEX(N'CONVERT(date,@dep)',@definition)=0
 THROW 51004,N'Unexpected procedure version for sp_ExchangeSegment; migration stopped.',1;
SET @definition=REPLACE(@definition,N'CONVERT(date,@dep)',N'CONVERT(date,DATEADD(hour,7,@dep))');
-- SQL Server may normalize CREATE OR ALTER to CREATE with extra whitespace.
SET @definition=N'ALTER '+SUBSTRING(@definition,CHARINDEX(N'PROCEDURE',UPPER(@definition)),LEN(@definition));
EXEC sys.sp_executesql @definition;
GO

CREATE OR ALTER PROCEDURE dbo.sp_SaveFlight @FlightID int=NULL,@FlightNumber varchar(8),@AircraftID int,@OriginID int,@DestinationID int,@DepartureTime datetime2(0),@ArrivalTime datetime2(0) AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @r int;
  EXEC @r=sys.sp_getapplock @Resource='AeroFlow:schedule',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @r<0 THROW 51001,N'Lịch bay đang được cập nhật.',1;
  IF @FlightID IS NOT NULL
  BEGIN
   EXEC dbo.sp_LockFlight @FlightID;
   IF NOT EXISTS(SELECT 1 FROM dbo.Flights WHERE FlightID=@FlightID AND Status='SCHEDULED') THROW 51010,N'Chỉ sửa chuyến đang mở bán.',1;
   IF EXISTS(SELECT 1 FROM dbo.BookingSegments WHERE FlightID=@FlightID) THROW 51011,N'Chuyến đã có lịch sử đặt vé. Hãy hủy chuyến và tạo chuyến mới nếu cần thay đổi lịch hoặc máy bay.',1;
  END;
  IF @OriginID=@DestinationID OR @ArrivalTime<=@DepartureTime OR @DepartureTime<=SYSUTCDATETIME() THROW 51004,N'Lịch bay không hợp lệ.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Aircraft WHERE AircraftID=@AircraftID AND IsActive=1) OR
    (SELECT COUNT(*) FROM dbo.Airports WHERE AirportID IN (@OriginID,@DestinationID) AND IsActive=1)<>2 THROW 51004,N'Máy bay hoặc sân bay không hoạt động.',1;
  IF EXISTS(SELECT 1 FROM dbo.Flights WITH(UPDLOCK,HOLDLOCK) WHERE AircraftID=@AircraftID AND Status<>'CANCELLED' AND FlightID<>COALESCE(@FlightID,0) AND DepartureTime<DATEADD(minute,45,@ArrivalTime) AND ArrivalTime>DATEADD(minute,-45,@DepartureTime))
   THROW 51012,N'Máy bay có lịch trùng hoặc chưa đủ 45 phút quay đầu.',1;
  IF EXISTS(SELECT 1 FROM dbo.Routes WHERE OriginID=@OriginID AND DestinationID=@DestinationID AND IsActive=0) THROW 51003,N'Đường bay đang tạm ngừng khai thác mới.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Routes WHERE OriginID=@OriginID AND DestinationID=@DestinationID) INSERT dbo.Routes(OriginID,DestinationID) VALUES(@OriginID,@DestinationID);
  IF @FlightID IS NULL
  BEGIN
   INSERT dbo.Flights(FlightNumber,AircraftID,OriginID,DestinationID,DepartureTime,ArrivalTime) VALUES(@FlightNumber,@AircraftID,@OriginID,@DestinationID,@DepartureTime,@ArrivalTime);
   SET @FlightID=SCOPE_IDENTITY();
  END
  ELSE UPDATE dbo.Flights SET FlightNumber=@FlightNumber,AircraftID=@AircraftID,OriginID=@OriginID,DestinationID=@DestinationID,DepartureTime=@DepartureTime,ArrivalTime=@ArrivalTime WHERE FlightID=@FlightID;
  -- Validate the complete aircraft chain after the proposed insert/update.
  -- Unpriced flights may represent positioning legs and remain outside public search.
  IF EXISTS(SELECT 1 FROM (
   SELECT OriginID,LAG(DestinationID) OVER(ORDER BY DepartureTime,FlightID) PreviousDestination
   FROM dbo.Flights WHERE AircraftID=@AircraftID AND Status<>'CANCELLED'
  ) chain WHERE PreviousDestination<>OriginID)
   THROW 51018,N'Lịch máy bay không liên tục giữa các sân bay. Cần bổ sung chặng định vị phù hợp.',1;
  COMMIT;
  SELECT @FlightID FlightID;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;