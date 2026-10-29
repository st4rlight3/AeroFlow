USE AeroFlow;
GO
-- Run AFTER 02,03,06,05,07,08. Includes lookup data and sample reservations.
-- Entire seed is atomic. Seed accounts cannot sign in.
SET NOCOUNT ON; SET XACT_ABORT ON;
IF EXISTS(SELECT 1 FROM dbo.Users WHERE Email=N'seed001@aeroflow.example')
BEGIN PRINT 'Seed already installed. Existing data preserved.'; RETURN; END;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.PassengerTypes(TypeCode,Name,PriceFactor) VALUES
 ('ADULT',N'Người lớn',1),('CHILD',N'Trẻ em',0.75),('INFANT',N'Em bé có ghế riêng',0.1);
 INSERT dbo.LoyaltyTiers(TierCode,Name,MinimumPoints) VALUES
 ('BLUE',N'Blue',0),('SILVER',N'Silver',1000),('GOLD',N'Gold',5000);
 INSERT dbo.Services(Code,Name,Category,UnitPrice,MaxQuantity,RefundPercent) VALUES
 ('BAG10',N'Thêm 10 kg hành lý ký gửi','BAGGAGE',250000,3,80),('MEAL',N'Suất ăn tiêu chuẩn','MEAL',120000,1,0),
 ('VEGMEAL',N'Suất ăn chay','MEAL',120000,1,0),('PRIORITY',N'Ưu tiên lên máy bay','PRIORITY',150000,1,100),('LOUNGE',N'Phòng chờ mô phỏng','LOUNGE',400000,1,100);
 INSERT dbo.DiscountCodes(Code,Kind,Method,Value,MaxDiscount,MinimumSpend,ValidFrom,ValidTo,MaxUses) VALUES
 ('ULTIMATE10','PROMO','PERCENT',10,200000,1000000,SYSUTCDATETIME(),DATEADD(year,1,SYSUTCDATETIME()),10000),
 ('DEMO100K','VOUCHER','FIXED',100000,100000,500000,SYSUTCDATETIME(),DATEADD(year,1,SYSUTCDATETIME()),10000);

 INSERT dbo.Roles(Name) SELECT 'ADMIN' WHERE NOT EXISTS(SELECT 1 FROM dbo.Roles WHERE Name='ADMIN');
 INSERT dbo.Roles(Name) SELECT 'CUSTOMER' WHERE NOT EXISTS(SELECT 1 FROM dbo.Roles WHERE Name='CUSTOMER');
 INSERT dbo.Airports(Code,Name,City) VALUES
 ('HAN',N'Nội Bài',N'Hà Nội'),('SGN',N'Tân Sơn Nhất',N'TP. Hồ Chí Minh'),('DAD',N'Đà Nẵng',N'Đà Nẵng'),
 ('CXR',N'Cam Ranh',N'Nha Trang'),('PQC',N'Phú Quốc',N'Phú Quốc'),('VCA',N'Cần Thơ',N'Cần Thơ'),
 ('HUI',N'Phú Bài',N'Huế'),('DLI',N'Liên Khương',N'Đà Lạt'),('HPH',N'Cát Bi',N'Hải Phòng'),('VII',N'Vinh',N'Vinh');
 INSERT dbo.Airlines(Code,Name) VALUES('AF',N'AeroFlow Air'),('LS',N'Lotus Sky'),('BA',N'Blue Arc');
 INSERT dbo.FareClasses(Code,Name,Cabin,BaggageKg,RefundPercent,Bundle,ChangeAllowed) VALUES
 ('ECO',N'Phổ thông tiết kiệm','ECONOMY',7,0,'BASIC',0),('FLEX',N'Phổ thông linh hoạt','ECONOMY',20,80,'FLEXIBLE',1),('BIZ',N'Thương gia','BUSINESS',30,90,'FLEXIBLE',1);
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
    VALUES(@air,CONCAT(CHAR(64+@col),@row),@row,CHAR(64+@col),CASE WHEN @row<=2 THEN 'BUSINESS' ELSE 'ECONOMY' END);
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
 -- Fresh installations use December for the November presentation. The seed
 -- guard above preserves every existing database, booking and ticket.
 DECLARE @earliest datetime2(0)=DATEADD(day,2,CONVERT(datetime2(0),CONVERT(date,SYSUTCDATETIME())));
 DECLARE @base datetime2(0)=CASE WHEN @earliest<CONVERT(datetime2(0),'20261201',112)
  THEN CONVERT(datetime2(0),'20261201',112) ELSE @earliest END,@depart datetime2(0),@origin int,@dest int;
 SET @n=0;
 WHILE @n<120
 BEGIN
  -- Two aircraft each fly an outbound/return pair, returning to HAN daily.
  SELECT @air=AircraftID FROM dbo.Aircraft WHERE Registration=CASE WHEN @n%4<2 THEN 'VN-AF1' ELSE 'VN-AF3' END;
  SELECT @origin=AirportID FROM dbo.Airports WHERE Code=CASE @n%4 WHEN 1 THEN 'SGN' WHEN 3 THEN 'DAD' ELSE 'HAN' END;
  SELECT @dest=AirportID FROM dbo.Airports WHERE Code=CASE @n%4 WHEN 0 THEN 'SGN' WHEN 2 THEN 'DAD' ELSE 'HAN' END;
  SET @depart=DATEADD(minute,CASE @n%4 WHEN 0 THEN 120 WHEN 1 THEN 330 WHEN 2 THEN 150 ELSE 315 END,DATEADD(day,@n/4,@base));
  INSERT dbo.Flights(FlightNumber,AircraftID,OriginID,DestinationID,DepartureTime,ArrivalTime)
   VALUES(CONCAT('AF',100+@n%4),@air,@origin,@dest,@depart,DATEADD(minute,CASE WHEN @n%4<2 THEN 130 ELSE 85 END,@depart));
  SET @fid=SCOPE_IDENTITY();
  INSERT dbo.FlightFares(FlightID,FareClassID,BasePrice,TaxRate)
   SELECT @fid,FareClassID,CASE Code WHEN 'ECO' THEN 950000 WHEN 'FLEX' THEN 1450000 ELSE 2900000 END+(@n%7)*50000,0.10 FROM dbo.FareClasses;
  SET @n+=1;
 END;
 INSERT dbo.Routes(OriginID,DestinationID) SELECT DISTINCT OriginID,DestinationID FROM dbo.Flights;
 SET @n=1;
 WHILE @n<=40
 BEGIN
  SELECT @uid=UserID FROM dbo.Users WHERE Email=CONCAT('seed',RIGHT(CONCAT('000',@n),3),'@aeroflow.example');
  SELECT @fid=FlightID,@air=AircraftID FROM dbo.Flights ORDER BY FlightID OFFSET (@n-1) ROWS FETCH NEXT 1 ROW ONLY;
  SELECT @seat=SeatID FROM dbo.AircraftSeats WHERE AircraftID=@air AND SeatNumber='B4';
  SELECT @class=FareClassID FROM dbo.FareClasses WHERE Code=CASE WHEN @n%2=0 THEN 'FLEX' ELSE 'ECO' END;
  SET @json=(SELECT @seat SeatID,@class FareClassID,CONCAT(N'Hành khách mẫu ',@n) FullName,'1998-05-20' DateOfBirth,CONCAT('DEMO',100000+@n) DocumentNumber FOR JSON PATH);
  EXEC dbo.sp_CreateBooking @uid,@fid,@json;
  SELECT TOP(1) @bid=BookingID FROM dbo.Bookings WHERE UserID=@uid AND FlightID=@fid ORDER BY BookingID DESC;
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
