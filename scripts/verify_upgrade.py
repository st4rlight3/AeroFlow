"""Create uniquely named disposable test databases; never drop or overwrite a database."""
import argparse,hashlib,json,os,re,sys,uuid
from pathlib import Path,PureWindowsPath
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pyodbc
from app.config import connection_string
from scripts import init_db
from scripts.migrate import apply,migration_files,drain

def snapshot(conn,columns=None):
    if columns is None:
        names=[r[0] for r in conn.execute("SELECT name FROM sys.tables WHERE schema_id=SCHEMA_ID('dbo') ORDER BY name")]
        columns={n:[r[0] for r in conn.execute('SELECT name FROM sys.columns WHERE object_id=OBJECT_ID(?) ORDER BY column_id','dbo.'+n)] for n in names}
    result={}
    for table,fields in columns.items():
        rows=[list(r) for r in conn.execute('SELECT '+','.join('['+f+']' for f in fields)+' FROM dbo.['+table+']')]
        serialized=sorted(json.dumps(r,default=str,ensure_ascii=False) for r in rows)
        result[table]=dict(count=len(rows),sha256=hashlib.sha256('\n'.join(serialized).encode()).hexdigest())
    return columns,result


def create_legacy_database(name):
    """Install the frozen old SQL baseline only into a new disposable database.

    This fixture is for upgrade verification. Normal installations use sql/.
    """
    if not re.fullmatch(r'AeroFlow_Test_[A-Za-z0-9_]+',name):
        raise ValueError('Legacy fixtures only permit a new AeroFlow_Test_* database.')
    fixture=Path(__file__).resolve().parents[1]/'tests/fixtures/legacy_sql'
    with pyodbc.connect(connection_string('master'),autocommit=True) as conn:
        conn.timeout=180
        if conn.execute('SELECT DB_ID(?)',name).fetchone()[0] is not None:
            raise ValueError('Legacy fixture target already exists; no overwrite performed.')
        for filename in init_db.ORDER:
            init_db.run_file(conn,fixture,filename,name)

def verify():
    original=os.environ.get('SQL_DATABASE');suffix=uuid.uuid4().hex[:10];name='AeroFlow_Test_Fresh_'+suffix;restored='AeroFlow_Test_Restore_'+suffix
    try:
        os.environ['SQL_DATABASE']=name
        with pyodbc.connect(connection_string('master'),autocommit=True) as master:
            assert master.execute('SELECT DB_ID(?)',name).fetchone()[0] is None
            backup_dir=master.execute("SELECT CONVERT(nvarchar(500),SERVERPROPERTY('InstanceDefaultBackupPath'))").fetchone()[0]
        create_legacy_database(name)
        with pyodbc.connect(connection_string(),autocommit=True) as conn:
            conn.timeout=180
            columns,before=snapshot(conn)
            backup=str(PureWindowsPath(backup_dir)/(name+'_before.bak'))
            applied=apply(conn,migration_files(),backup_file=backup)
            _,after=snapshot(conn,columns)
            assert before==after,'Original columns changed during upgrade'
            assert apply(conn,migration_files(),test_database=True)==[]
            cursor=conn.execute('DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS');violations=[]
            while True:
                if cursor.description: violations.extend(cursor.fetchall())
                if not cursor.nextset(): break
            assert not violations
        # Restore the pre-upgrade backup into a fresh database using unique physical paths.
        with pyodbc.connect(connection_string('master'),autocommit=True) as master:
            master.timeout=180
            assert master.execute('SELECT DB_ID(?)',restored).fetchone()[0] is None
            cursor=master.execute('RESTORE FILELISTONLY FROM DISK=?',backup)
            names=[d[0] for d in cursor.description]; files=[dict(zip(names,row)) for row in cursor.fetchall()];drain(cursor)
            moves=[]
            quote=lambda x:"N'"+str(x).replace("'","''")+"'"
            for i,file in enumerate(files):
                folder=PureWindowsPath(file['PhysicalName']).parent
                target=folder/(restored+'_'+str(i)+('.ldf' if file['Type']=='L' else '.mdf'))
                moves.append('MOVE '+quote(file['LogicalName'])+' TO '+quote(target))
            drain(master.execute('RESTORE DATABASE ['+restored+'] FROM DISK='+quote(backup)+' WITH '+','.join(moves)+',RECOVERY'))
        with pyodbc.connect(connection_string(restored),autocommit=True) as check:
            _,recovered=snapshot(check,columns)
            assert recovered==before,'Backup restoration changed original data'
        result=dict(database=name,restored_database=restored,migrations=applied,legacy_rows_unchanged=True,backup_verify='PASS',restore_compare='PASS',constraints='PASS',original_tables=before)
        out=Path(__file__).resolve().parents[1]/'evidence/ultimate-fresh-upgrade-restore.json';out.write_text(json.dumps(result,indent=2),encoding='utf-8')
        print(json.dumps({k:v for k,v in result.items() if k!='original_tables'},indent=2))
    finally:
        if original is None: os.environ.pop('SQL_DATABASE',None)
        else: os.environ['SQL_DATABASE']=original

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run',action='store_true');args=parser.parse_args()
    if not args.run: parser.error('--run creates two isolated test databases and a backup using SQL Server default directories; no data is deleted.')
    verify()
