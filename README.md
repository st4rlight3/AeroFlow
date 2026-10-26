# AeroFlow Marketplace — nhánh dịch vụ du lịch

Nhánh `feature/travel-marketplace` mở rộng từ `feature/presentation-demo-dec-jan`; vẫn dùng Flask, pyodbc và Microsoft SQL Server. Giữ giao diện AeroFlow và nghiệp vụ hàng không. Không có trợ lý AI.

Bản này có 12 nhóm dịch vụ: khách sạn, vé tham quan, tour, spa, eSIM, xe khách, đưa đón sân bay, thuê xe, du thuyền, tàu, visa và sự kiện. Tìm/lọc, chọn ngày–gói, báo giá, giữ chỗ 10 phút, thanh toán mô phỏng, hủy/hoàn tiền, QR/PDF, yêu thích, giỏ lựa chọn, lịch trình, hỗ trợ, đăng ký đối tác và quản trị đều đọc/ghi SQL Server. Danh mục mẫu gồm 132 dịch vụ, 264 gói và 16.368 lịch bán trong 01/12/2026–31/01/2027, ngoài 6.288 chuyến bay.

Các nhà cung cấp, dịch vụ, giá và lịch mới là dữ liệu hư cấu cho đồ án; không phải giá thị trường hay kho chỗ của Traveloka. Trang [tham khảo nhóm dịch vụ](https://www.traveloka.com/vi-vn/activities) dùng để đối chiếu phạm vi. Thanh toán, eSIM, visa và phiếu được mô phỏng. Không có kết nối nhà cung cấp, ngân hàng hoặc phát hành dịch vụ thật. Không tuyên bố đã sao chép đầy đủ mọi tính năng thương mại của Traveloka.

Cài trên Windows (Python 3.11+, SQL Server Express và Microsoft ODBC Driver 18; SSMS dùng quản trị SQL):

```powershell
git clone --branch feature/travel-marketplace https://github.com/st4rlight3/AeroFlow.git
cd AeroFlow
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe scripts\configure.py
```

Sửa `.env` theo SQL Server của bạn. Database mới: chạy `scripts/init_db.py`, sau đó áp dụng **001–022** theo `MIGRATION_GUIDE.md`. Database đã có dữ liệu: bỏ qua `init_db.py`, sao lưu và migrate; không chạy lại baseline lên database đã nâng cấp.

```powershell
.\.venv\Scripts\python.exe scripts\load_demo.py --preview
.\.venv\Scripts\python.exe scripts\load_demo.py --apply --start-date 2026-12-01 --days 62
.\.venv\Scripts\python.exe scripts\create_user.py --role ADMIN --email admin@example.test
.\.venv\Scripts\python.exe run.py
```

Mở `http://127.0.0.1:5000/#explore`; trang máy bay vẫn ở `#home` và `#ultimate`. Quản trị dịch vụ ở `#travel-admin`. `load_demo.py` gồm ba bộ nhập độc lập; mỗi bộ có transaction riêng, chạy lại không nhân bản hoặc ghi đè giá đã chỉnh. Có thể chỉ nhập du lịch bằng `scripts/seed_travel.py --apply`.

Trong SSMS, mở `sql/demo/verify_travel_marketplace.sql` để xem tên điểm đến, gói và giá đã lưu. Giá máy bay vẫn trong `dbo.FlightFares`; giá dịch vụ trong `dbo.TravelInventory`. Đơn dịch vụ có snapshot giá và điều kiện hủy, tách khỏi đơn vé máy bay. Điểm/tín dụng vé máy bay hiện chỉ áp dụng phân hệ hàng không. Giỏ lựa chọn lưu gói để đặt riêng; không quảng cáo thanh toán gộp hoặc đổi ngày tự động.

Kiểm thử mới nhất: **217 PASS**, gồm 40 ca dịch vụ và 4 ca kết nối bổ sung. XML: `evidence/marketplace-final-release-regression-20261026.xml`. Có kiểm tra bản sao lưu/khôi phục toàn bộ bảng và kiểm tra trên trình duyệt; xem `PROGRESS.md`. Các kết quả cũ bên dưới là lịch sử của phân hệ hàng không.

---

# AeroFlow trong nước và quốc tế — cập nhật 26/10/2026

Nhánh hiện tại: **feature/presentation-demo-dec-jan**. Bản lịch trình diễn 01/12/2026–31/01/2027 trên database demo sạch có **6.288 chuyến = 2.232 nội địa + 3.936 quốc tế + 120 baseline**, **42 sân bay**, **170 đường bay** và **74.376 dòng giá vé**. Phần quốc tế gồm 32 sân bay tại 20 quốc gia/vùng lãnh thổ ngoài Việt Nam. Đây là dữ liệu mô phỏng; số lượng trên không áp dụng cho database hồi quy có thêm fixtures.

Cài Python/SQL Server/ODBC và cấu hình theo mục **Chạy trên Windows** bên dưới. Database mới cần init baseline rồi migrate; database đã có dữ liệu bỏ qua init. Dừng website, kiểm tra `.env`, sao lưu rồi áp dụng đủ **migrations 001–017** trước khi nhập lịch. Các migration đã ghi trong ledger là bất biến.

```powershell
.\.venv\Scripts\python.exe scripts\load_demo.py --preview --start-date 2026-12-01 --days 62
.\.venv\Scripts\python.exe scripts\load_demo.py --apply --start-date 2026-12-01 --days 62
.\.venv\Scripts\python.exe run.py
```

`load_demo.py` là lối vào chung, gọi lần lượt hai bộ nhập độc lập. Có thể dùng riêng `seed_ultimate.py --preview/--apply` cho nội địa và `seed_international.py` cho quốc tế; với quốc tế, không có `--apply` là xem trước. Dùng cùng `--start-date 2026-12-01 --days 62` cho cả hai. Mỗi bộ nhập có transaction riêng và chạy lại không nhân đôi; nếu giai đoạn quốc tế thất bại, chạy lại sau khi xử lý nguyên nhân.

Website vẫn đọc dữ liệu trực tiếp từ Microsoft SQL Server qua ODBC/T-SQL. Ngày tìm kiếm/tuổi hành khách theo sân bay đi; giờ khởi hành và đến theo múi giờ từng sân bay, có xử lý DST. SQL lưu UTC. **Màn hình Admin nhập lịch bay vẫn dùng giờ Việt Nam**, đúng nhãn trên biểu mẫu. Các tệp [giá theo đường bay](data/demo_route_prices.csv) và [giá theo chuyến](data/demo_flight_prices.csv) chỉ là ảnh chụp dữ liệu SQL để xem trên GitHub/Excel, không cấp dữ liệu cho ứng dụng. Tái xuất bằng `scripts/export_demo_prices.py`.

Hồi quy quốc tế ban đầu, trước migration 017: **171 PASS, 0 FAIL/ERROR/SKIP, 207,953 giây**, xem `evidence/international-full-regression-20261026.xml`. Kiểm chứng cuối sau migration 017: **173 PASS, 0 FAIL/ERROR/SKIP**, 206.470 giây (`evidence/international-final-regression-20261026.xml`). Cài database mới, nâng cấp đủ 17 migrations, bảo toàn lịch sử, nhập lại không đổi dữ liệu và đối chiếu múi giờ đã đạt; xem `evidence/international-fresh-upgrade-20261026.json`, `evidence/international-final-validation-20261026.json`. Truy vấn SSMS: `sql/demo/verify_demo_catalog.sql` và `sql/demo/verify_international_catalog.sql`. Không chạy fixtures kiểm thử trên database trình diễn. Footer hiện tại đã bỏ nút chuyển động; các ghi chép về nút này dưới đây chỉ thuộc lịch sử.

Hoàn tất và push bản trên nhánh hiện tại trước khi tạo nhánh tiếp theo. **Nhánh mới không có tính năng trợ lý AI.** Không sửa/merge main hoặc tạo thêm slide/báo cáo trong phạm vi này. Các mục mang nhãn **Lịch sử** bên dưới mô tả đúng phiên bản cũ, không thay thế hướng dẫn hiện tại.

---

# Lịch sử 25/10/2026 — bản thuyết trình nội địa tháng 12 và tháng 1

Nhánh: **feature/presentation-demo-dec-jan**. Bản này gồm cập nhật giao diện, sửa hiển thị giá và bộ lịch **2.232 chuyến từ 01/12/2026 đến 31/01/2027**, 10 sân bay, 3 hãng giả lập, 9 máy bay mới × 150 ghế và 26.784 dòng giá. Cài mới có thêm 120 chuyến baseline trong tháng 12. Ngày ở giao diện là giờ Việt Nam; 06:00 ngày 01/12 được lưu dưới dạng UTC 23:00 ngày 30/11 trong SQL Server.

```powershell
git clone --branch feature/presentation-demo-dec-jan --single-branch https://github.com/st4rlight3/AeroFlow.git AeroFlow
cd AeroFlow
```

Cài Python/SQL Server/ODBC, tạo `.env`, init/migrate và Admin theo phần **Chạy trên Windows** bên dưới. Sau đó xem trước và nhập dữ liệu thuyết trình:

```powershell
.\.venv\Scripts\python.exe scripts\seed_ultimate.py --preview
.\.venv\Scripts\python.exe scripts\seed_ultimate.py --apply
.\.venv\Scripts\python.exe run.py
```

Trong tháng 11/2026, không truyền tham số sẽ chọn đúng 62 ngày trên. Có thể cố định bằng `--start-date 2026-12-01 --days 62`. `--start-date` riêng chọn cửa sổ 30 ngày; `--days` cho phép 1–90 ngày. Nếu chạy trong tháng 12/tháng 1, mặc định chỉ thêm phần còn ở tương lai đến 31/01. Sau mốc này mặc định chuyển sang 30 ngày từ ngày mai, tránh tạo chuyến đã hết hạn. Preview không kết nối database; `--apply` mới ghi dữ liệu. Dừng website, sao lưu và kiểm tra `.env` trước khi nạp vào database đã có.

Giá mẫu HAN–SGN phổ thông Basic khoảng **1,81–2,17 triệu đồng/người lớn**, gồm thuế mô phỏng 10%, chưa gồm ghế trả phí/dịch vụ thêm. Giá thay đổi theo tuyến, hãng, ngày, khoang và gói; nguồn tham khảo và giới hạn ở `scripts/demo_price_reference.json`, không phải dữ liệu bán trực tiếp của hãng.

**SSMS dùng bình thường:** backend vẫn kết nối Microsoft SQL Server qua ODBC và dùng T-SQL. Mở `sql/demo/verify_demo_catalog.sql` trong SSMS, chọn đúng database để kiểm tra lịch, giá, ràng buộc và vòng quay máy bay. Migrations 001–014 giữ nguyên checksum. Bản baseline 04 mới chỉ tác động lần cài mới: máy bay bay khứ hồi về căn cứ, khoang thương gia ở phía trước. Database cũ không bị đổi ngày/ghế của vé đã đặt; các chuyến cũ vẫn được giữ. Bộ nhập chỉ thêm chuyến mẫu mới và định giá lại đúng allowlist của seed.

Không chạy pytest trên database dùng để thuyết trình: fixtures cố tình tạo chuyến/giá và trạng thái lỗi. Dùng `AeroFlow_Test_*` riêng cho kiểm thử. Kết quả thực chạy mới nhất ở đầu `PROGRESS.md`; các mục ngày cũ bên dưới là lịch sử.

---

# Lịch sử 23/10/2026 — giao diện feature/frontend-refresh

Bản 23/10/2026, phát triển từ Ultimate commit 648139e. Trang chủ ảnh hàng không/điểm đến, bố cục mới, hiệu ứng chuyển trang/cuộn/hover, sơ đồ ghế và Dashboard đồng bộ. Frontend vẫn gọi Flask/SQL Server hiện có; không cần migration mới nếu đã cài Ultimate 001–014.

```powershell
# Nhánh được ghi nhận ở phiên 25/10/2026:
git clone --branch feature/presentation-demo-dec-jan --single-branch https://github.com/st4rlight3/AeroFlow.git AeroFlow
cd AeroFlow
```

Sau clone, cài Python/SQL Server/ODBC và cấu hình/chạy theo hướng dẫn bên dưới. GitHub lưu mã nguồn, không tự chạy Flask hoặc cung cấp SQL Server cho máy người clone.

Nút **Tắt chuyển động** ở cuối trang ghi nhớ lựa chọn trên trình duyệt; hỗ trợ `prefers-reduced-motion`, tạm dừng hiệu ứng khi tab ẩn. Ảnh minh họa AI lưu local dạng WebP, khoảng 637 KB cho cả bốn ảnh; không cần thư viện JavaScript hoặc font từ CDN. Nội dung giá/lịch/khả dụng vẫn từ SQL Server.

Kiểm chứng frontend: 76 tests hồi quy PASS trên database thử nghiệm riêng; browser desktop/mobile kiểm tra khứ hồi → đăng nhập → ghế A6 → thanh toán, Dashboard, nút chuyển động và nhớ lựa chọn sau tải lại. Chi tiết trong PROGRESS.md và evidence/frontend-*. Chưa kiểm tra mọi trình duyệt hoặc thiết bị thực; cài đặt giảm chuyển động của hệ điều hành chưa được ép bật trong phiên QA (nút tắt trong ứng dụng đã thử).

---

# AeroFlow — hướng dẫn vận hành hiện tại

Website hàng không mô phỏng: HTML/CSS/JavaScript ↔ Flask ↔ pyodbc ↔ Microsoft SQL Server. Nâng cấp từ AeroFlow trên nhánh `feature/ultimate-upgrade`. Không có SQLite hoặc dữ liệu nghiệp vụ thay thế trong frontend.

Nền tảng Ultimate được bàn giao lần đầu ngày 14/10/2026; hướng dẫn vận hành dưới đây đã cập nhật cho migrations 001–017. Kết quả và giới hạn: **PROGRESS.md**. Các tài liệu học thuật/slide cũ được giữ nguyên nhưng chưa cập nhật cho Ultimate theo yêu cầu tạm hoãn của người dùng. Ưu tiên README này và MIGRATION_GUIDE.md khi vận hành.

## Chạy trên Windows

Cần Python 3.11+, SQL Server Express (đã thử bản 2022), Microsoft ODBC Driver 18 cùng kiến trúc Python. Không cần Docker. SSMS hữu ích để xem dữ liệu. Windows account cần quyền tạo database và backup khi cài/nâng cấp.

Giải nén **AeroFlow_Ultimate_Complete.zip**, mở PowerShell trong **AeroFlow-Ultimate** có `run.py`:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe scripts\configure.py
notepad .env
```

Không cần kích hoạt venv hoặc đổi ExecutionPolicy. `configure.py` sinh SECRET_KEY ngẫu nhiên và không ghi đè `.env` đã có. Kiểm tra:

```dotenv
SQL_SERVER=.\SQLEXPRESS
SQL_DATABASE=AeroFlow
SQL_DRIVER=ODBC Driver 18 for SQL Server
SQL_TRUSTED_CONNECTION=yes
SQL_ENCRYPT=no
SQL_TRUST_SERVER_CERTIFICATE=yes
HOST=127.0.0.1
PORT=5000
```

Cấu hình trên dành cho demo cục bộ. SQL Authentication: đặt `SQL_TRUSTED_CONNECTION=no`, điền username/password riêng trong `.env`. Không commit/gửi `.env`. Khi triển khai HTTPS cần chứng chỉ đáng tin cậy và `SESSION_COOKIE_SECURE=true`. Cookie mặc định `aeroflow_ultimate`; dùng tên khác nhau khi chạy nhiều bản trên cùng hostname.

**Database mới:** chạy bước sau. **Database đã có dữ liệu AeroFlow:** bỏ qua bước này.

```powershell
.\.venv\Scripts\python.exe scripts\init_db.py
```

**Cả cài mới và nâng cấp đều cần migrations trước khi chạy website:** dừng ứng dụng/tác vụ nền, chọn đường dẫn backup mới rồi chạy:

```powershell
.\.venv\Scripts\python.exe scripts\migrate.py
.\.venv\Scripts\python.exe scripts\migrate.py --apply --backup-file "C:\SQLBackups\AeroFlow_before_international_20261026.bak"
.\.venv\Scripts\python.exe scripts\load_demo.py --apply --start-date 2026-12-01 --days 62
.\.venv\Scripts\python.exe scripts\create_user.py --role ADMIN --email admin@example.com --name "Quan tri AeroFlow"
.\.venv\Scripts\python.exe run.py
```

Backup path là ví dụ: thư mục phải tồn tại trên **máy SQL Server**, tài khoản dịch vụ SQL Server có quyền ghi, file chưa tồn tại. Có thể dùng thư mục Backup mặc định của instance. Lỗi backup sẽ dừng migration; không cấp quyền rộng cho toàn ổ đĩa. Runner dùng COPY_ONLY/CHECKSUM và VERIFYONLY trước migration. Xem MIGRATION_GUIDE.md.

`load_demo.py` nạp cả lịch nội địa và quốc tế; có thể chạy riêng hai module seed theo phần đầu README. Chạy khi website đã dừng, sau migrations 001–017. Các chuyến cũ được giữ; bộ quốc tế quản lý riêng máy bay DEMO-INT-… và không chuyển lịch hoặc giá vé đã phát hành.

Nhập mật khẩu Admin kín, 12–128 ký tự; **không có mật khẩu mặc định**. Mở **http://127.0.0.1:5000/#ultimate**. Khách đăng ký qua web. Admin đăng nhập → Quản trị. `/api/health` kiểm tra SQL Server. Không chạy `init_db.py` hoặc baseline 02–08 để ghi đè database đã nâng cấp.

## Chức năng và quy tắc mô phỏng

- Một chiều, khứ hồi, nhiều thành phố; tìm tối đa một điểm nối mỗi nhóm. Lịch giá ±3 ngày, lọc hãng/ngân sách/điểm dừng, sắp xếp giá/thời lượng/khởi hành, bốn khoang, so sánh điều kiện vé.
- Một PNR nhiều chặng, tối đa 9 khách; cần người lớn, mỗi người lớn tối đa một em bé. Tuổi xác minh theo ngày bay; em bé có ghế riêng. Nối cùng sân bay 60 phút–8 giờ; tối đa 6 nhóm/12 chặng; đóng bán trước giờ lịch 2 giờ.
- Hành khách lưu sẵn, hỗ trợ đặc biệt, chọn ghế từng người/từng chặng hoặc tự xếp. Ghế ưu tiên có phí. Chọn trên màn hình chưa giữ ghế; xác nhận đặt chỗ giữ 10 phút theo đồng hồ SQL Server.
- Hành lý/suất ăn/ưu tiên/phòng chờ. Mỗi vé một loại suất ăn. Một promo/voucher hoặc điểm, không cộng dồn. Điểm đổi 1.000 VND/điểm, tối đa 50% đơn; điểm được giữ cùng đơn HELD. Giá/thuế/phí/giảm giá do server tính.
- Thanh toán thất bại/thử lại/thành công hoặc travel credit đều mô phỏng. Idempotency key chống xử lý lặp. Chỉ chủ PNR hoặc Admin được đọc đặt chỗ.
- Đổi ngày/chuyến/nâng khoang cho toàn bộ khách của một chặng còn đủ vé hợp lệ, cùng đường bay, trước giờ lịch ít nhất 24 giờ, chưa check-in và hạng cũ cho đổi. Thu/hoàn chênh lệch MOCK, tự xếp ghế mới, giữ vé cũ VOID và lịch sử. Không chia PNR hoặc tự đổi sân bay; chênh lệch không tự chuyển sang credit.
- Hủy riêng vé hoặc cả đơn trước giờ lịch ít nhất 24 giờ; hoàn theo snapshot vé/dịch vụ sau phân bổ giảm giá. Hủy riêng cho chọn credit. Hãng hủy một chặng thì hủy toàn PNR và hoàn số đã thu trừ đã hoàn, không hoàn trùng. Phí đổi không hoàn khi khách tự hủy.
- Điểm mới: 1 điểm/10.000 VND thanh toán; hoàn tiền điều chỉnh điểm; số khả dụng tối thiểu 0. Không cộng hồi tố trước nâng cấp. Hạng thành viên theo điểm tích lũy ròng, độc lập điểm đã dùng.
- Check-in từng vé/chặng từ 24 giờ đến 1 giờ trước giờ dự kiến. QR DEMO chứa tham chiếu ngẫu nhiên. Admin nhập tham chiếu để xác minh và ghi nhận lên máy bay khi chuyến BOARDING. PDF vé, boarding pass, biên nhận và báo cáo vận hành có nhãn mô phỏng.
- Admin quản lý danh mục/đường bay/lịch/ghế/giá/dịch vụ/ưu đãi/hạng thành viên, khách/booking/giao dịch/refund, check-in/cửa/chậm chuyến, audit và báo cáo CSV/PDF. Biểu đồ đọc SQL Server. Báo cáo theo UTC; lịch bay công khai hiển thị giờ địa phương của từng sân bay. Biểu mẫu Admin nhập lịch theo giờ Việt Nam.

SQL dùng DECIMAL(14,2); API trả tiền bằng chuỗi, giao diện VND làm tròn đến đồng. Tổng booking sau thanh toán thể hiện tổng các lần thu; khoản hoàn xem trong lịch sử. PDF vé gồm dịch vụ/ưu đãi của vé; phí đổi riêng ở biên nhận. Snapshot hành lý và điều kiện đổi giữ nguyên khi sửa danh mục.

## Tác vụ bổ sung

- PDF dùng `C:/Windows/Fonts/arial.ttf`; nếu thiếu đặt `PDF_FONT_PATH` tới TTF Unicode. PDF đã tải không tự cập nhật sau đổi/hủy: tra lại website.
- `python scripts/expire_holds.py`: dọn giữ ghế; có thể chạy mỗi phút bằng Windows Task Scheduler, đúng venv/thư mục dự án/Windows account. Các API ghế/đặt/thanh toán cũng dọn hết hạn; không cần SQL Server Agent.
- Admin → Khai thác & check-in → tạo nhắc chuyến, chống trùng. Cửa/delay do Admin nhập, không kết nối dữ liệu hàng không thật.
- Email: khách bật tùy chọn; cấu hình SMTP trong `.env`. `python scripts/send_notifications.py` chỉ dry run. Người vận hành chủ động chạy `python scripts/send_notifications.py --send --limit 20` để gửi STARTTLS; tối đa 5 lần thử, trạng thái lưu SQL. Chưa kiểm chứng SMTP thật; có thể gửi lặp nếu crash sau gửi nhưng trước ghi nhận SQL, không bảo đảm exactly-once email.
- Reset mật khẩu: người vận hành xác minh chủ tài khoản rồi chạy `python scripts/issue_reset_token.py --email <email>`. Token một lần, hạn 15 phút, chỉ lưu SHA-256; nhập tại `/#reset-password`. Chưa có email reset tự động. Đổi/reset kết thúc phiên cũ.

## SQL và kiểm thử

Baseline: **01 → 02 → 03 → 05 → 06 → 07 → 08 → 04**, vì seed gọi procedure/function/trigger thực. Sau đó migrations **001 → 017** bằng runner ledger/checksum; không sửa các file đã được ghi trong ledger. `09_business_queries.sql` có 18 truy vấn; `10_test_cases.sql` kiểm tra ràng buộc/rollback. SSMS scripts mặc định `USE AeroFlow`; kiểm tra database trước khi chạy. Runner kiểm tra và thay tên database hợp lệ.

Tạo database test riêng, không dùng dữ liệu thật:

```powershell
$env:SQL_DATABASE="AeroFlow_Test_Local"
.\.venv\Scripts\python.exe scripts\init_db.py
.\.venv\Scripts\python.exe scripts\migrate.py --apply --test-database
$env:RUN_SQL_TESTS="1"
.\.venv\Scripts\python.exe -m pytest -q --junitxml=evidence\local-tests.xml
.\.venv\Scripts\python.exe scripts\verify_database.py --prefix local-
Remove-Item Env:RUN_SQL_TESTS
Remove-Item Env:SQL_DATABASE
```

`--test-database` chỉ cho `AeroFlow_Test_*`. Tests cố tình gây lỗi/tạo tài khoản và chuyến thử, giữ dữ liệu chứng minh trong DB đó. `python scripts/verify_upgrade.py --run` tạo các database tên riêng, kiểm tra baseline → migrate → no-op → backup/restore và hash cột cũ; cần quyền tạo/backup/restore và không tự xóa DB sau chạy.

Inventory dùng applock Exclusive cấp transaction chung + unique filtered index ghế hiệu lực. Bảo vệ toàn hành trình, rollback nhất quán; giới hạn thông lượng, chưa kiểm thử tải lớn. Queries có tham số, hash scrypt, backend kiểm tra quyền/CSRF/session. Chưa pentest độc lập.

## Demo nhanh và Git

1. Seed Ultimate, tìm HAN → SGN trong tháng 12/2026 hoặc tháng 1/2027. Chọn chuyến DX…, gói Linh hoạt và A7 có phí hoặc tự xếp miễn phí. Có thể chọn khứ hồi hoặc nối qua DAD.
2. Đặt vé, thêm hành lý, mã `ULTIMATE10` hoặc `DEMO100K` khi còn hiệu lực; thử thanh toán thất bại rồi thành công. Mở SSMS xem Bookings/BookingSegments/Tickets/Payments.
3. `pytest tests/test_itineraries.py -q` chứng minh tranh chấp ghế chặng dùng chung; chỉ một khách thành công.
4. Đổi ngày/nâng khoang, xem giá chênh lệch/vé cũ VOID; hủy riêng hoàn credit. `tests/test_exchange_wallet.py` kiểm tra chi tiêu credit đồng thời.
5. Admin mở dashboard, doanh thu, danh mục và khai thác. Demo check-in cần chuyến trong cửa sổ 24–1 giờ; dùng fixture test tạo lịch riêng, không sửa trực tiếp chuyến đã bán của người dùng.
6. `tests/test_migrations.py`, `sql/10_test_cases.sql` và integration tests minh chứng rollback/ràng buộc. Kết quả hồi quy hiện tại ở `evidence/international-full-regression-20261026.xml`; `evidence/ultimate-*` là lịch sử.

Không merge main. Dùng ZIP cập nhật repo đã clone: chuyển nhánh `feature/presentation-demo-dec-jan`, sao lưu thay đổi chưa commit, chép nội dung **bên trong AeroFlow-Ultimate** vào repo (không chép `.git`, không đè `.env`), xem diff, cài requirements, backup/migrate và test. Người dùng tự tạo PR/merge.

Đóng gói lại: `python scripts/package_release.py --output <đường-dẫn>\AeroFlow_Ultimate_Complete.zip`. ZIP chứa MANIFEST.sha256, kiểm tra CRC/từng byte; loại `.env`, venv, Git metadata, cache và backup DB.
