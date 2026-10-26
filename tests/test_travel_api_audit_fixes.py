"""Regression cases for reproduced API audit failures, using real SQL Server."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from threading import Barrier
import uuid

import pytest

from app.db import query
from app.errors import ApiError
from app.validation import integer
from tests.conftest import send, sign_in
from tests.test_travel_marketplace import travel_item, selection


@pytest.mark.parametrize('value', ['²', '１２', '١٢', 'Ⅳ', '-1', '1.0', ' 1', '1 ', True, None, [], {}, 1.0, '9' * 5000])
def test_integer_rejects_non_ascii_or_non_integer_values(value):
    with pytest.raises(ApiError) as error:
        integer({'Value': value}, 'Value')
    assert error.value.status == 400


@pytest.mark.parametrize('value,expected', [(1, 1), ('1', 1), ('001', 1), (2147483647, 2147483647)])
def test_integer_accepts_bounded_ascii_decimal(value, expected):
    assert integer({'Value': value}, 'Value') == expected


def test_unicode_page_is_validation_error(client):
    response = client.get('/api/travel/products', query_string={'Page': '²'})
    assert response.status_code == 400
    assert response.get_json()['error']['code'] == 'VALIDATION_ERROR'


def test_single_inventory_insert_persists_with_triggers(app, users, travel_item):
    admin = sign_in(app, users[2])
    day = datetime.fromisoformat(travel_item['StartDate']).date() + timedelta(days=3)
    start = datetime.combine(day, datetime.min.time(), timezone.utc) + timedelta(hours=7)
    data = dict(PackageID=travel_item['PackageID'], ServiceDate=str(day), SlotCode='EVENING',
                StartsAt=start.isoformat(), EndsAt=(start + timedelta(hours=22)).isoformat(),
                Capacity=3, UnitPrice=1234567)
    response = send(admin, '/api/admin/travel/inventory', data)
    assert response.status_code == 200, response.get_json()
    inventory_id = response.get_json()['InventoryID']
    row = query('SELECT * FROM dbo.TravelInventory WHERE InventoryID=?', (inventory_id,), one=True)
    assert row['PackageID'] == travel_item['PackageID'] and row['SlotCode'] == 'EVENING'
    assert row['Capacity'] == 3 and row['UnitPrice'] == Decimal('1234567')
    assert query("SELECT COUNT(*) N FROM dbo.TravelAuditLog WHERE Entity='INVENTORY' AND EntityID=? AND Action='SAVE'", (inventory_id,), one=True)['N'] == 1
    invalid = send(admin, '/api/admin/travel/inventory', {**data, 'SlotCode': 'NOT BOOKABLE'})
    assert invalid.status_code == 400
    assert query('SELECT COUNT(*) N FROM dbo.TravelInventory WHERE PackageID=? AND ServiceDate=?', (travel_item['PackageID'], day), one=True)['N'] == 1


def test_provider_concurrent_applications_create_exactly_one_profile(app, users):
    clients = [sign_in(app, users[0]) for _ in range(8)]
    tokens = [client.get('/api/csrf').get_json()['token'] for client in clients]
    barrier = Barrier(8)
    data = dict(Name='Đối tác kiểm thử đồng thời', Description='Hồ sơ tổng hợp riêng cho kiểm thử cạnh tranh.')

    def apply(index):
        barrier.wait()
        response = clients[index].post('/api/travel/provider/apply', json=data,
                                       headers={'X-CSRF-Token': tokens[index]})
        return response.status_code, response.get_json()

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(apply, range(8)))
    assert sorted(status for status, _ in results) == [201] + [409] * 7, results
    assert query('SELECT COUNT(*) N FROM dbo.TravelProviders WHERE OwnerUserID=?', (users[0]['UserID'],), one=True)['N'] == 1
    assert all('đã gửi hồ sơ' in result['error']['message'] for status, result in results if status == 409)


def test_support_post_returns_current_status_and_closed_thread_is_unchanged(app, users):
    customer = sign_in(app, users[0])
    admin = sign_in(app, users[2])
    created = send(customer, '/api/travel/support', dict(Subject='Kiểm tra phản hồi', Message='Tôi cần kiểm tra trạng thái yêu cầu.'))
    assert created.status_code == 201
    tid = created.get_json()['TicketID']
    admin_path = f'/api/admin/travel/support/{tid}'
    customer_path = f'/api/travel/support/{tid}'
    answered = send(admin, admin_path, dict(Message='Đã trả lời yêu cầu.', Status='ANSWERED'))
    assert answered.status_code == 200 and answered.get_json()['ticket']['Status'] == 'ANSWERED'
    reopened = send(customer, customer_path, dict(Message='Tôi cần hỏi thêm một nội dung.'))
    assert reopened.status_code == 200 and reopened.get_json()['ticket']['Status'] == 'OPEN'
    assert query('SELECT Status FROM dbo.TravelSupportTickets WHERE TicketID=?', (tid,), one=True)['Status'] == 'OPEN'
    assert len(reopened.get_json()['messages']) == 3
    closed = send(admin, admin_path, dict(Message='Đã giải quyết yêu cầu.', Status='CLOSED'))
    assert closed.status_code == 200 and closed.get_json()['ticket']['Status'] == 'CLOSED'
    assert send(customer, customer_path, dict(Message='Không được ghi vào yêu cầu đã đóng.')).status_code == 409
    assert query('SELECT COUNT(*) N FROM dbo.TravelSupportMessages WHERE TicketID=?', (tid,), one=True)['N'] == 4


def test_package_description_matches_sql_column_limit(app, users, travel_item):
    admin = sign_in(app, users[2])
    data = dict(ProductID=travel_item['ProductID'], Name='Gói kiểm tra độ dài', Description='M' * 1000,
                UnitCode='PERSON', UnitLabel='người', MaxGuests=1, RefundPercent=0, CancelCutoffHours=24)
    response = send(admin, '/api/admin/travel/packages', data)
    assert response.status_code == 201, response.get_json()
    package_id = response.get_json()['package']['PackageID']
    assert query('SELECT LEN(Description) N FROM dbo.TravelPackages WHERE PackageID=?', (package_id,), one=True)['N'] == 1000
    assert send(admin, '/api/admin/travel/packages', {**data, 'Description': 'M' * 1001}).status_code == 400


def test_coupon_code_limit_matches_sql_and_customer_selection(app, users, travel_item):
    admin = sign_in(app, users[2])
    code = 'A' + uuid.uuid4().hex[:29]
    now = datetime.now(timezone.utc)
    data = dict(Code=code, Title='Ưu đãi kiểm tra độ dài', Kind='FIXED', Amount=1000, MaxDiscount=1000,
                MinSubtotal=0, UsageLimit=100, PerUserLimit=2, ValidFrom=(now - timedelta(days=1)).isoformat(),
                ValidUntil=(now + timedelta(days=90)).isoformat())
    response = send(admin, '/api/admin/travel/coupons', data)
    assert response.status_code == 201, response.get_json()
    assert query('SELECT Code FROM dbo.TravelCoupons WHERE Code=?', (code.upper(),), one=True)['Code'] == code.upper()
    assert send(admin, '/api/admin/travel/coupons', {**data, 'Code': code + 'X'}).status_code == 400
    customer = sign_in(app, users[0])
    accepted = send(customer, '/api/travel/quotes', selection(travel_item, VoucherCode=code))
    assert accepted.status_code == 200, accepted.get_json()
    rejected = send(customer, '/api/travel/quotes', selection(travel_item, VoucherCode=code + 'X'))
    assert rejected.status_code == 400
