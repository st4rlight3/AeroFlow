"""Package source reproducibly; exclude credentials, environments and Git metadata."""
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT=Path(__file__).resolve().parents[1]
EXCLUDE={'.git','.venv','venv','__pycache__','.pytest_cache','node_modules','.env','Thumbs.db','docs'}

def package(output):
    output=Path(output).resolve(); output.parent.mkdir(parents=True,exist_ok=True)
    files=[]
    for path in sorted(ROOT.rglob('*')):
        rel=path.relative_to(ROOT)
        if not path.is_file() or any(part in EXCLUDE for part in rel.parts) or path.suffix.lower() in ('.pyc','.bak','.log','.zip','.docx','.pptx','.ppt','.odp','.key') or path.name in ('MANIFEST.sha256','SOURCE_MANIFEST.sha256'): continue
        if path.name.startswith('.env') and path.name!='.env.example': continue
        files.append((rel.as_posix(),path.read_bytes()))
    required={'README.md','requirements.txt','.env.example','MIGRATION_GUIDE.md','run.py','app/static/ultimate.js','app/static/customer.js','scripts/migrate.py'}
    required.update({'app/static/app.js','app/static/commerce.js','app/static/manage.js','app/static/ultimate.css','app/templates/index.html','app/routes/itineraries.py','app/routes/customer.py','app/routes/commerce.py','app/routes/operations.py','app/services/exchange.py','app/services/documents.py','scripts/seed_ultimate.py','tests/test_itineraries.py','tests/test_commerce.py','tests/test_exchange_wallet.py','tests/test_customer_operations.py','tests/test_ultimate_operations.py','evidence/ultimate-final-regression.xml','evidence/ultimate-fresh-upgrade-restore.json'})
    required.update({'app/static/frontend.css','app/static/frontend.js','app/static/images/aviation-hero.webp','app/static/images/hanoi.webp','app/static/images/danang.webp','app/static/images/saigon.webp','app/static/images/sky-panorama.svg','scripts/demo_catalog.py','scripts/demo_price_reference.json','tests/test_demo_catalog.py','tests/test_demo_seed_sql.py','tests/test_discovery_pricing.py','sql/demo/verify_demo_catalog.sql','evidence/pricing-regression-20261025.xml','evidence/demo-catalog-validation-20261025.json'})
    required.update({'tests/test_presentation_seed.py','evidence/presentation-regression-20261025.xml','evidence/presentation-validation-20261025.json'})
    required.update({
        'app/services/timezones.py',
        'scripts/international_catalog.py','scripts/seed_international.py','scripts/load_demo.py',
        'scripts/build_destination_art.py','scripts/export_demo_prices.py',
        'sql/migrations/015_airline_consistency.sql','sql/migrations/016_international_airports.sql',
        'sql/migrations/017_vancouver_timezone.sql',
        'sql/demo/verify_international_catalog.sql',
        'tests/test_airline_audit_fixes.py','tests/test_international_catalog.py',
        'data/demo_route_prices.csv','data/demo_flight_prices.csv',
        'evidence/international-full-regression-20261026.xml',
        'evidence/international-final-regression-20261026.xml','evidence/international-final-validation-20261026.json','evidence/international-fresh-upgrade-20261026.json','evidence/vancouver-migration-preservation-20261026.json',
    })
    destination_codes='BKK BOM CDG CEB CGK CNX DEL DOH DPS DXB FRA HKG HKT ICN IST JFK KIX KUL LAX LHR MEL MNL NRT PEK PEN PUS PVG SFO SIN SYD TPE YVR'.split()
    required.update(f'app/static/images/destinations/{code}.svg' for code in destination_codes)
    versions=sorted(int(Path(name).name.split('_')[0]) for name,_ in files if name.startswith('sql/migrations/') and name.endswith('.sql'))
    if versions!=list(range(1,18)): raise ValueError('Release requires the full immutable migration sequence 001–017.')
    baseline=[name for name,_ in files if name.startswith('sql/') and name.count('/')==1 and name.endswith('.sql')]
    if sorted(int(Path(name).name.split('_')[0]) for name in baseline)!=list(range(1,11)): raise ValueError('Baseline SQL scripts 01–10 are incomplete.')
    missing=required-{name for name,_ in files}
    if missing: raise ValueError('Missing files: '+str(sorted(missing)))
    manifest=''.join(hashlib.sha256(data).hexdigest()+'  '+name+'\n' for name,data in files)
    with ZipFile(output,'w',ZIP_DEFLATED) as archive:
        for name,data in files: archive.writestr('AeroFlow-Ultimate/'+name,data)
        archive.writestr('AeroFlow-Ultimate/MANIFEST.sha256',manifest)
    with ZipFile(output) as archive:
        if archive.testzip(): raise ValueError('ZIP CRC verification failed')
        for name,data in files:
            if archive.read('AeroFlow-Ultimate/'+name)!=data: raise ValueError('ZIP content mismatch: '+name)
        if any(Path(n).name=='.env' for n in archive.namelist()): raise ValueError('Secret file found')
    result=dict(file=output.name,entries=len(files)+1,bytes=output.stat().st_size,sha256=hashlib.sha256(output.read_bytes()).hexdigest(),crc='PASS',manifest='PASS')
    print(json.dumps(result,indent=2)); return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',required=True);args=parser.parse_args();package(args.output)
