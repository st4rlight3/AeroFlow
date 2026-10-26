"""Verify a named TEST database, copy-only backup and full restore into a new database.

Never drops databases, overwrites backups, changes application rows or restores over
an existing database. Backup files stay in SQL Server's configured backup folder.
"""
import argparse,hashlib,json,os,re,sys,uuid
from datetime import datetime,timezone
from pathlib import Path,PureWindowsPath
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
import pyodbc
from app.config import connection_string
from scripts.migrate import apply,migration_files,drain
from scripts.verify_upgrade import snapshot

def verify():
    name=os.getenv('SQL_DATABASE','')
    if not re.fullmatch(r'AeroFlow_Test_[A-Za-z0-9_]+',name):raise ValueError('SQL_DATABASE must name an isolated AeroFlow_Test_* database.')
    restored='AeroFlow_Test_Marketplace_Restore_'+uuid.uuid4().hex[:10]
    with pyodbc.connect(connection_string(),autocommit=True,timeout=10) as conn:
        conn.timeout=240
        assert apply(conn,migration_files(),test_database=True)==[],'Apply pending migrations before verification.'
        columns,before=snapshot(conn)
        constraints=[];c=conn.execute('DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS')
        while True:
            if c.description:constraints.extend(list(c.fetchall()))
            if not c.nextset():break
        assert not constraints,'Constraint violations found.'
        c=conn.execute('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS');errors=[]
        while True:
            if c.description:errors.extend(list(c.fetchall()))
            if not c.nextset():break
        assert not errors,'CHECKDB reported errors.'
        assert conn.execute('SELECT COUNT(*) FROM dbo.vw_TravelAvailability WHERE AvailableQuantity<0').fetchone()[0]==0
        counts={n:before[n]['count'] for n in before}
        folder=conn.execute("SELECT CONVERT(nvarchar(500),SERVERPROPERTY('InstanceDefaultBackupPath'))").fetchone()[0]
        backup=str(PureWindowsPath(folder)/(restored+'.bak'))
        exists=conn.execute('SELECT file_exists FROM sys.dm_os_file_exists(?)',backup).fetchone()
        assert not exists or not exists[0]
        drain(conn.execute('BACKUP DATABASE ['+name+'] TO DISK=? WITH COPY_ONLY,CHECKSUM,NOINIT',backup))
        drain(conn.execute('RESTORE VERIFYONLY FROM DISK=? WITH CHECKSUM',backup))
    quote=lambda s:"N'"+str(s).replace("'","''")+"'"
    with pyodbc.connect(connection_string('master'),autocommit=True,timeout=10) as master:
        master.timeout=240
        assert master.execute('SELECT DB_ID(?)',restored).fetchone()[0] is None
        cursor=master.execute('RESTORE FILELISTONLY FROM DISK=?',backup);fields=[d[0] for d in cursor.description];files=[dict(zip(fields,r)) for r in cursor.fetchall()];drain(cursor)
        moves=[]
        for i,file in enumerate(files):
            target=PureWindowsPath(file['PhysicalName']).parent/(restored+'_'+str(i)+('.ldf' if file['Type']=='L' else '.mdf'))
            moves.append('MOVE '+quote(file['LogicalName'])+' TO '+quote(target))
        drain(master.execute('RESTORE DATABASE ['+restored+'] FROM DISK='+quote(backup)+' WITH '+','.join(moves)+',RECOVERY'))
    with pyodbc.connect(connection_string(restored),autocommit=True,timeout=10) as conn:
        conn.timeout=240
        _,after=snapshot(conn,columns)
        assert before==after,'Full backup restoration changed application rows.'
        assert apply(conn,migration_files(),test_database=True)==[]
        version=conn.execute('SELECT MAX(Version) FROM dbo.SchemaMigrations').fetchone()[0]
        assert version==22
    result=dict(checked_at_utc=datetime.now(timezone.utc).isoformat(),database=name,restored_database=restored,migration_versions=list(range(1,23)),migration_rerun='NO_OP',checkconstraints='PASS',checkdb='PASS',over_capacity_rows=0,backup_verify='PASS',full_restore_all_tables='MATCH',tables=before)
    out=ROOT/'evidence'/'marketplace-database-validation-20261026.json';out.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='tables'},ensure_ascii=False))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--run',action='store_true');args=p.parse_args()
    if not args.run:p.error('--run is required; this creates a backup and a new isolated restore database.')
    verify()
