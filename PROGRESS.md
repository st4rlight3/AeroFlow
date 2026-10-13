# AeroFlow Ultimate — tiến độ

Ngày: 13/10/2026. Nhánh: `feature/ultimate-upgrade`, nền tảng Git `5c16bed`.

- Phase 1: đã đọc đủ 3 trang đề PDF, so sánh ZIP và repository. ZIP trùng bản bàn giao gốc. Checkout main sạch và khớp GitHub.
- Phase 2: đã triển khai và kiểm thử migration 001 có checksum, transaction, backfill và bảng chặng bay. Luồng backup có mã nguồn nhưng chưa chạy thực tế.
- Phase 3–8: đang chờ nền tảng migration được kiểm thử trước khi triển khai nghiệp vụ.
- Không push/merge main. Làm trong Git worktree từ repository `C:\AeroFlow-Git`.
- Theo điều chỉnh phạm vi: hoãn slide/báo cáo học thuật. Giữ nguyên tài liệu có sẵn, không mở rộng tài liệu lý thuyết dài.

Ưu tiên kế tiếp: kiểm thử migration bảo toàn dữ liệu; thống nhất đặt vé nhiều chặng và locking; bổ sung chức năng thực tế cùng kiểm thử.

Kiểm thử thực tế: baseline 39 PASS (66.63s), migration 6 PASS (0.82s), hồi quy sau migration 39 PASS (66.62s). XML và SHA-256 từng bảng cũ nằm trong evidence/ultimate-*. Chưa triển khai nghiệp vụ Ultimate nhiều chặng; không coi checkpoint nền tảng là sản phẩm hoàn chỉnh.

