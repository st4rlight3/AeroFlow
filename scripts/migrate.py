"""Versioned SQL Server migrations with checksums, backup verification and rollback."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from app.config import connection_string
import pyodbc


def migration_files(directory=None):
    paths = sorted((directory or ROOT / 'sql' / 'migrations').glob('[0-9][0-9][0-9]_*.sql'))
    versions = [int(p.name.split('_')[0]) for p in paths]
    if len(versions) != len(set(versions)):
        raise ValueError('Duplicate migration version.')
    return paths


def batches(sql):
    # Migration source is trusted, versioned project code. GO count is deliberately unsupported.
    if re.search(r'^\s*GO\s+\d+', sql, re.I | re.M):
        raise ValueError('GO repetition is not supported.')
    return [x.strip() for x in re.split(r'^\s*GO\s*(?:--[^\n]*)?$', sql, flags=re.I | re.M) if x.strip()]


def digest(path):
    # Normalize line endings so Windows Git checkout does not invalidate a migration.
    return hashlib.sha256(path.read_text(encoding='utf-8-sig').replace('\r\n', '\n').encode('utf-8')).hexdigest()


def drain(cursor):
    while cursor.nextset():
        pass


def apply(conn, files, backup_file=None, test_database=False):
    name = conn.execute('SELECT DB_NAME()').fetchone()[0]
    if not re.fullmatch(r'AeroFlow(?:_[A-Za-z0-9_]+)?', name):
        raise ValueError('Expected an AeroFlow database name.')
    if test_database and not name.startswith('AeroFlow_Test_'):
        raise ValueError('--test-database only permits AeroFlow_Test_* databases.')
    if not test_database and not backup_file:
        raise ValueError('Provide --backup-file with an unused absolute path readable by SQL Server.')
    result = conn.execute("DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource=N'AeroFlow:migrations',@LockMode='Exclusive',@LockOwner='Session',@LockTimeout=10000; SELECT @r;").fetchone()[0]
    if result < 0:
        raise RuntimeError('Another migration is running.')
    try:
        exists = conn.execute("SELECT OBJECT_ID('dbo.SchemaMigrations')").fetchone()[0]
        applied = dict(conn.execute('SELECT Version,Checksum FROM dbo.SchemaMigrations').fetchall()) if exists else {}
        for file in files:
            version = int(file.name.split('_')[0])
            if version in applied and applied[version] != digest(file):
                raise ValueError(f'Applied migration changed: {file.name}. Restore the original migration.')
        if any(v not in {int(p.name.split('_')[0]) for p in files} for v in applied):
            raise ValueError('Database contains a migration absent from this checkout.')
        pending = [p for p in files if int(p.name.split('_')[0]) not in applied]
        if not pending:
            return []
        if backup_file:
            path = Path(backup_file)
            if not path.is_absolute() or path.exists():
                raise ValueError('Backup must use a new absolute file path; existing files are never overwritten.')
            server_exists=conn.execute('SELECT file_exists,file_is_a_directory FROM sys.dm_os_file_exists(?)',str(path)).fetchone()
            if server_exists and (server_exists[0] or server_exists[1]):
                raise ValueError('Backup path already exists on the SQL Server host; use a new filename.')
            drain(conn.execute(f'BACKUP DATABASE [{name}] TO DISK=? WITH COPY_ONLY,CHECKSUM,NOINIT', str(path)))
            drain(conn.execute('RESTORE VERIFYONLY FROM DISK=? WITH CHECKSUM', str(path)))
        if not exists:
            conn.execute('CREATE TABLE dbo.SchemaMigrations(Version int CONSTRAINT PK_SchemaMigrations PRIMARY KEY,Name nvarchar(200) NOT NULL,Checksum char(64) NOT NULL,AppliedAt datetime2(0) NOT NULL CONSTRAINT DF_Migrations_Time DEFAULT SYSUTCDATETIME())')
        completed = []
        for file in pending:
            version = int(file.name.split('_')[0])
            try:
                conn.execute('SET XACT_ABORT ON; SET NOCOUNT ON; BEGIN TRANSACTION;')
                for batch in batches(file.read_text(encoding='utf-8-sig')):
                    drain(conn.execute(batch))
                conn.execute('INSERT dbo.SchemaMigrations(Version,Name,Checksum) VALUES(?,?,?)', version, file.name, digest(file))
                conn.execute('COMMIT TRANSACTION;')
            except Exception:
                conn.execute('IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;')
                raise
            completed.append(file.name)
        return completed
    finally:
        conn.execute("EXEC sys.sp_releaseapplock @Resource=N'AeroFlow:migrations',@LockOwner='Session'")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--backup-file')
    parser.add_argument('--test-database', action='store_true')
    args = parser.parse_args()
    with pyodbc.connect(connection_string(), autocommit=True, timeout=10) as conn:
        conn.timeout = 120
        files = migration_files()
        if args.apply:
            for name in apply(conn, files, args.backup_file, args.test_database):
                print('APPLIED', name, flush=True)
        else:
            exists = conn.execute("SELECT OBJECT_ID('dbo.SchemaMigrations')").fetchone()[0]
            applied = {r[0]:(r[1],r[2]) for r in conn.execute('SELECT Version,Checksum,Name FROM dbo.SchemaMigrations').fetchall()} if exists else {}
            for file in files:
                value = applied.get(int(file.name.split('_')[0]))
                status = 'PENDING' if value is None else 'CHECKSUM_MISMATCH' if value[0] != digest(file) else 'IN_BASELINE' if value[1].startswith('BASELINE: ') else 'APPLIED'
                print(status, file.name)


if __name__ == '__main__':
    main()
