"""Package the application, ten SQL scripts and installation instructions."""
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDE = {'.git', '.venv', 'venv', '__pycache__', '.pytest_cache', 'node_modules',
           '.env', 'Thumbs.db', 'docs'}
SQL_FILES = {
    'sql/01_create_database.sql', 'sql/02_create_tables.sql',
    'sql/03_constraints_indexes.sql', 'sql/04_seed_data.sql', 'sql/05_views.sql',
    'sql/06_functions.sql', 'sql/07_stored_procedures.sql', 'sql/08_triggers.sql',
    'sql/09_business_queries.sql', 'sql/10_test_cases.sql',
}


def package(output):
    output = Path(output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    files = []
    for path in sorted(ROOT.rglob('*')):
        rel = path.relative_to(ROOT)
        if not path.is_file() or any(part in EXCLUDE for part in rel.parts):
            continue
        if path.suffix.lower() in ('.pyc', '.bak', '.log', '.zip', '.docx', '.pptx', '.ppt', '.odp', '.key'):
            continue
        if path.name in ('MANIFEST.sha256', 'SOURCE_MANIFEST.sha256'):
            continue
        if path.name.startswith('.env') and path.name != '.env.example':
            continue
        files.append((rel.as_posix(), path.read_bytes()))
    names = {name for name, _ in files}
    required = SQL_FILES | {
        'README.md', 'requirements.txt', '.env.example', 'run.py',
        'scripts/init_db.py', 'scripts/database_schema.py', 'scripts/load_demo.py',
        'scripts/seed_ultimate.py', 'scripts/seed_international.py',
        'app/templates/index.html', 'app/static/app.js', 'app/static/frontend.js',
        'app/static/frontend.css', 'app/static/ultimate.js', 'app/static/customer.js',
        'app/static/commerce.js', 'app/static/manage.js',
        'app/routes/itineraries.py', 'app/routes/customer.py', 'app/routes/commerce.py',
        'app/services/itineraries.py', 'app/services/timezones.py',
        'app/static/images/aviation-hero.webp', 'tests/test_database_install.py',
    }
    missing = required - names
    if missing:
        raise ValueError('Missing files: '+str(sorted(missing)))
    actual_sql = {name for name in names if Path(name).suffix.lower() == '.sql'}
    if actual_sql != SQL_FILES:
        raise ValueError('The project must contain exactly the ten SQL scripts in sql/.')
    manifest = ''.join(hashlib.sha256(data).hexdigest()+'  '+name+'\n' for name, data in files)
    with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
        for name, data in files:
            archive.writestr('AeroFlow-Ultimate/'+name, data)
        archive.writestr('AeroFlow-Ultimate/MANIFEST.sha256', manifest)
    with ZipFile(output) as archive:
        if archive.testzip():
            raise ValueError('ZIP CRC verification failed.')
        for name, data in files:
            if archive.read('AeroFlow-Ultimate/'+name) != data:
                raise ValueError('ZIP content mismatch: '+name)
        if any(Path(name).name == '.env' for name in archive.namelist()):
            raise ValueError('Private configuration found in ZIP.')
    result = dict(file=output.name, entries=len(files)+1, bytes=output.stat().st_size,
                  sha256=hashlib.sha256(output.read_bytes()).hexdigest(), crc='PASS', manifest='PASS')
    print(json.dumps(result, indent=2))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    package(args.output)
