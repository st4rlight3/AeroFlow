"""Verify fresh consolidated SQL against the original baseline plus migrations.

Creates two uniquely named AeroFlow_Test_* databases and never overwrites or
drops an existing database. --run is required for the command-line entry point.
"""
from pathlib import Path
import argparse, json, os, re, sys, uuid
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pyodbc
from app.config import connection_string
from scripts import init_db
from scripts.migrate import apply, migration_files
from scripts.verify_upgrade import create_legacy_database, snapshot as row_snapshot

QUERIES={
'tables':"SELECT t.name,t.object_id FROM sys.tables t WHERE t.schema_id=SCHEMA_ID('dbo') ORDER BY t.name",
'columns':"SELECT t.name TableName,c.column_id,c.name,ty.name DataType,c.max_length,c.precision,c.scale,c.is_nullable,c.is_identity,c.is_computed,c.collation_name,c.is_rowguidcol,c.is_sparse,CONVERT(nvarchar(80),ic.seed_value) IdentitySeed,CONVERT(nvarchar(80),ic.increment_value) IdentityIncrement,cc.definition ComputedDefinition,cc.is_persisted,dc.name DefaultName,dc.definition DefaultDefinition,dc.is_system_named DefaultSystemNamed FROM sys.tables t JOIN sys.columns c ON c.object_id=t.object_id JOIN sys.types ty ON ty.user_type_id=c.user_type_id LEFT JOIN sys.identity_columns ic ON ic.object_id=c.object_id AND ic.column_id=c.column_id LEFT JOIN sys.computed_columns cc ON cc.object_id=c.object_id AND cc.column_id=c.column_id LEFT JOIN sys.default_constraints dc ON dc.object_id=c.default_object_id WHERE t.schema_id=SCHEMA_ID('dbo') ORDER BY t.name,c.column_id",
'checks':"SELECT OBJECT_NAME(parent_object_id) TableName,name,definition,is_disabled,is_not_trusted,is_not_for_replication,is_system_named FROM sys.check_constraints WHERE schema_id=SCHEMA_ID('dbo') ORDER BY TableName,name",
'keys':"SELECT OBJECT_NAME(k.parent_object_id) TableName,k.name,k.type,k.is_system_named,i.type_desc IndexType,i.is_unique,i.index_id FROM sys.key_constraints k JOIN sys.indexes i ON i.object_id=k.parent_object_id AND i.index_id=k.unique_index_id WHERE k.schema_id=SCHEMA_ID('dbo') ORDER BY TableName,k.name",
'indexes':"SELECT OBJECT_NAME(i.object_id) TableName,i.name,i.type_desc,i.is_unique,i.has_filter,i.filter_definition,i.is_disabled,i.is_primary_key,i.is_unique_constraint,i.index_id FROM sys.indexes i JOIN sys.tables t ON t.object_id=i.object_id WHERE t.schema_id=SCHEMA_ID('dbo') AND i.name IS NOT NULL ORDER BY TableName,i.name",
'index_columns':"SELECT OBJECT_NAME(ic.object_id) TableName,i.name IndexName,c.name,ic.key_ordinal,ic.index_column_id,ic.is_descending_key,ic.is_included_column FROM sys.index_columns ic JOIN sys.indexes i ON i.object_id=ic.object_id AND i.index_id=ic.index_id JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id JOIN sys.tables t ON t.object_id=ic.object_id WHERE t.schema_id=SCHEMA_ID('dbo') ORDER BY TableName,i.name,ic.key_ordinal,ic.index_column_id",
'foreign_keys':"SELECT OBJECT_NAME(parent_object_id) TableName,name,OBJECT_NAME(referenced_object_id) TargetTable,delete_referential_action_desc DeleteAction,update_referential_action_desc UpdateAction,is_disabled,is_not_trusted,is_not_for_replication,is_system_named FROM sys.foreign_keys WHERE schema_id=SCHEMA_ID('dbo') ORDER BY TableName,name",
'fk_columns':"SELECT fk.name,c.name ParentColumn,rc.name TargetColumn,fkc.constraint_column_id FROM sys.foreign_keys fk JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id=fk.object_id JOIN sys.columns c ON c.object_id=fkc.parent_object_id AND c.column_id=fkc.parent_column_id JOIN sys.columns rc ON rc.object_id=fkc.referenced_object_id AND rc.column_id=fkc.referenced_column_id WHERE fk.schema_id=SCHEMA_ID('dbo') ORDER BY fk.name,fkc.constraint_column_id",
'modules':"SELECT o.name,o.type,o.type_desc,m.definition,m.uses_ansi_nulls,m.uses_quoted_identifier,m.is_schema_bound,tr.is_disabled TriggerDisabled,OBJECT_NAME(tr.parent_id) TriggerTable FROM sys.objects o JOIN sys.sql_modules m ON m.object_id=o.object_id LEFT JOIN sys.triggers tr ON tr.object_id=o.object_id WHERE o.schema_id=SCHEMA_ID('dbo') AND o.is_ms_shipped=0 ORDER BY o.type,o.name",
'dependencies':"SELECT OBJECT_NAME(referencing_id) SourceName,referenced_entity_name TargetName FROM sys.sql_expression_dependencies WHERE referencing_id IN(SELECT object_id FROM sys.objects WHERE schema_id=SCHEMA_ID('dbo')) AND referenced_schema_name='dbo'",
}

def norm(s):return re.sub(r'\s+',' ',s or '').strip()

def signature(meta):
    result={}
    result['tables']=sorted(t['name'] for t in meta['tables'])
    result['columns']=sorted(tuple((k,c[k]) for k in ('TableName','column_id','name','DataType','max_length','precision','scale','is_nullable','is_identity','is_computed','collation_name','is_rowguidcol','is_sparse','IdentitySeed','IdentityIncrement','ComputedDefinition','is_persisted','DefaultDefinition')) for c in meta['columns'])
    result['checks']=sorted((c['TableName'],norm(c['definition']),c['is_disabled'],c['is_not_trusted'],c['is_not_for_replication']) for c in meta['checks'])
    result['keys']=[]
    for k in meta['keys']:
        cols=[(c['name'],c['key_ordinal'],c['is_descending_key']) for c in meta['index_columns'] if c['TableName']==k['TableName'] and c['IndexName']==k['name']]
        result['keys'].append((k['TableName'],k['type'],k['IndexType'],tuple(sorted(cols))))
    result['keys'].sort()
    result['indexes']=[]
    for i in meta['indexes']:
        cols=[(c['name'],c['key_ordinal'],c['is_descending_key'],c['is_included_column']) for c in meta['index_columns'] if c['TableName']==i['TableName'] and c['IndexName']==i['name']]
        result['indexes'].append((i['TableName'],i['type_desc'],i['is_unique'],norm(i['filter_definition']),i['is_disabled'],i['is_primary_key'],i['is_unique_constraint'],tuple(sorted(cols))))
    result['indexes'].sort()
    result['foreign_keys']=[]
    for fk in meta['foreign_keys']:
        cols=[(c['ParentColumn'],c['TargetColumn'],c['constraint_column_id']) for c in meta['fk_columns'] if c['name']==fk['name']]
        result['foreign_keys'].append((fk['TableName'],fk['TargetTable'],fk['DeleteAction'],fk['UpdateAction'],fk['is_disabled'],fk['is_not_trusted'],fk['is_not_for_replication'],tuple(sorted(cols))))
    result['foreign_keys'].sort()
    result['modules']=[]
    for m in meta['modules']:
        definition=re.sub(r'^(CREATE\s+OR\s+ALTER|CREATE|ALTER)\s+(?=(?:PROCEDURE|FUNCTION|VIEW|TRIGGER)\b)','',m['definition'].strip(),count=1,flags=re.I|re.M)
        result['modules'].append((m['name'],m['type'],norm(definition),m['uses_ansi_nulls'],m['uses_quoted_identifier'],m['is_schema_bound'],m['TriggerDisabled']))
    result['modules'].sort()
    return result

def schema_snapshot(conn):
    result={}
    for name,sql in QUERIES.items():
        cursor=conn.execute(sql)
        fields=[d[0] for d in cursor.description]
        result[name]=[dict(zip(fields,row)) for row in cursor.fetchall()]
    return result


def verify():
    root=Path(__file__).resolve().parents[1]
    original=os.environ.get('SQL_DATABASE')
    suffix=uuid.uuid4().hex[:10]
    legacy='AeroFlow_Test_Legacy_'+suffix
    fresh='AeroFlow_Test_Consolidated_'+suffix
    try:
        create_legacy_database(legacy)
        with pyodbc.connect(connection_string(legacy),autocommit=True) as conn:
            conn.timeout=180
            columns,before=row_snapshot(conn)
            migrated=apply(conn,migration_files(),test_database=True)
            _,after=row_snapshot(conn,columns)
            if before!=after:raise AssertionError('Existing row values changed during migration.')
            expected=schema_snapshot(conn)
        os.environ['SQL_DATABASE']=fresh
        init_db.main()
        with pyodbc.connect(connection_string(fresh),autocommit=True) as conn:
            conn.timeout=180
            current=schema_snapshot(conn)
            left,right=signature(expected),signature(current)
            differences=[k for k in left if left[k]!=right[k]]
            if differences:raise AssertionError('Schema mismatch: '+', '.join(differences))
            ledger=conn.execute('SELECT COUNT(*) FROM dbo.SchemaMigrations').fetchone()[0]
            if ledger!=17:raise AssertionError('Expected baseline versions 001-017.')
            if apply(conn,migration_files(),test_database=True):raise AssertionError('Fresh baseline replayed migrations.')
            for filename in ('09_business_queries.sql','10_test_cases.sql'):
                init_db.run_file(conn,root/'sql',filename,fresh)
            before_count=conn.execute('SELECT COUNT(*) FROM dbo.Bookings').fetchone()[0]
            init_db.run_file(conn,root/'sql','04_seed_data.sql',fresh)
            if conn.execute('SELECT COUNT(*) FROM dbo.Bookings').fetchone()[0]!=before_count:
                raise AssertionError('Seed rerun duplicated bookings.')
        try:init_db.main()
        except SystemExit as error:
            if 'already contains tables' not in str(error):raise
        else:raise AssertionError('Fresh installer accepted existing tables.')
        result={'legacy_database':legacy,'fresh_database':fresh,'legacy_migrations_applied':len(migrated),
                'legacy_rows_preserved':True,'schema_equivalent':True,'tables':len(current['tables']),
                'columns':len(current['columns']),'sql_modules':len(current['modules']),
                'foreign_keys':len(current['foreign_keys']),'indexes':len(current['indexes']),
                'checks':len(current['checks']),'fresh_migration_replay':'NO_OP',
                'existing_database_guard':'PASS','seed_rerun':'NO_OP',
                'business_queries':'PASS','sql_constraint_tests':'PASS'}
        (root/'evidence').mkdir(exist_ok=True)
        (root/'evidence/consolidated-sql-equivalence.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        return result
    finally:
        if original is None:os.environ.pop('SQL_DATABASE',None)
        else:os.environ['SQL_DATABASE']=original


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run',action='store_true')
    args=parser.parse_args()
    if not args.run:parser.error('--run creates two isolated test databases; existing databases are preserved.')
    print(json.dumps(verify(),indent=2))
