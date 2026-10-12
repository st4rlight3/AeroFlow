# REST API AeroFlow

Base URL local: `http://127.0.0.1:5000/api`. JSON UTF-8, cookie cùng origin. Tiền trả về chuỗi DECIMAL, ví dụ `"1100000.00"`; thời gian DATETIME2 UTC trả ISO 8601 có `+00:00`, ngày trả `YYYY-MM-DD`. ID là số nguyên dương. Không yêu cầu API key hoặc JWT.

## Xác thực và lỗi

GET `/csrf` trước, lấy `{ "token": "..." }`; giữ cookie và gửi `X-CSRF-Token` cho mọi request thay đổi dữ liệu. Login/logout trả `csrf` mới. Nếu session mất, tải lại token. Không gửi token vào URL.

```json
{"error":{"code":"SQL_51005","message":"Ghế vừa được người khác giữ. Vui lòng chọn ghế khác.","request_id":"..."}}
```

400 validation/constraint, 401 chưa login, 403 role/CSRF, 404 không tồn tại hoặc sai chủ booking, 409 conflict/state/idempotency, 413 payload quá 32 KB, 429 rate-limit, 503 DB không sẵn sàng. Không phân biệt booking người khác với booking không tồn tại.

## Công khai

| Method | Path | Input / Kết quả |
|---|---|---|
| GET | /health | Kiểm tra kết nối SQL Server thực, 200 hoặc 503 |
| GET | /csrf | token CSRF và cookie session |
| POST | /auth/register | FullName 2–120, Email ≤254, Password 12–128; 201; luôn CUSTOMER |
| POST | /auth/login | Email, Password; 200 và csrf mới |
| GET | /airports | items: AirportID, Code, Name, City (đang active) |
| GET | /discovery | routes có ghế/giá/mở bán, giá từ và chuyến kế tiếp |
| GET | /flights | origin, destination, date, passengers (1–9), ngày Việt Nam |
| GET | /flights/{id} | flight từ vw_FlightAvailability và fares từ fn_CalculateTicketPrice |
| GET | /flights/{id}/seats | items: SeatID, SeatNumber, RowNumber, ColumnLetter, Cabin, Available |

GET seats có cleanup hold hết hạn như housekeeping, không tạo quyền giữ ghế. Availability là ảnh chụp thời điểm đọc; người dùng phải xử lý 409 khi submit.

## Khách hàng đã đăng nhập

| Method | Path | Input / Kết quả |
|---|---|---|
| GET | /me | user: UserID,FullName,Email,Phone,Role |
| PUT | /me | FullName, Phone tùy chọn; không đổi email/role/password |
| POST | /auth/logout | Vô hiệu phiên toàn tài khoản, clear cookie |
| GET | /bookings | items chỉ của user, dọn holds hết hạn |
| POST | /bookings | FlightID, Passengers; 201 và booking |
| GET | /bookings/{id} | booking,tickets,payments; chỉ chủ hoặc admin |
| POST | /bookings/{id}/payments | Success bool, IdempotencyKey 16–80; chỉ chủ |
| POST | /bookings/{id}/cancel | body {}; chủ hoặc admin; hủy toàn booking |

Ví dụ body đặt vé (IDs lấy từ API, không copy ID ví dụ vào DB khác):

```json
{
  "FlightID": 1,
  "Passengers": [
    {"SeatID": 1, "FareClassID": 2, "FullName": "Khach Demo",
     "DateOfBirth": "1995-04-20", "DocumentNumber": "DEMO123456"}
  ]
}
```

Tên và giấy tờ ví dụ là dữ liệu giả. Cần 1–9 khách, ghế và giấy tờ không trùng trong đơn, ghế đúng máy bay/cabin. Không có trường giá cần client gửi. Booking response chứa BookingID, PNR, UserID, FlightID, Status, CreatedAt, ExpiresAt, TotalAmount, PassengerCount và route/time.

Payment Success=false ghi FAILED nhưng không giải phóng ghế ngay. Cùng key/cùng payload trả cùng PaymentID. Cùng key/khác payload trả 409. Booking trả tiền thành công chuyển CONFIRMED và tickets VALID. Key mới cho booking đã thanh toán bị từ chối. Request body chỉ dùng boolean mô phỏng, không có trường PAN/CVV/thẻ.

## Quản trị

Tất cả đường dẫn `/admin/*` cần login ADMIN và mutation cần CSRF như trên.

| Method | Path | Input / Kết quả |
|---|---|---|
| GET | /admin/overview | totals,monthly,occupancy từ views/functions |
| GET | /admin/flights | Tối đa 500 chuyến mới nhất |
| POST | /admin/flights | FlightNumber,AircraftID,OriginID,DestinationID,DepartureTime,ArrivalTime |
| PUT | /admin/flights/{id} | Các trường trên, chỉ chuyến chưa có lịch sử booking |
| PUT | /admin/flights/{id}/status | Status: SCHEDULED→BOARDING→DEPARTED→ARRIVED; SCHEDULED/BOARDING→CANCELLED |
| PUT | /admin/flights/{id}/fares/{classId} | BasePrice (1–100000000), TaxRate (0–1) |
| GET | /admin/bookings?q= | Tìm PNR/email, tối đa 300 |
| GET | /admin/customers | Tối đa 300 CUSTOMER |
| PUT | /admin/customers/{id} | IsActive bool, không tác động ADMIN |
| GET | /admin/reports/revenue?from=&to= | YYYY-MM-DD, inclusive days UTC, tối đa 366 ngày |
| GET | /admin/payments | Tối đa 300 giao dịch mới |
| GET | /admin/audit | Tối đa 300 hoạt động mới |
| GET | /admin/catalog/{entity} | items,key,fields; tối đa 2000 |
| POST | /admin/catalog/{entity} | Tạo danh mục, trả id |
| PUT | /admin/catalog/{entity}/{id} | Cập nhật danh mục |

DepartureTime/ArrivalTime khi tạo/sửa phải kèm múi giờ, ví dụ `2026-10-20T09:00:00+07:00`. Lịch máy bay không trùng và có 45 phút quay đầu. Tạo chuyến chưa có giá: dùng endpoint fares cho từng hạng muốn bán. Máy bay/ngày phải hợp lệ; kiểm tra giao nhau trong transaction có khóa lịch.

Catalog allowlist và fields:

- airports: Code,Name,City,IsActive.
- airlines: Code,Name.
- aircraft: AirlineID,Registration,Model,IsActive; khi tạo thêm Rows (1–40), BusinessRows (0–Rows), tự sinh 6 cột.
- seats: AircraftID,RowNumber (1–80),ColumnLetter (A–F),Cabin,IsActive. SeatNumber tính từ cột/hàng, không gửi tùy ý.
- fare-classes: Code,Name,Cabin,BaggageKg (0–60),RefundPercent (0–100). Cabin ECONOMY/BUSINESS.

Không có DELETE vật lý. Không có endpoint cấp quyền ADMIN qua web. Tạo quản trị bằng công cụ local có quyền DB của người cài.

## Ví dụ PowerShell giữ cookie

```powershell
$base = 'http://127.0.0.1:5000/api'
$csrf = Invoke-RestMethod "$base/csrf" -SessionVariable web
$headers = @{ 'X-CSRF-Token' = $csrf.token }
# Điền thông tin tài khoản do chính bạn tạo, không lưu password trong script công khai.
$body = @{ Email='your-demo@example.com'; Password=Read-Host 'Demo password' } | ConvertTo-Json
$login = Invoke-RestMethod "$base/auth/login" -Method Post -WebSession $web -Headers $headers -ContentType 'application/json' -Body $body
$headers['X-CSRF-Token'] = $login.csrf
Invoke-RestMethod "$base/bookings" -WebSession $web
```

Ví dụ nhằm minh họa contract. Đối với nhập mật khẩu không hiển thị, dùng web UI hoặc `scripts/create_user.py`.
