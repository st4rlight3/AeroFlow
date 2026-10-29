"""Install the complete schema through version 017 into an empty database.

The SQL files already contain the final tables, functions, views, procedures
and triggers. Historical migrations are only needed when upgrading an older
installation. Never replay the fresh-install SQL over an existing database.
"""
import os
from pathlib import Path
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.config import connection_string
import pyodbc

ORDER = ['01_create_database.sql','02_create_tables.sql','03_constraints_indexes.sql',
         '06_functions.sql','05_views.sql','07_stored_procedures.sql','08_triggers.sql','04_seed_data.sql']


def run_file(conn, directory, filename, name):
    sql = (directory / filename).read_text(encoding='utf-8-sig')
    # Only the fixed database token is replaced; user input is validated first.
    sql = re.sub(r'\bAeroFlow\b', name, sql) if filename == '01_create_database.sql' else sql.replace('USE AeroFlow;', f'USE [{name}];')
    for batch in re.split(r'^\s*GO\s*$', sql, flags=re.MULTILINE | re.IGNORECASE):
        if not batch.strip():
            continue
        cursor = conn.cursor().execute(batch)
        while cursor.nextset():
            pass

def main():
    name = os.getenv('SQL_DATABASE', 'AeroFlow')
    if not re.fullmatch(r'AeroFlow(?:_[A-Za-z0-9_]+)?', name):
        raise SystemExit('Use an isolated database named AeroFlow or AeroFlow_<suffix>.')
    directory = Path(__file__).resolve().parents[1] / 'sql'
    with pyodbc.connect(connection_string('master'), autocommit=True, timeout=10) as conn:
        if conn.execute('SELECT DB_ID(?)', name).fetchone()[0] is not None:
            conn.execute(f'USE [{name}]')
            if conn.execute("SELECT COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID('dbo')").fetchone()[0]:
                raise SystemExit('Database already contains tables. Keep its data and use scripts/migrate.py for upgrades, or choose a new SQL_DATABASE.')
            conn.execute('USE master')
        conn.timeout = 180
        run_file(conn, directory, ORDER[0], name)
        # Database creation cannot run inside the schema transaction. If any
        # later script fails, the new database stays empty and can be retried.
        conn.execute(f'USE [{name}]')
        conn.execute('SET XACT_ABORT ON; BEGIN TRANSACTION;')
        try:
            for filename in ORDER[1:]:
                run_file(conn, directory, filename, name)
            conn.execute('COMMIT TRANSACTION;')
        except BaseException:
            conn.execute('IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;')
            raise
        for filename in ORDER:
            print('APPLIED', filename, flush=True)
        count = conn.execute('SELECT COUNT(*) FROM dbo.Flights').fetchone()[0]
        print(f'Database {name} ready through version 017. Flights: {count}. No separate migration run is needed for this fresh install. Seed accounts are disabled.')

if __name__=='__main__':
    main()
