"""Run every minute using Windows Task Scheduler; Express needs no SQL Agent."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.db import query

for f in query("SELECT DISTINCT FlightID FROM dbo.Bookings WHERE Status='HELD' AND ExpiresAt<=SYSUTCDATETIME() ORDER BY FlightID"):
    query('EXEC dbo.sp_ExpireFlightHolds ?', (f['FlightID'],))
print('Expired holds released.')
