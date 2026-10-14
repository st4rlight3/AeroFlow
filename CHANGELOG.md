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
