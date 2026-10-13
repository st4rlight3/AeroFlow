# Nâng cấp SQL Server

Không DROP database. Không chạy lại baseline `init_db.py` trên database đã áp dụng Ultimate.

1. Dừng ứng dụng và tác vụ hết hạn giữ ghế trong cửa sổ bảo trì.
2. Kiểm tra `.env` trỏ đúng database và chạy `python scripts/migrate.py` để xem phiên bản.
3. Dùng đường dẫn backup mới trên máy SQL Server, nơi tài khoản dịch vụ SQL Server có quyền ghi:

```powershell
python scripts/migrate.py --apply --backup-file "C:\SQLBackups\AeroFlow_before_ultimate_20261013.bak"
```

Công cụ thực hiện COPY_ONLY/CHECKSUM và RESTORE VERIFYONLY trước migration. VERIFYONLY không thay thế diễn tập restore. Không ghi đè file backup tồn tại. SQL Server từ xa cần đường dẫn thuộc máy server.

Mỗi migration chạy trong một transaction cùng bản ghi SchemaMigrations. Khi lỗi, toàn bộ phiên bản đang chạy rollback; phiên bản đã commit trước đó vẫn được ghi nhận. Checksum chuẩn hóa LF/CRLF và phát hiện migration cũ bị sửa. Chạy lại không áp dụng trùng phiên bản. Sao lưu trước mọi lần nâng cấp có phiên bản mới.

Database test riêng tên `AeroFlow_Test_*` có thể dùng `--apply --test-database`. Tùy chọn này bị từ chối trên database tên khác.

001 tạo BookingSegments, ánh xạ mỗi booking cũ thành chặng thứ nhất, giữ nguyên PNR, vé, thanh toán, chủ tài khoản và khóa ghế. Trigger tương thích tạo chặng khi luồng cũ tạo booking. Bookings.FlightID tạm giữ làm khóa chuyến đầu cho API cũ.

Nếu phải quay về bản cũ: dừng ứng dụng, giữ bản backup, phục hồi backup vào một database khác và đối chiếu dữ liệu trước khi đổi cấu hình. Không có down migration tự xóa bảng/dữ liệu.
