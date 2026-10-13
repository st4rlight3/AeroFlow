# Changelog

## Ultimate — đang phát triển, 13/10/2026

- `scripts/migrate.py`: version ledger, checksum, khóa migration, backup được xác minh, transaction mỗi phiên bản.
- `sql/migrations/001_booking_segments.sql`: bảng chặng, backfill booking cũ, trigger tương thích, view hành trình.
- `scripts/init_db.py`: ngăn ghi đè SQL objects của database đã được nâng cấp.
- `PROGRESS.md`, `MIGRATION_GUIDE.md`, `RESUME_INSTRUCTIONS.md`: hướng dẫn vận hành và tiếp tục.
- Tạm hoãn việc tạo hoặc mở rộng slide/báo cáo theo điều chỉnh phạm vi của người dùng.

Chưa coi đây là bản Ultimate hoàn chỉnh. Trạng thái kiểm thử hiện tại được cập nhật trong PROGRESS.md; bằng chứng nằm trong evidence/ultimate-*.
