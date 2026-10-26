# Tiếp tục nhánh Marketplace

Dùng worktree `AeroFlow-Marketplace`, nhánh `feature/travel-marketplace`. Nhánh hàng không cũ là `feature/presentation-demo-dec-jan`; không đưa các bảng dịch vụ vào nhánh đó. Không đổi main. Không thêm trợ lý AI.

Đọc phần mới đầu README, PROGRESS và MIGRATION_GUIDE. Source dùng Flask/pyodbc/SQL Server, 001–022 bất biến; thêm migration mới nếu cần, không sửa file đã ledger-applied. `load_demo.py --apply` nhập ba catalogue độc lập, idempotent. Giá dịch vụ ở `TravelInventory`, snapshot đơn ở `TravelBookings/TravelBookingItems`; không thay bằng dữ liệu frontend.

Kết quả mới nhất: 217 PASS toàn bộ; 40 ca dịch vụ và 4 ca cô lập kết nối mới. Giữ cả báo cáo lỗi ban đầu 209/1 và bằng chứng bản sửa ODBC. SQL backup/restore toàn bộ bảng khớp hash. Xem `evidence/marketplace-*` và `pooled-isolation-*`. Chạy test trên database riêng `AeroFlow_Test_*`; không chạy regression trên database trình diễn.

Preview nội bộ nhánh mới dùng cổng 5082, nhánh hàng không 5080. Launcher, tài khoản QA và secret chỉ ở ngoài repo/ZIP. Bạn bè clone phải tạo `.env`, migrate, nhập mẫu và tự tạo tài khoản; không phụ thuộc máy của tác giả.

Phạm vi còn có thể mở rộng: số ghế xe/tàu; checkout nhiều gói trong một giao dịch; đổi lịch có chênh lệch/hoàn tiền; quản lý inventory của đối tác; tích hợp nguồn dịch vụ thật khi có hợp đồng/API. Không nói các tính năng này đã có. Giữ giao diện AeroFlow, không lấy nhãn hiệu hoặc ảnh thương mại của Traveloka. Không tạo slide/báo cáo nếu không có yêu cầu mới.

Sau thay đổi: chạy test phù hợp, xác nhận browser, cập nhật bằng chứng và đóng `AeroFlow_Ultimate_Complete.zip` bằng packager (đủ 001–022, manifest/CRC). Không đưa secret/venv/Git/backup SQL/tài khoản thật vào ZIP.

---

# Tiếp tục bản trong nước và quốc tế — 26/10/2026

Làm việc trên **feature/presentation-demo-dec-jan** trong `work/AeroFlow-Frontend`; đọc đầu README/PROGRESS và Git status trước khi sửa. Hoàn tất bản cũ, kiểm tra rồi push trước khi tạo nhánh mới. **Nhánh mới không có tính năng trợ lý AI.** Không chuyển nhánh sớm, không sửa/merge main và không tạo thêm slide/báo cáo; giữ tài liệu học thuật cũ.

Bộ demo sạch hiện có **6.288 chuyến (2.232 nội địa + 3.936 quốc tế + 120 baseline), 42 sân bay, 170 đường bay, 74.376 dòng giá** cho 01/12/2026–31/01/2027. Phần quốc tế gồm 32 sân bay tại 20 quốc gia/vùng lãnh thổ ngoài Việt Nam. Hồi quy quốc tế ban đầu trước migration 017: **171 PASS, 0 FAIL/ERROR/SKIP, 207,953 giây** được xác nhận từ `evidence/international-full-regression-20261026.xml`. Kiểm chứng sau017 đã đạt: 173 tests, database mới nâng cấp đủ001–017, idempotence và đối chiếu múi giờ; đọc PROGRESS đầu file. Không coi các ghi chú 154/119/76 tests hoặc detached/chưa push phía dưới là trạng thái hiện tại.

Cần migrations **001–017**; các file đã ghi ledger là bất biến. Database mới init baseline rồi migrate; database có dữ liệu không init lại, cần dừng ứng dụng, xác nhận `.env`, backup rồi migrate. Nhập demo bằng `scripts/load_demo.py --preview/--apply --start-date 2026-12-01 --days 62`, hoặc chạy riêng `seed_ultimate.py` rồi `seed_international.py` với cùng cửa sổ ngày. Quốc tế không có `--apply` là preview. Hai giai đoạn có transaction riêng và có thể chạy lại an toàn; không thêm BEGIN TRAN dư vào importer.

SQL lưu UTC. Ngày tìm kiếm/tuổi theo múi giờ sân bay đi, giờ đến theo sân bay đến, có DST. Biểu mẫu Admin nhập lịch vẫn dùng giờ Việt Nam. CSV `data/demo_route_prices.csv` và `data/demo_flight_prices.csv` là snapshot SQL để xem; runtime tiếp tục SQL Server, không chuyển sang CSV.

Không chạy bộ hồi quy trên database trình diễn hoặc dữ liệu người dùng. Sau sửa tiếp, chạy đúng kiểm tra bị ảnh hưởng rồi đóng gói qua `scripts/package_release.py`, kiểm tra CRC/manifest và thành phần 001–017, hai CSV, 32 SVG và bằng chứng hiện tại. Không đưa `.env`, credentials, Git metadata, venv hoặc backup vào ZIP. Không tuyên bố backup/restore 17 migrations chỉ từ bằng chứng restore 14 migrations cũ.

Tất cả các mục sau đây là lịch sử, gồm cả tên nhánh, lệnh và giới hạn của phiên cũ; không phải chỉ dẫn tiếp tục hiện hành.

---

# Lịch sử — tiếp tục từ bản thuyết trình tháng 11

Nhánh hiện tại: feature/presentation-demo-dec-jan, bao gồm giao diện mới và lịch 01/12/2026–31/01/2027. Không còn checkout detached. Giữ main nguyên trạng. Bản giá/lịch này có 154 tests PASS trên SQL Server; bằng chứng mới bắt đầu presentation-*. Đọc README/PROGRESS đầu file, các ghi chú detached/chưa push phía dưới thuộc phiên cũ.

SQLbaseline04 thay đổi chỉ cho cài mới; 001–014 bất biến. seed_ultimate.py mặc định 62 ngày khi chạy trong tháng 11, generic demo_catalog.build_plan vẫn 30 ngày rolling để tương thích. Database demo mới AeroFlow_Test_Presentation_20261025 có 2.352 chuyến; không chạy bộ test trên DB này. Launcher riêng ngoài project giữ cổng 5080; credentials/.env không được đưa lên Git hoặc ZIP.

Nếu nâng cấp database cũ: backup, dừng ứng dụng, giữ migrations đã áp dụng, chạy seed mới. Không chạy lại baseline hoặc tự chuyển ngày của vé cũ. Dữ liệu cũ vẫn được giữ; lịch mới được thêm. Sau mọi sửa tiếp theo, kiểm tra đúng test bị ảnh hưởng, đóng gói lại và đối chiếu checksum ZIP. Không tạo thêm slide/báo cáo trong phạm vi cập nhật này.

---

# Lịch sử — tiếp tục từ bản giá/lịch, 25/10/2026

Source hiện tại trong nhánh frontend đang checkout detached a09d803 với thay đổi chưa commit; không giả định GitHub đã có bản mới. Không sửa main hoặc đẩy nhánh nếu chưa có chỉ dẫn phù hợp. Đầu ra lần này là AeroFlow_Ultimate_Complete.zip.

Đã xong: 1.080 chuyến/30 ngày, giá theo tuyến/ngày/hãng/khoang/gói, 119 tests PASS trên SQL Server; đọc PROGRESS.md và evidence/pricing-* để biết phạm vi. Preview local dùng DB riêng AeroFlow_Test_Preview_20261025, không dùng DB Pricing chứa fixtures cho người dùng xem. SSMS kết nối `.\SQLEXPRESS`; source .env.example cấu hình server/database riêng.

Lưu ý importer mới dùng transaction do app.db.connection() quản lý, không thêm BEGIN TRAN dư. Đã có tests/test_demo_seed_sql.py bắt lỗi commit không bền và rollback giữa chừng. Không sửa migrations 001–014; baseline giữ nguyên. scripts/seed_ultimate.py không --apply chỉ preview. Muốn bổ sung lịch rolling chạy khi website dừng, backup trước và đọc MIGRATION_GUIDE.md.

Không tự mở rộng phạm vi sửa các phát hiện audit ngoài giá/dữ liệu. Không tạo lại slide/báo cáo trong lần cập nhật này. Không đưa .env, credentials, backup hoặc Git metadata vào ZIP. Gói bằng scripts/package_release.py, kiểm tra manifest/CRC, giữ các kết quả kiểm thử cũ dưới dạng lịch sử.

---

# Lịch sử — tiếp tục frontend refresh

Nhánh hiện tại được người dùng yêu cầu: `feature/frontend-refresh`, base Ultimate `648139e`; worktree phát triển `work/AeroFlow-Frontend`. Không làm việc tiếp trong nhánh Ultimate cũ cho yêu cầu giao diện này. Đọc phần đầu PROGRESS/README. Nguồn mới: frontend.css/frontend.js, home/search trong app.js, index.html và images/*.webp. Không có migration mới. Database QA riêng AeroFlow_Test_Frontend_20261023. Giữ nguyên các nghiệp vụ/API, không tự sửa hoặc merge main. Không tạo báo cáo/slide.

# Lịch sử — tiếp tục AeroFlow Ultimate

Đọc PROGRESS.md, README.md, CHANGELOG.md và Git status trước khi sửa. Nhánh duy nhất được phép: feature/ultimate-upgrade; repo gốc C:\AeroFlow-Git; worktree work/AeroFlow-Ultimate trong workspace Codex. Không clone lại, sửa/push/merge main. Không tạo slide/báo cáo học thuật; giữ docs cũ.

Đã triển khai unified itinerary, bốn khoang, dịch vụ/mã/điểm, đổi chặng/nâng khoang, hoàn riêng/credit, PDF/check-in/boarding, loyalty/thông báo/SMTP worker opt-in, quản trị mở rộng. Full suite 76 PASS; xem XML/evidence mới. Đã chạy backup/restore và hash bảo toàn dữ liệu qua 14 migrations.

SQL Server .\SQLEXPRESS Windows auth. DB hồi quy riêng AeroFlow_Test_Ultimate_Baseline_20261013. Không dùng database người dùng để gây lỗi. DB mới init + migrate, DB đã nâng cấp chỉ migrate. Không sửa 001–014 đã áp dụng; sửa schema bằng 015 trở lên và kiểm chứng fresh upgrade lại.

Nếu mở rộng: SMTP qua mailbox thử được người dùng cho phép; đo tải/giảm phạm vi applock kèm test deadlock; browser matrix; QR camera hoặc chia PNR khi được yêu cầu. Không tự gửi email hay kết nối thanh toán thật.

ZIP: AeroFlow_Ultimate_Complete.zip qua scripts/package_release.py; kiểm CRC/manifest/thành phần; loại .env/venv/Git/backup/QA secrets. Docs/ERD/slide cũ thuộc baseline; PROGRESS là trạng thái hiện tại.
