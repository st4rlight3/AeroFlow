# AeroFlow — Đặt vé máy bay

Nhánh `feature/presentation-demo-dec-jan`, dùng Flask và Microsoft SQL Server.

## 1. Chuẩn bị

Cài Git, Python 3.11 trở lên, SQL Server Express và Microsoft ODBC Driver 18 for SQL Server. Dùng SSMS để quản lý database.

## 2. Tải và cài dự án

Mở PowerShell:

```powershell
git clone --branch feature/presentation-demo-dec-jan --single-branch https://github.com/st4rlight3/AeroFlow.git
cd AeroFlow
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe scripts\configure.py
```

Nếu dùng ZIP, giải nén và mở PowerShell trong thư mục có `run.py`; bỏ qua hai lệnh `git clone` và `cd`.

## 3. Cấu hình kết nối

Mở `.env`, sửa tên server theo kết nối của bạn trong SSMS:

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

Giữ `SECRET_KEY` đã được tạo. Ví dụ trên dùng Windows Authentication; nếu dùng SQL Server Authentication, đặt `SQL_TRUSTED_CONNECTION=no`, rồi điền `SQL_USERNAME` và `SQL_PASSWORD`.

Nếu trước đó đã cài nhánh Marketplace, dùng database hàng không riêng hoặc tạo database khác cho nhánh này.

## 4. Khởi tạo database

**Database mới:** chạy một lần:

```powershell
.\.venv\Scripts\python.exe scripts\init_db.py
```

**Database đã có dữ liệu:** bỏ qua lệnh trên.

Áp dụng migrations theo [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md), rồi nạp dữ liệu mẫu:

```powershell
.\.venv\Scripts\python.exe scripts\load_demo.py --apply
```

## 5. Mở website

```powershell
.\.venv\Scripts\python.exe run.py
```

Mở [http://127.0.0.1:5000](http://127.0.0.1:5000). Giữ cửa sổ PowerShell đang chạy; nhấn `Ctrl+C` để dừng.

Muốn chạy cổng **5082**, sửa `PORT=5082` trong `.env`, chạy lại `run.py`, rồi mở [http://127.0.0.1:5082](http://127.0.0.1:5082). Nếu cổng đang được dùng, dừng ứng dụng cũ hoặc chọn cổng khác.

Khách hàng tạo tài khoản bằng nút **Đăng ký** trên website. Nếu cần tài khoản quản trị, chạy lệnh dưới và nhập mật khẩu khi được hỏi:

```powershell
.\.venv\Scripts\python.exe scripts\create_user.py --role ADMIN --email admin@example.test --name "Quản trị AeroFlow"
```

Đăng nhập ADMIN để hiện menu **Quản trị**; tài khoản khách hàng không có quyền này. Thanh toán trong ứng dụng là mô phỏng.

## 6. Những lần mở tiếp theo

```powershell
cd <thu-muc-du-an>
.\.venv\Scripts\python.exe run.py
```

Sau khi cập nhật mã nguồn bằng `git pull`, xem [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) trước khi nâng cấp database. Không chạy lại `init_db.py` trên database đã nâng cấp.
