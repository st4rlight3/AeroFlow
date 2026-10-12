# Giả định và các quyết định phạm vi

Nguồn bắt buộc: `assignment.pdf` (3 trang). Các phần workflow của đề được triển khai cùng yêu cầu sản phẩm bổ sung của người dùng. Không có xung đột công nghệ: SQL Server Express, Flask, pyodbc được giữ nguyên.

1. Một chiều, bay thẳng nội địa Việt Nam, VND. Không yêu cầu tích hợp hãng hoặc giá thị trường thật; seed là dữ liệu mô phỏng nhất quán nằm trong SQL Server.
2. Mỗi hành khách có ghế riêng, không infant-on-lap, không phân loại giá theo độ tuổi. Tối đa 9 người/booking. Nếu cần nhiều hơn phải đặt nhiều booking; chúng không nguyên tử với nhau.
3. Ký hiệu ghế là cột trước hàng (A1) để khớp demo. Mỗi máy bay có SeatID riêng. 6 cột A–F và hàng BUSINESS ở cuối là cấu hình demo, không sao chép sơ đồ hãng.
4. Giữ ghế 10 phút từ SYSUTCDATETIME. Không giữ lúc click ghế; giữ khi xác nhận booking đầy đủ. Hết hạn giải phóng bởi request cleanup hoặc scheduler mỗi phút.
5. Đóng bán trước khởi hành 2 giờ. Không sửa lịch/máy bay của chuyến có lịch sử booking; hủy và tạo mới để bảo vệ vé cũ. Không xóa cứng lịch sử.
6. Customer hủy toàn booking trước 24 giờ sau khi trả tiền. ECO hoàn 0%, FLEX 80%, BIZ 90% theo điều khoản snapshot. Chuyến bị hãng hủy hoàn 100%. Không áp dụng quy định hãng hàng không thực tế hoặc tư vấn pháp lý.
7. Thanh toán Success true/false do người dùng chủ động mô phỏng để phục vụ demo, không thể dùng cho mua vé thật. Không thu thập dữ liệu thẻ.
8. Thời gian DB UTC, tìm theo ngày Việt Nam, báo cáo tiền theo ngày UTC có nhãn rõ ràng. Không dùng timezone máy host để quyết định giá hay expiry.
9. Password tối thiểu 12 ký tự, tài khoản tạo trên web luôn CUSTOMER. Người cài quản trị database tạo ADMIN bằng CLI.
10. Báo cáo và slide cung cấp nội dung hoàn chỉnh của hệ thống; thông tin trường/lớp/sinh viên chưa được cung cấp nên có dòng điền trước khi in. Không tự tạo danh tính, mã sinh viên hoặc xác nhận in/đóng quyển.
11. Chỉ kiểm chứng SQL Server 2022 Express trên Windows với ODBC18/Python3.12; các phiên bản tương thích khác cần xác nhận tại máy nhận.
12. Dữ liệu UI hoàn toàn lấy API SQL Server. State biểu mẫu đang nhập, lựa chọn ghế và token idempotency ở browser không thay thế dữ liệu nghiệp vụ bền vững.
