"""Actual migration checks run only against the explicitly isolated test database."""
import hashlib
import json
from pathlib import Path
import os
import pyodbc
import pytest
from app.config import connection_string
from scripts.migrate import apply, batches, digest, migration_files


def test_migration_batch_parser():
    assert batches('SELECT 1;\nGO\nSELECT 2;\nGO -- end') == ['SELECT 1;', 'SELECT 2;']
    with pytest.raises(ValueError):
        batches('SELECT 1;\nGO 3')


def test_migration_checksum_line_endings(tmp_path):
    a, b = tmp_path/'001_a.sql', tmp_path/'001_b.sql'
    a.write_bytes(b'SELECT 1;\nGO\n')
    b.write_bytes(b'SELECT 1;\r\nGO\r\n')
    assert digest(a) == digest(b)


def snapshot(conn, columns=None):
    if columns is None:
        names=[r[0] for r in conn.execute("SELECT name FROM sys.tables WHERE schema_id=SCHEMA_ID('dbo') AND name NOT IN ('SchemaMigrations','BookingSegments') ORDER BY name")]
        columns={n:[r[0] for r in conn.execute('SELECT name FROM sys.columns WHERE object_id=OBJECT_ID(?) ORDER BY column_id', 'dbo.'+n)] for n in names}
    result={}
    for name,fields in columns.items():
        rows=[list(row) for row in conn.execute('SELECT '+','.join('['+x+']' for x in fields)+' FROM dbo.['+name+'] ORDER BY 1')]
        result[name]={'count':len(rows),'sha256':hashlib.sha256(json.dumps(rows,default=str,ensure_ascii=False).encode()).hexdigest()}
    return columns,result


@pytest.fixture(scope='module')
def migrated():
    if os.getenv('RUN_SQL_TESTS')!='1':
        pytest.skip('Real SQL Server integration not enabled.')
    assert os.getenv('SQL_DATABASE','').startswith('AeroFlow_Test_')
    conn=pyodbc.connect(connection_string(),autocommit=True)
    conn.timeout=120
    cols,before=snapshot(conn)
    applied=apply(conn,migration_files(),test_database=True)
    _,after=snapshot(conn,cols)
    assert before==after
    assert conn.execute('SELECT COUNT(*) FROM dbo.Bookings b WHERE NOT EXISTS(SELECT 1 FROM dbo.BookingSegments s WHERE s.BookingID=b.BookingID AND s.SegmentOrder=1 AND s.FlightID=b.FlightID)').fetchone()[0]==0
    evidence={'database':os.environ['SQL_DATABASE'],'applied':applied,'legacy_rows_unchanged':True,'before':before,'after':after}
    (Path(__file__).resolve().parents[1]/'evidence/marketplace-migration-preservation.json').write_text(json.dumps(evidence,indent=2),encoding='utf-8')
    yield conn
    conn.close()


def test_migration_preserves_original_data(migrated):
    assert migrated.execute('SELECT COUNT(*) FROM dbo.BookingSegments').fetchone()[0]>0


def test_migration_rerun_is_noop(migrated):
    count=migrated.execute('SELECT COUNT(*) FROM dbo.BookingSegments').fetchone()[0]
    assert apply(migrated,migration_files(),test_database=True)==[]
    assert migrated.execute('SELECT COUNT(*) FROM dbo.BookingSegments').fetchone()[0]==count


def test_migration_checksum_tamper_is_rejected(migrated,tmp_path):
    source=migration_files()[0]
    changed=tmp_path/source.name
    changed.write_text(source.read_text(encoding='utf-8')+'\n-- tampered',encoding='utf-8')
    with pytest.raises(ValueError,match='Applied migration changed'):
        apply(migrated,[changed],test_database=True)


def test_migration_failure_rolls_back_ddl_and_ledger(migrated,tmp_path):
    broken=tmp_path/'999_failure_probe.sql'
    broken.write_text("CREATE TABLE dbo.UltimateMigrationProbe(ID int PRIMARY KEY);\nGO\nTHROW 51999,'Injected migration failure',1;",encoding='utf-8')
    with pytest.raises(pyodbc.Error):
        apply(migrated,migration_files()+[broken],test_database=True)
    assert migrated.execute("SELECT OBJECT_ID('dbo.UltimateMigrationProbe')").fetchone()[0] is None
    assert migrated.execute('SELECT COUNT(*) FROM dbo.SchemaMigrations WHERE Version=999').fetchone()[0]==0
