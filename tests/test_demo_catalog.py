"""Offline checks for the importable timetable, seat map and price catalogue.

These tests do not create database records. SQL import and legacy ticket
preservation are covered separately by the SQL Server verification run.
"""
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal

import pytest

import scripts.demo_catalog as catalog
from scripts.demo_catalog import (
    TAX_RATE,
    VIETNAM,
    adult_total,
    build_plan,
    fare_base,
    preview,
    seat_plan,
)


START = date(2026, 10, 26)
AIRPORTS = {'HAN', 'SGN', 'DAD', 'CXR', 'PQC', 'VCA', 'HUI', 'DLI', 'HPH', 'VII'}
CABINS = ('ECONOMY', 'PREMIUM', 'BUSINESS', 'FIRST')
BUNDLES = ('BASIC', 'STANDARD', 'FLEXIBLE')


def test_default_month_has_hundreds_of_flights_and_national_coverage():
    flights = build_plan(start_date=START)
    assert len(flights) == 1080
    assert {f.airline for f in flights} == {'AF', 'LS', 'BA'}
    assert len({f.registration for f in flights}) == 9
    assert {a for f in flights for a in (f.origin, f.destination)} == AIRPORTS
    daily = defaultdict(list)
    for flight in flights:
        daily[flight.local_date].append(flight)
        assert flight.origin != flight.destination
        assert {flight.origin, flight.destination} not in (
            {'HAN', 'HPH'}, {'SGN', 'VCA'}, {'DAD', 'HUI'},
        )
    assert set(daily) == {START + timedelta(days=n) for n in range(30)}
    assert all(len(flights_on_day) == 36 for flights_on_day in daily.values())


@pytest.mark.parametrize('start', [date(2026, 1, 30), date(2026, 12, 30), date(2028, 2, 28)])
def test_aircraft_rotations_are_flyable_across_calendar_boundaries(start):
    rotations = defaultdict(list)
    for flight in build_plan(5, start):
        rotations[flight.registration].append(flight)
        assert timedelta(minutes=45) <= flight.arrival - flight.departure <= timedelta(hours=3)
        arrival_local = flight.arrival.replace(tzinfo=timezone.utc).astimezone(VIETNAM)
        assert arrival_local.date() == flight.local_date
    for registration, flights in rotations.items():
        flights.sort(key=lambda f: f.departure)
        for earlier, later in zip(flights, flights[1:]):
            assert earlier.destination == later.origin
            assert later.departure - earlier.arrival >= timedelta(minutes=60)
        days = defaultdict(list)
        for flight in flights:
            days[flight.local_date].append(flight)
        base = registration.rsplit('-', 1)[1]
        for daily_rotation in days.values():
            assert len(daily_rotation) == 4
            assert daily_rotation[0].origin == base
            assert daily_rotation[-1].destination == base


def test_reimport_and_overlapping_windows_preserve_flight_identity_and_price():
    whole = build_plan(30, START)
    overlap = build_plan(7, START + timedelta(days=10))
    identity = lambda f: (f.registration, f.number, f.departure)
    whole_by_id = {identity(f): f for f in whole}
    assert len(whole_by_id) == len(whole)
    assert len({(f.number, f.local_date) for f in whole}) == len(whole)
    assert build_plan(30, START.isoformat()) == whole
    for flight in overlap:
        original = whole_by_id[identity(flight)]
        assert original == flight
        for cabin in CABINS:
            for bundle in BUNDLES:
                args = (flight.origin, flight.destination, flight.airline, flight.local_date, cabin, bundle)
                original_args = (original.origin, original.destination, original.airline, original.local_date, cabin, bundle)
                assert fare_base(*args) == fare_base(*original_args)


def test_calendar_dates_use_vietnam_time_even_when_utc_date_is_previous_day():
    flights = build_plan(1, START)
    assert all(f.departure.tzinfo is None and f.arrival.tzinfo is None for f in flights)
    assert all(f.local_date == START for f in flights)
    early = [f for f in flights if f.departure.date() == START - timedelta(days=1)]
    assert early, 'An early morning Vietnam departure must be stored on the preceding UTC date.'
    for flight in flights:
        local_departure = flight.departure.replace(tzinfo=timezone.utc).astimezone(VIETNAM)
        assert local_departure.date() == START
        assert local_departure.utcoffset() == timedelta(hours=7)


def test_default_window_starts_tomorrow_in_vietnam(monkeypatch):
    monkeypatch.setattr(catalog, 'local_today', lambda: date(2026, 12, 31))
    assert {f.local_date for f in build_plan(1)} == {date(2027, 1, 1)}


@pytest.mark.parametrize('airline', ['AF', 'LS', 'BA'])
@pytest.mark.parametrize('day', [date(2026, 10, 26), date(2026, 10, 30), date(2026, 10, 31)])
def test_total_prices_are_decimal_symmetric_and_ordered_by_cabin_and_bundle(airline, day):
    for origin, destination in (('HAN', 'SGN'), ('SGN', 'DAD'), ('HAN', 'PQC')):
        totals = {}
        for cabin in CABINS:
            for bundle in BUNDLES:
                args = (origin, destination, airline, day, cabin, bundle)
                base = fare_base(*args)
                total = adult_total(*args)
                assert isinstance(base, Decimal) and isinstance(total, Decimal)
                assert base > 0 and total > base
                assert total == (base * (Decimal('1') + TAX_RATE)).quantize(Decimal('0.01'))
                assert total == total.quantize(Decimal('0.01'))
                assert total == adult_total(destination, origin, airline, day, cabin, bundle)
                totals[cabin, bundle] = total
        for cabin in CABINS:
            assert [totals[cabin, bundle] for bundle in BUNDLES] == sorted(
                {totals[cabin, bundle] for bundle in BUNDLES}
            )
        for bundle in BUNDLES:
            assert [totals[cabin, bundle] for cabin in CABINS] == sorted(
                {totals[cabin, bundle] for cabin in CABINS}
            )
        assert adult_total('HAN', 'SGN', airline, day) >= Decimal('1600000')
        assert adult_total('SGN', 'DAD', airline, day) < adult_total('HAN', 'SGN', airline, day)


def test_layout_has_150_unique_seats_and_bookable_seats_in_every_cabin():
    seats = list(seat_plan())
    assert len(seats) == 150
    assert len({seat[0] for seat in seats}) == 150
    assert len({(seat[1], seat[2]) for seat in seats}) == 150
    assert {seat[3] for seat in seats} == set(CABINS)
    cabin_positions = defaultdict(list)
    for number, row, column, cabin, fee, is_priority in seats:
        assert number == f'{column}{row}'
        assert row > 0 and column in 'ABCDEF'
        assert isinstance(fee, Decimal) and fee >= 0
        assert isinstance(is_priority, bool)
        cabin_positions[cabin].append(row)
    # Premium cabins belong toward the nose; no mixed cabin can occupy a row.
    for front, rear in zip(reversed(CABINS), list(reversed(CABINS))[1:]):
        assert max(cabin_positions[front]) < min(cabin_positions[rear])
    assert len({row for _, row, _, _, _, is_priority in seats if is_priority}) >= 1


def test_preview_agrees_with_records_that_would_be_imported():
    result = preview(7, START)
    flights = build_plan(7, START)
    totals = [adult_total(f.origin, f.destination, f.airline, f.local_date) for f in flights]
    assert result['mode'] == 'PREVIEW_ONLY'
    assert result['planned_flights'] == len(flights)
    assert result['planned_fare_rows'] == len(flights) * 12
    assert result['planned_aircraft'] == len({f.registration for f in flights})
    assert result['seats_per_aircraft'] == len(list(seat_plan()))
    assert result['local_first_date'] == START.isoformat()
    assert result['local_last_date'] == (START + timedelta(days=6)).isoformat()
    assert Decimal(result['economy_basic_total_vnd']['min']) == min(totals)
    assert Decimal(result['economy_basic_total_vnd']['max']) == max(totals)


@pytest.mark.parametrize('days', [0, -1, 91, 1.5, '30', True, False, None])
def test_invalid_days_are_rejected(days):
    with pytest.raises(ValueError):
        build_plan(days, START)


@pytest.mark.parametrize('days', [1, 90])
def test_supported_window_boundaries(days):
    flights = build_plan(days, START)
    assert len(flights) == days * 36
    assert min(f.local_date for f in flights) == START
    assert max(f.local_date for f in flights) == START + timedelta(days=days - 1)


@pytest.mark.parametrize('start', ['not-a-date', '2026-02-30', '2026-10-26T06:00:00', '', datetime(2026, 10, 26), 0, 42, True, False])
def test_invalid_start_dates_are_rejected(start):
    with pytest.raises(ValueError):
        build_plan(1, start)
