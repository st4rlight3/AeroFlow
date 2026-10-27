$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path $PSScriptRoot -Parent)
if (-not (Test-Path -LiteralPath '.venv\Scripts\python.exe')) {
    python -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.11+ is required.' }
}
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
& .\.venv\Scripts\python.exe scripts\configure.py
if ($LASTEXITCODE -ne 0) { throw 'Configuration failed.' }
Write-Host 'Edit .env. NEW database only: run .\.venv\Scripts\python.exe scripts\init_db.py'
Write-Host 'Then apply SQL migrations with a new backup path: see MIGRATION_GUIDE.md.'
Write-Host 'Existing database: skip init_db.py. Stop the app, back up and migrate first.'
