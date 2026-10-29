"""Fresh consolidated SQL and historical upgrades must lead to the same schema."""
import os
from pathlib import Path
import re
import uuid

import pyodbc
import pytest

from app.config import connection_string
from scripts import init_db
from scripts.migrate import digest, migration_files
from scripts.verify_sql_baseline import verify

ROOT=Path(__file__).resolve().parents[1]


def test_baseline_records_every_unchanged_historical_version():
    sql=(ROOT/'sql/04_seed_data.sql').read_text(encoding='utf-8')
    records=re.findall(r"\((\d+),N'BASELINE: ([^']+)','([0-9a-f]{64})'\)",sql)
    expected=[(str(int(p.name.split('_')[0])),p.name,digest(p)) for p in migration_files()]
    assert records==expected
    assert len(records)==17


def test_baseline_contains_final_direct_sql_definitions():
    modules='\n'.join((ROOT/'sql'/name).read_text(encoding='utf-8') for name in
                      ('05_views.sql','06_functions.sql','07_stored_procedures.sql','08_triggers.sql'))
    definitions=re.findall(r'CREATE OR ALTER (?:PROCEDURE|FUNCTION|VIEW|TRIGGER) dbo\.(\w+)',modules,re.I)
    assert len(definitions)==len(set(definitions))==40
    assert 'OBJECT_DEFINITION(' not in modules
    assert 'dbo.fn_FlightLocalDate(FlightID)' in modules
    assert '@ExpectedAmount decimal(14,2)' in modules
    assert '@PreviousAircraftID' in modules
    assert 'UX_Assignments_ActiveSeat' in (ROOT/'sql/03_constraints_indexes.sql').read_text(encoding='utf-8')


@pytest.mark.integration
def test_fresh_schema_equals_real_legacy_upgrade(sql_ready):
    result=verify()
    assert result['legacy_migrations_applied']==17
    assert result['legacy_rows_preserved']
    assert result['schema_equivalent']
    assert result['fresh_migration_replay']=='NO_OP'
    assert result['existing_database_guard']=='PASS'


@pytest.mark.integration
def test_failed_fresh_install_rolls_back_schema_and_can_retry(sql_ready,monkeypatch):
    name='AeroFlow_Test_InitRollback_'+uuid.uuid4().hex[:10]
    monkeypatch.setenv('SQL_DATABASE',name)
    actual=init_db.run_file
    def fail_after_constraints(conn,directory,filename,database):
        actual(conn,directory,filename,database)
        if filename=='03_constraints_indexes.sql':
            raise RuntimeError('Injected install failure')
    monkeypatch.setattr(init_db,'run_file',fail_after_constraints)
    with pytest.raises(RuntimeError,match='Injected install failure'):
        init_db.main()
    with pyodbc.connect(connection_string(name),autocommit=True) as conn:
        assert conn.execute("SELECT COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID('dbo')").fetchone()[0]==0
    monkeypatch.setattr(init_db,'run_file',actual)
    init_db.main()
    with pyodbc.connect(connection_string(name),autocommit=True) as conn:
        assert conn.execute('SELECT COUNT(*) FROM dbo.SchemaMigrations').fetchone()[0]==17
        assert conn.execute('SELECT COUNT(*) FROM dbo.Flights').fetchone()[0]==120
