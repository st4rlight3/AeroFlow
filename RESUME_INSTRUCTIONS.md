# Tiếp tục từ bản thuyết trình tháng 11

Nhánh hiện tại: feature/presentation-demo-dec-jan, bao gồm giao diện mới và lịch 01/12/2026–31/01/2027. Không còn checkout detached. Giữ main nguyên trạng. Bản giá/lịch này có 154 tests PASS trên SQL Server; bằng chứng mới bắt đầu presentation-*. Đọc README/PROGRESS đầu file, các ghi chú detached/chưa push phía dưới thuộc phiên cũ.

SQLbaseline04 thay đổi chỉ cho cài mới; 001–014 bất biến. seed_ultimate.py mặc định 62 ngày khi chạy trong tháng 11, generic demo_catalog.build_plan vẫn 30 ngày rolling để tương thích. Database demo mới AeroFlow_Test_Presentation_20261025 có 2.352 chuyến; không chạy bộ test trên DB này. Launcher riêng ngoài project giữ cổng 5080; credentials/.env không được đưa lên Git hoặc ZIP.

Nếu nâng cấp database cũ: backup, dừng ứng dụng, giữ migrations đã áp dụng, chạy seed mới. Không chạy lại baseline hoặc tự chuyển ngày của vé cũ. Dữ liệu cũ vẫn được giữ; lịch mới được thêm. Sau mọi sửa tiếp theo, kiểm tra đúng test bị ảnh hưởng, đóng gói lại và đối chiếu checksum ZIP. Không tạo thêm slide/báo cáo trong phạm vi cập nhật này.

---

# Tiếp tục từ bản giá/lịch mới — 25/10/2026

Source hiện tại trong nhánh frontend đang checkout detached a09d803 với thay đổi chưa commit; không giả định GitHub đã có bản mới. Không sửa main hoặc đẩy nhánh nếu chưa có chỉ dẫn phù hợp. Đầu ra lần này là AeroFlow_Ultimate_Complete.zip.

Đã xong: 1.080 chuyến/30 ngày, giá theo tuyến/ngày/hãng/khoang/gói, 119 tests PASS trên SQL Server; đọc PROGRESS.md và evidence/pricing-* để biết phạm vi. Preview local dùng DB riêng AeroFlow_Test_Preview_20261025, không dùng DB Pricing chứa fixtures cho người dùng xem. SSMS kết nối `.\SQLEXPRESS`; source .env.example cấu hình server/database riêng.

Lưu ý importer mới dùng transaction do app.db.connection() quản lý, không thêm BEGIN TRAN dư. Đã có tests/test_demo_seed_sql.py bắt lỗi commit không bền và rollback giữa chừng. Không sửa migrations 001–014; baseline giữ nguyên. scripts/seed_ultimate.py không --apply chỉ preview. Muốn bổ sung lịch rolling chạy khi website dừng, backup trước và đọc MIGRATION_GUIDE.md.

Không tự mở rộng phạm vi sửa các phát hiện audit ngoài giá/dữ liệu. Không tạo lại slide/báo cáo trong lần cập nhật này. Không đưa .env, credentials, backup hoặc Git metadata vào ZIP. Gói bằng scripts/package_release.py, kiểm tra manifest/CRC, giữ các kết quả kiểm thử cũ dưới dạng lịch sử.

---

# Tiếp tục frontend refresh

Nhánh hiện tại được người dùng yêu cầu: `feature/frontend-refresh`, base Ultimate `648139e`; worktree phát triển `work/AeroFlow-Frontend`. Không làm việc tiếp trong nhánh Ultimate cũ cho yêu cầu giao diện này. Đọc phần đầu PROGRESS/README. Nguồn mới: frontend.css/frontend.js, home/search trong app.js, index.html và images/*.webp. Không có migration mới. Database QA riêng AeroFlow_Test_Frontend_20261023. Giữ nguyên các nghiệp vụ/API, không tự sửa hoặc merge main. Không tạo báo cáo/slide.

# Tiếp tục AeroFlow Ultimate

Đọc PROGRESS.md, README.md, CHANGELOG.md và Git status trước khi sửa. Nhánh duy nhất được phép: feature/ultimate-upgrade; repo gốc C:\AeroFlow-Git; worktree work/AeroFlow-Ultimate trong workspace Codex. Không clone lại, sửa/push/merge main. Không tạo slide/báo cáo học thuật; giữ docs cũ.

Đã triển khai unified itinerary, bốn khoang, dịch vụ/mã/điểm, đổi chặng/nâng khoang, hoàn riêng/credit, PDF/check-in/boarding, loyalty/thông báo/SMTP worker opt-in, quản trị mở rộng. Full suite 76 PASS; xem XML/evidence mới. Đã chạy backup/restore và hash bảo toàn dữ liệu qua 14 migrations.

SQL Server .\SQLEXPRESS Windows auth. DB hồi quy riêng AeroFlow_Test_Ultimate_Baseline_20261013. Không dùng database người dùng để gây lỗi. DB mới init + migrate, DB đã nâng cấp chỉ migrate. Không sửa 001–014 đã áp dụng; sửa schema bằng 015 trở lên và kiểm chứng fresh upgrade lại.

Nếu mở rộng: SMTP qua mailbox thử được người dùng cho phép; đo tải/giảm phạm vi applock kèm test deadlock; browser matrix; QR camera hoặc chia PNR khi được yêu cầu. Không tự gửi email hay kết nối thanh toán thật.

ZIP: AeroFlow_Ultimate_Complete.zip qua scripts/package_release.py; kiểm CRC/manifest/thành phần; loại .env/venv/Git/backup/QA secrets. Docs/ERD/slide cũ thuộc baseline; PROGRESS là trạng thái hiện tại.
