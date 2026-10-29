# AeroFlow — Hướng dẫn chạy trên Windows

Hướng dẫn cho nhánh `feature/consolidated-sql`. Bạn sẽ chạy website và lưu dữ liệu trong SQL Server trên máy của mình. Các file SQL đã bao gồm toàn bộ cấu trúc và nghiệp vụ đến phiên bản 017.

## 1. Cài những phần mềm cần dùng

Nếu đã có phần mềm trong bảng, bạn không cần cài lại.

| Phần mềm | Công dụng |
| --- | --- |
| [Python 3.11 trở lên, bản 64-bit](https://www.python.org/downloads/windows/) | Chạy chương trình AeroFlow. |
| [SQL Server Express](https://www.microsoft.com/en-us/sql-server/sql-server-downloads) | Lưu tài khoản, chuyến bay, giá và vé đã đặt. |
| [SQL Server Management Studio — SSMS](https://learn.microsoft.com/en-us/ssms/install/install) | Kết nối và xem dữ liệu trong SQL Server. Cài cả SQL Server Express và SSMS. |
| [Microsoft ODBC Driver 18 for SQL Server](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server) | Cho phép chương trình Python kết nối SQL Server. |
| [Git for Windows](https://git-scm.com/install/windows) | Tải và cập nhật mã nguồn từ GitHub. Có thể bỏ qua nếu dùng file ZIP. |

Mở **PowerShell** từ menu Start, nhập lệnh dưới rồi nhấn Enter:

```powershell
python --version
```

Kết quả cần là `Python 3.11` hoặc phiên bản mới hơn. Nếu máy báo không tìm thấy `python`, hoàn tất cài Python rồi mở lại PowerShell trước khi tiếp tục.

## 2. Tải mã nguồn

**Nếu dùng GitHub**, chạy lần lượt hai lệnh:

```powershell
git clone --branch feature/consolidated-sql --single-branch https://github.com/st4rlight3/AeroFlow.git
cd AeroFlow
```

**Nếu dùng ZIP**, giải nén ra một thư mục bình thường. Mở thư mục có các file `run.py`, `requirements.txt` và thư mục `app`. Bấm vào thanh địa chỉ của File Explorer, gõ `powershell` rồi Enter để mở cửa sổ lệnh ngay tại đó.

Từ đây, mọi lệnh PowerShell đều phải chạy trong **thư mục có `run.py`**. Mỗi dòng là một lệnh riêng: nhấn Enter và chờ lệnh chạy xong rồi mới nhập dòng tiếp theo.

## 3. Cài thư viện và tạo file cấu hình

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe scripts\configure.py
```

`.venv` là thư mục Python riêng cho dự án. Dòng thứ hai cài các thư viện cần dùng; dòng cuối tạo file `.env` chứa cấu hình kết nối.

Khi thấy `Created .env`, file đã được tạo. Nếu thấy `.env already exists; preserved.`, chương trình giữ lại file bạn đã có.

## 4. Kết nối đúng SQL Server

1. Mở **SSMS**. Trong cửa sổ **Connect to Server**, chọn **Server type: Database Engine** và **Authentication: Windows Authentication**.
2. Kết nối bằng tên SQL Server trên máy bạn. Nếu cài Express với tên mặc định, tên thường là `.\SQLEXPRESS`. Giữ lại đúng giá trị **Server name** đã kết nối thành công.
3. Quay về PowerShell của dự án, mở file cấu hình:

```powershell
notepad .env
```

Sửa các dòng sau trong file, rồi lưu bằng `Ctrl+S`:

```dotenv
SQL_SERVER=.\SQLEXPRESS
SQL_DATABASE=AeroFlow
SQL_DRIVER=ODBC Driver 18 for SQL Server
SQL_TRUSTED_CONNECTION=yes
HOST=127.0.0.1
PORT=5000
```

- **`SQL_SERVER`**: thay bằng đúng **Server name** bạn dùng trong SSMS.
- **`SQL_DATABASE`**: tên cơ sở dữ liệu của dự án. Giữ `AeroFlow` nếu đang cài lần đầu; bước tiếp theo sẽ tạo database này.
- **`HOST` và `PORT`**: để nguyên như trên khi cài lần đầu.
- Giữ các dòng cấu hình khác, nhất là **`SECRET_KEY`** do chương trình đã tạo. File cần giữ tên `.env`, không đổi thành `.env.txt`.

<details>
<summary>Nếu SSMS của bạn đăng nhập bằng SQL Server Authentication</summary>

Trong `.env`, đổi `SQL_TRUSTED_CONNECTION=no`, rồi điền `SQL_USERNAME` và `SQL_PASSWORD` bằng tài khoản SQL Server đang sử dụng. Các bước còn lại giống bên dưới.

</details>

## 5. Tạo database và thêm dữ liệu mẫu

**Cài lần đầu, chưa có database AeroFlow:** chạy một lần:

```powershell
.\.venv\Scripts\python.exe scripts\init_db.py
```

Lệnh này tạo đầy đủ bảng, ràng buộc, chỉ mục, function, view, stored procedure, trigger và dữ liệu nền. **Cài mới không cần chạy riêng các migration 001–017.** Nếu lệnh báo database đã có bảng, chương trình dừng để giữ dữ liệu cũ; xem trường hợp bên dưới.

**Đã có database từ nhánh đặt vé cũ:** bỏ qua `init_db.py`. Làm theo [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) để kiểm tra và nâng cấp khi cần. Nếu trước đó bạn cài nhánh Marketplace, chọn tên database khác cho nhánh đặt vé này.

Sau khi cài mới hoặc nâng cấp thành công, nạp bộ chuyến bay và giá vé mẫu:

```powershell
.\.venv\Scripts\python.exe scripts\load_demo.py --apply
```

Chờ chương trình chạy xong. Phần tạo database và cài thư viện chỉ làm khi cài đặt; những lần mở web sau không cần làm lại.

<details>
<summary>Nếu muốn tạo database bằng cách mở các file SQL trong SSMS</summary>

Dùng một database mới, rỗng. Các file `sql/01`–`sql/08` chứa định nghĩa cuối cùng; không cần chạy thêm thư mục `sql/migrations` cho lần cài mới.

Thứ tự chạy là **01 → 02 → 03 → 06 → 05 → 07 → 08 → 04**. File `06_functions.sql` phải chạy trước view dùng các hàm đó; `04_seed_data.sql` chạy cuối vì tạo đặt chỗ mẫu qua stored procedure. File `09_business_queries.sql` và `10_test_cases.sql` dùng để truy vấn, kiểm tra sau khi cài.

Trong SSMS, các script dùng tên database `AeroFlow`. Nếu bạn chọn tên khác, đổi `AeroFlow` trong file `01` và dòng `USE AeroFlow;` đầu các file. Không chạy bộ cài mới lên database đang có dữ liệu.

`sql/migrations` giữ lịch sử nâng cấp cho database cũ. `sql/demo` là các truy vấn kiểm tra dữ liệu mẫu. `tests/fixtures/legacy_sql` chỉ dùng cho automated tests kiểm chứng nâng cấp, không dùng để cài ứng dụng.

</details>

## 6. Khởi động và mở website

Trong PowerShell của dự án, chạy:

```powershell
.\.venv\Scripts\python.exe run.py
```

Khi khởi động, chương trình sẽ in địa chỉ:

```text
AeroFlow: http://127.0.0.1:5000
```

Mở Chrome, Cốc Cốc hoặc Edge, dán **địa chỉ vừa được in ra** vào thanh địa chỉ rồi Enter. Với cấu hình mặc định ở trên, địa chỉ là [http://127.0.0.1:5000](http://127.0.0.1:5000).

**Cách hiểu địa chỉ:** `127.0.0.1` chỉ máy tính bạn đang dùng. `5000` là **cổng**, tức số mà chương trình dùng để nhận kết nối từ trình duyệt. Bạn không phải tự chọn hay mở nhiều địa chỉ; chỉ dùng địa chỉ chương trình in ra.

**Giữ cửa sổ PowerShell mở trong lúc dùng web.** Cửa sổ có thể đứng chờ sau khi in địa chỉ; đây là lúc chương trình đang phục vụ website. Khi dùng xong, quay lại PowerShell và nhấn `Ctrl+C` để tắt chương trình.

<details>
<summary>Tùy chọn: dùng địa chỉ có số 5082 thay cho 5000</summary>

Chỉ cần phần này nếu bạn muốn dùng 5082 hoặc chương trình báo 5000 đang được ứng dụng khác sử dụng. Hai số này là hai lựa chọn cổng cho cùng ứng dụng.

1. Dừng chương trình bằng `Ctrl+C` trong PowerShell đang chạy web.
2. Mở `.env`, đổi dòng `PORT=5000` thành `PORT=5082`, lưu file.
3. Chạy lại `.\.venv\Scripts\python.exe run.py`.
4. Chương trình sẽ in `AeroFlow: http://127.0.0.1:5082`. Mở [http://127.0.0.1:5082](http://127.0.0.1:5082) để dùng web.

Nếu giữ `PORT=5000`, bạn vẫn dùng địa chỉ có số 5000. Khi đổi cổng, dùng địa chỉ mới mà chương trình in ra.

</details>

## 7. Đăng ký và đăng nhập

### Dùng như khách hàng

Trên website, bấm **Đăng nhập → Đăng ký**. Điền họ tên, email và mật khẩu từ **12 ký tự**. Sau khi đăng ký thành công, đăng nhập bằng tài khoản vừa tạo để đặt vé.

Tài khoản đăng ký trên web là tài khoản khách hàng. Bạn không cần tạo tài khoản quản trị để tìm chuyến bay hoặc đặt vé. Thanh toán trong ứng dụng là mô phỏng.

### Tài khoản quản trị — chỉ tạo nếu cần quản lý chuyến bay

Tài khoản này được phép quản lý chuyến bay, khách hàng, doanh thu và mã ưu đãi.

1. Nếu website đang chạy, quay về PowerShell và nhấn `Ctrl+C`.
2. Chạy lệnh dưới. Bạn có thể thay `admin@example.test` bằng email muốn dùng để đăng nhập:

```powershell
.\.venv\Scripts\python.exe scripts\create_user.py --role ADMIN --email admin@example.test --name "Quản trị AeroFlow"
```

3. Khi hiện `Password (12+ characters):`, nhập mật khẩu ít nhất 12 ký tự rồi Enter. Khi hiện `Confirm password:`, nhập lại cùng mật khẩu rồi Enter. **Mật khẩu không hiện ký tự khi gõ; đó là bình thường.**
4. Khi thấy `Account created.`, tài khoản đã được tạo. Chạy lại `.\.venv\Scripts\python.exe run.py`.
5. Mở địa chỉ chương trình in ra và đăng nhập bằng email, mật khẩu vừa tạo. Menu **Quản trị** sẽ hiện cho tài khoản này.

## 8. Những lần mở web tiếp theo

Mở thư mục dự án có `run.py`, gõ `powershell` vào thanh địa chỉ File Explorer rồi Enter. Chỉ cần chạy:

```powershell
.\.venv\Scripts\python.exe run.py
```

Sau đó mở địa chỉ PowerShell in ra. Không cần cài lại thư viện hoặc tạo lại database mỗi lần dùng.

<details>
<summary>Cập nhật bản đã tải bằng Git</summary>

Dừng website bằng `Ctrl+C`. Trong thư mục dự án, chạy:

```powershell
git pull
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Lệnh đầu tải thay đổi mới, lệnh sau cập nhật thư viện nếu cần. Xem [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) để kiểm tra database trước khi mở lại bằng `run.py`.

</details>

## Khi chưa chạy được

| Hiện tượng | Cách kiểm tra |
| --- | --- |
| Báo không tìm thấy `requirements.txt` hoặc `run.py` | PowerShell chưa mở đúng thư mục dự án. Mở thư mục có hai file này rồi mở lại PowerShell tại đó. |
| Báo không tìm thấy `.venv\Scripts\python.exe` | Kiểm tra lệnh `python -m venv .venv` ở bước 3 đã chạy thành công. |
| Báo thiếu ODBC Driver | Cài **ODBC Driver 18**, rồi kiểm tra tên `SQL_DRIVER` trong `.env`. |
| Không kết nối được database | Thử kết nối SSMS trước, rồi so lại `SQL_SERVER`, `SQL_DATABASE` và cách đăng nhập trong `.env`. |
| Trình duyệt không mở được trang | Kiểm tra PowerShell vẫn đang chạy `run.py` và địa chỉ trên trình duyệt khớp địa chỉ được in ra. |
| Báo cổng đang được sử dụng | Dừng bản web cũ nếu bạn đang chạy hai lần, hoặc làm phần tùy chọn đổi sang 5082 ở bước 6. |
| Tìm chuyến bay không có kết quả | Kiểm tra đã nạp dữ liệu ở bước 5 và đang tìm đúng ngày, đường bay có trong dữ liệu mẫu. |
