# Checklist và ma trận truy vết yêu cầu

PDF đã đọc đủ 3 trang và đối chiếu hình trang với text. Bảng dưới bao phủ cả yêu cầu chung và các bước gợi ý chi tiết; không xem ví dụ Thư viện/quản lý sinh viên trong tài liệu là chủ đề phải làm.

| ID | Nguồn / yêu cầu | Triển khai | Bằng chứng |
|---|---|---|---|
| P01 | Trang 1: chọn đề tài, không quản lý sinh viên | AeroFlow đặt vé máy bay, ARCHITECTURE.md | Web chạy Flask |
| P02 | Trang 1,3: báo cáo PDF, in quyển, slide, SQL | BAO_CAO.pdf, AeroFlow_Slides.pptx, 10 SQL | PDF/PPTX đã render; người dùng tự in/đóng quyển |
| P03 | Trang 1: ≥6 bảng chính, không tính log | 15 bảng nghiệp vụ + AuditLogs | database-inventory.json |
| P04 | Trang 1,2: PK/FK/UQ/NOT NULL/DEFAULT/CHECK | 02_create_tables.sql + 03 | metadata, 10_test_cases, integration constraints |
| P05 | Trang 1,2: 30–200 rows một số bảng | 40 users/passengers/bookings/tickets, 120 flights, 48 payments | inventory và seed rerun |
| P06 | Trang 1,2: ≥10 business queries | 18 truy vấn đánh số Q01–Q18 | sql-checks.json |
| P07 | Trang 1,2: ≥3 stored procedures nghiệp vụ | 10 procs, application gọi 9 procs trực tiếp hoặc gián tiếp | real integration tests |
| P08 | Trang 1,2: ≥2 functions được dùng | tính giá, tỷ lệ ghế | fares API, overview, Q16 |
| P09 | Trang 1,2: ≥3 views phục vụ UI/báo cáo | 4 views availability, bookings, monthly, occupancy | search/history/dashboard APIs |
| P10 | Trang 1: README chạy toàn bộ | README thứ tự 01,02,03,05,06,07,08,04,09,10 | init_db lần đầu và chạy lại |
| P11 | Trang 1: phân tích chức năng/thực thể/quan hệ | ARCHITECTURE, DATABASE_DESIGN, ASSUMPTIONS | báo cáo |
| P12 | Trang 2: ERD có PK/FK/thuộc tính/kiểu | ERD.md, ERD.mmd, ERD.svg, data dictionary | metadata thật sau DDL |
| P13 | Trang 2: chuẩn hóa đến 3NF, nêu bước | DATABASE_DESIGN phần 1NF/2NF/3NF | logical model và DDL |
| P14 | Trang 2: DDL đặt constraint rõ tên | 02/03 mọi constraint có tên | inventory |
| P15 | Trang 2: INNER/LEFT/RIGHT/FULL JOIN | Q02/Q03/Q04/Q05 | đã execute |
| P16 | Trang 2: GROUP BY/HAVING | Q06 | đã execute |
| P17 | Trang 2: scalar/table subquery | Q07/Q08 + Q18 correlated | đã execute |
| P18 | Trang 2: UNION/INTERSECT/EXCEPT | Q09/Q10/Q11 | đã execute |
| P19 | Trang 2: SELECT *, LIKE, BETWEEN, TOP/PERCENT | Q01/Q12/Q13/Q14 | đã execute |
| P20 | Trang 2: WITH CHECK OPTION nếu cần | Views tổng hợp/join chỉ đọc; không dùng vì không cập nhật qua view | Giải thích trong báo cáo |
| P21 | Trang 2: tham số IN/OUT nếu cần | sp_CreateBooking @BookingID OUTPUT; procs có tham số | seed + runtime |
| P22 | Trang 2: kiểm thử constraint và transaction | 10_test_cases và pytest trigger fault | SQL/JUnit logs |
| P23 | Trang 2: INDEX/tối ưu cơ bản | filtered unique + indexes search/expiry/report | DDL, inventory; chưa benchmark tải |
| P24 | Trang 3: mô tả bảng/cột/query/procs/functions/hướng dẫn | DATA_DICTIONARY, BAO_CAO, README | PDF + source |
| P25 | Trang 3: slide/demo 10–15 phút | PPTX 12 slide và DEMO.md theo phút | nội dung và render |
| U01 | Customer và Admin portals tiếng Việt | app/static/app.js + routes | browser customer, integration admin |
| U02 | auth/logout/hash/role/CSRF/session | security.py, auth.py | unit + integration |
| U03 | tìm chuyến/giá/chi tiết | flights.py + view/function | test_search_and_details |
| U04 | ghế/hành khách/PNR/booking | sp_CreateBooking + checkout UI | booking tests + UI |
| U05 | thanh toán thất bại/trùng/đồng thời | sp_ConfirmPayment, UUID, unique indexes | payment tests |
| U06 | vé điện tử/in/hồ sơ/lịch sử | booking detail, print CSS, profile | API + browser |
| U07 | hủy/hoàn đúng quy tắc | sp_CancelBooking/status | cancel/cutoff/airline tests |
| U08 | admin chuyến/sân bay/máy bay/ghế/giá | admin.py CATALOGS + save procs | catalog/flight tests |
| U09 | khách hàng/đặt vé | admin lists and active state | roles/disable/IDOR tests |
| U10 | dashboard/chart/revenue/audit | 4 views, report proc, canvas từ API | admin views integration |
| U11 | chống double booking / hold expiry | flight applock + active unique index + cleanup | real concurrency and expiration |
| U12 | rollback/orphan/integrity | XACT_ABORT TRY/CATCH + transactional creation | fault injection counts + DBCC |
| U13 | SQL Injection và DB unavailable | binding validation sanitized errors | unit + integration |
| U14 | responsive/loading/empty/error/validation | CSS media rules, forms, toast, modal | browser QA và form/API tests |
| U15 | Windows/env/Git/ZIP/đủ tài liệu | scripts, .env.example, source-history.bundle, manifest | packaging audit |
| U16 | kết quả trung thực | TESTING.md / evidence | tách API tự động và browser thủ công |

Giới hạn còn lại cần người nhận: tự tạo mật khẩu quản trị, bổ sung thông tin bìa, in/đóng báo cáo. Chưa có kiểm thử tải/production security hoặc kiểm chứng trực quan toàn bộ màn hình admin; xem TESTING.md. Không thiếu SQL Server trong môi trường thực hiện: các test tích hợp đã chạy trên Express thật.
