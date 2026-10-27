# Cài đặt và nâng cấp SQL Server

Chạy các lệnh trong thư mục dự án, sau khi cài thư viện và cấu hình `.env` theo README.

1. Dừng website bằng `Ctrl+C` và tạm dừng tác vụ hết hạn giữ ghế nếu đang chạy.
2. Kiểm tra `SQL_SERVER`, `SQL_DATABASE` trỏ đúng database hàng không. Nếu database thuộc nhánh Marketplace, dùng database khác cho nhánh này.
3. Database mới cần chạy `scripts/init_db.py` một lần; database đã có dữ liệu thì bỏ qua.
4. Kiểm tra phiên bản hiện tại:

```powershell
.\.venv\Scripts\python.exe scripts\migrate.py
```

5. Trong SSMS, lấy thư mục backup của SQL Server:

```sql
SELECT SERVERPROPERTY('InstanceDefaultBackupPath') AS BackupFolder;
```

6. Thay đường dẫn trong lệnh dưới bằng thư mục vừa lấy và chọn tên file chưa tồn tại. Thư mục thuộc máy chạy SQL Server; tài khoản dịch vụ SQL Server cần quyền ghi vào đó.

```powershell
.\.venv\Scripts\python.exe scripts\migrate.py --apply --backup-file "C:\SQLBackups\AeroFlow_before_upgrade.bak"
```

Công cụ sao lưu `COPY_ONLY`, kiểm tra backup rồi áp dụng các migrations còn thiếu. Nếu file backup đã tồn tại, chọn tên khác.

7. Chạy lại lệnh kiểm tra trạng thái: toàn bộ **001–017** phải là `APPLIED`. Không sửa hoặc xóa file migration đã áp dụng.
8. Nạp dữ liệu mẫu nếu cần, rồi mở website:

```powershell
.\.venv\Scripts\python.exe scripts\load_demo.py --apply
.\.venv\Scripts\python.exe run.py
```

Không chạy lại baseline SQL hoặc `init_db.py` trên database đã nâng cấp. Nếu báo checksum không khớp, kiểm tra lại nhánh và file migration trước khi tiếp tục.

Chỉ với database kiểm thử riêng có tên `AeroFlow_Test_*`, có thể dùng `--test-database` thay cho `--backup-file`. Không dùng cờ này cho database đang sử dụng.
