# Bảo mật và giới hạn triển khai

- Password hash scrypt từ Werkzeug, không plaintext; không tài khoản admin mặc định, không mật khẩu trong ZIP. Seed user dùng chuỗi vô hiệu và IsActive=0.
- Truy vấn pyodbc dùng dấu `?` cho mọi giá trị. Tên bảng/cột trong admin lấy từ CATALOGS allowlist, không nối chuỗi input làm SQL identifiers. Tên DB trong runner có allowlist pattern riêng.
- Session cookie ký với SECRET_KEY ngẫu nhiên, HttpOnly, SameSite=Lax, thời hạn 1 giờ. Local HTTP cần SESSION_COOKIE_SECURE=false; dùng HTTPS phải đặt true. Logout tăng SessionVersion và vô hiệu các phiên cùng tài khoản; khóa khách hàng cũng tăng version.
- Đọc role/active/version từ DB mỗi request bảo vệ. Mọi endpoint admin có authenticated(admin=True). Booking xem/thanh toán/hủy kiểm tra chủ sở hữu; admin được xem/hủy, không giả làm chủ để thanh toán.
- Mọi POST/PUT/PATCH/DELETE của API đều kiểm tra X-CSRF-Token so sánh constant time, kể cả đăng nhập/đăng ký. Cùng origin, không bật CORS. Login xoay session/CSRF token.
- Rate limit đăng nhập/đăng ký theo IP: 10 lần trong 10 phút, dùng bộ nhớ process có khóa. Chạy nhiều process/host cần kho rate-limit dùng chung trước khi public. Đây không phải WAF hoặc cơ chế chống DDoS.
- Validation cả HTML/JS và Python, constraints SQL là tầng cuối. Không tin tổng tiền hoặc giá do client gửi. Mọi số tiền lưu DECIMAL, không float.
- Frontend escape nội dung DB trước khi đưa vào HTML. CSP chỉ cho script/style cùng origin, cấm nhúng frame, không inline script hoặc CDN phụ thuộc. CSV export xử lý tiền tố có thể thành spreadsheet formula.
- Lỗi API thống nhất gồm code/message/request_id, không chuỗi kết nối, SQL raw, stack trace hay password. Log chỉ mã request, lớp lỗi và mã lỗi đã lọc. API booking chỉ trả 4 ký tự cuối giấy tờ.
- Chỉ dùng dữ liệu hành khách giả khi demo. Không nhập số thẻ hoặc giấy tờ thật. Không gửi email, SMS, analytics hoặc dữ liệu ra dịch vụ khác.

## Quyền SQL Server

Bước init/schema/seed cần tài khoản quản trị database. Chạy app bằng tài khoản riêng có quyền tối thiểu trong triển khai thật. Bản local đã kiểm thử dưới Windows Authentication có quyền rộng của máy thực hiện; chưa chứng nhận cấu hình least-privilege production. Các endpoint backend là ranh giới phân quyền người dùng ứng dụng. Không cấp sysadmin hoặc quyền DML trực tiếp cho khách hàng.

Đề xuất tách DB principal cho migration và runtime; runtime SELECT các view/danh mục, EXEC các procedure, quyền INSERT/UPDATE cần thiết trên Users/danh mục và AuditLogs cho các routes admin. Muốn hạn chế DML runtime hơn nữa, chuyển các thao tác catalog/auth sang stored procedures và chỉ cấp EXEC/SELECT. Kiểm thử lại dưới principal hạn chế trước khi triển khai công khai. Không tự động tạo login server hoặc thay đổi firewall từ bộ cài.

## Giới hạn đã công bố

Chỉ demo localhost. Chưa thực hiện penetration test, thử tải, failover, khôi phục backup hoặc xác minh TLS thực tế. Chưa cấu hình CI hay triển khai Internet. CSRF/rate-limit/cookie/permission có tests nhưng không tương đương kiểm toán an ninh toàn diện. App secret trong cookie phải giữ kín. Dùng reverse proxy TLS với chứng chỉ tin cậy nếu mở mạng; không bật debug.

Tài liệu tham khảo: [Flask Security Considerations](https://flask.palletsprojects.com/en/stable/web-security/) và [Flask Configuration](https://flask.palletsprojects.com/en/stable/config/).
