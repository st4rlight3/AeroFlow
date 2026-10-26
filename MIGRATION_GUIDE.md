# Nâng cấp trong nước và quốc tế — 26/10/2026

Bản hiện tại cần đủ **migrations 001–017**, không chỉ 001–014. 015 sửa tính nhất quán lịch/tuổi; 016 bổ sung quốc gia, khu vực, múi giờ sân bay và xử lý ngày địa phương cho tìm kiếm/đặt/đổi chuyến. 017 sửa metadata múi giờ Vancouver (YVR), ưu tiên British Columbia Standard Time, dự phòng Yukon Standard Time theo múi giờ cài trên host; không đổi thời điểm UTC hoặc lịch sử vé. Các migration đã ghi trong ledger là bất biến: sửa tiếp bằng migration mới, không thay checksum.

Database mới: init baseline một lần rồi migrate. Database đã có dữ liệu: **không chạy lại init/baseline**; dừng ứng dụng, xác nhận `.env`, tạo backup mới và migrate theo mục **Nâng cấp SQL Server** bên dưới. Sau đó xem trước/nhập toàn bộ lịch:

```powershell
python scripts/migrate.py
python scripts/migrate.py --apply --backup-file "C:\SQLBackups\AeroFlow_before_international_20261026.bak"
python scripts/load_demo.py --preview --start-date 2026-12-01 --days 62
python scripts/load_demo.py --apply --start-date 2026-12-01 --days 62
```

Có thể gọi riêng `seed_ultimate.py` rồi `seed_international.py` với cùng cửa sổ ngày; quốc tế không có `--apply` là preview. Hai bộ nhập có transaction riêng, chạy lại không nhân đôi và giữ lịch sử Bookings/Tickets/Payments. Database demo sạch sau nhập có **6.288 chuyến (2.232 nội địa + 3.936 quốc tế + 120 baseline), 42 sân bay, 170 đường bay, 74.376 dòng giá**; 32 sân bay quốc tế thuộc 20 quốc gia/vùng lãnh thổ ngoài Việt Nam. Database cũ có dữ liệu khác có thể có tổng khác.

SQL lưu UTC; tìm kiếm/ngày tính tuổi theo sân bay đi, giờ đến theo sân bay đến, có DST. Biểu mẫu Admin nhập lịch vẫn dùng giờ Việt Nam. Kiểm tra trong SSMS bằng `sql/demo/verify_international_catalog.sql` và truy vấn nội địa hiện có. Hồi quy quốc tế ban đầu, trước migration 017: **171 PASS**, `evidence/international-full-regression-20261026.xml`; kiểm chứng 017 đang chờ hoàn tất. Bằng chứng restore 001–014 bên dưới chỉ thuộc lần kiểm chứng cũ.

Các mục **Lịch sử** sau đây không còn là hướng dẫn nâng cấp hiện tại.

---

# Lịch sử 25/10/2026 — lịch nội địa cho buổi thuyết trình tháng 11

Mặc định mới của `python scripts/seed_ultimate.py --apply` là 01/12/2026–31/01/2027 khi chạy trong tháng 11: 2.232 chuyến, 26.784 giá vé. `--preview` xem trước; dùng `--start-date 2026-12-01 --days 62` để cố định. Thêm dữ liệu qua stored procedures trong transaction; nhập lại không nhân đôi. Backup, dừng ứng dụng và kiểm tra `.env` trước khi nhập. Không cần migration schema mới; 001–014 bất biến.

**Cài mới:** baseline 04 đặt lịch sang tháng 12 hoặc thời điểm còn trong tương lai, sửa hai vòng bay khứ hồi và vị trí khoang thương gia. **Database đã có:** không chạy lại init/baseline. Guard seed001 bảo vệ dữ liệu cũ, không chuyển ngày của vé đã phát hành. Allowlist giá bao phủ cả cách đánh số/đường bay baseline cũ và mới. Vé, booking và thanh toán giữ giá trị đã chốt. Chỉ chạy seed mới sau khi database đã đủ migrations 001–014.

Truy vấn SSMS `sql/demo/verify_demo_catalog.sql` kiểm tra cả vòng quay baseline mới. Nếu database cũ có lịch một chiều minh họa từ bản đầu, truy vấn vòng quay có thể báo các dòng cũ; đó không phải lỗi lịch mới. Muốn có database thuyết trình sạch, tạo database demo mới theo README thay vì ghi đè database đang có. Không tự xóa chuyến hoặc dữ liệu của khách.

---

# Lịch sử 25/10/2026 — cập nhật lịch và giá mẫu

Bản này không đổi schema, không sửa migrations 001–014. Database đã nâng cấp đủ 14 phiên bản chỉ cần thay source, dừng website, sao lưu rồi `python scripts/seed_ultimate.py --preview --days 30` và `python scripts/seed_ultimate.py --apply --days 30`. Chọn đúng `.env` trước khi chạy. Database mới vẫn phải init baseline rồi migrate theo phần dưới.

Seeder nhập lịch bằng stored procedures trong một transaction; lỗi sẽ rollback. Chỉ repricing FlightFares của các chuyến tương lai SCHEDULED đúng allowlist của seed gốc (VN-AF1–4/AF100–103 và DEMO-ULT-1–2/UA100–203 đúng đường bay) cùng máy bay DEMO-AF/LS/BA do seed mới quản lý. Không cập nhật Tickets, Bookings, Payments, chính sách hạng đã có hoặc lịch/giá chuyến Admin tự tạo. Không thay sơ đồ ghế máy bay cũ. Nếu layout của máy bay mới đã bị thay đổi, importer dừng thay vì tự ghi đè.

Mở SSMS kết nối instance SQL_SERVER trong `.env`, chọn SQL_DATABASE và kiểm tra bằng `sql/demo/verify_demo_catalog.sql` (đổi dòng USE cho database khác AeroFlow). Giá tổng demo dùng mức thuế mô phỏng 10% hiện có, không phải phép tính thuế/phí hàng không theo quy định thực tế. Mã nguồn tham khảo công khai và công thức giá nằm trong `scripts/demo_price_reference.json` và `scripts/demo_catalog.py`.

---

# Nâng cấp SQL Server

Không DROP database. Không chạy lại baseline `init_db.py` trên database đã áp dụng Ultimate.

1. Dừng ứng dụng và tác vụ hết hạn giữ ghế trong cửa sổ bảo trì.
2. Kiểm tra `.env` trỏ đúng database và chạy `python scripts/migrate.py` để xem phiên bản.
3. Dùng đường dẫn backup mới trên máy SQL Server, nơi tài khoản dịch vụ SQL Server có quyền ghi:

```powershell
python scripts/migrate.py --apply --backup-file "C:\SQLBackups\AeroFlow_before_international_20261026.bak"
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

**Bằng chứng lịch sử ngày 14/10/2026:** đã chạy 001–014, backup CHECKSUM/VERIFYONLY và restore sang DB khác, hash 16 bảng gốc PASS: evidence/ultimate-fresh-upgrade-restore.json. Tái tạo bằng scripts/verify_upgrade.py --run (cần quyền SQL thích hợp, không tự xóa DB test). Vẫn phải tạo backup mới của database người dùng trước mỗi lần nâng cấp.

015–017 bổ sung quy tắc lịch máy bay, metadata sân bay, hàm ngày địa phương và sửa múi giờ YVR; xem phần đầu file. Sau migration khởi động lại Flask, kiểm tra /api/health và thử nghiệp vụ trên demo. `load_demo.py` là tùy chọn thêm cả dữ liệu nội địa/quốc tế; chạy khi website dừng để tránh tranh chấp khóa lịch/inventory. Không chạy lại baseline 02–08 sau nâng cấp.
