# AeroFlow — Intelligent Airline Reservation & Management System

Ứng dụng bài tập lớn DBMS, giao diện tiếng Việt, HTML/CSS/JavaScript + Flask + pyodbc + Microsoft SQL Server. **Không có chế độ SQLite, dữ liệu giả trong frontend hoặc thanh toán ngân hàng thật.**

## Trạng thái bàn giao

- Đã tạo và chạy trên SQL Server 2022 Express 16.0.1000.6, Python 3.12, ODBC Driver 18, Windows.
- 16 bảng (15 bảng nghiệp vụ + AuditLogs), 4 view, 2 function, 10 procedure, 6 trigger.
- Bộ seed: 120 chuyến, 396 ghế, 40 khách mẫu, 40 booking, 40 hành khách, 40 vé, 48 giao dịch.
- Kết quả kiểm thử thực tế và giới hạn: xem `TESTING.md`, `evidence/pytest-results.xml`, `evidence/sql-checks.json`.
- `docs/BAO_CAO.pdf` để in; `docs/AeroFlow_Slides.pptx` để thuyết trình; `DEMO.md` cho demo 10–15 phút.
- Tài khoản mẫu đều bị khóa. Không có mật khẩu quản trị mặc định. Người cài tự tạo tài khoản.

## 1. Điều kiện trên Windows

1. Python 3.11 trở lên và Python Launcher (`py`). Bản kiểm thử dùng Python 3.12.
2. Microsoft SQL Server 2019+ hoặc 2022 Express, dịch vụ `SQL Server (SQLEXPRESS)` đang chạy. SQL Server 2022 Express là bản đã kiểm chứng.
3. Microsoft ODBC Driver 18 for SQL Server đúng kiến trúc với Python (khuyến nghị cả hai 64-bit).
4. SSMS để quan sát DB và chạy các truy vấn trong demo. SSMS không bắt buộc để ứng dụng chạy.
5. Windows account có quyền tạo database cho bước khởi tạo. Phần mềm không tự cài hoặc đổi cấu hình SQL Server.

Liên kết chính thức: [Python Windows](https://www.python.org/downloads/windows/), [SQL Server Express](https://www.microsoft.com/en-us/sql-server/sql-server-downloads), [ODBC Driver](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server), [SSMS](https://learn.microsoft.com/en-us/ssms/install/install).

## 2. Cài đặt và chạy

Giải nén ZIP. Mở PowerShell tại thư mục `AeroFlow` có `run.py`:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe scripts\configure.py
notepad .env
```

Không cần kích hoạt môi trường ảo hoặc đổi ExecutionPolicy. Có thể dùng `scripts/setup.ps1` nếu máy cho phép chạy PowerShell script; các lệnh trên có tác dụng tương đương.

Trong `.env`, kiểm tra ít nhất:

```dotenv
SQL_SERVER=.\SQLEXPRESS
SQL_DATABASE=AeroFlow
SQL_DRIVER=ODBC Driver 18 for SQL Server
SQL_TRUSTED_CONNECTION=yes
SQL_ENCRYPT=no
SQL_TRUST_SERVER_CERTIFICATE=yes
```

`configure.py` sinh SECRET_KEY ngẫu nhiên. Giữ `.env` riêng trên máy, không commit hoặc gửi cùng ZIP. Dùng SQL Authentication thì đặt `SQL_TRUSTED_CONNECTION=no`, điền `SQL_USERNAME` và `SQL_PASSWORD`. Tên instance phải đúng máy cài, ví dụ `localhost` cho default instance. Cấu hình TLS trên dành cho demo cục bộ; xem `SECURITY.md` nếu triển khai ngoài localhost.

```powershell
.\.venv\Scripts\python.exe scripts\init_db.py
.\.venv\Scripts\python.exe scripts\create_user.py --role ADMIN --email admin@example.com --name "Quan tri AeroFlow"
.\.venv\Scripts\python.exe run.py
```

Nhập mật khẩu quản trị từ 12 ký tự khi được hỏi; công cụ không hiển thị mật khẩu. Mở **http://127.0.0.1:5000**. Tạo tài khoản Customer ở trang Đăng ký hoặc dùng `create_user.py --role CUSTOMER`. Email trong lệnh là ví dụ do người cài lựa chọn, không phải thông tin đăng nhập có sẵn.

Trang chủ tự đọc ngày bay đầu tiên và các tuyến đang mở bán từ SQL Server. Bộ seed sinh chuyến từ ngày UTC hiện tại + 2 đến + 31. Sau hơn 30 ngày, dùng quản trị tạo lịch mới hoặc tạo một database demo mới để sinh lịch mới. Không tự động xóa dữ liệu cũ.

## 3. Trình tự script SQL

Chạy tự động bằng `scripts/init_db.py` hoặc trong SSMS theo đúng thứ tự sau:

1. `01_create_database.sql`
2. `02_create_tables.sql`
3. `03_constraints_indexes.sql`
4. `05_views.sql`
5. `06_functions.sql`
6. `07_stored_procedures.sql`
7. `08_triggers.sql`
8. `04_seed_data.sql`
9. `09_business_queries.sql` để xem truy vấn
10. `10_test_cases.sql` để kiểm tra CHECK, UNIQUE, FK, ROLLBACK và các bất biến

**Lý do 04 chạy sau 08:** seed thật sự gọi procedure đặt vé/thanh toán/hủy, sử dụng function/view và tạo log qua trigger. File 05 không phụ thuộc function; file 06 có function đọc view. Không chạy theo thứ tự tên file một cách máy móc.

Khởi tạo không DROP DATABASE, không DROP TABLE. DDL bỏ qua schema đã có; indexes kiểm tra tồn tại; objects dùng CREATE OR ALTER; seed dùng marker `seed001@aeroflow.example` và transaction toàn bộ. Chạy lại trên cùng phiên bản không nhân đôi dữ liệu. Đây không phải hệ thống migration cho schema đã bị sửa hoặc phiên bản cũ: nếu schema khác, tạo database mới `AeroFlow_<suffix>` và cập nhật `.env`. `init_db.py` chỉ nhận tên `AeroFlow` hoặc `AeroFlow_<letters_digits_underscores>`.

Scripts SSMS mặc định `USE AeroFlow`. Runner tự thay tên DB đã kiểm tra hợp lệ. Không tự sửa script thành một database đang phục vụ hệ thống khác.

## 4. Chức năng

Khách hàng: đăng ký/đăng nhập/đăng xuất, tìm chuyến theo tuyến/ngày/số khách, chi tiết và hạng vé, sơ đồ ghế theo máy bay, nhập hành khách, xác nhận/giữ ghế, mô phỏng thanh toán thành công/thất bại, in vé điện tử, lịch sử đặt vé/giao dịch, hồ sơ, hủy cả booking.

Quản trị: dashboard từ view và function, tạo/sửa chuyến chưa có lịch sử booking, cập nhật trạng thái, giá từng hạng, quản lý sân bay/hãng bay/máy bay/sơ đồ ghế/hạng vé, tra cứu booking, khóa/kích hoạt khách hàng, doanh thu theo ngày và CSV, giao dịch, nhật ký. Tạo máy bay tự sinh sơ đồ 6 cột A–F, số hàng do admin nhập. Sơ đồ đã có chuyến bay không được sửa để bảo toàn lịch sử.

Quy tắc: một chiều, tối đa 9 khách/booking, mọi khách có ghế riêng, đóng bán trước 2 giờ, giữ ghế 10 phút theo thời gian SQL Server UTC, hủy sau thanh toán trước khởi hành ít nhất 24 giờ, hoàn theo điều kiện chốt trên vé. Khi hãng hủy chuyến, hoàn đủ giá vé đã thanh toán. Không hỗ trợ đổi vé, khứ hồi/nối chuyến, infant-on-lap hoặc tiền tệ khác VND trong phạm vi này.

Giá hiển thị là giá đã gồm thuế. Backend không sử dụng giá tiền do client gửi. Điểm dữ liệu duy nhất là SQL Server. Mất DB trả lỗi 503, không thay bằng bộ dữ liệu frontend.

## 5. Giữ ghế và tác vụ định kỳ

Truy vấn ghế, chi tiết/lịch sử booking, đặt vé và thanh toán đều dọn giữ ghế hết hạn bằng procedure chung. Chạy thêm tác vụ sau mỗi phút qua Windows Task Scheduler nếu muốn giải phóng ngay cả khi không có truy cập:

```powershell
.\.venv\Scripts\python.exe scripts\expire_holds.py
```

Task Scheduler: Program là đường dẫn tuyệt đối tới `.venv\Scripts\python.exe`; Arguments là đường dẫn `scripts\expire_holds.py`; Start in là thư mục dự án. Dùng account Windows có quyền kết nối DB. Không cần SQL Server Agent (Express không có Agent chạy lịch).

## 6. Kiểm thử lại

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_unit.py -q
$env:SQL_DATABASE="AeroFlow_Test_Local"
.\.venv\Scripts\python.exe scripts\init_db.py
$env:RUN_SQL_TESTS="1"
.\.venv\Scripts\python.exe -m pytest -q --junitxml=evidence\pytest-results.xml
Remove-Item Env:RUN_SQL_TESTS
Remove-Item Env:SQL_DATABASE
.\.venv\Scripts\python.exe scripts\verify_database.py
```

Integration suite tạo thêm dữ liệu và trigger lỗi tạm thời trong DB test, tự gỡ trigger ở `finally`. Không chạy suite này trên DB demo/production. Biến `SQL_DATABASE` trong phiên shell ưu tiên `.env`; đóng shell hoặc gỡ biến sau kiểm thử. DB test chỉ chấp nhận tên bắt đầu `AeroFlow_Test_`. Giữ database test để kiểm tra bằng chứng hoặc tự xóa sau khi không còn cần.

## 7. Tổ chức mã nguồn

```text
AeroFlow/
  app/                 Flask factory, configuration, security, validation, database
    routes/            auth, flights, bookings, admin
    services/          booking orchestration and ownership
    templates/         HTML shell
    static/            CSS, JavaScript and original SVG logo
  sql/                 10 required T-SQL scripts
  scripts/             configure, init_db, create_user, expire_holds, verify_database
  tests/               unit/security and real SQL integration tests
  docs/                source assignment, report PDF/source, ERD, slide PPTX
  evidence/            actual test results, SQL inventory, browser evidence
  .env.example         configuration template, no real secrets
  requirements.txt
  run.py               Waitress localhost entrypoint
```

`SOURCE_MANIFEST.sha256` đối chiếu các file được đóng gói. Git snapshot/history đi kèm trong `source-history.bundle`, không chứa `.env`, deps, dữ liệu runtime hoặc tài khoản thử. Có thể khôi phục bằng `git clone source-history.bundle AeroFlow-history`, hoặc `git init` ngay trong thư mục giải nén để phát triển tiếp.

## 8. Khắc phục lỗi

| Hiện tượng | Kiểm tra |
|---|---|
| ODBC driver not found | Cài ODBC Driver 18 64-bit, Python 64-bit; kiểm tra tên SQL_DRIVER |
| Không kết nối database / 503 | Kiểm tra dịch vụ SQL Server, đúng instance, `.env`, Windows login có quyền DB |
| Login failed for user | Kiểm tra Windows Authentication hoặc SQL user; không đưa mật khẩu vào lỗi API |
| Certificate verify failed | Demo localhost có thể dùng TrustServerCertificate=yes; triển khai thật dùng chứng chỉ tin cậy |
| SECRET_KEY chưa cấu hình | Chạy configure.py, không dùng placeholder trong .env.example |
| Không có chuyến | Kiểm tra ngày, tuyến, giá vé và số ghế; seed chỉ có cửa sổ 30 ngày từ lúc khởi tạo |
| Không sửa được sơ đồ/lịch | Dữ liệu đã có lịch sử: tạo máy bay/chuyến mới theo quy tắc bảo toàn vé |
| Ghế vừa bị giữ | Tải lại sơ đồ. SQL Server quyết định quyền sở hữu ghế, giao diện chỉ tham khảo |

Không in mật khẩu, chuỗi kết nối hoặc stack trace trong phản hồi. Mã request có trong thông báo lỗi để đối chiếu log an toàn.
