USE AeroFlow;
GO
-- Run AFTER 02,03,06,05,07,08. Includes final lookup data and baseline ledger.
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
 -- These versions are INCLUDED in this fresh baseline; they were not replayed.
 INSERT dbo.SchemaMigrations(Version,Name,Checksum) VALUES
 (1,N'BASELINE: 001_booking_segments.sql','a6a8df1d7148a6b183df16f77f59e9455f43d8d06621672ea2e4b52668c25833'),
 (2,N'BASELINE: 002_unified_ticket_core.sql','88a2fd19c888e0225ce67189313be597b424c695ded30104efa72329d559597b'),
 (3,N'BASELINE: 003_create_itinerary.sql','7ea4a35c2fb9db8d7f6f2bc69f00d2767fd1bb5734814802abe975267145dcc6'),
 (4,N'BASELINE: 004_assignment_and_summary.sql','7741e8fd62cc793e550d6ada6107b93dd5e26bb5407f34b824adc928e4ad8f5e'),
 (5,N'BASELINE: 005_customer_operations.sql','db18585bd9232516795dc4291a9a4d2e84ec2cb867f5d696779a68f1da8ff0eb'),
 (6,N'BASELINE: 006_assistance_snapshot.sql','c90e2472edc5789ef442ed1a70c3a7b95654b2388f8f1aa67d1462ef982e24d6'),
 (7,N'BASELINE: 007_services_and_partial_refunds.sql','67a492cd2f9b275b2d30873afea8257900daf2891f34c3764d5421970ede7e97'),
 (8,N'BASELINE: 008_pricing_integration.sql','fc4077c9d8b0f4a3ace3b8dbf6f8f755bee1ad419a6ec5a1b666a58ae9cfa1ae'),
 (9,N'BASELINE: 009_exchange_and_wallet_schema.sql','29084347156b8bb7614bbc834ca04ab9c7e4869b140f895b5679bc7e549d4f22'),
 (10,N'BASELINE: 010_exchange_segment.sql','699102a8b80f4f8c09f64b9817ad67202aa22e9f3e0d6305454f7101600d06e3'),
 (11,N'BASELINE: 011_wallet_points_and_pricing.sql','3f26ac94d7c025529a1e6a1d491b5e8184caa8a6a0fabd04b60860a8f4187442'),
 (12,N'BASELINE: 012_operational_controls.sql','4bbea0dc3fb6b77650ec0cc808c86c2f1015d4a293db6d31e168a46100b5fcf8'),
 (13,N'BASELINE: 013_payment_guard_and_routes.sql','e90fed3dfad7eff8f41056946756a5e8c904a2949381532e85564c3779ec382e'),
 (14,N'BASELINE: 014_current_booking_summary.sql','4c4c699f97d34b37329314664eeafe27e7dffffa69071ed5620fb1501dade433'),
 (15,N'BASELINE: 015_airline_consistency.sql','f3a455eb30c58efa0e1a320bf8eb0c6006556f52fd03323400eee4204565eb3d'),
 (16,N'BASELINE: 016_international_airports.sql','8e06284dfd3822383e72c1aac6218e86f6fdb6700da4636ebee606a2e771e9f9'),
 (17,N'BASELINE: 017_vancouver_timezone.sql','31db4059ac0b8b46bb1463f6fed5a46b6cc4c0bf7fe197194c274435e9d4a46a');
 COMMIT;
 PRINT 'Seed complete: 120 flights, 396 seats, 40 sample customers/bookings/passengers/tickets.';
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
GO
