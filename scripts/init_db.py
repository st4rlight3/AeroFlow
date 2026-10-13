"""Non-destructive SQL batch runner. A fresh database uses the exact ordered scripts."""
import os
from pathlib import Path
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.config import connection_string
import pyodbc

ORDER = ['01_create_database.sql','02_create_tables.sql','03_constraints_indexes.sql',
         '05_views.sql','06_functions.sql','07_stored_procedures.sql','08_triggers.sql','04_seed_data.sql']

def main():
    name = os.getenv('SQL_DATABASE', 'AeroFlow')
    if not re.fullmatch(r'AeroFlow(?:_[A-Za-z0-9_]+)?', name):
        raise SystemExit('Use an isolated database named AeroFlow or AeroFlow_<suffix>.')
    root = Path(__file__).resolve().parents[1]
    with pyodbc.connect(connection_string('master'), autocommit=True, timeout=10) as conn:
        if conn.execute('SELECT DB_ID(?)', name).fetchone()[0] is not None:
            conn.execute(f'USE [{name}]')
            if conn.execute("SELECT OBJECT_ID('dbo.SchemaMigrations')").fetchone()[0] is not None:
                if conn.execute('SELECT COUNT(*) FROM dbo.SchemaMigrations').fetchone()[0]:
                    raise SystemExit('Database has Ultimate migrations. Use scripts/migrate.py; do not replay baseline SQL objects.')
            conn.execute('USE master')
        for filename in ORDER:
            sql = (root/'sql'/filename).read_text(encoding='utf-8')
            # Only the fixed database-name token is substituted, never arbitrary user SQL.
            sql = re.sub(r'\bAeroFlow\b', name, sql) if filename=='01_create_database.sql' else sql.replace('USE AeroFlow;', f'USE [{name}];')
            for batch in re.split(r'^\s*GO\s*$', sql, flags=re.MULTILINE|re.IGNORECASE):
                if not batch.strip():
                    continue
                c = conn.cursor().execute(batch)
                while c.nextset():
                    pass
            print('APPLIED', filename, flush=True)
        count = conn.execute('SELECT COUNT(*) FROM dbo.Flights').fetchone()[0]
        print(f'Database {name} ready. Flights: {count}. Seed accounts are disabled.')

if __name__=='__main__':
    main()
