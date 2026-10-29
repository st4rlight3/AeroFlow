# Nâng cấp database đã có dữ liệu

Hướng dẫn này dành cho nhánh `feature/consolidated-sql`, sau khi bạn đã cài thư viện và sửa `.env` theo README.

**Cài mới:** chạy `scripts/init_db.py` như README. Các SQL script chính đã bao gồm toàn bộ thay đổi đến phiên bản 017; bạn không cần thực hiện các bước nâng cấp bên dưới.

**Đã có database của nhánh đặt vé trước đây:** giữ database đó và dùng hướng dẫn này. Thư mục `sql/migrations` được giữ nguyên để cập nhật dữ liệu cũ, không phải bước bắt buộc sau mỗi lần cài mới.

**Migration** là các bước cập nhật cấu trúc database đã được dự án chuẩn bị sẵn. Công cụ sẽ chạy những bước còn thiếu; bạn không cần tự sửa file SQL.

## 1. Chuẩn bị

- Nếu website đang chạy, nhấn `Ctrl+C` trong cửa sổ PowerShell đó để dừng.
- Nếu đã cài tác vụ tự động hết hạn giữ ghế, tạm dừng tác vụ trong lúc nâng cấp.
- Kiểm tra `SQL_SERVER` và `SQL_DATABASE` trong `.env` trỏ đúng database hàng không. Database của nhánh Marketplace cần để riêng.
- Nếu đang cài mới và chưa chạy `scripts/init_db.py`, làm bước khởi tạo database trong README trước. Nếu database đã có dữ liệu, bỏ qua `init_db.py`.

Mọi lệnh PowerShell dưới đây chạy trong thư mục có `run.py`.

## 2. Xem các bước còn thiếu

```powershell
.\.venv\Scripts\python.exe scripts\migrate.py
```

`APPLIED` nghĩa là bước đó đã chạy; `IN_BASELINE` nghĩa là thay đổi đã nằm trong bộ SQL gộp khi cài mới; `PENDING` nghĩa là còn thiếu. Nếu toàn bộ **001–017** đều là `APPLIED` hoặc `IN_BASELINE`, chuyển thẳng đến bước 5 bên dưới.

## 3. Lấy lệnh sao lưu và nâng cấp trong SSMS

Công cụ cần tạo bản sao lưu trước khi thay đổi database. Dùng thư mục backup sẵn có của SQL Server để tránh nhập nhầm đường dẫn.

1. Mở **SSMS**, kết nối đúng server đang ghi trong `.env`.
2. Bấm **New Query** để mở ô viết SQL.
3. Dán đoạn SQL sau vào ô đó, rồi nhấn **F5** hoặc bấm **Execute**:

```sql
DECLARE @folder nvarchar(4000) =
    CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultBackupPath'));

SELECT N'.\.venv\Scripts\python.exe scripts\migrate.py --apply --backup-file "'
    + @folder
    + CASE WHEN RIGHT(@folder, 1) IN (N'\', N'/') THEN N'' ELSE N'\' END
    + N'AeroFlow_before_upgrade.bak"' AS LenhCanChay;
```

4. Bên dưới sẽ xuất hiện một ô kết quả trong cột **LenhCanChay**. Sao chép toàn bộ nội dung của ô đó. Đây là lệnh PowerShell đã có sẵn đường dẫn backup theo máy bạn.

## 4. Chạy lệnh vừa lấy

Quay về PowerShell của dự án, dán lệnh đã sao chép ở bước 3 rồi Enter. Đoạn SQL ở trên chạy trong SSMS; lệnh tạo ra từ ô kết quả chạy trong PowerShell.

Chương trình sẽ sao lưu, kiểm tra bản sao lưu rồi áp dụng các bước còn thiếu. Chờ chương trình kết thúc và trả lại dòng lệnh.

Nếu chương trình báo file `AeroFlow_before_upgrade.bak` đã tồn tại, giữ lại bản backup đó và đổi tên file trong lệnh, ví dụ thành `AeroFlow_before_upgrade_2.bak`, rồi chạy lại. Tài khoản dịch vụ SQL Server cần có quyền ghi vào thư mục backup; nếu báo thiếu quyền, xử lý quyền thư mục trước khi tiếp tục.

Kiểm tra lại:

```powershell
.\.venv\Scripts\python.exe scripts\migrate.py
```

Khi các phiên bản **001–017** đều hiện `APPLIED` hoặc `IN_BASELINE`, cấu trúc database đã sẵn sàng cho nhánh này. Nếu báo `CHECKSUM_MISMATCH`, kiểm tra đúng nhánh và file migration; không tự sửa hoặc xóa các file đã áp dụng để bỏ qua lỗi.

## 5. Tiếp tục cài đặt hoặc mở lại web

Nếu đang cài lần đầu, quay lại **bước 5 của [README.md](README.md)** để nạp dữ liệu mẫu, rồi làm bước 6 để mở website. Không cần chạy thêm lệnh khởi tạo database trong hướng dẫn này.

Nếu chỉ nâng cấp một bản đã cài, làm theo mục **Những lần mở web tiếp theo** trong README để chạy lại chương trình. Bật lại tác vụ hết hạn giữ ghế nếu bạn đã tạm dừng ở bước 1.

Không chạy lại `init_db.py` hoặc các file baseline SQL trên database đã nâng cấp.

Chỉ khi tự chuẩn bị database kiểm thử riêng có tên `AeroFlow_Test_*`, bạn mới dùng cờ `--test-database` thay cho bản sao lưu. Cài đặt và nâng cấp thông thường làm theo quy trình backup ở trên.
