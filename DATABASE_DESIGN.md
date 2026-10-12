# Thiết kế dữ liệu và giao dịch

## ERD và từ điển dữ liệu

Xem `ERD.md`, `docs/ERD.mmd`, `docs/ERD.svg` và `docs/DATA_DICTIONARY.md`. Từ điển lấy trực tiếp từ metadata SQL Server sau khi chạy DDL. Hệ thống có 16 bảng, trong đó 15 bảng nghiệp vụ và 1 bảng log. Bảng danh mục nhỏ như Roles không bị tăng giả lên 30 bản ghi. Các bảng Flights, Users, Passengers, Bookings, BookingPassengers, Tickets, Payments có 30–200 bản ghi mẫu; FlightFares và AircraftSeats nhiều hơn do quan hệ dữ liệu tự nhiên.

## Chuẩn hóa

Mô hình thô có thể là một dòng đặt vé chứa email, tên khách, hãng bay, mã sân bay, máy bay, danh sách hành khách/ghế, số tiền và giao dịch. Dạng này lặp danh mục và khó cập nhật một phần.

1. **1NF:** tách mỗi hành khách/ghế/vé/thanh toán thành bản ghi riêng, không lưu danh sách ghế hay hành khách trong một cột. JSON chỉ là tham số transport của procedure, không phải cấu trúc lưu trữ nghiệp vụ.
2. **2NF:** FlightFares có khóa (FlightID, FareClassID); BasePrice/TaxRate phụ thuộc cả chuyến và hạng, còn tên hạng, cabin, hành lý ở FareClasses. AircraftSeats giữ hàng/cột thuộc từng máy bay, không giả định A1 đồng nhất giữa mọi máy bay.
3. **3NF:** tên sân bay/thành phố chỉ ở Airports; hãng bay thuộc Aircraft qua AirlineID, không lặp AirlineID trên Flights; thông tin tài khoản ở Users, quyền ở Roles. Bookings tham chiếu User và Flight. BookingPassengers nối Booking với Passenger/FareClass. Tickets tham chiếu BookingPassenger và Assignment bằng hai khóa UNIQUE. FlightSeatAssignments chỉ giữ FlightID, SeatID và IsActive, không lặp BookingID/PassengerID/AircraftID. Như vậy không có chuỗi phụ thuộc bắc cầu giữa các thuộc tính không khóa trong cùng bảng.

Các quan hệ chức năng tiêu biểu: UserID → Email, FullName, RoleID; FlightID → AircraftID, OriginID, DestinationID, thời gian; (FlightID,FareClassID) → BasePrice,TaxRate; SeatID → AircraftID,RowNumber,ColumnLetter,Cabin; BookingPassengerID → BookingID,PassengerID,FareClassID; TicketID/BookingPassengerID/AssignmentID/TicketNumber (mỗi giá trị là candidate key trong Tickets) → Amount,RefundPercent,Status.

Amount và RefundPercent trên Tickets là **điều khoản lịch sử tại lúc đặt**, không phải bản sao đồng nghĩa của giá hoặc tỷ lệ hiện hành. Sửa bảng giá không đổi vé cũ. Passengers được ghi như hồ sơ hành khách bất biến tại lần đặt, cho phép cùng giấy tờ xuất hiện trong những booking khác nhau mà không sửa ngược lịch sử. Email user là duy nhất; DocumentNumber không duy nhất toàn hệ thống vì hồ sơ hành khách là snapshot theo lần mua. Trong cùng booking, procedure từ chối giấy tờ trùng.

Booking không lưu tổng tiền dư thừa: view cộng Tickets.Amount. Aircraft không lưu số ghế: view đếm AircraftSeats. Tỷ lệ lấp đầy = vé VALID có assignment active / số ghế active của máy bay, chỉ phản ánh ghế đã thanh toán, không tính ghế đang giữ. Doanh thu ròng = CHARGE SUCCESS − REFUND SUCCESS theo ngày nhận tiền.

## Quan hệ

- 1–N: Roles–Users; Airlines–Aircraft; Aircraft–AircraftSeats/Flights; Airports–Flights hai vai trò đi/đến; Users–Bookings; Flights–Bookings/FlightFares/Assignments; Bookings–BookingPassengers/Payments; FareClasses–BookingPassengers.
- N–N: Flights–FareClasses qua FlightFares; Bookings–Passengers qua BookingPassengers; Flights–AircraftSeats qua lịch sử FlightSeatAssignments.
- 1–1 bắt buộc về phía vé: mỗi Ticket tham chiếu đúng một BookingPassenger và một Assignment qua UNIQUE NOT NULL. Việc tạo ba bản ghi diễn ra cùng transaction; FK đơn lẻ không ép một BP phải có vé ngay ở giữa transaction.
- ActorID trên AuditLogs cho phép NULL cho seed/scheduler. Không ghi password, document đầy đủ hoặc payload trong log.

## Ràng buộc và index

16 PRIMARY KEY, 19 FOREIGN KEY, 19 UNIQUE constraints, 27 CHECK, 14 DEFAULT tại lần kiểm chứng. NOT NULL ở mọi cột nghiệp vụ bắt buộc. CHECK bao phủ lộ trình khác điểm, thời gian đến sau khởi hành, giá/thuế/tỷ lệ hoàn hợp lệ, tập trạng thái, cabin/hàng/cột và số ghế. Bằng chứng metadata ở `evidence/database-inventory.json`.

`UX_Assignments_ActiveSeat(FlightID,SeatID) WHERE IsActive=1` là hàng rào cuối chống hai lượt cấp ghế còn hiệu lực. Assignment lịch sử giữ lại với IsActive=0 nên có thể bán lại sau hủy/hết hạn. `UX_Payments_SuccessCharge(BookingID)` chỉ CHARGE SUCCESS; `UX_Payments_Refund(BookingID)` chỉ REFUND; `UQ_Payments_Key` bảo vệ idempotency key toàn cục.

`IX_Flights_Search(OriginID,DestinationID,DepartureTime)` phục vụ tìm chuyến theo route/date range và INCLUDE các cột hiển thị. `IX_Bookings_Expiry` phục vụ dọn giữ ghế; `IX_Bookings_User` phục vụ lịch sử; `IX_Payments_Report` hỗ trợ báo cáo theo thời gian; `IX_BP_Booking` hỗ trợ cộng tiền; `IX_Audit_Created` phục vụ nhật ký mới nhất. Không tạo index theo cảm tính trên mọi cột. Với bộ dữ liệu nhỏ, chi phí view correlated subquery vẫn phù hợp; chưa đo tải sản xuất, nên xem actual execution plan và STATISTICS IO khi tăng dữ liệu.

## Khóa và transaction

Connection dùng READ COMMITTED mặc định. Các procedure bật SET XACT_ABORT ON và BEGIN TRY/CATCH; lỗi rollback toàn bộ nếu còn transaction. sp_LockFlight dùng `sp_getapplock` Exclusive, LockOwner=Transaction, resource `AeroFlow:flight:<FlightID>`, timeout 10 giây. Tất cả tác vụ làm thay đổi quyền sở hữu ghế dùng cùng resource: đặt, thanh toán, hủy, expire, status, giá. Lock tự nhả khi transaction kết thúc. UPDLOCK/HOLDLOCK bảo vệ đọc quyết định trong create booking, bổ sung unique filtered index cho phòng vệ trực tiếp ở DB.

Luồng tranh ghế: T1 giữ khóa chuyến, kiểm tra ghế và chèn assignment; T2 đợi. T1 commit; T2 nhận khóa, thấy assignment active, trả SQL_51005/HTTP409. Nếu T1 lỗi, rollback loại bỏ toàn bộ rows và T2 có thể thành công. Unique index còn từ chối hai assignment active ngay cả khi một writer bỏ qua application lock.

Khóa theo chuyến (thay vì từng ghế) đơn giản hóa chứng minh đúng đắn và tránh thứ tự khóa ghế khác nhau ở nhóm nhiều khách. Đổi lại, thông lượng một chuyến bị tuần tự hóa. Admin sửa lịch lấy khóa lịch toàn cục rồi khóa chuyến; các luồng booking không lấy khóa lịch nên không đảo thứ tự. Catalog aircraft/seat chỉ sửa trước khi có chuyến. SQL Server vẫn có thể phát hiện deadlock ở writer bên ngoài: API trả 409 để thử lại, không tự động lặp một booking có thể đã commit.

sp_ExpireFlightHolds cập nhật booking EXPIRED, vé VOID, assignment inactive cùng transaction. Đọc availability loại trừ hold hết hạn theo đồng hồ SQL trước cả lúc job chạy. Khi chọn ghế/procedure tạo mới, cleanup chạy dưới cùng khóa và giải phóng physical unique index. Thanh toán chạy cleanup rồi khóa lại và kiểm tra thời hạn lần nữa, nên không thể trả tiền cho một hold đã hết hạn trong khoảng giữa hai bước.

## Idempotency và rollback

Client tạo UUID cho mỗi lần thanh toán; giữ key trong sessionStorage cho đến khi nhận phản hồi. Nếu mất mạng, gửi lại cùng key/cùng booking/cùng Success sẽ nhận lại PaymentID. Dùng key cũ cho booking khác hoặc kết quả khác bị từ chối. Khi booking đã CONFIRMED, key mới không tạo CHARGE thứ hai. Hai request đồng thời cùng key dùng khóa chuyến và unique constraints để trả một giao dịch duy nhất.

Failed payment là bản ghi FAILED, booking vẫn HELD đến deadline. Customer cancellation lặp không tạo REFUND lần hai; refund key ổn định theo booking và filtered unique index. Hãng hủy chuyến trả 100% cho booking CONFIRMED, không hoàn cho hold chưa thu tiền. Hoàn bằng 0 vẫn được ghi để thể hiện vé không hoàn.

Kiểm thử rollback cài trigger lỗi **chỉ trong DB test** tại INSERT Tickets, sau khi Booking/Passenger/BP/Assignment đã được chèn. Đếm 6 bảng trước và sau phải bằng nhau, gồm AuditLogs; trigger lỗi được gỡ trong finally. Đây là minh chứng rollback thực, không chỉ lỗi validation trước khi transaction bắt đầu.

## Triggers có phạm vi cụ thể

tr_Bookings_Audit và tr_Flights_Audit ghi thay đổi, đồng thời ngăn thay Flight/aircraft làm sai ghế đã cấp. tr_Seats_ImmutableLayout chặn sửa sơ đồ của máy bay đã có chuyến. tr_Assignments_Integrity kiểm tra ghế thuộc đúng máy bay và không đổi liên kết assignment. tr_Tickets_Integrity kiểm tra Flight/Cabin/booking và bảo vệ giá/liên kết vé đã tạo. tr_Payments_Audit ghi CHARGE/REFUND. Không dùng trigger để tự phát hành vé hoặc tự tính tiền; business procedure thể hiện rõ thứ tự thao tác.

## Tài liệu kỹ thuật tham khảo

- Microsoft, [sp_getapplock](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-getapplock-transact-sql): khóa ứng dụng thuộc transaction.
- Microsoft, [Filtered indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/create-filtered-indexes): giới hạn tập row còn hiệu lực.
- Microsoft, [TRY...CATCH](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/try-catch-transact-sql), [XACT_ABORT](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-xact-abort-transact-sql).
