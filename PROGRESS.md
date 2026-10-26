# Trạng thái hiện tại — trong nước và quốc tế, 26/10/2026

Nhánh đang hoàn thiện: **feature/presentation-demo-dec-jan**. Các kết quả dưới đây thuộc bản quốc tế hiện tại; mọi mục sau phần này là lịch sử. Không suy ra commit/push đã hoàn tất từ kết quả kiểm thử.

- Hồi quy quốc tế ban đầu trước migration 017: XML `evidence/international-full-regression-20261026.xml` ghi **171 PASS, 0 FAIL, 0 ERROR, 0 SKIP, 207,953 giây**; thời điểm bắt đầu 13:59:20 ngày 26/10/2026, UTC+7. Gồm hồi quy nghiệp vụ, sửa tính nhất quán và quốc tế/múi giờ. Sau migration 017, hồi quy cuối **173 PASS, 0 FAIL/ERROR/SKIP**, 206.470 giây (`evidence/international-final-regression-20261026.xml`). Database mới cài baseline và đủ 17 migrations giữ nguyên 40 booking/40 ticket/48 payment cũ; nhập lại không nhân đôi và kết nối mới đọc được dữ liệu. Kiểm tra 3.936 lịch quốc tế và 2.604 ngày sân bay không lệch IANA trong cửa sổ demo. Xem `international-fresh-upgrade-20261026.json`, `international-final-validation-20261026.json` và `vancouver-migration-preservation-20261026.json`.
- Database demo sạch có **6.288 chuyến = 2.232 nội địa + 3.936 quốc tế + 120 baseline**, **42 sân bay**, **170 đường bay**, **74.376 dòng giá** cho bộ lịch trình diễn 01/12/2026–31/01/2027. Quốc tế gồm 32 sân bay tại 20 quốc gia/vùng lãnh thổ ngoài Việt Nam. Không dùng số liệu database hồi quy có fixtures để mô tả bộ demo.
- Source và bộ nhập cần **migrations 001–017**. Các file đã ledger-applied là bất biến. SQL lưu UTC; tìm kiếm/ngày tuổi theo sân bay đi, giờ đến theo sân bay đến và xử lý DST. Admin nhập lịch vẫn theo giờ Việt Nam.
- `scripts/load_demo.py --preview/--apply` là lối vào chung cho hai bộ nhập độc lập; vẫn giữ `seed_ultimate.py` và `seed_international.py`. Mỗi bộ nhập có transaction riêng, chạy lại không nhân đôi; không tuyên bố toàn bộ hai giai đoạn là một transaction.
- `data/demo_route_prices.csv` và `data/demo_flight_prices.csv` là bản xuất từ SQL để xem trên GitHub/Excel; ứng dụng tiếp tục đọc SQL Server. Có 32 ảnh SVG local riêng cho điểm đến quốc tế. Footer đã bỏ nút chuyển động.
- Bằng chứng restore 14 migrations và browser/test cũ dưới đây chỉ là lịch sử. Chưa dùng kết quả 171 tests để tuyên bố restore đầy đủ 17 migrations, thử mọi trình duyệt, tải lớn hoặc SMTP thật.

Hoàn tất, kiểm tra và push bản hiện tại trước khi tạo nhánh tiếp theo. **Nhánh mới không có tính năng trợ lý AI.** Giữ main và tài liệu học thuật/slide cũ; không tạo thêm slide/báo cáo trong phạm vi này. Các yêu cầu tiếp tục hiện hành nằm ở đầu `RESUME_INSTRUCTIONS.md`.

---

# Lịch sử — bản thuyết trình tháng 11, 25/10/2026

Nhánh phát hành: **feature/presentation-demo-dec-jan**, phát triển từ frontend a09d803. Kết quả dưới đây thuộc bản lịch tháng 12/tháng 1; các phần phía dưới là lịch sử của bản 30 ngày cũ.

- **154 PASS, 0 FAIL/ERROR/SKIP, 140,29 giây**, chạy với SQL Server Express thật trên database hồi quy riêng `AeroFlow_Test_Presentation_Regression_20261025`. Bao gồm 35 test preset mới và toàn bộ 119 test trước đó. `evidence/presentation-regression-20261025.xml`.
- Đã tạo **2.232 chuyến mới, 26.784 giá vé**, từ **01/12/2026 đến 31/01/2027 theo giờ Việt Nam**. 9 máy bay ×150 ghế, 10 sân bay, 3 hãng giả lập, 4 khoang/12 gói. Database demo sạch `AeroFlow_Test_Presentation_20261025` có tổng **2.352 chuyến** kể cả 120 baseline, không chạy fixtures hồi quy trên database này.
- Baseline 04 cho cài mới đặt lịch tháng 12, máy bay khứ hồi về căn cứ, quay đầu 80 phút, khoang thương gia ở trước, ghế mẫu B4 đúng khoang. Giữ guard bảo vệ DB cũ; không di chuyển ngày hoặc sơ đồ ghế đã bán. Migrations 001–014 giữ nguyên checksum.
- Nhập lại cả bộ: **0 bản ghi chuyến/giá mới hoặc bị sửa**. Hash Tickets/Bookings/Payments giữ nguyên. SQL tests xác nhận snapshot lần nhập đầu, rollback khi xung đột giữa kế hoạch, giá ngoài allowlist không đổi. `evidence/presentation-validation-20261025.json`.
- `DBCC CHECKDB`, `DBCC CHECKCONSTRAINTS`, vòng quay/khóa ghế và giá/ngày gợi ý: PASS. Cả `09_business_queries.sql` và `10_test_cases.sql` chạy không lỗi, đầy đủ các phép kiểm tra ràng buộc/rollback. `evidence/presentation-sql-checks.json` và `presentation-database-inventory.json`.
- Browser thật: gợi ý HAN–SGN **02/12/2026, 1.809.500 VND/người lớn**; tìm ngày 02/12 trả 4 chuyến, ngày 15/01/2027 trả 3 chuyến. Desktop 1280×800/mobile 390×844 không tràn ngang, không console error/warning trong thao tác đã thử. `evidence/presentation-browser-checks-20261025.json`, ảnh `presentation-*.png`.
- Giá phổ thông Basic HAN–SGN khoảng 1,81–2,17 triệu VND, gồm thuế mô phỏng, không phải báo giá trực tiếp của hãng. Discovery trên 2.352 chuyến đo local khoảng 283–447 ms, không thay thế benchmark tải. Python AST/Node syntax đều đạt; `presentation-source-checks-20261025.json`.

Giới hạn giữ nguyên: đây là hệ thống mô phỏng; chưa thử mọi trình duyệt, tải nhiều người dùng hoặc SMTP thật. Chỉ sửa phạm vi giá/lịch/dữ liệu mẫu và các lỗi giá liên quan; không tự xử lý các phát hiện audit khác. Main giữ nguyên. Clone nhánh mới theo README, cấu hình SQL Server/ODBC và chạy seed sau migrations; GitHub không tự tạo database cho máy clone.

---

# Lịch sử — giá và dữ liệu demo, 25/10/2026

Phạm vi lần này: sửa giá mẫu, mở rộng lịch bay, giá gợi ý/tìm kiếm và đóng gói. Giữ Microsoft SQL Server/T-SQL, dùng SSMS bình thường; không đổi Flask, không sửa migrations 001–014. Các kết quả ngày cũ phía dưới là lịch sử.

- **119 PASS, 0 FAIL, 0 ERROR, 0 SKIP, 186,77 giây** trên SQL Server Express thật, database kiểm thử riêng `AeroFlow_Test_Pricing_20261025`; `evidence/pricing-regression-20261025.xml`. Gồm 76 test cũ, 37 test lịch/giá thuần, 4 test giá công khai và 2 test importer SQL.
- Preview riêng `AeroFlow_Test_Preview_20261025` nạp **1.080 chuyến mới**, 9 máy bay × 150 ghế, 12.960 giá vé, 10 sân bay, 3 hãng giả lập; cộng 120 chuyến baseline là 1.200 chuyến. Khoảng ngày Việt Nam 26/10–24/11/2026. Database demo không chạy fixtures nghiệp vụ; database/tài khoản cũ không bị xóa.
- Đọc bằng kết nối mới xác nhận đủ số dòng; nhập lại **0 chuyến mới, 0 giá thay đổi**. Hash Tickets/Bookings/Payments giữ nguyên qua lần nhập lại. SQL test riêng đối chiếu toàn bộ hàng trước/sau lần nhập đầu và giữ nguyên giá chuyến ngoài allowlist. Lỗi giữa ngày thứ hai rollback toàn bộ thay đổi của importer. `evidence/demo-seed-sql-20261025.xml`.
- Đã phát hiện và sửa lỗi transaction lồng trong importer mới: `BEGIN TRANSACTION` dư làm ODBC commit chưa kết thúc giao dịch và close rollback. Các kết quả thành công hiện tại đều được xác nhận bằng kết nối SQL mới sau khi sửa.
- `DBCC CHECKDB`, `DBCC CHECKCONSTRAINTS`, vòng quay máy bay, khoảng nghỉ tối thiểu 60 phút, giá/ngày gợi ý và khóa ghế không trùng: PASS. `evidence/demo-catalog-validation-20261025.json`; truy vấn SSMS ở `sql/demo/verify_demo_catalog.sql`.
- Tổng phổ thông Basic HAN–SGN trong bộ mẫu 1.809.500–2.170.300 VND/người lớn; giá đã gồm thuế mô phỏng 10%, chưa gồm ghế/dịch vụ mua thêm. Nguồn tham khảo chính thức và giới hạn ở `scripts/demo_price_reference.json`. Không phải giá trực tiếp của hãng.
- Browser thật: trang chủ hiển thị HAN–SGN 1.809.500 VND với ngày 27/10; tìm kiếm ngày đó trả 6 chuyến; chi tiết cho 2 khách có 12 hạng còn chỗ; Ultimate hiển thị lịch giá/hãng/điều kiện vé. Desktop 1440/1280 và mobile 390 không tràn ngang; không có console error/warning trong các thao tác đã thử. `evidence/pricing-browser-checks-20261025.json`, ảnh `pricing-*.png`.
- Truy vấn discovery trên 1.200 chuyến khoảng 224–239 ms trong phép đo local này; đây không phải kiểm thử tải. Python AST và Node syntax kiểm tra thành công: `evidence/source-verification-20261025.json`.

Giới hạn: chỉ các trường hợp nêu trên đã kiểm chứng; không tuyên bố mọi trình duyệt/tình huống đều đạt, chưa benchmark nhiều người dùng đồng thời, chưa thử SMTP thật hoặc triển khai public. Những phát hiện audit khác ngoài giá/dữ liệu không được tự sửa trong lần này. Mã hiện tại được đóng gói ZIP, chưa push/merge GitHub. Dùng README và MIGRATION_GUIDE để cập nhật database hiện có.

---

# Lịch sử — frontend refresh, 23/10/2026

Cập nhật nền: bầu trời/mây/đường bay local SVG cho các khoảng trống trên toàn website; tiêu đề và footer có nền sáng, khai báo only light. Đã thử thao tác tìm chuyến (4 phương án HAN–SGN 26/10), desktop/mobile không tràn ngang và nút dừng chuyển động; xem `evidence/sky-browser-checks.json` và ảnh `sky-*.png`. Chưa thử cơ chế ép màu tối của Cốc Cốc. Bản cập nhật nền chỉ có HTML/CSS/SVG; không chạy lại bộ 76 test nghiệp vụ (kết quả bên dưới thuộc lần chạy trước).

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

# Lịch sử — AeroFlow Ultimate, trạng thái bàn giao 14/10/2026

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
