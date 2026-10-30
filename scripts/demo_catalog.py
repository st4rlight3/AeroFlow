"""Deterministic fictional timetables and VND demo fares, not live airline offers.

This module has no database dependency. Keeping the plan independent makes the
preview, scheduling checks and SQL-backed import use exactly the same records.
"""
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from math import asin, ceil, cos, radians, sin, sqrt

VIETNAM = timezone(timedelta(hours=7))
TAX_RATE = Decimal('0.1000')  # Existing teaching model, not an airline tax quote.
DEMO_MODEL = 'AeroFlow demo 150 • 4 khoang'
MAX_DAYS = 90
AIRLINES = ('AF', 'LS', 'BA')
BASES = ('HAN', 'SGN', 'DAD')
AIRPORT_COORDINATES = {
    'HAN': (21.221, 105.807), 'SGN': (10.819, 106.652),
    'DAD': (16.044, 108.199), 'CXR': (11.998, 109.219),
    'PQC': (10.170, 103.993), 'VCA': (10.085, 105.712),
    'HUI': (16.401, 107.703), 'DLI': (11.750, 108.367),
    'HPH': (20.819, 106.725), 'VII': (18.737, 105.671),
}
# Avoid implausibly short HAN–HPH, SGN–VCA and DAD–HUI services. The
# secondary spokes rotate by calendar date, not by the chosen import window.
SPOKES = {
    'HAN': ('SGN', 'DAD', 'CXR', 'PQC', 'VCA', 'HUI', 'DLI', 'VII'),
    'SGN': ('DAD', 'HAN', 'CXR', 'PQC', 'HUI', 'DLI', 'HPH', 'VII'),
    'DAD': ('HAN', 'SGN', 'CXR', 'PQC', 'VCA', 'DLI', 'HPH', 'VII'),
}
CABIN_MULTIPLIER = {
    'ECONOMY': Decimal('1.00'), 'PREMIUM': Decimal('1.40'),
    'BUSINESS': Decimal('2.20'), 'FIRST': Decimal('3.30'),
}
AIRLINE_MULTIPLIER = {'AF': Decimal('1.00'), 'LS': Decimal('1.04'), 'BA': Decimal('0.98')}
BUNDLE_PREMIUM = {'BASIC': Decimal('0'), 'STANDARD': Decimal('180000'), 'FLEXIBLE': Decimal('380000')}
CABINS = (
    ('ECONOMY', 'E', 'Phổ thông'), ('PREMIUM', 'P', 'Phổ thông đặc biệt'),
    ('BUSINESS', 'B', 'Thương gia'), ('FIRST', 'F', 'Hạng nhất'),
)
BUNDLES = (
    ('BASIC', 'B', 'Tiết kiệm', 0, False, 0),
    ('STANDARD', 'S', 'Tiêu chuẩn', 50, True, 20),
    ('FLEXIBLE', 'F', 'Linh hoạt', 90, True, 30),
)


@dataclass(frozen=True)
class PlannedFlight:
    registration: str
    airline: str
    number: str
    origin: str
    destination: str
    departure: datetime  # Naive UTC, matching SQL Server DATETIME2 convention.
    arrival: datetime

    @property
    def local_date(self):
        return self.departure.replace(tzinfo=timezone.utc).astimezone(VIETNAM).date()


def local_today():
    return datetime.now(VIETNAM).date()


def distance_km(origin, destination):
    a, b = AIRPORT_COORDINATES[origin], AIRPORT_COORDINATES[destination]
    lat1, lat2 = radians(a[0]), radians(b[0])
    dlat, dlon = lat2 - lat1, radians(b[1] - a[1])
    return round(6371 * 2 * asin(sqrt(sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2)))


def block_minutes(origin, destination):
    # Rounded block time includes taxi/climb, at an approximate 720 km/h cruise.
    return max(55, int(ceil((30 + distance_km(origin, destination) / 12) / 5) * 5))


def build_plan(days=30, start_date=None):
    """Return 36 legs/day, continuous aircraft rotations and 60-minute turns.

    Explicit dates may be historical for reproducible offline tests; the SQL
    importer separately rejects past departures. No old flight is rescheduled.
    """
    if not isinstance(days, int) or isinstance(days, bool) or not 1 <= days <= MAX_DAYS:
        raise ValueError(f'--days must be between 1 and {MAX_DAYS}.')
    if start_date is None:
        start_date = local_today() + timedelta(days=1)
    if isinstance(start_date, str):
        start_date = date.fromisoformat(start_date)
    if not isinstance(start_date, date) or isinstance(start_date, datetime):
        raise ValueError('--start-date must be an ISO date (YYYY-MM-DD).')
    flights = []
    for offset in range(days):
        day = start_date + timedelta(days=offset)
        for ai, airline in enumerate(AIRLINES):
            for bi, base in enumerate(BASES):
                spokes = SPOKES[base]
                second = spokes[1 + (day.toordinal() + ai * 2 + bi) % (len(spokes) - 1)]
                itinerary = (base, spokes[0], base, second, base)
                local = datetime.combine(day, time(6, 0), VIETNAM) + timedelta(minutes=ai * 20 + bi * 10)
                for leg, (origin, destination) in enumerate(zip(itinerary, itinerary[1:]), 1):
                    departure = local.astimezone(timezone.utc).replace(tzinfo=None)
                    arrival = departure + timedelta(minutes=block_minutes(origin, destination))
                    flights.append(PlannedFlight(
                        f'DEMO-{airline}-{base}', airline, f'DX{airline}{"HSD"[bi]}{leg}',
                        origin, destination, departure, arrival,
                    ))
                    local = (arrival.replace(tzinfo=timezone.utc).astimezone(VIETNAM)
                             + timedelta(minutes=60))
    return flights


def _target_total(origin, destination, airline, day, cabin, bundle):
    distance = distance_km(origin, destination)
    route_floor = Decimal('900000') + Decimal(distance) * Decimal('750')
    if {origin, destination} == {'HAN', 'SGN'}:
        route_floor = max(route_floor, Decimal('1850000'))
    # A modest repeatable spread avoids every date/airline showing one price.
    weekday = Decimal('1.08') if day.weekday() in (4, 5, 6) else Decimal('1.00')
    date_spread = Decimal('1') + Decimal(day.toordinal() % 4) * Decimal('0.015')
    fare = (route_floor * AIRLINE_MULTIPLIER.get(airline, Decimal('1.00'))
            * weekday * date_spread * CABIN_MULTIPLIER[cabin]
            + BUNDLE_PREMIUM[bundle] * CABIN_MULTIPLIER[cabin])
    return (fare / Decimal('10000')).quantize(Decimal('1'), rounding=ROUND_HALF_UP) * Decimal('10000')


def fare_base(origin, destination, airline, day, cabin='ECONOMY', bundle='BASIC'):
    # An integral 1,000 VND base keeps SQL's 10% tax arithmetic exact to the
    # dong, so preview, search and ticket calculations cannot differ by a cent.
    target = _target_total(origin, destination, airline, day, cabin, bundle)
    return (target / (Decimal('1') + TAX_RATE) / Decimal('1000')).quantize(
        Decimal('1'), rounding=ROUND_HALF_UP) * Decimal('1000.00')


def adult_total(origin, destination, airline, day, cabin='ECONOMY', bundle='BASIC'):
    """Adult ticket total in VND, excluding optional seat and service purchases.

    These deterministic fares are deliberately ordinary demo prices. They are
    not scraped inventory or a claim that a real airline sells at this price.
    """
    return (fare_base(origin, destination, airline, day, cabin, bundle)
            * (Decimal('1') + TAX_RATE)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)


def seat_plan():
    """150 seats: 2–2 first/business, 3–3 premium/economy in the demo layout."""
    for row in range(1, 27):
        cabin = 'FIRST' if row == 1 else 'BUSINESS' if row <= 3 else 'PREMIUM' if row <= 6 else 'ECONOMY'
        columns = 'ABEF' if cabin in ('FIRST', 'BUSINESS') else 'ABCDEF'
        for col in columns:
            yield (f'{col}{row}', row, col, cabin,
                   Decimal('80000') if row == 7 else Decimal('0'), row == 7)


def preview(days=30, start_date=None):
    plan = build_plan(days, start_date)
    prices = [adult_total(f.origin, f.destination, f.airline, f.local_date) for f in plan]
    route_prices = [adult_total(f.origin, f.destination, f.airline, f.local_date)
                    for f in plan if {f.origin, f.destination} == {'HAN', 'SGN'}]
    return {
        'mode': 'PREVIEW_ONLY', 'days': days, 'planned_flights': len(plan),
        'planned_aircraft': len({f.registration for f in plan}),
        'airport_codes': sorted({x for f in plan for x in (f.origin, f.destination)}),
        'airline_codes': list(AIRLINES), 'fare_classes_per_flight': 12,
        'planned_fare_rows': len(plan) * 12, 'seats_per_aircraft': len(list(seat_plan())),
        'local_first_date': min(f.local_date for f in plan).isoformat(),
        'local_last_date': max(f.local_date for f in plan).isoformat(),
        'economy_basic_total_vnd': {'min': str(min(prices)), 'max': str(max(prices))},
        'han_sgn_economy_basic_total_vnd': {'min': str(min(route_prices)), 'max': str(max(route_prices))},
        'minimum_turnaround_minutes': 60,
        'note': 'Fictional AeroFlow training timetable and reference-based demo fares; not live airline offers.',
    }
