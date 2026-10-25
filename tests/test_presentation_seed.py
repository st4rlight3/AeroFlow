"""Check the November presentation preset without touching a SQL database."""

from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
import json
import sys

import pytest

from scripts import demo_catalog, seed_ultimate


@pytest.mark.parametrize(('today', 'start', 'days'), [
    (date(2026, 11, 1), date(2026, 12, 1), 62),
    (date(2026, 11, 30), date(2026, 12, 1), 62),
    (date(2026, 12, 15), date(2026, 12, 16), 47),
    (date(2027, 1, 30), date(2027, 1, 31), 1),
    (date(2027, 1, 31), date(2027, 2, 1), 30),
    (date(2027, 2, 3), date(2027, 2, 4), 30),
])
def test_presentation_window_remains_future_during_november_and_afterward(monkeypatch, today, start, days):
    monkeypatch.setattr(seed_ultimate, 'local_today', lambda: today)
    assert seed_ultimate.resolve_window() == (days, start)


@pytest.mark.parametrize(('days', 'start', 'expected'), [
    (7, None, (7, date(2026, 12, 1))),
    (None, date(2026, 12, 10), (30, date(2026, 12, 10))),
    (None, '2027-01-10', (30, date(2027, 1, 10))),
    (None, '2026-11-01', (30, date(2026, 11, 1))),
    (10, '2027-01-10', (10, date(2027, 1, 10))),
    (None, date(2027, 2, 1), (30, date(2027, 2, 1))),
    (90, date(2026, 12, 1), (90, date(2026, 12, 1))),
])
def test_explicit_window_options_are_respected(monkeypatch, days, start, expected):
    monkeypatch.setattr(seed_ultimate, 'local_today', lambda: date(2026, 11, 10))
    assert seed_ultimate.resolve_window(days, start) == expected


@pytest.mark.parametrize('days', [0, -1, 91, 1.5, '62', True, False])
def test_bad_day_count_cannot_silently_select_default_preset(monkeypatch, days):
    monkeypatch.setattr(seed_ultimate, 'local_today', lambda: date(2026, 11, 10))
    with pytest.raises(ValueError):
        seed_ultimate.resolve_window(days=days)


@pytest.mark.parametrize('start', ['', 'not-a-date', '2026-02-30', '2026-12-01T06:00:00',
                                  datetime(2026, 12, 1), 0, True, False])
def test_bad_start_date_cannot_silently_select_default_preset(monkeypatch, start):
    monkeypatch.setattr(seed_ultimate, 'local_today', lambda: date(2026, 11, 10))
    with pytest.raises(ValueError):
        seed_ultimate.resolve_window(start_date=start)


def test_entire_presentation_timetable_covers_two_months_with_continuous_rotations(monkeypatch):
    monkeypatch.setattr(seed_ultimate, 'local_today', lambda: date(2026, 11, 30))
    days, start = seed_ultimate.resolve_window()
    plan = demo_catalog.build_plan(days, start)
    assert len(plan) == 2232
    assert len({(flight.number, flight.departure) for flight in plan}) == 2232
    assert {flight.airline for flight in plan} == {'AF', 'LS', 'BA'}
    assert {code for flight in plan for code in (flight.origin, flight.destination)} == set(demo_catalog.AIRPORT_COORDINATES)
    assert min(flight.local_date for flight in plan) == date(2026, 12, 1)
    assert max(flight.local_date for flight in plan) == date(2027, 1, 31)
    # The first morning departures occur on the preceding UTC date in SQL.
    assert min(flight.departure for flight in plan).date() == date(2026, 11, 30)

    aircraft = defaultdict(list)
    per_day = defaultdict(list)
    for flight in plan:
        aircraft[flight.registration].append(flight)
        per_day[flight.local_date].append(flight)
        assert flight.arrival > flight.departure
        assert flight.arrival.replace(tzinfo=timezone.utc).astimezone(demo_catalog.VIETNAM).date() == flight.local_date
    assert len(aircraft) == 9
    assert len(per_day) == 62
    assert all(len(flights) == 36 for flights in per_day.values())
    for registration, flights in aircraft.items():
        flights.sort(key=lambda flight: flight.departure)
        assert len(flights) == 248
        for earlier, later in zip(flights, flights[1:]):
            assert earlier.destination == later.origin
            assert later.departure - earlier.arrival >= timedelta(minutes=60)
        base = registration.rsplit('-', 1)[1]
        for offset in range(0, len(flights), 4):
            rotation = flights[offset:offset + 4]
            assert rotation[0].origin == base
            assert rotation[-1].destination == base

    summary = demo_catalog.preview(days, start)
    assert summary['planned_flights'] == 2232
    assert summary['planned_fare_rows'] == 26784
    assert summary['local_first_date'] == '2026-12-01'
    assert summary['local_last_date'] == '2027-01-31'


def test_generic_planner_keeps_rolling_compatibility(monkeypatch):
    monkeypatch.setattr(demo_catalog, 'local_today', lambda: date(2026, 11, 10))
    plan = demo_catalog.build_plan()
    assert len(plan) == 1080
    assert min(flight.local_date for flight in plan) == date(2026, 11, 11)
    assert max(flight.local_date for flight in plan) == date(2026, 12, 10)


@pytest.mark.parametrize(('options', 'expected'), [
    ([], (62, date(2026, 12, 1))),
    (['--days', '7'], (7, date(2026, 12, 1))),
    (['--start-date', '2027-01-20'], (30, date(2027, 1, 20))),
    (['--start-date', '2027-01-20', '--days', '5'], (5, date(2027, 1, 20))),
])
def test_preview_cli_uses_same_resolved_window_without_database_access(monkeypatch, capsys, options, expected):
    monkeypatch.setattr(seed_ultimate, 'local_today', lambda: date(2026, 11, 10))
    monkeypatch.setattr(sys, 'argv', ['seed_ultimate.py', '--preview', *options])
    calls = []

    def capture_preview(days, start_date):
        calls.append((days, start_date))
        return {'mode': 'PREVIEW_ONLY', 'planned_flights': days * 36}

    def forbid_apply(*args, **kwargs):
        pytest.fail('Preview must not invoke the SQL importer.')

    monkeypatch.setattr(seed_ultimate, 'preview', capture_preview)
    monkeypatch.setattr(seed_ultimate, 'seed_demo', forbid_apply)
    seed_ultimate.main()
    assert calls == [expected]
    assert json.loads(capsys.readouterr().out)['planned_flights'] == expected[0] * 36


def test_importer_default_resolves_presentation_window_before_opening_sql(monkeypatch):
    monkeypatch.setattr(seed_ultimate, 'local_today', lambda: date(2026, 11, 10))
    calls = []

    class PlanCaptured(Exception):
        pass

    def capture_plan(days, start_date):
        calls.append((days, start_date))
        raise PlanCaptured

    monkeypatch.setattr(seed_ultimate, 'build_plan', capture_plan)
    with pytest.raises(PlanCaptured):
        seed_ultimate.seed_demo()
    assert calls == [(62, date(2026, 12, 1))]
