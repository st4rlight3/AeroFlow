# AeroFlow Ultimate

Website hàng không mô phỏng: HTML/CSS/JavaScript ↔ Flask ↔ pyodbc ↔ Microsoft SQL Server. Nâng cấp từ AeroFlow trên nhánh `feature/ultimate-upgrade`. Không có SQLite hoặc dữ liệu nghiệp vụ thay thế trong frontend.

Bản bàn giao 14/10/2026. Kết quả và giới hạn: **PROGRESS.md**. Các tài liệu học thuật/slide cũ được giữ nguyên nhưng chưa cập nhật cho Ultimate theo yêu cầu tạm hoãn của người dùng. Ưu tiên README này và MIGRATION_GUIDE.md khi vận hành.

## Chạy trên Windows

Cần Python 3.11+, SQL Server Express (đã thử bản 2022), Microsoft ODBC Driver 18 cùng kiến trúc Python. Không cần Docker. SSMS hữu ích để xem dữ liệu. Windows account cần quyền tạo database và backup khi cài/nâng cấp.

Giải nén **AeroFlow_Ultimate_Complete.zip**, mở PowerShell trong **AeroFlow-Ultimate** có `run.py`:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe scripts\configure.py
notepad .env
```

Không cần kích hoạt venv hoặc đổi ExecutionPolicy. `configure.py` sinh SECRET_KEY ngẫu nhiên và không ghi đè `.env` đã có. Kiểm tra:

```dotenv
SQL_SERVER=.\SQLEXPRESS
SQL_DATABASE=AeroFlow
SQL_DRIVER=ODBC Driver 18 for SQL Server
SQL_TRUSTED_CONNECTION=yes
SQL_ENCRYPT=no
SQL_TRUST_SERVER_CERTIFICATE=yes
HOST=127.0.0.1
PORT=5000
```

Cấu hình trên dành cho demo cục bộ. SQL Authentication: đặt `SQL_TRUSTED_CONNECTION=no`, điền username/password riêng trong `.env`. Không commit/gửi `.env`. Khi triển khai HTTPS cần chứng chỉ đáng tin cậy và `SESSION_COOKIE_SECURE=true`. Cookie mặc định `aeroflow_ultimate`; dùng tên khác nhau khi chạy nhiều bản trên cùng hostname.

**Database mới:** chạy bước sau. **Database đã có dữ liệu AeroFlow:** bỏ qua bước này.

```powershell
.\.venv\Scripts\python.exe scripts\init_db.py
```

**Cả cài mới và nâng cấp đều cần migrations trước khi chạy website:** dừng ứng dụng/tác vụ nền, chọn đường dẫn backup mới rồi chạy:

```powershell
.\.venv\Scripts\python.exe scripts\migrate.py
.\.venv\Scripts\python.exe scripts\migrate.py --apply --backup-file "C:\SQLBackups\AeroFlow_before_ultimate_20261014.bak"
.\.venv\Scripts\python.exe scripts\seed_ultimate.py --apply
.\.venv\Scripts\python.exe scripts\create_user.py --role ADMIN --email admin@example.com --name "Quan tri AeroFlow"
.\.venv\Scripts\python.exe run.py
```

Backup path là ví dụ: thư mục phải tồn tại trên **máy SQL Server**, tài khoản dịch vụ SQL Server có quyền ghi, file chưa tồn tại. Có thể dùng thư mục Backup mặc định của instance. Lỗi backup sẽ dừng migration; không cấp quyền rộng cho toàn ổ đĩa. Runner dùng COPY_ONLY/CHECKSUM và VERIFYONLY trước migration. Xem MIGRATION_GUIDE.md.

`seed_ultimate.py` là bước tùy chọn cho demo: thêm hai máy bay, bốn khoang, 12 hạng Basic/Standard/Flexible, 84 chuyến trong 14 ngày từ ngày UTC hiện tại + 2. Có HAN–SGN–HAN và HAN–DAD–SGN nối 90 phút. Chạy lại cùng ngày không nhân đôi; ngày sau chỉ thêm lịch còn thiếu. Không ghi đè dữ liệu cũ. Chạy khi website đã dừng.

Nhập mật khẩu Admin kín, 12–128 ký tự; **không có mật khẩu mặc định**. Mở **http://127.0.0.1:5000/#ultimate**. Khách đăng ký qua web. Admin đăng nhập → Quản trị. `/api/health` kiểm tra SQL Server. Không chạy `init_db.py` hoặc baseline 02–08 để ghi đè database đã nâng cấp.

## Chức năng và quy tắc mô phỏng

- Một chiều, khứ hồi, nhiều thành phố; tìm tối đa một điểm nối mỗi nhóm. Lịch giá ±3 ngày, lọc hãng/ngân sách/điểm dừng, sắp xếp giá/thời lượng/khởi hành, bốn khoang, so sánh điều kiện vé.
- Một PNR nhiều chặng, tối đa 9 khách; cần người lớn, mỗi người lớn tối đa một em bé. Tuổi xác minh theo ngày bay; em bé có ghế riêng. Nối cùng sân bay 60 phút–8 giờ; tối đa 6 nhóm/12 chặng; đóng bán trước giờ lịch 2 giờ.
- Hành khách lưu sẵn, hỗ trợ đặc biệt, chọn ghế từng người/từng chặng hoặc tự xếp. Ghế ưu tiên có phí. Chọn trên màn hình chưa giữ ghế; xác nhận đặt chỗ giữ 10 phút theo đồng hồ SQL Server.
- Hành lý/suất ăn/ưu tiên/phòng chờ. Mỗi vé một loại suất ăn. Một promo/voucher hoặc điểm, không cộng dồn. Điểm đổi 1.000 VND/điểm, tối đa 50% đơn; điểm được giữ cùng đơn HELD. Giá/thuế/phí/giảm giá do server tính.
- Thanh toán thất bại/thử lại/thành công hoặc travel credit đều mô phỏng. Idempotency key chống xử lý lặp. Chỉ chủ PNR hoặc Admin được đọc đặt chỗ.
- Đổi ngày/chuyến/nâng khoang cho toàn bộ khách của một chặng còn đủ vé hợp lệ, cùng đường bay, trước giờ lịch ít nhất 24 giờ, chưa check-in và hạng cũ cho đổi. Thu/hoàn chênh lệch MOCK, tự xếp ghế mới, giữ vé cũ VOID và lịch sử. Không chia PNR hoặc tự đổi sân bay; chênh lệch không tự chuyển sang credit.
- Hủy riêng vé hoặc cả đơn trước giờ lịch ít nhất 24 giờ; hoàn theo snapshot vé/dịch vụ sau phân bổ giảm giá. Hủy riêng cho chọn credit. Hãng hủy một chặng thì hủy toàn PNR và hoàn số đã thu trừ đã hoàn, không hoàn trùng. Phí đổi không hoàn khi khách tự hủy.
- Điểm mới: 1 điểm/10.000 VND thanh toán; hoàn tiền điều chỉnh điểm; số khả dụng tối thiểu 0. Không cộng hồi tố trước nâng cấp. Hạng thành viên theo điểm tích lũy ròng, độc lập điểm đã dùng.
- Check-in từng vé/chặng từ 24 giờ đến 1 giờ trước giờ dự kiến. QR DEMO chứa tham chiếu ngẫu nhiên. Admin nhập tham chiếu để xác minh và ghi nhận lên máy bay khi chuyến BOARDING. PDF vé, boarding pass, biên nhận và báo cáo vận hành có nhãn mô phỏng.
- Admin quản lý danh mục/đường bay/lịch/ghế/giá/dịch vụ/ưu đãi/hạng thành viên, khách/booking/giao dịch/refund, check-in/cửa/chậm chuyến, audit và báo cáo CSV/PDF. Biểu đồ đọc SQL Server. Báo cáo theo UTC; lịch bay hiển thị UTC+7.

SQL dùng DECIMAL(14,2); API trả tiền bằng chuỗi, giao diện VND làm tròn đến đồng. Tổng booking sau thanh toán thể hiện tổng các lần thu; khoản hoàn xem trong lịch sử. PDF vé gồm dịch vụ/ưu đãi của vé; phí đổi riêng ở biên nhận. Snapshot hành lý và điều kiện đổi giữ nguyên khi sửa danh mục.

## Tác vụ bổ sung

- PDF dùng `C:/Windows/Fonts/arial.ttf`; nếu thiếu đặt `PDF_FONT_PATH` tới TTF Unicode. PDF đã tải không tự cập nhật sau đổi/hủy: tra lại website.
- `python scripts/expire_holds.py`: dọn giữ ghế; có thể chạy mỗi phút bằng Windows Task Scheduler, đúng venv/thư mục dự án/Windows account. Các API ghế/đặt/thanh toán cũng dọn hết hạn; không cần SQL Server Agent.
- Admin → Khai thác & check-in → tạo nhắc chuyến, chống trùng. Cửa/delay do Admin nhập, không kết nối dữ liệu hàng không thật.
- Email: khách bật tùy chọn; cấu hình SMTP trong `.env`. `python scripts/send_notifications.py` chỉ dry run. Người vận hành chủ động chạy `python scripts/send_notifications.py --send --limit 20` để gửi STARTTLS; tối đa 5 lần thử, trạng thái lưu SQL. Chưa kiểm chứng SMTP thật; có thể gửi lặp nếu crash sau gửi nhưng trước ghi nhận SQL, không bảo đảm exactly-once email.
- Reset mật khẩu: người vận hành xác minh chủ tài khoản rồi chạy `python scripts/issue_reset_token.py --email <email>`. Token một lần, hạn 15 phút, chỉ lưu SHA-256; nhập tại `/#reset-password`. Chưa có email reset tự động. Đổi/reset kết thúc phiên cũ.

## SQL và kiểm thử

Baseline: **01 → 02 → 03 → 05 → 06 → 07 → 08 → 04**, vì seed gọi procedure/function/trigger thực. Sau đó migrations **001 → 014** bằng runner ledger/checksum. `09_business_queries.sql` có 18 truy vấn; `10_test_cases.sql` kiểm tra ràng buộc/rollback. SSMS scripts mặc định `USE AeroFlow`; kiểm tra database trước khi chạy. Runner kiểm tra và thay tên database hợp lệ.

Tạo database test riêng, không dùng dữ liệu thật:

```powershell
$env:SQL_DATABASE="AeroFlow_Test_Local"
.\.venv\Scripts\python.exe scripts\init_db.py
.\.venv\Scripts\python.exe scripts\migrate.py --apply --test-database
$env:RUN_SQL_TESTS="1"
.\.venv\Scripts\python.exe -m pytest -q --junitxml=evidence\local-tests.xml
.\.venv\Scripts\python.exe scripts\verify_database.py --prefix local-
Remove-Item Env:RUN_SQL_TESTS
Remove-Item Env:SQL_DATABASE
```

`--test-database` chỉ cho `AeroFlow_Test_*`. Tests cố tình gây lỗi/tạo tài khoản và chuyến thử, giữ dữ liệu chứng minh trong DB đó. `python scripts/verify_upgrade.py --run` tạo các database tên riêng, kiểm tra baseline → migrate → no-op → backup/restore và hash cột cũ; cần quyền tạo/backup/restore và không tự xóa DB sau chạy.

Inventory dùng applock Exclusive cấp transaction chung + unique filtered index ghế hiệu lực. Bảo vệ toàn hành trình, rollback nhất quán; giới hạn thông lượng, chưa kiểm thử tải lớn. Queries có tham số, hash scrypt, backend kiểm tra quyền/CSRF/session. Chưa pentest độc lập.

## Demo nhanh và Git

1. Seed Ultimate, tìm HAN → SGN ngày có UA100. Chọn Flexible và A6 có phí hoặc tự xếp miễn phí. Có thể chọn khứ hồi hoặc nối qua DAD.
2. Đặt vé, thêm hành lý, mã `ULTIMATE10` hoặc `DEMO100K` khi còn hiệu lực; thử thanh toán thất bại rồi thành công. Mở SSMS xem Bookings/BookingSegments/Tickets/Payments.
3. `pytest tests/test_itineraries.py -q` chứng minh tranh chấp ghế chặng dùng chung; chỉ một khách thành công.
4. Đổi ngày/nâng khoang, xem giá chênh lệch/vé cũ VOID; hủy riêng hoàn credit. `tests/test_exchange_wallet.py` kiểm tra chi tiêu credit đồng thời.
5. Admin mở dashboard, doanh thu, danh mục và khai thác. Demo check-in cần chuyến trong cửa sổ 24–1 giờ; dùng fixture test tạo lịch riêng, không sửa trực tiếp chuyến đã bán của người dùng.
6. `tests/test_migrations.py`, `sql/10_test_cases.sql` và integration tests minh chứng rollback/ràng buộc. Kết quả mới ở `evidence/ultimate-*`.

Chưa push/merge main. Dùng ZIP cập nhật repo đã clone: chuyển nhánh `feature/ultimate-upgrade`, sao lưu thay đổi chưa commit, chép nội dung **bên trong AeroFlow-Ultimate** vào repo (không chép `.git`, không đè `.env`), xem diff, cài requirements, backup/migrate và test. Người dùng tự tạo PR/merge.

Đóng gói lại: `python scripts/package_release.py --output <đường-dẫn>\AeroFlow_Ultimate_Complete.zip`. ZIP chứa MANIFEST.sha256, kiểm tra CRC/từng byte; loại `.env`, venv, Git metadata, cache và backup DB.
