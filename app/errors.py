class ApiError(Exception):
    def __init__(self, message, status=400, code='VALIDATION_ERROR'):
        super().__init__(message)
        self.message, self.status, self.code = message, status, code

SQL_ERRORS = {
    51001: ('Dữ liệu đang được cập nhật. Vui lòng thử lại.', 409),
    51002: ('Tài khoản không hoạt động.', 403),
    51003: ('Chuyến bay không còn mở bán hoặc cho phép thanh toán.', 409),
    51004: ('Dữ liệu chưa hợp lệ. Kiểm tra hành khách, ghế, hạng vé và lịch bay.', 400),
    51005: ('Ghế vừa được người khác giữ. Vui lòng chọn ghế khác.', 409),
    51006: ('Không tìm thấy dữ liệu hoặc bạn không có quyền truy cập.', 404),
    51007: ('Mã thanh toán đã được dùng cho yêu cầu khác.', 409),
    51008: ('Đơn đã thanh toán, đã hủy hoặc hết hạn giữ ghế.', 409),
    51009: ('Chỉ hủy vé đã thanh toán trước giờ bay ít nhất 24 giờ.', 409),
    51010: ('Trạng thái hiện tại không cho phép thao tác này.', 409),
    51011: ('Dữ liệu đã có lịch sử sử dụng. Hãy tạo bản ghi mới để giữ nguyên lịch sử.', 409),
    51012: ('Máy bay có lịch trùng hoặc chưa đủ 45 phút quay đầu.', 409),
    51013: ('Giá hoặc ghế đã thay đổi. Vui lòng kiểm tra lại báo giá.', 409),
    51014: ('Chưa thể check-in. Vé phải còn hiệu lực, trong khoảng từ 24 giờ đến 1 giờ trước giờ bay dự kiến.', 409),
    51015: ('Mã giảm giá không hợp lệ, hết lượt hoặc chưa đủ giá trị đơn tối thiểu.', 409),
    51016: ('Số dư tín dụng/điểm không đủ hoặc vượt giới hạn giảm giá bằng điểm.', 409),
    51017: ('Không thể đổi chặng theo lựa chọn này. Kiểm tra điều kiện vé, hạn 24 giờ và thời gian nối chuyến.', 409),
}
