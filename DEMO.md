# Kịch bản demo 10–15 phút

## Chuẩn bị trước giờ trình bày

Chạy README từ đầu, tạo một Admin và hai Customer bằng mật khẩu riêng. Mở ứng dụng, SSMS đúng SQL_DATABASE, PowerShell trong venv. Mở slide và `sql/09_business_queries.sql`. Chọn ngày có lịch seed từ trang chủ. Giờ hiển thị trong web là Việt Nam, DB UTC. Không dùng thông tin cá nhân thật.

Seed đã có 40 booking phục vụ dashboard; tài khoản seed không đăng nhập được. Chuẩn bị DB `AeroFlow_Test_Demo` riêng cho pytest concurrency/rollback. Không chạy test có fault injection trên DB demo đang mở của lớp.

## 00:00–02:00: Đề tài, phạm vi và ERD

Giới thiệu đặt vé một chiều. Mở ERD: 15 bảng nghiệp vụ + log; phân biệt User và Passenger; Bookings–Passengers là N–N qua BP. Giải thích Tickets–Assignment một-một và lịch sử giữ ghế inactive. Chỉ ra PK/FK, CHECK và unique filtered index.

## 02:00–04:00: Demo 1 — Tìm chuyến bay

Customer tìm Hà Nội → TP.HCM, ngày đang mở bán, 1 hành khách. Mở DevTools Network nếu cần để chỉ `/api/flights`. Mở SSMS:

```sql
SELECT TOP(10) FlightID,FlightNumber,OriginCode,DestinationCode,DepartureTime,FromPrice,AvailableSeats
FROM dbo.vw_FlightAvailability WHERE OriginCode='HAN' AND DestinationCode='SGN'
ORDER BY DepartureTime;
```

Đối chiếu số hiệu chuyến/giá và chênh lệch 7 giờ. Chỉ ra function tính giá BasePrice*(1+TaxRate), decimal và rounding.

## 04:00–06:00: Demo 2 — Giữ ghế và dữ liệu liên quan

Chọn hạng FLEX để có hoàn tiền, chọn A1 còn trống, điền passenger giả, xác nhận. Web hiển thị PNR và đồng hồ 10 phút. Ghi BookingID từ URL `#booking/<id>` rồi xem:

```sql
DECLARE @id int = 41; -- thay bằng BookingID vừa tạo
SELECT * FROM dbo.vw_BookingDetails WHERE BookingID=@id;
SELECT p.FullName,t.TicketNumber,t.Status,t.Amount,s.SeatNumber,a.IsActive
FROM dbo.BookingPassengers bp JOIN dbo.Passengers p ON p.PassengerID=bp.PassengerID
JOIN dbo.Tickets t ON t.BookingPassengerID=bp.BookingPassengerID
JOIN dbo.FlightSeatAssignments a ON a.AssignmentID=t.AssignmentID
JOIN dbo.AircraftSeats s ON s.SeatID=a.SeatID WHERE bp.BookingID=@id;
```

Giải thích HELD/PENDING/IsActive=1 chưa phải vé có hiệu lực.

## 06:00–08:00: Demo 3 — Hai khách tranh cùng ghế

Hai cửa sổ đăng nhập hai Customer chọn cùng chuyến và ghế còn trống. Cả hai có thể chọn trên giao diện trước submit; một xác nhận thành công, người còn lại nhận 409 rõ nghĩa. Chứng minh tự động trên DB test riêng:

```powershell
$env:SQL_DATABASE='AeroFlow_Test_Demo'
.\.venv\Scripts\python.exe scripts\init_db.py
$env:RUN_SQL_TESTS='1'
.\.venv\Scripts\python.exe -m pytest tests\test_integration.py::test_two_customers_same_seat_concurrently -v
```

Test dùng Barrier để hai client gửi đồng thời, assert status [201,409] và COUNT(active assignment)=1. Không dùng delay để giả vờ concurrency.

## 08:00–09:30: Demo 4 — Thanh toán và vé

Trên booking đang giữ, nhấn mô phỏng thất bại: Payments FAILED, booking vẫn HELD. Nhấn thành công: CONFIRMED, VALID. Mở vé và In/Lưu PDF. Giải thích UUID idempotency. Chạy `test_concurrent_payment_exactly_once` để chứng minh hai request cùng key trả chung PaymentID, chỉ một CHARGE SUCCESS.

## 09:30–10:30: Demo 5 — Dashboard

Đăng nhập Admin, mở Tổng quan, Doanh thu, Giao dịch, Nhật ký. Doanh thu ròng từ vw_MonthlyRevenue; tỷ lệ ghế đã bán từ vw_FlightOccupancy và fn_GetFlightOccupancyRate. Hủy một booking FLEX trước 24 giờ; kiểm tra REFUND 80% và ghế được bán lại. Nếu demo hủy chuyến bởi hãng, giải thích hoàn 100% khác hủy tự nguyện.

## 10:30–12:00: Demo 6 — Rollback giữa transaction

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_integration.py::test_transaction_rollback_after_partial_writes -v
```

Test đặt trigger lỗi tại INSERT Tickets trong DB test sau khi đã thêm booking, passenger, BP và assignment. Đếm 6 bảng trước/sau không thay đổi; log cùng rollback. Mở code test, chỉ try/finally gỡ trigger. Không cài trigger này trong database chính của demo.

## 12:00–13:30: Demo 7 — Constraints và truy vấn

Trong SSMS chạy `10_test_cases.sql` đúng DB. Phải thấy PASS UNIQUE, FOREIGN KEY, CHECK, ROLLBACK; DBCC không trả violation. Chọn một FULL JOIN và GROUP BY/HAVING từ `09_business_queries.sql`, sau đó EXCEPT tìm sân bay chưa có chuyến đi. 18 truy vấn đều có mục đích nghiệp vụ và chú thích.

## 13:30–15:00: Tổng kết bằng chứng và phạm vi

Mở TESTING.md và JUnit report, nêu đúng môi trường kiểm thử. Giải thích trade-off khóa theo chuyến, index, held expiration và UTC. Chưa chứng nhận tải sản xuất hay bảo mật production. Nhắc chuẩn bị bìa thông tin sinh viên và in 1 quyển báo cáo theo yêu cầu giảng viên.

## Phương án khi mất DB lúc demo

Web phải hiện lỗi 503 dễ hiểu, không đổi sang dữ liệu giả. Dùng bằng chứng test/ảnh đã lưu trong evidence để trình bày, nói rõ đây là kết quả lần kiểm thử trước. Kiểm tra dịch vụ/instance bằng SSMS, khôi phục kết nối rồi tải lại. Không tuyên bố demo live đã chạy nếu DB đang mất kết nối.
