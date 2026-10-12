# ERD AeroFlow

Xem bản vector đầy đủ `docs/ERD.svg`. Kiểu tiền DECIMAL, thời gian UTC DATETIME2, chữ tiếng Việt NVARCHAR.

```mermaid
erDiagram
    Aircraft {
        int AircraftID PK
        int AirlineID FK
        varchar(20) Registration
        nvarchar(80) Model
        bit IsActive
    }
    AircraftSeats {
        int SeatID PK
        int AircraftID FK
        varchar(5) SeatNumber
        int RowNumber
        char(1) ColumnLetter
        varchar(12) Cabin
        bit IsActive
    }
    Airlines {
        int AirlineID PK
        char(2) Code
        nvarchar(100) Name
    }
    Airports {
        int AirportID PK
        char(3) Code
        nvarchar(120) Name
        nvarchar(80) City
        bit IsActive
    }
    AuditLogs {
        bigint AuditID PK
        int ActorID FK
        varchar(40) Entity
        int EntityID
        varchar(40) Action
        nvarchar(1000) Details
        datetime2(0) CreatedAt
    }
    BookingPassengers {
        int BookingPassengerID PK
        int BookingID FK
        int PassengerID FK
        int FareClassID FK
    }
    Bookings {
        int BookingID PK
        char(8) PNR
        int UserID FK
        int FlightID FK
        varchar(12) Status
        datetime2(0) CreatedAt
        datetime2(0) ExpiresAt
    }
    FareClasses {
        int FareClassID PK
        varchar(10) Code
        nvarchar(60) Name
        varchar(12) Cabin
        int BaggageKg
        decimal(5_2) RefundPercent
    }
    FlightFares {
        int FlightID PK,FK
        int FareClassID PK,FK
        decimal(14_2) BasePrice
        decimal(5_4) TaxRate
    }
    Flights {
        int FlightID PK
        varchar(8) FlightNumber
        int AircraftID FK
        int OriginID FK
        int DestinationID FK
        datetime2(0) DepartureTime
        datetime2(0) ArrivalTime
        varchar(12) Status
    }
    FlightSeatAssignments {
        int AssignmentID PK
        int FlightID FK
        int SeatID FK
        bit IsActive
    }
    Passengers {
        int PassengerID PK
        nvarchar(120) FullName
        date DateOfBirth
        nvarchar(30) DocumentNumber
    }
    Payments {
        int PaymentID PK
        int BookingID FK
        varchar(80) IdempotencyKey
        decimal(14_2) Amount
        varchar(10) Kind
        varchar(10) Status
        datetime2(0) CreatedAt
    }
    Roles {
        int RoleID PK
        varchar(20) Name
    }
    Tickets {
        int TicketID PK
        int AssignmentID FK
        varchar(20) TicketNumber
        int BookingPassengerID FK
        decimal(14_2) Amount
        decimal(5_2) RefundPercent
        varchar(12) Status
    }
    Users {
        int UserID PK
        int RoleID FK
        nvarchar(254) Email
        nvarchar(120) FullName
        varchar(256) PasswordHash
        varchar(20) Phone
        bit IsActive
        int SessionVersion
        datetime2(0) CreatedAt
    }
    Airlines ||--o{ Aircraft : "AirlineID"
    Flights ||--o{ FlightSeatAssignments : "FlightID"
    AircraftSeats ||--o{ FlightSeatAssignments : "SeatID"
    Users ||--o{ AuditLogs : "ActorID"
    Flights ||--o{ Bookings : "FlightID"
    Users ||--o{ Bookings : "UserID"
    Bookings ||--o{ BookingPassengers : "BookingID"
    FareClasses ||--o{ BookingPassengers : "FareClassID"
    Passengers ||--o{ BookingPassengers : "PassengerID"
    FareClasses ||--o{ FlightFares : "FareClassID"
    Flights ||--o{ FlightFares : "FlightID"
    Aircraft ||--o{ Flights : "AircraftID"
    Airports ||--o{ Flights : "DestinationID"
    Airports ||--o{ Flights : "OriginID"
    Bookings ||--o{ Payments : "BookingID"
    Aircraft ||--o{ AircraftSeats : "AircraftID"
    FlightSeatAssignments ||--o| Tickets : "AssignmentID"
    BookingPassengers ||--o| Tickets : "BookingPassengerID"
    Roles ||--o{ Users : "RoleID"
```

Vé liên kết một-một với BookingPassenger và Assignment bằng UNIQUE NOT NULL. Unique filtered index ở Assignment áp dụng cho FlightID + SeatID khi IsActive=1. Các trigger kiểm tra tính tương thích máy bay/ghế/cabin mà không lặp AircraftID,BookingID trên bảng cấp ghế.
