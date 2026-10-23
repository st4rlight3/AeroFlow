# Frontend refresh — 23/10/2026

Nhánh `feature/frontend-refresh` từ Ultimate `648139e`. Phiên này chỉ sửa frontend và tài liệu vận hành/bằng chứng. Các mục Ultimate bên dưới là lịch sử; nhánh tiếp tục hiện tại là frontend-refresh.

- Trang chủ mới có ảnh hàng không và 3 ảnh điểm đến minh họa AI, WebP local (tổng 637.084 bytes), các tuyến/giá/lịch truy vấn API thật.
- Giao diện đồng bộ cho tìm kiếm, so sánh giá, ghế, thông tin hành khách, vé, tài khoản và Admin. Không thêm dependency runtime, không sửa backend/schema SQL.
- Hiệu ứng vào trang, reveal khi cuộn, hover/nút/modal/toast, mây/đường bay/thẻ gợi ý. Nút tắt chuyển động nhớ lựa chọn, CSS prefers-reduced-motion, tạm dừng khi tab ẩn, unobserve phần tử đã bỏ để tránh giữ tham chiếu khi chuyển nhiều trang.
- Header chỉ báo trang hiện tại, progress khi tải, aria-busy vùng nội dung, focus về nội dung sau chuyển trang. Khứ hồi trên trang chủ chọn đúng loại hành trình; nút lên đầu trang đã thử về scrollY=0.
- **76 PASS, 0 FAIL, 0 SKIP (173.26s)** trên AeroFlow_Test_Frontend_20261023; evidence/frontend-regression.xml. Node --check toàn bộ JS PASS.
- Browser thật: khứ hồi HAN–SGN 26/10, SGN–HAN 29/10, Flexible/A6 (phí 80.000), một PNR C9FDB683 với 2 vé, trả mô phỏng 3.380.000 thành công; ảnh frontend-booking-mobile/seats-mobile.
- Desktop và mobile 390×844: trang chủ, tìm khứ hồi, ghế, booking và Dashboard không tràn ngang trang; bảng/lịch giá có vùng cuộn riêng. Dashboard còn kiểm tra viewport 360, 768, 1280. Ảnh frontend-home/admin-*. Tất cả 4 ảnh tải thành công; console không có lỗi trong các luồng đã thử.
- Nút tắt chuyển động, reload nhớ trạng thái và bật lại đã thử: animationName=none khi tắt, af-float/af-page-in khi bật. Giảm chuyển động theo OS được triển khai nhưng chưa ép bật cài đặt OS để thử; chưa thử Safari/iPhone/Android thật hoặc mọi trang/tổ hợp dữ liệu. Chưa chạy audit WCAG/Lighthouse độc lập.
- Chưa triển khai website lên host công cộng; đầu ra là nhánh mã nguồn GitHub. Không thay đổi main.

---

# AeroFlow Ultimate — trạng thái bàn giao

Ngày 14/10/2026, Asia/Saigon. Nhánh feature/ultimate-upgrade, base 5c16bed. Không sửa/push/merge main. ZIP mục tiêu: AeroFlow_Ultimate_Complete.zip.

## Phạm vi đã triển khai

| Nhóm | Nguồn chính | Bằng chứng |
|---|---|---|
| One-way/round-trip/multi-city/nối chuyến, tuổi, báo giá, giữ/ghế từng chặng | routes/services/itineraries.py; ultimate.js; migrations 001–004,006 | test_itineraries.py; ultimate-roundtrip-paid/seat-mobile |
| Bốn khoang, 12 hạng, lịch giá/lọc/sắp xếp, phí ghế | seed_ultimate.py; ultimate.js | Seed 84 chuyến rồi chạy lại 0; browser UA100/Flexible/A6 |
| Dịch vụ, promo/voucher/điểm, thanh toán, hủy riêng/refund/credit | commerce.py; commerce.js/manage.js; 007–011,013 | test_commerce.py; test_exchange_wallet.py; ảnh services-paid/wallet-refund |
| Đổi ngày/chuyến/nâng khoang, snapshot và idempotency | exchange.py; manage.js; 009–011,014 | tests exchange; ảnh ultimate-exchanged; summary ngày chặng mới |
| Tài khoản, khách lưu sẵn, hỗ trợ, tùy chọn, mật khẩu | auth/customer.py; customer.js; 005–006 | tests customer_operations/integration |
| PDF vé/boarding/QR DEMO, check-in/boarding, receipt | documents.py; customer/operations.py; 005,012 | tests customer/ultimate_operations; PDF/PNG mẫu trong evidence |
| Loyalty, in-app notices, trạng thái/gate/delay, nhắc chuyến | customer/operations.py; 005,011–012 | tests customer/operations; SMTP chỉ mock/dry run |
| Admin danh mục/lịch/khách/booking/giao dịch/ưu đãi/check-in/báo cáo | admin/commerce/operations.py; app.js/customer.js | tests integration/operations; ảnh admin-dashboard/mobile/service-save |
| Bảo toàn dữ liệu, backup/migration/restore | migrate.py; verify_upgrade.py; 001–014 | ultimate-fresh-upgrade-restore.json; test_migrations.py |

Phases 1–8 đã có mã nguồn, các luồng chính đã kiểm chứng. Đây là sản phẩm học tập mô phỏng; các giới hạn dưới đây vẫn áp dụng, không tuyên bố sẵn sàng thương mại.

## Kết quả thực chạy

- Full suite: **76 PASS, 0 FAIL, 0 SKIP, 173.43 giây**, evidence/ultimate-final-regression.xml. Lần trước 75 PASS/1 FAIL do kỳ vọng cũ từ chối no-op save ghế; đã sửa test theo quy tắc mới, vẫn kiểm tra chặn đổi hình học ghế đã có lịch sử.
- Bao phủ xác thực/phân quyền/CSRF/SQL injection/DB unavailable; tranh chấp ghế và chặng thứ hai; hết hạn cả hành trình; rollback/lỗi giá; payment fail/retry/idempotency; refund; promo cuối/credit đồng thời; điểm; đổi chặng; check-in đồng thời; boarding/QR quyền; PDF/ownership và migration.
- Cài mới → 14 migrations → chạy lại no-op → DBCC → restore backup vào DB khác: **PASS**, hash toàn bộ cột gốc 16 bảng không đổi. DB bằng chứng: AeroFlow_Test_Fresh_b6c3e82f46 và AeroFlow_Test_Restore_b6c3e82f46. Xem ultimate-fresh-upgrade-restore.json.
- SQL 09_business_queries và 10_test_cases: chạy không lỗi; bất biến không vi phạm. Inventory: **38 bảng gồm bảng phụ/audit/migration; 17 procedures; 4 scalar functions; 6 views; 12 triggers**. ultimate-database-inventory.json và ultimate-sql-checks.json. Số bản ghi trong DB hồi quy gồm test tích lũy, không phải seed chuẩn.
- Seed Ultimate ở DB mới tạo 84 chuyến; lần hai cùng ngày 0. Baseline có 120 Flights, 396 AircraftSeats, 40 Bookings/Passengers, 48 Payments.
- Browser phase trước: đăng ký/đăng nhập, khứ hồi, tự xếp ghế, thanh toán fail→success. Browser 14/10: Flexible/A6 phí 80.000; thêm hành lý/mã ULTIMATE10, trả 1.782.000; đổi ngày 17→18/10, nâng Business Flexible thu thêm 1.900.000; vé cũ VOID/mới VALID; hủy riêng vào credit; Dashboard, đường bay/dịch vụ và lưu dịch vụ tắt vào SQL.
- Responsive sơ đồ ghế và dashboard ở viewport 390×844 không tràn ngang trang, bảng/tab có vùng cuộn. Chưa kiểm tra mọi thiết bị/màn hình.
- PDF vé/boarding thật qua API: Unicode và DEMO PASS, mẫu 1 trang, đã render kiểm tra. Node --check JavaScript PASS; không lỗi console trong luồng khách đã kiểm tra.
- SMTP tạo nội dung qua mock và worker dry run PASS; không gửi email ra ngoài.

## Đối chiếu PDF giảng viên (đủ 3 trang)

| Yêu cầu | Kết quả |
|---|---|
| Hệ thống không quản lý sinh viên, ≥6 bảng chính | Đặt vé máy bay; baseline 16 bảng, Ultimate mở rộng nghiệp vụ |
| PK/FK/UNIQUE/NOT NULL/DEFAULT/CHECK | 02/03 + migrations; tests/DBCC thực chạy |
| 30–200 bản ghi trên các bảng phù hợp | 120 flights, 396 seats, 40 bookings/passengers ở baseline; thêm seed Ultimate |
| ≥10 queries đầy đủ nhóm cú pháp | 09 có 18 truy vấn INNER/LEFT/RIGHT/FULL, GROUP/HAVING, scalar/table subqueries, UNION/INTERSECT/EXCEPT, LIKE/BETWEEN/TOP/PERCENT |
| ≥3 procedures, ≥2 functions, ≥3 views | Thực tế 17/4/6, được API/dashboard sử dụng |
| Transaction/rollback/ràng buộc/index | SQL scripts, integration/concurrency tests PASS |
| README chạy SQL/ứng dụng | README và MIGRATION_GUIDE; fresh upgrade/restore đã chứng minh |
| ERD/3NF, báo cáo PDF/in, slide 10–15 phút | Ghi nhận; giữ tài liệu gốc; **tạm hoãn cập nhật/tạo mới báo cáo/slide/lý thuyết dài** theo phạm vi mới. Không coi docs cũ là báo cáo schema Ultimate |

## Giới hạn / NOT TESTED

- SMTP thật/giao nhận email chưa kiểm chứng; reset hiện do vận hành cấp token, chưa email reset tự động. Email có thể gửi trùng nếu crash trước ghi nhận SQL.
- Chưa pentest độc lập, tải lớn, mọi browser/mobile, HTTPS hoặc SQL Server từ xa. Applock inventory chung giới hạn thông lượng.
- Không GDS/hãng bay/ngân hàng/delay thật; chỉ VND; infant ghế riêng; không chia PNR; đổi toàn bộ khách của chặng. QR verify nhập tham chiếu, chưa camera scanner.
- API Admin được kiểm thử; browser đã kiểm dashboard/danh mục/lưu dịch vụ, chưa mọi tổ hợp form hoặc boarding camera.
- Vé cũ có LEGACY_TOTAL; rules cũ backfill LEGACY_CURRENT. Không suy đoán chi tiết giá hoặc quy tắc quá khứ.
- Tài liệu học thuật/ERD/slide gốc chưa cập nhật Ultimate theo yêu cầu tạm hoãn; yêu cầu kỹ thuật SQL vẫn được thực hiện.

Bằng chứng không có tiền tố ultimate- thuộc baseline. XML phase là lịch sử, không thay kết quả mới nhất. Không bàn giao credentials QA.

Kiểm tra sau sửa PDF và đọc snapshot hành lý: **34 PASS, 114.25 giây**, ultimate-release-fixes.xml (14/10/2026). Hai mẫu PDF phiên bản cuối đã render và kiểm tra một trang, đủ nhãn DEMO/tiếng Việt/QR.

Đã giải nén ZIP, xác minh toàn bộ MANIFEST/CRC và loại trừ .env/Git/venv/cache; **17 unit tests chạy từ nguồn đã giải nén PASS (1.16 giây)**, ultimate-zip-unit.xml. Các test SQL dùng môi trường Windows/SQL Server Express hiện có; chưa cài dependencies lại qua Internet trên máy Windows sạch.
