# Kết quả kiểm thử thực tế

## Môi trường và phạm vi

Ngày 12/10/2026 (Asia/Ho_Chi_Minh), Windows, Python 3.12, Flask 3.1.2, pyodbc 5.3.0, Microsoft ODBC Driver 18, SQL Server 2022 Express 16.0.1000.6. Không mock database trong integration suite. Database test riêng `AeroFlow_Test_Final_20261012`, tách khỏi DB phục vụ kiểm tra UI.

**Lần chạy cuối: 39 passed, 0 failed, 0 skipped, 35.77 giây.** Đây là kết quả pytest từ `evidence/pytest-output.txt` và `evidence/pytest-results.xml`, không phải cam kết mọi trường hợp đều an toàn hoặc đã đạt kiểm thử production.

17 test unit/security (bao gồm các trường hợp parameterized) và 22 test tích hợp SQL Server. `test_unavailable_database_safe_response` cố ý giả lập lỗi connect ở unit test để kiểm tra phản hồi 503 không lộ bí mật; test đó không chứng minh mất kết nối mạng thật. Các integration test sử dụng connection SQL Server thật và có commit/rollback thật.

## Các trường hợp đã chạy đạt

| Nhóm | Bằng chứng |
|---|---|
| Đăng ký, trùng email, mật khẩu sai, đăng nhập, logout | test_registration_login_logout; xác nhận hash scrypt trong DB |
| Chưa login, Customer bị chặn Admin, admin đọc báo cáo | test_unauthenticated_endpoints; test_roles_and_admin_views |
| Tìm chuyến, giá function, chi tiết, 12 ghế test | test_search_and_details |
| Tạo booking, không nhận giá do frontend tự khai | test_booking_uses_database_price_and_seat_conflict |
| Hai khách đặt cùng ghế đồng thời | Barrier + 2 clients: một 201, một 409; active count=1 |
| Unique index chặn writer trực tiếp | test_filtered_unique_index_blocks_direct_double_assignment |
| Đặt hai hành khách nguyên tử | test_group_booking_atomic_total; 2 vé VALID, tổng 2.200.000 |
| Thanh toán thất bại, gửi lại cùng key, key khác payload | test_failed_duplicate_and_success_payment |
| Hai payment cùng key đồng thời | test_concurrent_payment_exactly_once; một PaymentID |
| Thanh toán tranh với hủy | test_payment_cancel_race_preserves_final_state |
| Hết hạn hold, vé VOID, bán lại ghế, không pay hold cũ | test_expired_hold_releases_and_cannot_pay |
| Hủy tự nguyện, hoàn 80%, không refund lặp | test_cancel_refund_and_idempotent_release |
| Hủy trong 24 giờ bị từ chối | test_cancel_cutoff |
| Truy cập booking người khác (GET/pay/cancel) | test_ownership_prevents_idor |
| Thiếu dữ liệu, sinh trong tương lai, ghế/giấy tờ trùng, seat sai | test_booking_validation |
| SQL Injection là literal data, không chạy DROP | test_sql_injection_is_data; validation tests |
| Lỗi giữa transaction sau các insert ban đầu | test_transaction_rollback_after_partial_writes; 6 bảng giữ nguyên số row |
| CHECK/FK/UNIQUE, vé/booking/assignment nhất quán | test_check_unique_fk_and_consistency + 10_test_cases.sql |
| Sửa giá không đổi vé cũ; hãng hủy hoàn 100%; state invalid | test_admin_catalog_fares_and_status |
| Tạo máy bay 18 ghế và lịch bay, từ chối lịch trùng | test_admin_creates_aircraft_flight_and_seat |
| Không đổi cabin hạng vé đã dùng | test_fare_cabin_change_is_blocked_when_used |
| Khóa customer vô hiệu phiên | test_customer_disable_invalidates_session |
| CSRF, cookie/security headers, giới hạn payload, số/time | test_unit.py |

SQL scripts được chạy thật: 01–08 theo thứ tự dependency, Q01–Q18 của 09, và 10 gồm các thao tác sai có kiểm tra ERROR_NUMBER, rollback, DBCC CHECKCONSTRAINTS. `evidence/sql-checks.json` lưu số result set/row, `database-inventory.json` lưu schema/ràng buộc/index/số dòng, `rerun-scripts.txt` lưu lần khởi tạo lại không nhân đôi seed.

Inventory được chụp ngay sau seed và rerun, trước khi UI test tạo thêm Customer/booking. Vì vậy số liệu seed và số bản ghi trên máy sau kiểm tra UI có thể khác nhau, không phải dữ liệu seed bị nhân đôi.

## Kiểm tra trình duyệt đã thực hiện

Codex in-app browser, desktop 1366×900 và mobile 390×844. Đã thao tác thực trên ứng dụng localhost kết nối SQL Server:

- Đăng ký Customer giả lập, đăng nhập, tìm HAN→SGN ngày 14/10/2026, chọn hạng FLEX và ghế A1.
- Nhập passenger giả, xác nhận tạo booking 41, PNR 02C06863, giá 1.595.000 VND lấy từ DB.
- Thanh toán mô phỏng FAILED rồi SUCCESS: booking CONFIRMED, ticket VALID, số tiền không đổi.
- Hủy trước 24 giờ: booking CANCELLED, ticket VOID, REFUND 1.276.000 VND (80%). Lịch sử hiển thị ba giao dịch đúng trạng thái.
- Kiểm tra bố cục vé ở mobile: document width 375 trong viewport 390 (phần còn lại dành scrollbar), không tràn ngang.
- Ảnh trang chủ, sơ đồ ghế, vé desktop/mobile, hủy trên mobile nằm trong `evidence/ui-*.jpg`.

Ảnh là dữ liệu demo giả lập, không phải vé hoặc giao dịch ngân hàng thật. Các screenshot không thay thế assertions của pytest.

## Phần chưa kiểm chứng và việc cần người nhận thực hiện

- Chưa kiểm tra trực quan toàn bộ màn hình quản trị. API admin, report, catalog, cập nhật chuyến/giá/khách đã có integration tests. Một yêu cầu tạo ADMIN UI với mật khẩu cố định bị automatic approval review từ chối; không tạo tài khoản đó hoặc tìm cách vượt chặn. Người nhận tự tạo admin bằng CLI và kiểm tra UI quản trị.
- Chưa kiểm chứng hộp thoại in của từng trình duyệt/máy in, in/đóng bìa vật lý, hoặc mở slide bằng Microsoft PowerPoint. PDF/slide được render và kiểm tra package/layout bằng công cụ tài liệu, không tự nhận đã mở PowerPoint.
- Chưa chạy tải lớn, stress dài hạn, deadlock stress nhiều chuyến, restart process/network fault thực, backup/restore/failover, đa node, pentest hay TLS công khai.
- Chưa kiểm chứng dưới SQL principal bị giới hạn quyền, SQL Server 2019, phiên bản ODBC khác hoặc Python3.11; Windows/Python3.12/Express2022/ODBC18 là tổ hợp có bằng chứng.
- Chưa triển khai public. App chạy local, không payment thật. Windows Task Scheduler có hướng dẫn nhưng không tự cấu hình tác vụ lâu dài trên máy người dùng.

## Cách tái hiện

Theo README mục kiểm thử, dùng database tên `AeroFlow_Test_<suffix>`, chạy init trước rồi RUN_SQL_TESTS=1. Nếu không bật RUN_SQL_TESTS, các test SQL sẽ SKIP, không được tính là PASS. Thời gian chạy có thể khác tùy phần cứng. Suite để lại các bản ghi thử trong DB test nhằm cho phép quan sát lại; không gọi đó là seed production.

Lịch sử sửa: lần đầu 34 passed/1 failed vì test kỳ vọng login injection trả401 trong khi validation từ chối sớm400. Đã chỉnh payload để thực sự đến truy vấn có tham số, chạy lại35 passed. Sau rà soát bổ sung4 trường hợp và sửa bảo vệ cabin, lần cuối39 passed. Các log cuối bàn giao không chứa mật khẩu của fixture.
