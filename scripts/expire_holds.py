"""Run every minute using Windows Task Scheduler; Express needs no SQL Agent."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.db import query

for f in query("SELECT DISTINCT s.FlightID FROM dbo.Bookings b JOIN dbo.BookingSegments s ON s.BookingID=b.BookingID WHERE b.Status='HELD' AND b.ExpiresAt<=SYSUTCDATETIME() ORDER BY s.FlightID"):
    query('EXEC dbo.sp_ExpireFlightHolds ?', (f['FlightID'],))
print('Expired holds released.')
