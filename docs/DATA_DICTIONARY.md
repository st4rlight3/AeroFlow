# Từ điển dữ liệu AeroFlow
Metadata đối chiếu trực tiếp với SQL Server 2022 Express. Tất cả thời gian nghiệp vụ là UTC.

## Aircraft
Một cấu hình máy bay gắn hãng và số đăng ký ổn định.
Khóa chính: AircraftID. Dữ liệu mẫu: 6 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| AircraftID | int | PK; NOT NULL | Khóa cấu hình máy bay |
| AirlineID | int | FK; NOT NULL | Khóa hãng bay |
| Registration | varchar(20) | -; NOT NULL | Mã đăng ký máy bay duy nhất |
| Model | nvarchar(80) | -; NOT NULL | Tên cấu hình máy bay |
| IsActive | bit | -; NOT NULL | Có hoạt động hoặc còn hiệu lực |

## AircraftSeats
Danh mục ghế theo máy bay; số ghế A1 chỉ có nghĩa trong một máy bay.
Khóa chính: SeatID. Dữ liệu mẫu: 396 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| SeatID | int | PK; NOT NULL | Khóa ghế vật lý trong cấu hình |
| AircraftID | int | FK; NOT NULL | Khóa cấu hình máy bay |
| SeatNumber | varchar(5) | -; NOT NULL | Số ghế cột trước hàng, ví dụ A1 |
| RowNumber | int | -; NOT NULL | Số hàng ghế |
| ColumnLetter | char(1) | -; NOT NULL | Cột A–F |
| Cabin | varchar(12) | -; NOT NULL | ECONOMY hoặc BUSINESS |
| IsActive | bit | -; NOT NULL | Có hoạt động hoặc còn hiệu lực |

## Airlines
Hãng bay giả lập của dự án.
Khóa chính: AirlineID. Dữ liệu mẫu: 3 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| AirlineID | int | PK; NOT NULL | Khóa hãng bay |
| Code | char(2) | -; NOT NULL | Mã danh mục |
| Name | nvarchar(100) | -; NOT NULL | Tên hiển thị |

## Airports
Danh mục sân bay nội địa, mã IATA mô phỏng và thành phố.
Khóa chính: AirportID. Dữ liệu mẫu: 10 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| AirportID | int | PK; NOT NULL | Khóa sân bay |
| Code | char(3) | -; NOT NULL | Mã danh mục |
| Name | nvarchar(120) | -; NOT NULL | Tên hiển thị |
| City | nvarchar(80) | -; NOT NULL | Thành phố |
| IsActive | bit | -; NOT NULL | Có hoạt động hoặc còn hiệu lực |

## AuditLogs
Nhật ký hoạt động quan trọng, actor có thể NULL cho tác vụ hệ thống.
Khóa chính: AuditID. Dữ liệu mẫu: 248 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| AuditID | bigint | PK; NOT NULL | Khóa log |
| ActorID | int | FK; NULL | Người thao tác; NULL cho system |
| Entity | varchar(40) | -; NOT NULL | Tên loại đối tượng |
| EntityID | int | -; NOT NULL | ID đối tượng |
| Action | varchar(40) | -; NOT NULL | Loại thao tác |
| Details | nvarchar(1000) | -; NULL | Tóm tắt thay đổi, không chứa mật khẩu/PII đầy đủ |
| CreatedAt | datetime2(0) | -; NOT NULL | Thời điểm tạo UTC |

## BookingPassengers
Quan hệ booking với từng hành khách và hạng vé.
Khóa chính: BookingPassengerID. Dữ liệu mẫu: 40 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| BookingPassengerID | int | PK; NOT NULL | Khóa hành khách trong booking |
| BookingID | int | FK; NOT NULL | Khóa đặt chỗ |
| PassengerID | int | FK; NOT NULL | Khóa hồ sơ hành khách |
| FareClassID | int | FK; NOT NULL | Khóa hạng vé |

## Bookings
PNR, chủ tài khoản, chuyến bay, thời hạn giữ và trạng thái.
Khóa chính: BookingID. Dữ liệu mẫu: 40 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| BookingID | int | PK; NOT NULL | Khóa đặt chỗ |
| PNR | char(8) | -; NOT NULL | Mã đặt chỗ 8 ký tự duy nhất |
| UserID | int | FK; NOT NULL | Khóa tài khoản |
| FlightID | int | FK; NOT NULL | Khóa chuyến bay |
| Status | varchar(12) | -; NOT NULL | Trạng thái theo CHECK riêng từng bảng |
| CreatedAt | datetime2(0) | -; NOT NULL | Thời điểm tạo UTC |
| ExpiresAt | datetime2(0) | -; NOT NULL | Hạn giữ ghế UTC |

## FareClasses
Điều kiện hạng vé hiện hành, khoang, hành lý, tỷ lệ hoàn.
Khóa chính: FareClassID. Dữ liệu mẫu: 3 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| FareClassID | int | PK; NOT NULL | Khóa hạng vé |
| Code | varchar(10) | -; NOT NULL | Mã danh mục |
| Name | nvarchar(60) | -; NOT NULL | Tên hiển thị |
| Cabin | varchar(12) | -; NOT NULL | ECONOMY hoặc BUSINESS |
| BaggageKg | int | -; NOT NULL | Hạn mức hành lý kg |
| RefundPercent | decimal(5,2) | -; NOT NULL | Tỷ lệ hoàn 0–100% (snapshot trên vé) |

## FlightFares
Bảng giá hiện hành theo cặp chuyến/hạng.
Khóa chính: FlightID,FareClassID. Dữ liệu mẫu: 360 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| FlightID | int | PK,FK; NOT NULL | Khóa chuyến bay |
| FareClassID | int | PK,FK; NOT NULL | Khóa hạng vé |
| BasePrice | decimal(14,2) | -; NOT NULL | Giá cơ sở VND decimal |
| TaxRate | decimal(5,4) | -; NOT NULL | Thuế dạng tỷ lệ 0–1 |

## Flights
Lịch chuyến bay, máy bay, sân bay đi/đến và trạng thái.
Khóa chính: FlightID. Dữ liệu mẫu: 120 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| FlightID | int | PK; NOT NULL | Khóa chuyến bay |
| FlightNumber | varchar(8) | -; NOT NULL | Số hiệu chuyến |
| AircraftID | int | FK; NOT NULL | Khóa cấu hình máy bay |
| OriginID | int | FK; NOT NULL | FK sân bay đi |
| DestinationID | int | FK; NOT NULL | FK sân bay đến |
| DepartureTime | datetime2(0) | -; NOT NULL | Giờ khởi hành UTC |
| ArrivalTime | datetime2(0) | -; NOT NULL | Giờ đến UTC |
| Status | varchar(12) | -; NOT NULL | Trạng thái theo CHECK riêng từng bảng |

## FlightSeatAssignments
Lịch sử cấp ghế của chuyến, active bit cho unique filtered index.
Khóa chính: AssignmentID. Dữ liệu mẫu: 40 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| AssignmentID | int | PK; NOT NULL | Khóa lượt cấp ghế |
| FlightID | int | FK; NOT NULL | Khóa chuyến bay |
| SeatID | int | FK; NOT NULL | Khóa ghế vật lý trong cấu hình |
| IsActive | bit | -; NOT NULL | Có hoạt động hoặc còn hiệu lực |

## Passengers
Thông tin hành khách bất biến ở lần đặt.
Khóa chính: PassengerID. Dữ liệu mẫu: 40 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| PassengerID | int | PK; NOT NULL | Khóa hồ sơ hành khách |
| FullName | nvarchar(120) | -; NOT NULL | Họ tên Unicode |
| DateOfBirth | date | -; NOT NULL | Ngày sinh hành khách |
| DocumentNumber | nvarchar(30) | -; NOT NULL | Giấy tờ giả lập; không unique toàn hệ thống |

## Payments
Các lần thanh toán hoặc hoàn mô phỏng, idempotency key duy nhất.
Khóa chính: PaymentID. Dữ liệu mẫu: 48 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| PaymentID | int | PK; NOT NULL | Khóa giao dịch |
| BookingID | int | FK; NOT NULL | Khóa đặt chỗ |
| IdempotencyKey | varchar(80) | -; NOT NULL | Khóa chống xử lý trùng |
| Amount | decimal(14,2) | -; NOT NULL | Số tiền VND đã làm tròn 2 chữ số |
| Kind | varchar(10) | -; NOT NULL | CHARGE hoặc REFUND |
| Status | varchar(10) | -; NOT NULL | Trạng thái theo CHECK riêng từng bảng |
| CreatedAt | datetime2(0) | -; NOT NULL | Thời điểm tạo UTC |

## Roles
Vai trò ứng dụng ADMIN hoặc CUSTOMER.
Khóa chính: RoleID. Dữ liệu mẫu: 2 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| RoleID | int | PK; NOT NULL | Khóa vai trò |
| Name | varchar(20) | -; NOT NULL | Tên hiển thị |

## Tickets
Vé gắn duy nhất BP và assignment, lưu giá và tỷ lệ hoàn tại lúc mua.
Khóa chính: TicketID. Dữ liệu mẫu: 40 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| TicketID | int | PK; NOT NULL | Khóa vé |
| AssignmentID | int | FK; NOT NULL | Khóa lượt cấp ghế |
| TicketNumber | varchar(20) | -; NOT NULL | Số vé duy nhất |
| BookingPassengerID | int | FK; NOT NULL | Khóa hành khách trong booking |
| Amount | decimal(14,2) | -; NOT NULL | Số tiền VND đã làm tròn 2 chữ số |
| RefundPercent | decimal(5,2) | -; NOT NULL | Tỷ lệ hoàn 0–100% (snapshot trên vé) |
| Status | varchar(12) | -; NOT NULL | Trạng thái theo CHECK riêng từng bảng |

## Users
Tài khoản đăng nhập, hash mật khẩu và trạng thái phiên.
Khóa chính: UserID. Dữ liệu mẫu: 40 dòng.

| Cột | Kiểu | Khóa / NULL | Ý nghĩa |
|---|---|---|---|
| UserID | int | PK; NOT NULL | Khóa tài khoản |
| RoleID | int | FK; NOT NULL | Khóa vai trò |
| Email | nvarchar(254) | -; NOT NULL | Email đăng nhập duy nhất |
| FullName | nvarchar(120) | -; NOT NULL | Họ tên Unicode |
| PasswordHash | varchar(256) | -; NOT NULL | Hash scrypt, không lưu mật khẩu gốc |
| Phone | varchar(20) | -; NULL | Số liên hệ tùy chọn |
| IsActive | bit | -; NOT NULL | Có hoạt động hoặc còn hiệu lực |
| SessionVersion | int | -; NOT NULL | Phiên bản dùng thu hồi session |
| CreatedAt | datetime2(0) | -; NOT NULL | Thời điểm tạo UTC |