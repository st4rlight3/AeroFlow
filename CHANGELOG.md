# 26/10/2026 — Sửa lỗi sau audit Marketplace

- Thêm migration023 bảo vệ giờ sử dụng và chủ hồ sơ đối tác; giữ lịch sử thanh toán, không sửa migration cũ.
- Sửa thêm lịch đơn lẻ khi bảng có trigger, hồ sơ đối tác đồng thời, trạng thái hỗ trợ và validation.
- Giữ dữ liệu biểu mẫu qua đăng nhập/giỏ; không tự đổi giờ đã lưu bị hết chỗ; sửa đổi ngày và phản hồi giá/lịch cũ.
- Ẩn bộ lọc sao ngoài khách sạn; giữ giao diện AeroFlow.
- Bổ sung test SQL/API/JavaScript; sửa fixture lệch ngày UTC và giả định seed đã đủ cửa sổ. Giữ các kết quả chạy chưa đạt, che credential trong trace.
- Đóng gói yêu cầu đủ001–023 và bằng chứng thành công khớp mã nguồn; từ chối báo cáo lỗi hoặc JavaScript evidence cũ.

---

# 26/10/2026 — Travel Marketplace

- Thêm 12 loại dịch vụ, 132 sản phẩm mẫu tại 11 điểm đến; 264 gói, 16.368 lịch bán tháng 12/2026–01/2027.
- Tìm theo loại, từ khóa, điểm đến, ngày, số khách, ngân sách, sao và sắp xếp; tính tổng đủ các đêm/ngày và số đơn vị cần cho nhóm khách.
- Thêm báo giá SQL, giữ chỗ 10 phút, chống vượt sức chứa khi đặt đồng thời, payment idempotency, coupon quota, hủy/hoàn theo snapshot, QR/PDF và eSIM mô phỏng.
- Thêm yêu thích, giỏ lựa chọn, lịch trình cá nhân, hỗ trợ, hồ sơ đối tác, quản trị danh mục/gói/lịch/giá/ưu đãi/đánh giá/phiếu và báo cáo SQL.
- Giữ giao diện hàng không; thêm thanh dịch vụ. Không thêm trợ lý AI.
- Sửa sắp xếp Mới nhất gây lỗi ORDER BY; sửa điều hướng bất đồng bộ để trang cũ không ghi đè trang vừa chọn.
- Sửa ODBC pooling giữ SERIALIZABLE giữa yêu cầu, dẫn đến tranh chấp thanh toán–hủy. Khôi phục READ COMMITTED ở đầu mỗi kết nối, giữ khóa mạnh tại nghiệp vụ cần thiết. Bản sửa chung cũng được đưa sang nhánh hàng không.
- Hồi quy đầu: 209 PASS / 1 FAIL; sau sửa: 214 PASS; bản bổ sung tác vụ hết hạn, đổi QR và lịch địa phương đạt 217 PASS. Không che hoặc coi lần chạy lỗi là thành công.

---

# Trong nước và quốc tế — 26/10/2026

- Giữ nhánh `feature/presentation-demo-dec-jan`; lịch 01/12/2026–31/01/2027 gồm **3.936 chuyến quốc tế + 2.232 nội địa + 120 baseline = 6.288 chuyến**, **42 sân bay**, **170 đường bay**, **74.376 dòng giá** trên database demo sạch. Quốc tế có 32 sân bay tại 20 quốc gia/vùng lãnh thổ ngoài Việt Nam.
- Bổ sung migrations 015–017, metadata quốc gia/khu vực/múi giờ, tìm kiếm và tuổi theo ngày địa phương, lịch máy bay liên tục. SQL giữ UTC; Admin nhập lịch theo giờ Việt Nam. Không sửa migration đã ghi trong ledger hoặc lịch sử vé đã phát hành.
- Thêm điểm đến quốc tế, 32 ảnh SVG local, bộ lọc và lịch/giá từ SQL Server. Footer đã bỏ nút chuyển động theo yêu cầu.
- Giữ hai module nhập nội địa/quốc tế; `scripts/load_demo.py` cung cấp `--preview`/`--apply` chung. CSV tại `data/demo_route_prices.csv` và `data/demo_flight_prices.csv` là ảnh chụp SQL để xem, không phải nguồn runtime.
- Hồi quy quốc tế ban đầu trước 017: **171 PASS, 0 FAIL/ERROR/SKIP, 207,953 giây**; `evidence/international-full-regression-20261026.xml`. Kiểm chứng migration 017 đang chờ hoàn tất. Đóng gói yêu cầu migrations 001–017, mã/SQL/tests mới, 32 SVG và hai CSV.
- Hoàn tất và push nhánh hiện tại trước khi tạo nhánh mới; **nhánh mới không có tính năng trợ lý AI**. Không thay main, không tạo thêm slide/báo cáo.

Toàn bộ mục dưới đây là lịch sử theo ngày; các số lượng và hướng dẫn cũ không thay thế phiên bản 26/10/2026.

---

# Lịch sử — bản thuyết trình 25/10/2026

- Chọn mặc định 01/12/2026–31/01/2027: 62 ngày, 2.232 chuyến và 26.784 mức giá; không hết lịch trong buổi thuyết trình tháng 11. Cửa sổ tự lùi tới phần tương lai khi chạy muộn, có tùy chọn ngày/số ngày rõ ràng.
- Baseline 04 cho cài mới chuyển sang tháng 12, máy bay thực hiện khứ hồi với ít nhất 80 phút quay đầu, thương gia ở đầu cabin; ghế mẫu B4 đúng khoang phổ thông. Database cũ được guard bảo toàn, migrations 001–014 không sửa.
- Bổ sung 35 kiểm thử cửa sổ thuyết trình và kiểm chứng lại dữ liệu SQL, website, ZIP. Giữ các sửa giá/cabin/date/idempotency ở bản trước.
- Nhánh phát hành `feature/presentation-demo-dec-jan`, tách từ giao diện hiện có; main giữ nguyên.

---

# Lịch sử — giá và lịch bay 25/10/2026

- Thêm lịch 1.080 chuyến/30 ngày, 10 sân bay, 3 hãng, 9 máy bay 150 ghế. Lịch liên tục theo vị trí máy bay, quay về căn cứ mỗi ngày, nghỉ tối thiểu 60 phút.
- Giá mẫu theo khoảng cách/ngày/hãng/khoang/gói; tham khảo hai trang Vietnam Airlines, không coi giá khuyến mãi là giá cuối cùng cho mọi chuyến. Tiền tính bằng Decimal, tổng preview khớp SQL Server.
- Import preview/apply, nhập lại không trùng và rollback khi lỗi; repricing giới hạn chuyến mẫu tương lai. Giữ nguyên giá vé đã phát hành và dữ liệu giao dịch.
- Sửa API giá gợi ý gắn sai ngày, giá khoang hết ghế và chuyến không có giá hiển thị 0 đồng. Chi tiết chuyến kiểm tra đủ chỗ cho số khách được chọn.
- Giao diện ghi ngày bay và giá một người lớn gồm thuế; giải thích khoản ghế/dịch vụ mua thêm. Bổ sung truy vấn kiểm tra trực tiếp bằng SSMS.
- Đóng gói bắt buộc kiểm tra frontend mới, ảnh/nền, bộ dữ liệu, SQL/tests và bằng chứng; `.env`/credentials/backup không đưa vào ZIP. Kết quả thực chạy ở PROGRESS.md.

---

# Lịch sử — frontend refresh 23/10/2026

- Bổ sung nền bầu trời SVG local (1.608 bytes) cho toàn bộ trang, mây trôi/đường bay nhẹ, nền tiêu đề và footer sáng. Lớp trang trí không nhận thao tác và được ẩn khỏi trình đọc màn hình, bản in; tuân theo nút tắt chuyển động và prefers-reduced-motion.
- Khai báo color-scheme light/only light để ngăn Chromium tự đổi nền sáng thành tối. Extension ép màu của trình duyệt vẫn có thể ghi đè; chưa kiểm chứng trực tiếp Cốc Cốc.
- Kiểm tra browser trang chủ/tìm hành trình ở 1440×900 và 390×844, tìm HAN–SGN 26/10 trả 4 phương án, tắt hiệu ứng dừng cả mây/đường bay. Bằng chứng `evidence/sky-*`. Không cần migration SQL.

- `app/static/app.js`: trang chủ/tìm nhanh mới, điểm đến theo dữ liệu SQL, vòng đời chuyển trang/focus/progress/title.
- `app/static/frontend.css`: theme xanh ngọc/nền sáng, responsive, form/seat/ticket/admin, hover/reveal/mây/đường bay, giảm chuyển động và print.
- `app/static/frontend.js`: SVG icons local, điều hướng active, lựa chọn khứ hồi/multi-city từ trang chủ, hiệu ứng theo viewport, tắt/nhớ chuyển động, dọn observer, tạm dừng tab ẩn, về đầu trang.
- `app/static/images/aviation-hero.webp`, `hanoi.webp`, `danang.webp`, `saigon.webp`: ảnh minh họa AI được tối ưu; không có số liệu/giá hard-code.
- `app/templates/index.html`: nạp CSS/JS mới, title/theme-color, progress, footer và điều khiển chuyển động.
- README/PROGRESS/RESUME_INSTRUCTIONS cập nhật cách clone/chạy và giới hạn xác minh; evidence/frontend-* ghi hồi quy, asset manifest và ảnh browser. Các file học thuật cũ không sửa.
- Tương thích toàn bộ backend và SQL 001–014 hiện có; không thêm dependency, không cần migration mới.

---

# Lịch sử — AeroFlow Ultimate, 14/10/2026

Nâng cấp AeroFlow từ base 5c16bed trên feature/ultimate-upgrade. Không thay stack, không tạo repository mới hoặc sửa main.

- Unified itinerary với nhiều chặng, khứ hồi/nhiều thành phố/nối chuyến; transaction bảo vệ toàn PNR, báo giá/tuổi/chọn ghế và phí ghế từ SQL.
- Bốn khoang, 12 hạng demo, lịch giá/lọc/sắp xếp, saved travellers/hỗ trợ/ưu tiên ghế, profile/mật khẩu/tùy chọn.
- Dịch vụ và promo/voucher/points; price guard khi thanh toán; partial refund, credit, chống chi tiêu đồng thời; đổi ngày/chuyến/nâng khoang và giữ lịch sử vé.
- PDF e-ticket/boarding QR/receipt/report; check-in/boarding, thông báo và loyalty, worker SMTP opt-in (chưa thử SMTP thật).
- Admin mở rộng routes/services/tiers/promotions/passengers/loyalty/operations và reports; responsive; cookie riêng và chuyển về đăng nhập khi session hết hạn.
- 14 migrations có backup/checksum/transaction; fresh upgrade và restore được kiểm chứng. Không sửa dữ liệu cũ; quy tắc backfill LEGACY_CURRENT được ghi rõ trong MIGRATION_GUIDE.
- Bộ kiểm thử 76 PASS; 34 kiểm thử chịu ảnh hưởng sửa cuối PASS. Chi tiết/giới hạn ở PROGRESS.md; không tuyên bố pentest/tải lớn/SMTP thật đã hoàn tất.
- Chỉ cập nhật hướng dẫn chạy/migration/tiến độ; không tạo hoặc mở rộng slide/báo cáo học thuật.

## Tương thích

Database mới: init baseline rồi migrate. Database hiện hữu: bỏ init, backup rồi migrate. Cài thêm reportlab. Restart Flask sau nâng cấp. Không sửa migration đã áp dụng; thay đổi tiếp theo dùng 015+. API cũ một chặng giữ hoạt động, nhưng cùng một booking dùng một fare class và kiểm tra tuổi theo luồng thống nhất. Được phép no-op save/phí ghế; không đổi hình học ghế có lịch sử.

## Danh sách file thay đổi/thêm so với base

- `.env.example`
- `CHANGELOG.md`
- `MIGRATION_GUIDE.md`
- `PROGRESS.md`
- `README.md`
- `RESUME_INSTRUCTIONS.md`
- `app/__init__.py`
- `app/config.py`
- `app/errors.py`
- `app/routes/admin.py`
- `app/routes/bookings.py`
- `app/routes/commerce.py`
- `app/routes/customer.py`
- `app/routes/itineraries.py`
- `app/routes/operations.py`
- `app/services/documents.py`
- `app/services/exchange.py`
- `app/services/itineraries.py`
- `app/static/app.js`
- `app/static/commerce.js`
- `app/static/customer.js`
- `app/static/manage.js`
- `app/static/ultimate.css`
- `app/static/ultimate.js`
- `app/templates/index.html`
- `evidence/ultimate-admin-dashboard.png`
- `evidence/ultimate-admin-mobile.png`
- `evidence/ultimate-admin-service-save.png`
- `evidence/ultimate-baseline.xml`
- `evidence/ultimate-boarding-page-1.png`
- `evidence/ultimate-boarding-sample.pdf`
- `evidence/ultimate-browser-checks.json`
- `evidence/ultimate-commerce-api.xml`
- `evidence/ultimate-customer-api.xml`
- `evidence/ultimate-database-inventory.json`
- `evidence/ultimate-exchange-wallet.xml`
- `evidence/ultimate-exchanged.png`
- `evidence/ultimate-final-regression.xml`
- `evidence/ultimate-fresh-upgrade-restore.json`
- `evidence/ultimate-migration-preservation.json`
- `evidence/ultimate-migrations.xml`
- `evidence/ultimate-phase3-api.xml`
- `evidence/ultimate-phase4-regression.xml`
- `evidence/ultimate-product-pdf-checks.json`
- `evidence/ultimate-regression-phase2.xml`
- `evidence/ultimate-release-fixes.xml`
- `evidence/ultimate-roundtrip-paid.jpg`
- `evidence/ultimate-seat-mobile.png`
- `evidence/ultimate-services-paid.png`
- `evidence/ultimate-sql-checks.json`
- `evidence/ultimate-static-checks.json`
- `evidence/ultimate-ticket-page-1.png`
- `evidence/ultimate-ticket-pdf.png`
- `evidence/ultimate-ticket-sample.pdf`
- `evidence/ultimate-wallet-refund.png`
- `evidence/ultimate-zip-unit.xml`
- `requirements.txt`
- `scripts/init_db.py`
- `scripts/issue_reset_token.py`
- `scripts/migrate.py`
- `scripts/package_release.py`
- `scripts/seed_ultimate.py`
- `scripts/send_notifications.py`
- `scripts/setup.ps1`
- `scripts/verify_database.py`
- `scripts/verify_upgrade.py`
- `sql/migrations/001_booking_segments.sql`
- `sql/migrations/002_unified_ticket_core.sql`
- `sql/migrations/003_create_itinerary.sql`
- `sql/migrations/004_assignment_and_summary.sql`
- `sql/migrations/005_customer_operations.sql`
- `sql/migrations/006_assistance_snapshot.sql`
- `sql/migrations/007_services_and_partial_refunds.sql`
- `sql/migrations/008_pricing_integration.sql`
- `sql/migrations/009_exchange_and_wallet_schema.sql`
- `sql/migrations/010_exchange_segment.sql`
- `sql/migrations/011_wallet_points_and_pricing.sql`
- `sql/migrations/012_operational_controls.sql`
- `sql/migrations/013_payment_guard_and_routes.sql`
- `sql/migrations/014_current_booking_summary.sql`
- `tests/test_commerce.py`
- `tests/test_customer_operations.py`
- `tests/test_exchange_wallet.py`
- `tests/test_integration.py`
- `tests/test_itineraries.py`
- `tests/test_migrations.py`
- `tests/test_ultimate_operations.py`
