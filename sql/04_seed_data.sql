USE AeroFlow;
GO
-- Run AFTER 05,06,07,08. Entire seed is atomic. Seed accounts cannot sign in.
SET NOCOUNT ON; SET XACT_ABORT ON;
IF EXISTS(SELECT 1 FROM dbo.Users WHERE Email=N'seed001@aeroflow.example')
BEGIN PRINT 'Seed already installed. Existing data preserved.'; RETURN; END;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.Roles(Name) SELECT 'ADMIN' WHERE NOT EXISTS(SELECT 1 FROM dbo.Roles WHERE Name='ADMIN');
 INSERT dbo.Roles(Name) SELECT 'CUSTOMER' WHERE NOT EXISTS(SELECT 1 FROM dbo.Roles WHERE Name='CUSTOMER');
 INSERT dbo.Airports(Code,Name,City) VALUES
 ('HAN',N'Nội Bài',N'Hà Nội'),('SGN',N'Tân Sơn Nhất',N'TP. Hồ Chí Minh'),('DAD',N'Đà Nẵng',N'Đà Nẵng'),
 ('CXR',N'Cam Ranh',N'Nha Trang'),('PQC',N'Phú Quốc',N'Phú Quốc'),('VCA',N'Cần Thơ',N'Cần Thơ'),
 ('HUI',N'Phú Bài',N'Huế'),('DLI',N'Liên Khương',N'Đà Lạt'),('HPH',N'Cát Bi',N'Hải Phòng'),('VII',N'Vinh',N'Vinh');
 INSERT dbo.Airlines(Code,Name) VALUES('AF',N'AeroFlow Air'),('LS',N'Lotus Sky'),('BA',N'Blue Arc');
 INSERT dbo.FareClasses(Code,Name,Cabin,BaggageKg,RefundPercent) VALUES
 ('ECO',N'Phổ thông tiết kiệm','ECONOMY',7,0),('FLEX',N'Phổ thông linh hoạt','ECONOMY',20,80),('BIZ',N'Thương gia','BUSINESS',30,90);
 DECLARE @n int=1,@air int,@row int,@col int,@uid int,@fid int,@bid int,@seat int,@class int,@json nvarchar(max),@paid bit;
 WHILE @n<=6
 BEGIN
  INSERT dbo.Aircraft(AirlineID,Registration,Model) SELECT AirlineID,CONCAT('VN-AF',@n),CASE WHEN @n%2=0 THEN N'AF-72 • 72 ghế' ELSE N'AF-60 • 60 ghế' END FROM dbo.Airlines WHERE Code=CASE WHEN @n<=2 THEN 'AF' WHEN @n<=4 THEN 'LS' ELSE 'BA' END;
  SET @air=SCOPE_IDENTITY(); SET @row=1;
  WHILE @row<=CASE WHEN @n%2=0 THEN 12 ELSE 10 END
  BEGIN
   SET @col=1;
   WHILE @col<=6
   BEGIN
    INSERT dbo.AircraftSeats(AircraftID,SeatNumber,RowNumber,ColumnLetter,Cabin)
    VALUES(@air,CONCAT(CHAR(64+@col),@row),@row,CHAR(64+@col),CASE WHEN @row>=9 THEN 'BUSINESS' ELSE 'ECONOMY' END);
    SET @col+=1;
   END;
   SET @row+=1;
  END;
  SET @n+=1;
 END;
 SET @n=1;
 WHILE @n<=40
 BEGIN
  INSERT dbo.Users(RoleID,Email,FullName,PasswordHash) SELECT RoleID,CONCAT('seed',RIGHT(CONCAT('000',@n),3),'@aeroflow.example'),CONCAT(N'Khách mẫu ',@n),'!disabled-seed-account!' FROM dbo.Roles WHERE Name='CUSTOMER';
  SET @n+=1;
 END;
 DECLARE @base datetime2(0)=DATEADD(day,2,CONVERT(datetime2(0),CONVERT(date,SYSUTCDATETIME()))),@depart datetime2(0),@origin int,@dest int;
 SET @n=0;
 WHILE @n<120
 BEGIN
  SELECT @air=AircraftID FROM dbo.Aircraft WHERE Registration=CONCAT('VN-AF',(@n%4)+1);
  SELECT @origin=AirportID FROM dbo.Airports WHERE Code=CASE WHEN @n%4=3 THEN 'SGN' ELSE 'HAN' END;
  SELECT @dest=AirportID FROM dbo.Airports WHERE Code=CASE WHEN @n%4 IN (0,1) THEN 'SGN' WHEN @n%4=2 THEN 'DAD' ELSE 'HAN' END;
  SET @depart=DATEADD(hour,2+(@n%4)*3,DATEADD(day,@n/4,@base));
  INSERT dbo.Flights(FlightNumber,AircraftID,OriginID,DestinationID,DepartureTime,ArrivalTime) VALUES(CONCAT('AF',100+@n%4),@air,@origin,@dest,@depart,DATEADD(minute,CASE WHEN @n%4=2 THEN 80 ELSE 125 END,@depart));
  SET @fid=SCOPE_IDENTITY();
  INSERT dbo.FlightFares(FlightID,FareClassID,BasePrice,TaxRate)
   SELECT @fid,FareClassID,CASE Code WHEN 'ECO' THEN 950000 WHEN 'FLEX' THEN 1450000 ELSE 2900000 END+(@n%7)*50000,0.10 FROM dbo.FareClasses;
  SET @n+=1;
 END;
 SET @n=1;
 WHILE @n<=40
 BEGIN
  SELECT @uid=UserID FROM dbo.Users WHERE Email=CONCAT('seed',RIGHT(CONCAT('000',@n),3),'@aeroflow.example');
  SELECT @fid=FlightID,@air=AircraftID FROM dbo.Flights ORDER BY FlightID OFFSET (@n-1) ROWS FETCH NEXT 1 ROW ONLY;
  SELECT @seat=SeatID FROM dbo.AircraftSeats WHERE AircraftID=@air AND SeatNumber='B2';
  SELECT @class=FareClassID FROM dbo.FareClasses WHERE Code=CASE WHEN @n%2=0 THEN 'FLEX' ELSE 'ECO' END;
  SET @json=(SELECT @seat SeatID,@class FareClassID,CONCAT(N'Hành khách mẫu ',@n) FullName,'1998-05-20' DateOfBirth,CONCAT('DEMO',100000+@n) DocumentNumber FOR JSON PATH);
  EXEC dbo.sp_CreateBooking @uid,@fid,@json,@bid OUTPUT;
  SET @paid=CASE WHEN @n%5=0 THEN 0 ELSE 1 END;
  DECLARE @key varchar(80)=CONCAT('seed-payment-',RIGHT(CONCAT('000000',@n),6));
  EXEC dbo.sp_ConfirmPayment @uid,@bid,@key,@paid;
  IF @paid=1
  BEGIN
   IF @n%4=0 EXEC dbo.sp_CancelBooking @uid,@bid;
   -- Historical sales for reporting, all ticket state changes have already used business procedures.
   DECLARE @created datetime2(0)=DATEADD(day,-(@n%28+1),SYSUTCDATETIME());
   UPDATE dbo.Bookings SET CreatedAt=@created,ExpiresAt=DATEADD(minute,10,@created) WHERE BookingID=@bid;
   UPDATE dbo.Payments SET CreatedAt=DATEADD(minute,CASE WHEN Kind='CHARGE' THEN 2 ELSE 5 END,@created) WHERE BookingID=@bid;
  END;
  SET @n+=1;
 END;
 UPDATE dbo.Users SET IsActive=0 WHERE Email LIKE 'seed%@aeroflow.example';
 COMMIT;
 PRINT 'Seed complete: 120 flights, 396 seats, 40 sample customers/bookings/passengers/tickets.';
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
GO
