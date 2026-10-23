# Tiếp tục frontend refresh

Nhánh hiện tại được người dùng yêu cầu: `feature/frontend-refresh`, base Ultimate `648139e`; worktree phát triển `work/AeroFlow-Frontend`. Không làm việc tiếp trong nhánh Ultimate cũ cho yêu cầu giao diện này. Đọc phần đầu PROGRESS/README. Nguồn mới: frontend.css/frontend.js, home/search trong app.js, index.html và images/*.webp. Không có migration mới. Database QA riêng AeroFlow_Test_Frontend_20261023. Giữ nguyên các nghiệp vụ/API, không tự sửa hoặc merge main. Không tạo báo cáo/slide.

# Tiếp tục AeroFlow Ultimate

Đọc PROGRESS.md, README.md, CHANGELOG.md và Git status trước khi sửa. Nhánh duy nhất được phép: feature/ultimate-upgrade; repo gốc C:\AeroFlow-Git; worktree work/AeroFlow-Ultimate trong workspace Codex. Không clone lại, sửa/push/merge main. Không tạo slide/báo cáo học thuật; giữ docs cũ.

Đã triển khai unified itinerary, bốn khoang, dịch vụ/mã/điểm, đổi chặng/nâng khoang, hoàn riêng/credit, PDF/check-in/boarding, loyalty/thông báo/SMTP worker opt-in, quản trị mở rộng. Full suite 76 PASS; xem XML/evidence mới. Đã chạy backup/restore và hash bảo toàn dữ liệu qua 14 migrations.

SQL Server .\SQLEXPRESS Windows auth. DB hồi quy riêng AeroFlow_Test_Ultimate_Baseline_20261013. Không dùng database người dùng để gây lỗi. DB mới init + migrate, DB đã nâng cấp chỉ migrate. Không sửa 001–014 đã áp dụng; sửa schema bằng 015 trở lên và kiểm chứng fresh upgrade lại.

Nếu mở rộng: SMTP qua mailbox thử được người dùng cho phép; đo tải/giảm phạm vi applock kèm test deadlock; browser matrix; QR camera hoặc chia PNR khi được yêu cầu. Không tự gửi email hay kết nối thanh toán thật.

ZIP: AeroFlow_Ultimate_Complete.zip qua scripts/package_release.py; kiểm CRC/manifest/thành phần; loại .env/venv/Git/backup/QA secrets. Docs/ERD/slide cũ thuộc baseline; PROGRESS là trạng thái hiện tại.
