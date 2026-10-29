"""Check the ten-script installer, database readiness and rollback behavior."""
from pathlib import Path
import re
import uuid

import pyodbc
import pytest

from app.config import connection_string
from scripts import init_db
from scripts.database_schema import REQUIRED_COLUMNS, REQUIRED_OBJECTS, require_database

ROOT = Path(__file__).resolve().parents[1]


def test_project_contains_exactly_ten_sql_scripts():
    files = sorted(ROOT.rglob('*.sql'))
    assert len(files) == 10
    assert all(path.parent == ROOT/'sql' for path in files)
    assert sorted(int(path.name.split('_')[0]) for path in files) == list(range(1, 11))


def test_complete_sql_modules_are_declared_once():
    source = '\n'.join((ROOT/'sql'/name).read_text(encoding='utf-8') for name in
                       ('05_views.sql', '06_functions.sql', '07_stored_procedures.sql', '08_triggers.sql'))
    names = re.findall(r'CREATE OR ALTER (?:PROCEDURE|FUNCTION|VIEW|TRIGGER) dbo\.(\w+)', source, re.I)
    assert len(names) == len(set(names)) == 40
    assert 'OBJECT_DEFINITION(' not in source
    assert 'dbo.fn_FlightLocalDate(FlightID)' in source
    assert '@ExpectedAmount decimal(14,2)' in source
    assert '@PreviousAircraftID' in source
    assert 'UX_Assignments_ActiveSeat' in (ROOT/'sql/03_constraints_indexes.sql').read_text(encoding='utf-8')


class CapabilityConnection:
    def __init__(self, missing=None):
        self.columns = [(table, name) for table, names in REQUIRED_COLUMNS.items() for name in names]
        self.objects = list(REQUIRED_OBJECTS.items())
        self.missing = missing

    def execute(self, sql):
        if 'sys.tables' in sql:
            self.rows = [row for row in self.columns if '.'.join(row) != self.missing]
        elif 'sys.objects' in sql:
            self.rows = [row for row in self.objects if row[0] != self.missing]
        else:
            raise AssertionError('Unexpected readiness query: '+sql)
        return self

    def fetchall(self):
        return self.rows


def test_ready_database_is_checked_by_its_capabilities():
    require_database(CapabilityConnection())


@pytest.mark.parametrize('missing', ['Airports.IanaTimeZone', 'sp_CreateItinerary'])
def test_incomplete_database_is_rejected_before_sample_import(missing):
    with pytest.raises(ValueError, match=re.escape(missing)):
        require_database(CapabilityConnection(missing))


@pytest.mark.integration
def test_fresh_install_is_complete_and_does_not_overwrite_data(sql_ready, monkeypatch):
    name = 'AeroFlow_Test_SQLInstall_'+uuid.uuid4().hex[:10]
    monkeypatch.setenv('SQL_DATABASE', name)
    init_db.main()
    with pyodbc.connect(connection_string(name), autocommit=True) as conn:
        require_database(conn)
        assert conn.execute("SELECT COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID('dbo')").fetchone()[0] == 37
        assert conn.execute("SELECT COUNT(*) FROM sys.sql_modules WHERE object_id IN (SELECT object_id FROM sys.objects WHERE schema_id=SCHEMA_ID('dbo'))").fetchone()[0] == 40
        assert conn.execute('SELECT COUNT(*) FROM dbo.Flights').fetchone()[0] == 120
        counts = {table: conn.execute('SELECT COUNT(*) FROM dbo.['+table+']').fetchone()[0]
                  for table in ('Bookings', 'Tickets', 'Payments')}
        init_db.run_file(conn, ROOT/'sql', '04_seed_data.sql', name)
        assert counts == {table: conn.execute('SELECT COUNT(*) FROM dbo.['+table+']').fetchone()[0] for table in counts}
        for filename in ('09_business_queries.sql', '10_test_cases.sql'):
            init_db.run_file(conn, ROOT/'sql', filename, name)
    with pytest.raises(SystemExit, match='already contains tables'):
        init_db.main()
    with pyodbc.connect(connection_string(name), autocommit=True) as conn:
        assert counts == {table: conn.execute('SELECT COUNT(*) FROM dbo.['+table+']').fetchone()[0] for table in counts}


@pytest.mark.integration
def test_failed_install_leaves_empty_database_and_can_retry(sql_ready, monkeypatch):
    name = 'AeroFlow_Test_SQLRetry_'+uuid.uuid4().hex[:10]
    monkeypatch.setenv('SQL_DATABASE', name)
    actual = init_db.run_file

    def fail_after_constraints(conn, directory, filename, database):
        actual(conn, directory, filename, database)
        if filename == '03_constraints_indexes.sql':
            raise RuntimeError('Injected install failure')

    monkeypatch.setattr(init_db, 'run_file', fail_after_constraints)
    with pytest.raises(RuntimeError, match='Injected install failure'):
        init_db.main()
    with pyodbc.connect(connection_string(name), autocommit=True) as conn:
        assert conn.execute("SELECT COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID('dbo')").fetchone()[0] == 0
    monkeypatch.setattr(init_db, 'run_file', actual)
    init_db.main()
    with pyodbc.connect(connection_string(name), autocommit=True) as conn:
        require_database(conn)
        assert conn.execute('SELECT COUNT(*) FROM dbo.Flights').fetchone()[0] == 120
