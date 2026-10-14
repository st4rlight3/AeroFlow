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

002–004 thống nhất vé theo BookingSegmentID; giá cũ giữ LEGACY_TOTAL, không suy đoán lại thuế lịch sử. Luồng mới lưu BaseFare/TaxAmount/SeatFee. Một ghế đang giữ hoặc đã bán chỉ có một assignment đang hiệu lực. Hủy chuyến bất kỳ của hành trình hiện hoàn/hủy cả hành trình theo chính sách mô phỏng.

005 thêm hồ sơ lưu sẵn, tùy chọn, mã khôi phục (chỉ lưu SHA-256), thông báo, sổ điểm, hạng và check-in. Điểm chỉ tích cho giao dịch sau nâng cấp; không tự sửa giao dịch cũ. 006 thêm snapshot hỗ trợ hành khách. Mọi migration đã áp dụng là bất biến; sửa lỗi phải tạo phiên bản mới. Không chạy trực tiếp 02–08 để ghi đè procedure sau nâng cấp.


007–008: Services, BookingExtras, DiscountCodes, phân bổ giảm giá/vé, nhiều refund và hủy riêng; đồng bộ giá/thanh toán/hủy hãng. Cho sửa phí/ưu tiên ghế cho lần đặt mới; hình học đã có lịch sử vẫn bất biến.

009–011: TicketRules, BookingChanges, TravelCreditLedger, LoyaltySpends. SegmentOrder duy nhất ở ACTIVE; lịch sử EXCHANGED giữ cùng thứ tự. Payments thêm Purpose/Settlement, unique successful charge chỉ cho BOOKING; exchange có idempotency riêng. Hoàn hãng = tổng đã thu trừ đã hoàn. PNR và Bookings.FlightID gốc giữ nguyên.

012: Routes, NotificationDeliveries, EmailNotifications, BoardedAt và thủ tục boarding. 013: bảo vệ ExpectedAmount và đường bay tắt. 014: view lịch sử lấy ngày/chuyến của chặng hiện tại sau exchange.

Rules vé trước 009 ghi Source=LEGACY_CURRENT theo danh mục lúc nâng cấp; vé mới ISSUED_SNAPSHOT. Không suy đoán quy tắc quá khứ hoặc tạo điểm/ví giả hồi tố.

Đã chạy 001–014, backup CHECKSUM/VERIFYONLY và restore sang DB khác, hash 16 bảng gốc PASS: evidence/ultimate-fresh-upgrade-restore.json. Tái tạo bằng scripts/verify_upgrade.py --run (cần quyền SQL thích hợp, không tự xóa DB test). Vẫn phải tạo backup mới của database người dùng trước mỗi lần nâng cấp.

Sau migration khởi động lại Flask, kiểm tra /api/health và thử nghiệp vụ trên demo. Seed Ultimate là tùy chọn thêm dữ liệu DEMO; chạy khi website dừng để tránh tranh chấp khóa lịch/inventory. Không chạy lại baseline 02–08 sau nâng cấp.
