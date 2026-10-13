# Tiếp tục AeroFlow Ultimate

Đọc PROGRESS.md, CHANGELOG.md và trạng thái Git. Nhánh được phép: feature/ultimate-upgrade. Repository gốc C:\AeroFlow-Git, không sửa/push/merge main và không clone lại.

Worktree phát triển nằm tại thư mục `work/AeroFlow-Ultimate` trong workspace Codex hiện tại. Yêu cầu mới nhất: tập trung website/API/SQL/migration/tests; không tạo slide hoặc báo cáo học thuật. Giữ các tài liệu cũ.

Database hồi quy riêng: AeroFlow_Test_Ultimate_Baseline_20261013. Không dùng database demo hoặc database người dùng cho destructive/fault-injection tests. Chạy migration bằng scripts/migrate.py; chỉ dùng --test-database với AeroFlow_Test_*.

Nguồn chuẩn: yêu cầu Ultimate đính kèm của người dùng và 3 trang docs/assignment.pdf. Phải hỗ trợ unified itinerary, round-trip, multi-city, connection validation, hành khách/ghế từng chặng, dịch vụ/giảm giá, thanh toán idempotent, đổi/hủy/hoàn, PDF vé/boarding pass DEMO, check-in, loyalty, thông báo và admin. Chỉ công bố tính năng sau khi đã triển khai và kiểm thử.

Đầu ra cuối: AeroFlow_Ultimate_Complete.zip. Checkpoint phải có toàn bộ nguồn và trạng thái chính xác, không có .env, .venv, __pycache__ hoặc thông tin đăng nhập.
