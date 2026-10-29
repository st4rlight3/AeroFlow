USE AeroFlow;
GO
-- 02 - Final tables, column definitions, primary/unique/check/default constraints.
-- Consolidated schema through migration 017. For a NEW database only.
-- Existing installations use scripts/migrate.py and the unchanged sql/migrations history.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
SET XACT_ABORT ON;
IF EXISTS(SELECT 1 FROM sys.tables WHERE schema_id=SCHEMA_ID('dbo'))
 THROW 51980,N'Consolidated SQL requires an empty database. Use migrations for existing data.',1;
BEGIN TRANSACTION;

CREATE TABLE dbo.[Aircraft] (
 [AircraftID] int IDENTITY(1,1) NOT NULL,
 [AirlineID] int NOT NULL,
 [Registration] varchar(20) NOT NULL,
 [Model] nvarchar(80) NOT NULL,
 [IsActive] bit NOT NULL CONSTRAINT [DF_Aircraft_Active] DEFAULT ((1)),
 CONSTRAINT [PK_Aircraft] PRIMARY KEY CLUSTERED ([AircraftID] ASC),
 CONSTRAINT [UQ_Aircraft_Registration] UNIQUE NONCLUSTERED ([Registration] ASC)
);

CREATE TABLE dbo.[AircraftSeats] (
 [SeatID] int IDENTITY(1,1) NOT NULL,
 [AircraftID] int NOT NULL,
 [SeatNumber] varchar(5) NOT NULL,
 [RowNumber] int NOT NULL,
 [ColumnLetter] char(1) NOT NULL,
 [Cabin] varchar(12) NOT NULL,
 [IsActive] bit NOT NULL CONSTRAINT [DF_Seats_Active] DEFAULT ((1)),
 [SeatFee] decimal(14,2) NOT NULL CONSTRAINT [DF_SeatFee] DEFAULT ((0)),
 [IsPriority] bit NOT NULL CONSTRAINT [DF_SeatPriority] DEFAULT ((0)),
 CONSTRAINT [PK_AircraftSeats] PRIMARY KEY CLUSTERED ([SeatID] ASC),
 CONSTRAINT [UQ_Seats_AircraftKey] UNIQUE NONCLUSTERED ([SeatID] ASC, [AircraftID] ASC),
 CONSTRAINT [UQ_Seats_Number] UNIQUE NONCLUSTERED ([AircraftID] ASC, [SeatNumber] ASC),
 CONSTRAINT [UQ_Seats_Position] UNIQUE NONCLUSTERED ([AircraftID] ASC, [RowNumber] ASC, [ColumnLetter] ASC),
 CONSTRAINT [CK_SeatFee] CHECK ([SeatFee]>=(0) AND [SeatFee]<=(5000000)),
 CONSTRAINT [CK_Seats_Cabin] CHECK ([Cabin]='FIRST' OR [Cabin]='BUSINESS' OR [Cabin]='PREMIUM' OR [Cabin]='ECONOMY'),
 CONSTRAINT [CK_Seats_Column] CHECK ([ColumnLetter]='F' OR [ColumnLetter]='E' OR [ColumnLetter]='D' OR [ColumnLetter]='C' OR [ColumnLetter]='B' OR [ColumnLetter]='A'),
 CONSTRAINT [CK_Seats_Number] CHECK ([SeatNumber]=([ColumnLetter]+CONVERT([varchar](3),[RowNumber]))),
 CONSTRAINT [CK_Seats_Row] CHECK ([RowNumber]>=(1) AND [RowNumber]<=(80))
);

CREATE TABLE dbo.[Airlines] (
 [AirlineID] int IDENTITY(1,1) NOT NULL,
 [Code] char(2) NOT NULL,
 [Name] nvarchar(100) NOT NULL,
 CONSTRAINT [PK_Airlines] PRIMARY KEY CLUSTERED ([AirlineID] ASC),
 CONSTRAINT [UQ_Airlines_Code] UNIQUE NONCLUSTERED ([Code] ASC)
);

CREATE TABLE dbo.[Airports] (
 [AirportID] int IDENTITY(1,1) NOT NULL,
 [Code] char(3) NOT NULL,
 [Name] nvarchar(120) NOT NULL,
 [City] nvarchar(80) NOT NULL,
 [IsActive] bit NOT NULL CONSTRAINT [DF_Airports_Active] DEFAULT ((1)),
 [CountryCode] char(2) NOT NULL CONSTRAINT [DF_Airports_CountryCode] DEFAULT ('VN'),
 [CountryName] nvarchar(80) NOT NULL CONSTRAINT [DF_Airports_CountryName] DEFAULT (N'Việt Nam'),
 [RegionCode] varchar(12) NOT NULL CONSTRAINT [DF_Airports_Region] DEFAULT ('ASIA'),
 [TimeZoneName] nvarchar(64) NOT NULL CONSTRAINT [DF_Airports_WindowsZone] DEFAULT (N'SE Asia Standard Time'),
 [IanaTimeZone] nvarchar(64) NOT NULL CONSTRAINT [DF_Airports_IanaZone] DEFAULT (N'Asia/Ho_Chi_Minh'),
 CONSTRAINT [PK_Airports] PRIMARY KEY CLUSTERED ([AirportID] ASC),
 CONSTRAINT [UQ_Airports_Code] UNIQUE NONCLUSTERED ([Code] ASC),
 CONSTRAINT [CK_Airports_Code] CHECK (NOT [Code] like '%[^A-Z]%'),
 CONSTRAINT [CK_Airports_Country] CHECK (NOT [CountryCode] like '%[^A-Z]%' AND len([CountryName])>(0)),
 CONSTRAINT [CK_Airports_Region] CHECK ([RegionCode]='AFRICA' OR [RegionCode]='MIDDLE_EAST' OR [RegionCode]='AMERICAS' OR [RegionCode]='OCEANIA' OR [RegionCode]='EUROPE' OR [RegionCode]='ASIA')
);

CREATE TABLE dbo.[AuditLogs] (
 [AuditID] bigint IDENTITY(1,1) NOT NULL,
 [ActorID] int NULL,
 [Entity] varchar(40) NOT NULL,
 [EntityID] int NOT NULL,
 [Action] varchar(40) NOT NULL,
 [Details] nvarchar(1000) NULL,
 [CreatedAt] datetime2(0) NOT NULL CONSTRAINT [DF_Audit_Created] DEFAULT (sysutcdatetime()),
 CONSTRAINT [PK_AuditLogs] PRIMARY KEY CLUSTERED ([AuditID] ASC)
);

CREATE TABLE dbo.[BookingChanges] (
 [ChangeID] int IDENTITY(1,1) NOT NULL,
 [BookingID] int NOT NULL,
 [OldSegmentID] int NOT NULL,
 [NewSegmentID] int NOT NULL,
 [PaymentID] int NOT NULL,
 [ChangeFee] decimal(14,2) NOT NULL,
 [FareDifference] decimal(14,2) NOT NULL,
 [IdempotencyKey] varchar(80) NOT NULL,
 [CreatedAt] datetime2(0) NOT NULL CONSTRAINT [DF_BookingChanges_CreatedAt_f8d53ef5] DEFAULT (sysutcdatetime()),
 CONSTRAINT [PK_BookingChanges] PRIMARY KEY CLUSTERED ([ChangeID] ASC),
 CONSTRAINT [UQ_ChangeKey] UNIQUE NONCLUSTERED ([IdempotencyKey] ASC),
 CONSTRAINT [UQ_ChangeNewSegment] UNIQUE NONCLUSTERED ([NewSegmentID] ASC),
 CONSTRAINT [UQ_ChangeOldSegment] UNIQUE NONCLUSTERED ([OldSegmentID] ASC),
 CONSTRAINT [UQ_ChangePayment] UNIQUE NONCLUSTERED ([PaymentID] ASC),
 CONSTRAINT [CK_BookingChanges___ChangeFee____0___b0a9a428] CHECK ([ChangeFee]>=(0))
);

CREATE TABLE dbo.[BookingDiscounts] (
 [BookingID] int NOT NULL,
 [DiscountCodeID] int NOT NULL,
 [Code] varchar(30) NOT NULL,
 [Amount] decimal(14,2) NOT NULL,
 CONSTRAINT [PK_BookingDiscounts] PRIMARY KEY CLUSTERED ([BookingID] ASC),
 CONSTRAINT [CK_BookingDiscounts___Amount____0___becaaffb] CHECK ([Amount]>=(0))
);

CREATE TABLE dbo.[BookingExtras] (
 [TicketID] int NOT NULL,
 [ServiceID] int NOT NULL,
 [ServiceName] nvarchar(100) NOT NULL,
 [Quantity] int NOT NULL,
 [UnitPrice] decimal(14,2) NOT NULL,
 [RefundPercent] decimal(5,2) NOT NULL,
 CONSTRAINT [PK_BookingExtras] PRIMARY KEY CLUSTERED ([TicketID] ASC, [ServiceID] ASC),
 CONSTRAINT [CK_BookingExtras___Quantity____1__AND__Quantity____5___5d241618] CHECK ([Quantity]>=(1) AND [Quantity]<=(5)),
 CONSTRAINT [CK_BookingExtras___RefundPercent____0__AND__RefundPercent____100___5aae80a6] CHECK ([RefundPercent]>=(0) AND [RefundPercent]<=(100)),
 CONSTRAINT [CK_BookingExtras___UnitPrice____0___ce719ca1] CHECK ([UnitPrice]>=(0))
);

CREATE TABLE dbo.[BookingPassengers] (
 [BookingPassengerID] int IDENTITY(1,1) NOT NULL,
 [BookingID] int NOT NULL,
 [PassengerID] int NOT NULL,
 [FareClassID] int NOT NULL,
 CONSTRAINT [PK_BookingPassengers] PRIMARY KEY CLUSTERED ([BookingPassengerID] ASC),
 CONSTRAINT [UQ_BP_BookingKey] UNIQUE NONCLUSTERED ([BookingPassengerID] ASC, [BookingID] ASC),
 CONSTRAINT [UQ_BP_Passenger] UNIQUE NONCLUSTERED ([BookingID] ASC, [PassengerID] ASC)
);

CREATE TABLE dbo.[Bookings] (
 [BookingID] int IDENTITY(1,1) NOT NULL,
 [PNR] char(8) NOT NULL,
 [UserID] int NOT NULL,
 [FlightID] int NOT NULL,
 [Status] varchar(12) NOT NULL CONSTRAINT [DF_Bookings_Status] DEFAULT ('HELD'),
 [CreatedAt] datetime2(0) NOT NULL CONSTRAINT [DF_Bookings_Created] DEFAULT (sysutcdatetime()),
 [ExpiresAt] datetime2(0) NOT NULL,
 [JourneyType] varchar(12) NOT NULL CONSTRAINT [DF_Bookings_Journey] DEFAULT ('ONE_WAY'),
 CONSTRAINT [PK_Bookings] PRIMARY KEY CLUSTERED ([BookingID] ASC),
 CONSTRAINT [UQ_Bookings_FlightKey] UNIQUE NONCLUSTERED ([BookingID] ASC, [FlightID] ASC),
 CONSTRAINT [UQ_Bookings_PNR] UNIQUE NONCLUSTERED ([PNR] ASC),
 CONSTRAINT [CK_Bookings_Expiry] CHECK ([ExpiresAt]>=[CreatedAt]),
 CONSTRAINT [CK_Bookings_Journey] CHECK ([JourneyType]='MULTI_CITY' OR [JourneyType]='ROUND_TRIP' OR [JourneyType]='ONE_WAY'),
 CONSTRAINT [CK_Bookings_Status] CHECK ([Status]='EXPIRED' OR [Status]='CANCELLED' OR [Status]='CONFIRMED' OR [Status]='HELD')
);

CREATE TABLE dbo.[BookingSegments] (
 [BookingSegmentID] int IDENTITY(1,1) NOT NULL,
 [BookingID] int NOT NULL,
 [SegmentOrder] int NOT NULL,
 [JourneyGroup] int NOT NULL CONSTRAINT [DF_Segments_Group] DEFAULT ((1)),
 [FlightID] int NOT NULL,
 [Status] varchar(12) NOT NULL CONSTRAINT [DF_Segments_Status] DEFAULT ('ACTIVE'),
 CONSTRAINT [PK_BookingSegments] PRIMARY KEY CLUSTERED ([BookingSegmentID] ASC),
 CONSTRAINT [UQ_Segments_BookingKey] UNIQUE NONCLUSTERED ([BookingSegmentID] ASC, [BookingID] ASC),
 CONSTRAINT [CK_Segments_Group] CHECK ([JourneyGroup]>=(1) AND [JourneyGroup]<=(6)),
 CONSTRAINT [CK_Segments_Order] CHECK ([SegmentOrder]>=(1) AND [SegmentOrder]<=(12)),
 CONSTRAINT [CK_Segments_Status] CHECK ([Status]='EXCHANGED' OR [Status]='CANCELLED' OR [Status]='ACTIVE')
);

CREATE TABLE dbo.[CheckIns] (
 [CheckInID] int IDENTITY(1,1) NOT NULL,
 [TicketID] int NOT NULL,
 [Reference] uniqueidentifier NOT NULL CONSTRAINT [DF_CheckIns_Reference_71bf9093] DEFAULT (newid()),
 [Status] varchar(8) NOT NULL CONSTRAINT [DF_CheckIns_Status_920e413c] DEFAULT ('ACTIVE'),
 [CheckedInAt] datetime2(0) NOT NULL CONSTRAINT [DF_CheckIns_CheckedInAt_c5ff9269] DEFAULT (sysutcdatetime()),
 [RevokedAt] datetime2(0) NULL,
 [BoardedAt] datetime2(0) NULL,
 CONSTRAINT [PK_CheckIns] PRIMARY KEY CLUSTERED ([CheckInID] ASC),
 CONSTRAINT [UQ_CheckIn_Reference] UNIQUE NONCLUSTERED ([Reference] ASC),
 CONSTRAINT [UQ_CheckIn_Ticket] UNIQUE NONCLUSTERED ([TicketID] ASC),
 CONSTRAINT [CK_CheckIns___Status___REVOKED__OR__Status___ACTIVE___aba86f2f] CHECK ([Status]='REVOKED' OR [Status]='ACTIVE')
);

CREATE TABLE dbo.[DiscountCodes] (
 [DiscountCodeID] int IDENTITY(1,1) NOT NULL,
 [Code] varchar(30) NOT NULL,
 [Kind] varchar(8) NOT NULL,
 [Method] varchar(8) NOT NULL,
 [Value] decimal(14,2) NOT NULL,
 [MaxDiscount] decimal(14,2) NOT NULL,
 [MinimumSpend] decimal(14,2) NOT NULL CONSTRAINT [DF_DiscountCodes_MinimumSpend_20540ae9] DEFAULT ((0)),
 [ValidFrom] datetime2(0) NOT NULL,
 [ValidTo] datetime2(0) NOT NULL,
 [MaxUses] int NOT NULL,
 [IsActive] bit NOT NULL CONSTRAINT [DF_DiscountCodes_IsActive_57401e59] DEFAULT ((1)),
 CONSTRAINT [PK_DiscountCodes] PRIMARY KEY CLUSTERED ([DiscountCodeID] ASC),
 CONSTRAINT [UQ_DiscountCode] UNIQUE NONCLUSTERED ([Code] ASC),
 CONSTRAINT [CK_DiscountCodes___MaxDiscount___0___152ebd16] CHECK ([MaxDiscount]>(0)),
 CONSTRAINT [CK_DiscountCodes___MaxUses___0___be853b57] CHECK ([MaxUses]>(0)),
 CONSTRAINT [CK_DiscountCodes___Method___FIXED__OR__Method___PERCENT___8d9c54eb] CHECK ([Method]='FIXED' OR [Method]='PERCENT'),
 CONSTRAINT [CK_DiscountCodes___MinimumSpend____0___c54d9d6f] CHECK ([MinimumSpend]>=(0)),
 CONSTRAINT [CK_DiscountCodes___Value___0___bc231f00] CHECK ([Value]>(0)),
 CONSTRAINT [CK_DiscountCodes___Kind___VOUCHER__OR__Kind___PROMO___3bf9a133] CHECK ([Kind]='VOUCHER' OR [Kind]='PROMO'),
 CONSTRAINT [CK_DiscountTerms] CHECK ([ValidTo]>[ValidFrom] AND ([Method]<>'PERCENT' OR [Value]<=(50)))
);

CREATE TABLE dbo.[FareClasses] (
 [FareClassID] int IDENTITY(1,1) NOT NULL,
 [Code] varchar(10) NOT NULL,
 [Name] nvarchar(60) NOT NULL,
 [Cabin] varchar(12) NOT NULL,
 [BaggageKg] int NOT NULL,
 [RefundPercent] decimal(5,2) NOT NULL,
 [Bundle] varchar(10) NOT NULL CONSTRAINT [DF_FareBundle] DEFAULT ('STANDARD'),
 [ChangeAllowed] bit NOT NULL CONSTRAINT [DF_FareChange] DEFAULT ((1)),
 [ChangeFee] decimal(14,2) NOT NULL CONSTRAINT [DF_FareChangeFee] DEFAULT ((200000)),
 [CabinBaggageKg] int NOT NULL CONSTRAINT [DF_CabinBaggage] DEFAULT ((7)),
 CONSTRAINT [PK_FareClasses] PRIMARY KEY CLUSTERED ([FareClassID] ASC),
 CONSTRAINT [UQ_FareClasses_Code] UNIQUE NONCLUSTERED ([Code] ASC),
 CONSTRAINT [CK_CabinBaggage] CHECK ([CabinBaggageKg]>=(0) AND [CabinBaggageKg]<=(30)),
 CONSTRAINT [CK_FareBundle] CHECK ([Bundle]='FLEXIBLE' OR [Bundle]='STANDARD' OR [Bundle]='BASIC'),
 CONSTRAINT [CK_FareChangeFee] CHECK ([ChangeFee]>=(0)),
 CONSTRAINT [CK_FareClasses_Baggage] CHECK ([BaggageKg]>=(0) AND [BaggageKg]<=(60)),
 CONSTRAINT [CK_FareClasses_Cabin] CHECK ([Cabin]='FIRST' OR [Cabin]='BUSINESS' OR [Cabin]='PREMIUM' OR [Cabin]='ECONOMY'),
 CONSTRAINT [CK_FareClasses_Refund] CHECK ([RefundPercent]>=(0) AND [RefundPercent]<=(100))
);

CREATE TABLE dbo.[FlightFares] (
 [FlightID] int NOT NULL,
 [FareClassID] int NOT NULL,
 [BasePrice] decimal(14,2) NOT NULL,
 [TaxRate] decimal(5,4) NOT NULL CONSTRAINT [DF_Fares_Tax] DEFAULT ((0.10)),
 CONSTRAINT [PK_FlightFares] PRIMARY KEY CLUSTERED ([FlightID] ASC, [FareClassID] ASC),
 CONSTRAINT [CK_Fares_Price] CHECK ([BasePrice]>(0) AND [BasePrice]<=(100000000)),
 CONSTRAINT [CK_Fares_Tax] CHECK ([TaxRate]>=(0) AND [TaxRate]<=(1))
);

CREATE TABLE dbo.[Flights] (
 [FlightID] int IDENTITY(1,1) NOT NULL,
 [FlightNumber] varchar(8) NOT NULL,
 [AircraftID] int NOT NULL,
 [OriginID] int NOT NULL,
 [DestinationID] int NOT NULL,
 [DepartureTime] datetime2(0) NOT NULL,
 [ArrivalTime] datetime2(0) NOT NULL,
 [Status] varchar(12) NOT NULL CONSTRAINT [DF_Flights_Status] DEFAULT ('SCHEDULED'),
 [Gate] nvarchar(12) NULL,
 [EstimatedDeparture] datetime2(0) NULL,
 [OperationNote] nvarchar(300) NULL,
 CONSTRAINT [PK_Flights] PRIMARY KEY CLUSTERED ([FlightID] ASC),
 CONSTRAINT [UQ_Flights_AircraftKey] UNIQUE NONCLUSTERED ([FlightID] ASC, [AircraftID] ASC),
 CONSTRAINT [UQ_Flights_NumberTime] UNIQUE NONCLUSTERED ([FlightNumber] ASC, [DepartureTime] ASC),
 CONSTRAINT [CK_Flights_Route] CHECK ([OriginID]<>[DestinationID]),
 CONSTRAINT [CK_Flights_Status] CHECK ([Status]='CANCELLED' OR [Status]='ARRIVED' OR [Status]='DEPARTED' OR [Status]='BOARDING' OR [Status]='SCHEDULED'),
 CONSTRAINT [CK_Flights_Time] CHECK ([ArrivalTime]>[DepartureTime])
);

CREATE TABLE dbo.[FlightSeatAssignments] (
 [AssignmentID] int IDENTITY(1,1) NOT NULL,
 [FlightID] int NOT NULL,
 [SeatID] int NOT NULL,
 [IsActive] bit NOT NULL CONSTRAINT [DF_Assignments_Active] DEFAULT ((1)),
 CONSTRAINT [PK_Assignments] PRIMARY KEY CLUSTERED ([AssignmentID] ASC)
);

CREATE TABLE dbo.[LoyaltyLedger] (
 [LoyaltyID] bigint IDENTITY(1,1) NOT NULL,
 [UserID] int NOT NULL,
 [PaymentID] int NOT NULL,
 [Points] int NOT NULL,
 [Reason] nvarchar(120) NOT NULL,
 [CreatedAt] datetime2(0) NOT NULL CONSTRAINT [DF_LoyaltyLedger_CreatedAt_f8d53ef5] DEFAULT (sysutcdatetime()),
 CONSTRAINT [PK_LoyaltyLedger] PRIMARY KEY CLUSTERED ([LoyaltyID] ASC),
 CONSTRAINT [UQ_Loyalty_Payment] UNIQUE NONCLUSTERED ([PaymentID] ASC)
);

CREATE TABLE dbo.[LoyaltySpends] (
 [BookingID] int NOT NULL,
 [UserID] int NOT NULL,
 [Points] int NOT NULL,
 [Amount] decimal(14,2) NOT NULL,
 CONSTRAINT [PK_LoyaltySpends] PRIMARY KEY CLUSTERED ([BookingID] ASC),
 CONSTRAINT [CK_LoyaltySpends___Amount___0___d2edacfb] CHECK ([Amount]>(0)),
 CONSTRAINT [CK_LoyaltySpends___Points___0___b8bbc9f9] CHECK ([Points]>(0))
);

CREATE TABLE dbo.[LoyaltyTiers] (
 [TierCode] varchar(10) NOT NULL,
 [Name] nvarchar(50) NOT NULL,
 [MinimumPoints] int NOT NULL,
 [LoyaltyTierID] int IDENTITY(1,1) NOT NULL,
 CONSTRAINT [PK_LoyaltyTiers] PRIMARY KEY CLUSTERED ([TierCode] ASC),
 CONSTRAINT [UQ_Loyalty_Minimum] UNIQUE NONCLUSTERED ([MinimumPoints] ASC),
 CONSTRAINT [CK_LoyaltyTiers___MinimumPoints____0___53c92386] CHECK ([MinimumPoints]>=(0))
);

CREATE TABLE dbo.[NotificationDeliveries] (
 [NotificationID] bigint NOT NULL,
 [SentAt] datetime2(0) NULL,
 [Attempts] int NOT NULL CONSTRAINT [DF_NotificationDeliveries_Attempts_06e70139] DEFAULT ((0)),
 [LastError] varchar(80) NULL,
 CONSTRAINT [PK_NotificationDelivery] PRIMARY KEY CLUSTERED ([NotificationID] ASC)
);

CREATE TABLE dbo.[Notifications] (
 [NotificationID] bigint IDENTITY(1,1) NOT NULL,
 [UserID] int NOT NULL,
 [BookingID] int NULL,
 [Title] nvarchar(120) NOT NULL,
 [Message] nvarchar(1000) NOT NULL,
 [IsRead] bit NOT NULL CONSTRAINT [DF_Notifications_IsRead_a91cfc93] DEFAULT ((0)),
 [EventKey] varchar(100) NULL,
 [CreatedAt] datetime2(0) NOT NULL CONSTRAINT [DF_Notifications_CreatedAt_f8d53ef5] DEFAULT (sysutcdatetime()),
 CONSTRAINT [PK_Notifications] PRIMARY KEY CLUSTERED ([NotificationID] ASC)
);

CREATE TABLE dbo.[Passengers] (
 [PassengerID] int IDENTITY(1,1) NOT NULL,
 [FullName] nvarchar(120) NOT NULL,
 [DateOfBirth] date NOT NULL,
 [DocumentNumber] nvarchar(30) NOT NULL,
 [Assistance] varchar(12) NOT NULL CONSTRAINT [DF_PassengerAssistance] DEFAULT ('NONE'),
 CONSTRAINT [PK_Passengers] PRIMARY KEY CLUSTERED ([PassengerID] ASC),
 CONSTRAINT [CK_PassengerAssistance] CHECK ([Assistance]='VISION' OR [Assistance]='HEARING' OR [Assistance]='WHEELCHAIR' OR [Assistance]='NONE'),
 CONSTRAINT [CK_Passengers_Doc] CHECK (len([DocumentNumber])>=(5)),
 CONSTRAINT [CK_Passengers_Name] CHECK (len([FullName])>=(2))
);

CREATE TABLE dbo.[PassengerTypes] (
 [TypeCode] varchar(8) NOT NULL,
 [Name] nvarchar(60) NOT NULL,
 [PriceFactor] decimal(5,4) NOT NULL,
 CONSTRAINT [PK_PassengerTypes] PRIMARY KEY CLUSTERED ([TypeCode] ASC),
 CONSTRAINT [CK_TypeFactor] CHECK ([PriceFactor]>(0) AND [PriceFactor]<=(1))
);

CREATE TABLE dbo.[PasswordResetTokens] (
 [TokenHash] char(64) NOT NULL,
 [UserID] int NOT NULL,
 [ExpiresAt] datetime2(0) NOT NULL,
 [UsedAt] datetime2(0) NULL,
 [CreatedAt] datetime2(0) NOT NULL CONSTRAINT [DF_PasswordResetTokens_CreatedAt_f8d53ef5] DEFAULT (sysutcdatetime()),
 CONSTRAINT [PK_ResetTokens] PRIMARY KEY CLUSTERED ([TokenHash] ASC)
);

CREATE TABLE dbo.[Payments] (
 [PaymentID] int IDENTITY(1,1) NOT NULL,
 [BookingID] int NOT NULL,
 [IdempotencyKey] varchar(80) NOT NULL,
 [Amount] decimal(14,2) NOT NULL,
 [Kind] varchar(10) NOT NULL,
 [Status] varchar(10) NOT NULL,
 [CreatedAt] datetime2(0) NOT NULL CONSTRAINT [DF_Payments_Created] DEFAULT (sysutcdatetime()),
 [Purpose] varchar(12) NOT NULL CONSTRAINT [DF_PaymentPurpose] DEFAULT ('BOOKING'),
 [Settlement] varchar(8) NOT NULL CONSTRAINT [DF_PaymentSettlement] DEFAULT ('MOCK'),
 CONSTRAINT [PK_Payments] PRIMARY KEY CLUSTERED ([PaymentID] ASC),
 CONSTRAINT [UQ_Payments_Key] UNIQUE NONCLUSTERED ([IdempotencyKey] ASC),
 CONSTRAINT [CK_PaymentPurpose] CHECK ([Purpose]='EXCHANGE' OR [Purpose]='BOOKING'),
 CONSTRAINT [CK_Payments_Amount] CHECK ([Amount]>=(0)),
 CONSTRAINT [CK_Payments_Kind] CHECK ([Kind]='REFUND' OR [Kind]='CHARGE'),
 CONSTRAINT [CK_Payments_Refund] CHECK ([Kind]='CHARGE' OR [Status]='SUCCESS'),
 CONSTRAINT [CK_Payments_Status] CHECK ([Status]='FAILED' OR [Status]='SUCCESS'),
 CONSTRAINT [CK_PaymentSettlement] CHECK ([Settlement]='CREDIT' OR [Settlement]='MOCK')
);

CREATE TABLE dbo.[Roles] (
 [RoleID] int IDENTITY(1,1) NOT NULL,
 [Name] varchar(20) NOT NULL,
 CONSTRAINT [PK_Roles] PRIMARY KEY CLUSTERED ([RoleID] ASC),
 CONSTRAINT [UQ_Roles_Name] UNIQUE NONCLUSTERED ([Name] ASC),
 CONSTRAINT [CK_Roles_Name] CHECK ([Name]='CUSTOMER' OR [Name]='ADMIN')
);

CREATE TABLE dbo.[Routes] (
 [RouteID] int IDENTITY(1,1) NOT NULL,
 [OriginID] int NOT NULL,
 [DestinationID] int NOT NULL,
 [IsActive] bit NOT NULL CONSTRAINT [DF_Routes_IsActive_57401e59] DEFAULT ((1)),
 CONSTRAINT [PK_Routes] PRIMARY KEY CLUSTERED ([RouteID] ASC),
 CONSTRAINT [UQ_Route] UNIQUE NONCLUSTERED ([OriginID] ASC, [DestinationID] ASC),
 CONSTRAINT [CK_Route] CHECK ([OriginID]<>[DestinationID])
);

CREATE TABLE dbo.[SavedTravellers] (
 [TravellerID] int IDENTITY(1,1) NOT NULL,
 [UserID] int NOT NULL,
 [FullName] nvarchar(120) NOT NULL,
 [DateOfBirth] date NOT NULL,
 [DocumentNumber] nvarchar(30) NOT NULL,
 [Assistance] varchar(12) NOT NULL CONSTRAINT [DF_SavedTravellers_Assistance_1b451b10] DEFAULT ('NONE'),
 CONSTRAINT [PK_SavedTravellers] PRIMARY KEY CLUSTERED ([TravellerID] ASC),
 CONSTRAINT [UQ_SavedTraveller] UNIQUE NONCLUSTERED ([UserID] ASC, [DocumentNumber] ASC),
 CONSTRAINT [CK_SavedTraveller] CHECK (len([FullName])>=(2) AND len([DocumentNumber])>=(5) AND ([Assistance]='VISION' OR [Assistance]='HEARING' OR [Assistance]='WHEELCHAIR' OR [Assistance]='NONE'))
);

CREATE TABLE dbo.[SchemaMigrations] (
 [Version] int NOT NULL,
 [Name] nvarchar(200) NOT NULL,
 [Checksum] char(64) NOT NULL,
 [AppliedAt] datetime2(0) NOT NULL CONSTRAINT [DF_Migrations_Time] DEFAULT (sysutcdatetime()),
 CONSTRAINT [PK_SchemaMigrations] PRIMARY KEY CLUSTERED ([Version] ASC)
);

CREATE TABLE dbo.[Services] (
 [ServiceID] int IDENTITY(1,1) NOT NULL,
 [Code] varchar(20) NOT NULL,
 [Name] nvarchar(100) NOT NULL,
 [Category] varchar(12) NOT NULL,
 [UnitPrice] decimal(14,2) NOT NULL,
 [MaxQuantity] int NOT NULL CONSTRAINT [DF_Services_MaxQuantity_2856dda5] DEFAULT ((1)),
 [RefundPercent] decimal(5,2) NOT NULL CONSTRAINT [DF_Services_RefundPercent_5601f9ac] DEFAULT ((0)),
 [IsActive] bit NOT NULL CONSTRAINT [DF_Services_IsActive_57401e59] DEFAULT ((1)),
 CONSTRAINT [PK_Services] PRIMARY KEY CLUSTERED ([ServiceID] ASC),
 CONSTRAINT [UQ_ServiceCode] UNIQUE NONCLUSTERED ([Code] ASC),
 CONSTRAINT [CK_Services___Category___LOUNGE__OR__Category___PRIORITY__OR__Category___MEAL__OR__Category___BAGGAGE___4c9392bd] CHECK ([Category]='LOUNGE' OR [Category]='PRIORITY' OR [Category]='MEAL' OR [Category]='BAGGAGE'),
 CONSTRAINT [CK_Services___MaxQuantity____1__AND__MaxQuantity____5___49701363] CHECK ([MaxQuantity]>=(1) AND [MaxQuantity]<=(5)),
 CONSTRAINT [CK_Services___RefundPercent____0__AND__RefundPercent____100___5aae80a6] CHECK ([RefundPercent]>=(0) AND [RefundPercent]<=(100)),
 CONSTRAINT [CK_Services___UnitPrice____0__AND__UnitPrice____10000000___669e15f2] CHECK ([UnitPrice]>=(0) AND [UnitPrice]<=(10000000))
);

CREATE TABLE dbo.[TicketDiscounts] (
 [TicketID] int NOT NULL,
 [Amount] decimal(14,2) NOT NULL,
 CONSTRAINT [PK_TicketDiscounts] PRIMARY KEY CLUSTERED ([TicketID] ASC),
 CONSTRAINT [CK_TicketDiscounts___Amount____0___becaaffb] CHECK ([Amount]>=(0))
);

CREATE TABLE dbo.[TicketRefunds] (
 [TicketID] int NOT NULL,
 [PaymentID] int NOT NULL,
 [Amount] decimal(14,2) NOT NULL,
 [CreatedAt] datetime2(0) NOT NULL CONSTRAINT [DF_TicketRefunds_CreatedAt_f8d53ef5] DEFAULT (sysutcdatetime()),
 CONSTRAINT [PK_TicketRefunds] PRIMARY KEY CLUSTERED ([TicketID] ASC),
 CONSTRAINT [CK_TicketRefunds___Amount____0___becaaffb] CHECK ([Amount]>=(0))
);

CREATE TABLE dbo.[TicketRules] (
 [TicketID] int NOT NULL,
 [ChangeAllowed] bit NOT NULL,
 [ChangeFee] decimal(14,2) NOT NULL,
 [BaggageKg] int NOT NULL,
 [CabinBaggageKg] int NOT NULL,
 [Source] varchar(16) NOT NULL,
 CONSTRAINT [PK_TicketRules] PRIMARY KEY CLUSTERED ([TicketID] ASC),
 CONSTRAINT [CK_TicketRules___ChangeFee____0___b0a9a428] CHECK ([ChangeFee]>=(0)),
 CONSTRAINT [CK_TicketRules___Source___ISSUED_SNAPSHOT__OR__Source___LEGACY_CURRENT___b0fa31db] CHECK ([Source]='ISSUED_SNAPSHOT' OR [Source]='LEGACY_CURRENT')
);

CREATE TABLE dbo.[Tickets] (
 [TicketID] int IDENTITY(1,1) NOT NULL,
 [AssignmentID] int NOT NULL,
 [TicketNumber] varchar(20) NOT NULL,
 [BookingPassengerID] int NOT NULL,
 [Amount] decimal(14,2) NOT NULL,
 [RefundPercent] decimal(5,2) NOT NULL,
 [Status] varchar(12) NOT NULL CONSTRAINT [DF_Tickets_Status] DEFAULT ('PENDING'),
 [BookingSegmentID] int NULL,
 [FareClassID] int NULL,
 [PassengerType] varchar(8) NOT NULL CONSTRAINT [DF_TicketPassengerType] DEFAULT ('ADULT'),
 [BaseFare] decimal(14,2) NOT NULL CONSTRAINT [DF_TicketBase] DEFAULT ((0)),
 [TaxAmount] decimal(14,2) NOT NULL CONSTRAINT [DF_TicketTax] DEFAULT ((0)),
 [SeatFee] decimal(14,2) NOT NULL CONSTRAINT [DF_TicketSeatFee] DEFAULT ((0)),
 [BreakdownSource] varchar(12) NOT NULL CONSTRAINT [DF_TicketBreakdown] DEFAULT ('LEGACY_TOTAL'),
 CONSTRAINT [PK_Tickets] PRIMARY KEY CLUSTERED ([TicketID] ASC),
 CONSTRAINT [UQ_Tickets_Assignment] UNIQUE NONCLUSTERED ([AssignmentID] ASC),
 CONSTRAINT [UQ_Tickets_Number] UNIQUE NONCLUSTERED ([TicketNumber] ASC),
 CONSTRAINT [CK_Tickets_Amount] CHECK ([Amount]>(0)),
 CONSTRAINT [CK_Tickets_Breakdown] CHECK ([BaseFare]>=(0) AND [TaxAmount]>=(0) AND [SeatFee]>=(0) AND ([BreakdownSource]='DETAILED' OR [BreakdownSource]='LEGACY_TOTAL')),
 CONSTRAINT [CK_Tickets_Refund] CHECK ([RefundPercent]>=(0) AND [RefundPercent]<=(100)),
 CONSTRAINT [CK_Tickets_Status] CHECK ([Status]='VOID' OR [Status]='VALID' OR [Status]='PENDING')
);

CREATE TABLE dbo.[TravelCreditLedger] (
 [CreditID] bigint IDENTITY(1,1) NOT NULL,
 [UserID] int NOT NULL,
 [PaymentID] int NOT NULL,
 [Amount] decimal(14,2) NOT NULL,
 [CreatedAt] datetime2(0) NOT NULL CONSTRAINT [DF_TravelCreditLedger_CreatedAt_f8d53ef5] DEFAULT (sysutcdatetime()),
 CONSTRAINT [PK_TravelCredits] PRIMARY KEY CLUSTERED ([CreditID] ASC),
 CONSTRAINT [UQ_CreditPayment] UNIQUE NONCLUSTERED ([PaymentID] ASC)
);

CREATE TABLE dbo.[UserPreferences] (
 [UserID] int NOT NULL,
 [PreferredCabin] varchar(12) NOT NULL CONSTRAINT [DF_UserPreferences_PreferredCabin_992acfc8] DEFAULT ('ECONOMY'),
 [SeatPreference] varchar(8) NOT NULL CONSTRAINT [DF_UserPreferences_SeatPreference_90e1166b] DEFAULT ('ANY'),
 [Reminders] bit NOT NULL CONSTRAINT [DF_UserPreferences_Reminders_7971dd75] DEFAULT ((1)),
 [EmailNotifications] bit NOT NULL CONSTRAINT [DF_EmailPreference] DEFAULT ((0)),
 CONSTRAINT [PK_UserPreferences] PRIMARY KEY CLUSTERED ([UserID] ASC),
 CONSTRAINT [CK_UserPreferences] CHECK (([PreferredCabin]='FIRST' OR [PreferredCabin]='BUSINESS' OR [PreferredCabin]='PREMIUM' OR [PreferredCabin]='ECONOMY') AND ([SeatPreference]='AISLE' OR [SeatPreference]='WINDOW' OR [SeatPreference]='ANY'))
);

CREATE TABLE dbo.[Users] (
 [UserID] int IDENTITY(1,1) NOT NULL,
 [RoleID] int NOT NULL,
 [Email] nvarchar(254) NOT NULL,
 [FullName] nvarchar(120) NOT NULL,
 [PasswordHash] varchar(256) NOT NULL,
 [Phone] varchar(20) NULL,
 [IsActive] bit NOT NULL CONSTRAINT [DF_Users_Active] DEFAULT ((1)),
 [SessionVersion] int NOT NULL CONSTRAINT [DF_Users_Session] DEFAULT ((1)),
 [CreatedAt] datetime2(0) NOT NULL CONSTRAINT [DF_Users_Created] DEFAULT (sysutcdatetime()),
 CONSTRAINT [PK_Users] PRIMARY KEY CLUSTERED ([UserID] ASC),
 CONSTRAINT [UQ_Users_Email] UNIQUE NONCLUSTERED ([Email] ASC),
 CONSTRAINT [CK_Users_Email] CHECK ([Email] like '%_@_%._%'),
 CONSTRAINT [CK_Users_Name] CHECK (len([FullName])>=(2))
);

COMMIT TRANSACTION;
GO
