-- Additive international airport metadata. Existing IDs and ticket prices stay intact.
ALTER TABLE dbo.Airports ADD
 CountryCode char(2) NOT NULL CONSTRAINT DF_Airports_CountryCode DEFAULT 'VN',
 CountryName nvarchar(80) NOT NULL CONSTRAINT DF_Airports_CountryName DEFAULT N'Việt Nam',
 RegionCode varchar(12) NOT NULL CONSTRAINT DF_Airports_Region DEFAULT 'ASIA',
 TimeZoneName nvarchar(64) NOT NULL CONSTRAINT DF_Airports_WindowsZone DEFAULT N'SE Asia Standard Time',
 IanaTimeZone nvarchar(64) NOT NULL CONSTRAINT DF_Airports_IanaZone DEFAULT N'Asia/Ho_Chi_Minh';
GO
ALTER TABLE dbo.Airports ADD CONSTRAINT CK_Airports_Country CHECK(CountryCode NOT LIKE '%[^A-Z]%' AND LEN(CountryName)>0),
 CONSTRAINT CK_Airports_Region CHECK(RegionCode IN ('ASIA','EUROPE','OCEANIA','AMERICAS','MIDDLE_EAST','AFRICA'));
GO
CREATE OR ALTER FUNCTION dbo.fn_FlightLocalDate(@FlightID int) RETURNS date AS
BEGIN
 DECLARE @zone nvarchar(64),@departure datetime2(0);
 SELECT @zone=a.TimeZoneName,@departure=f.DepartureTime FROM dbo.Flights f JOIN dbo.Airports a ON a.AirportID=f.OriginID WHERE f.FlightID=@FlightID;
 RETURN CONVERT(date,(@departure AT TIME ZONE 'UTC') AT TIME ZONE @zone);
END;
GO
CREATE OR ALTER VIEW dbo.vw_FlightAvailability AS
 SELECT f.FlightID,f.FlightNumber,f.AircraftID,f.OriginID,f.DestinationID,
 o.Code OriginCode,o.City OriginCity,d.Code DestinationCode,d.City DestinationCity,
 o.CountryCode OriginCountryCode,o.CountryName OriginCountryName,d.CountryCode DestinationCountryCode,d.CountryName DestinationCountryName,
 d.RegionCode DestinationRegion,o.IanaTimeZone OriginTimeZone,d.IanaTimeZone DestinationTimeZone,
 CONVERT(date,(f.DepartureTime AT TIME ZONE 'UTC') AT TIME ZONE o.TimeZoneName) DepartureDate,
 CONVERT(date,(f.ArrivalTime AT TIME ZONE 'UTC') AT TIME ZONE d.TimeZoneName) ArrivalDate,
 f.DepartureTime,f.ArrivalTime,f.Status,a.Model,l.Name AirlineName,l.Code AirlineCode,
 (SELECT COUNT(*) FROM dbo.AircraftSeats s WHERE s.AircraftID=f.AircraftID AND s.IsActive=1) TotalSeats,
 (SELECT COUNT(*) FROM dbo.AircraftSeats s WHERE s.AircraftID=f.AircraftID AND s.IsActive=1)
 - (SELECT COUNT(*) FROM dbo.FlightSeatAssignments x JOIN dbo.Tickets t ON t.AssignmentID=x.AssignmentID JOIN dbo.BookingPassengers bp ON bp.BookingPassengerID=t.BookingPassengerID JOIN dbo.Bookings b ON b.BookingID=bp.BookingID
     WHERE x.FlightID=f.FlightID AND x.IsActive=1 AND (b.Status='CONFIRMED' OR (b.Status='HELD' AND b.ExpiresAt>SYSUTCDATETIME()))) AvailableSeats,
 (SELECT MIN(ROUND(BasePrice*(1+TaxRate),2)) FROM dbo.FlightFares ff WHERE ff.FlightID=f.FlightID) FromPrice
 FROM dbo.Flights f JOIN dbo.Airports o ON o.AirportID=f.OriginID
 JOIN dbo.Airports d ON d.AirportID=f.DestinationID JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID
 JOIN dbo.Airlines l ON l.AirlineID=a.AirlineID;
GO

DECLARE @definition nvarchar(max)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_CreateItinerary'));
IF @definition IS NULL OR CHARINDEX(N'CONVERT(date,DATEADD(hour,7,DepartureTime)) FROM @s WHERE N=1',@definition)=0
 THROW 51004,N'Unexpected procedure version: sp_CreateItinerary.',1;
SET @definition=REPLACE(@definition,N'CONVERT(date,DATEADD(hour,7,DepartureTime)) FROM @s WHERE N=1',N'dbo.fn_FlightLocalDate(FlightID) FROM @s WHERE N=1');
SET @definition=N'ALTER '+SUBSTRING(@definition,CHARINDEX(N'PROCEDURE',UPPER(@definition)),LEN(@definition));
EXEC sys.sp_executesql @definition;
GO

DECLARE @definition nvarchar(max)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_CreateBooking'));
IF @definition IS NULL OR CHARINDEX(N'CONVERT(date,DATEADD(hour,7,DepartureTime)) FROM dbo.Flights WHERE FlightID=@FlightID',@definition)=0
 THROW 51004,N'Unexpected procedure version: sp_CreateBooking.',1;
SET @definition=REPLACE(@definition,N'CONVERT(date,DATEADD(hour,7,DepartureTime)) FROM dbo.Flights WHERE FlightID=@FlightID',N'dbo.fn_FlightLocalDate(FlightID) FROM dbo.Flights WHERE FlightID=@FlightID');
SET @definition=N'ALTER '+SUBSTRING(@definition,CHARINDEX(N'PROCEDURE',UPPER(@definition)),LEN(@definition));
EXEC sys.sp_executesql @definition;
GO

DECLARE @definition nvarchar(max)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_ExchangeSegment'));
IF @definition IS NULL OR CHARINDEX(N'CONVERT(date,DATEADD(hour,7,@dep))',@definition)=0
 THROW 51004,N'Unexpected procedure version: sp_ExchangeSegment.',1;
SET @definition=REPLACE(@definition,N'CONVERT(date,DATEADD(hour,7,@dep))',N'dbo.fn_FlightLocalDate(@NewFlightID)');
SET @definition=N'ALTER '+SUBSTRING(@definition,CHARINDEX(N'PROCEDURE',UPPER(@definition)),LEN(@definition));
EXEC sys.sp_executesql @definition;
GO
CREATE OR ALTER PROCEDURE dbo.sp_SaveFlight @FlightID int=NULL,@FlightNumber varchar(8),@AircraftID int,@OriginID int,@DestinationID int,@DepartureTime datetime2(0),@ArrivalTime datetime2(0) AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @r int,@PreviousAircraftID int;
  SELECT @PreviousAircraftID=AircraftID FROM dbo.Flights WHERE FlightID=@FlightID;
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
   SELECT OriginID,LAG(DestinationID) OVER(PARTITION BY AircraftID ORDER BY DepartureTime,FlightID) PreviousDestination
   FROM dbo.Flights WHERE AircraftID IN (@AircraftID,@PreviousAircraftID) AND Status<>'CANCELLED'
  ) chain WHERE PreviousDestination<>OriginID)
   THROW 51018,N'Lịch máy bay không liên tục giữa các sân bay. Cần bổ sung chặng định vị phù hợp.',1;
  COMMIT;
  SELECT @FlightID FlightID;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
