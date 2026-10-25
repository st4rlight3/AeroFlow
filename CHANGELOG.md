# Bản thuyết trình — 25/10/2026

- Chọn mặc định 01/12/2026–31/01/2027: 62 ngày, 2.232 chuyến và 26.784 mức giá; không hết lịch trong buổi thuyết trình tháng 11. Cửa sổ tự lùi tới phần tương lai khi chạy muộn, có tùy chọn ngày/số ngày rõ ràng.
- Baseline 04 cho cài mới chuyển sang tháng 12, máy bay thực hiện khứ hồi với ít nhất 80 phút quay đầu, thương gia ở đầu cabin; ghế mẫu B4 đúng khoang phổ thông. Database cũ được guard bảo toàn, migrations 001–014 không sửa.
- Bổ sung 35 kiểm thử cửa sổ thuyết trình và kiểm chứng lại dữ liệu SQL, website, ZIP. Giữ các sửa giá/cabin/date/idempotency ở bản trước.
- Nhánh phát hành `feature/presentation-demo-dec-jan`, tách từ giao diện hiện có; main giữ nguyên.

---

# Giá và lịch bay — 25/10/2026

- Thêm lịch 1.080 chuyến/30 ngày, 10 sân bay, 3 hãng, 9 máy bay 150 ghế. Lịch liên tục theo vị trí máy bay, quay về căn cứ mỗi ngày, nghỉ tối thiểu 60 phút.
- Giá mẫu theo khoảng cách/ngày/hãng/khoang/gói; tham khảo hai trang Vietnam Airlines, không coi giá khuyến mãi là giá cuối cùng cho mọi chuyến. Tiền tính bằng Decimal, tổng preview khớp SQL Server.
- Import preview/apply, nhập lại không trùng và rollback khi lỗi; repricing giới hạn chuyến mẫu tương lai. Giữ nguyên giá vé đã phát hành và dữ liệu giao dịch.
- Sửa API giá gợi ý gắn sai ngày, giá khoang hết ghế và chuyến không có giá hiển thị 0 đồng. Chi tiết chuyến kiểm tra đủ chỗ cho số khách được chọn.
- Giao diện ghi ngày bay và giá một người lớn gồm thuế; giải thích khoản ghế/dịch vụ mua thêm. Bổ sung truy vấn kiểm tra trực tiếp bằng SSMS.
- Đóng gói bắt buộc kiểm tra frontend mới, ảnh/nền, bộ dữ liệu, SQL/tests và bằng chứng; `.env`/credentials/backup không đưa vào ZIP. Kết quả thực chạy ở PROGRESS.md.

---

# Frontend refresh — 23/10/2026

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

# Changelog — AeroFlow Ultimate, 14/10/2026

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
