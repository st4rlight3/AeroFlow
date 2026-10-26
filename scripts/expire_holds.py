"""Run every minute using Windows Task Scheduler; Express needs no SQL Agent."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.db import query,connection

for f in query("SELECT DISTINCT FlightID FROM dbo.Bookings WHERE Status='HELD' AND ExpiresAt<=SYSUTCDATETIME() ORDER BY FlightID"):
    query('EXEC dbo.sp_ExpireFlightHolds ?', (f['FlightID'],))
if query("SELECT OBJECT_ID('dbo.TravelBookings') ID",one=True)['ID']:
    for p in query("SELECT DISTINCT ProductID FROM dbo.TravelBookings WHERE Status='HELD' AND ExpiresAt<=SYSUTCDATETIME() ORDER BY ProductID"):
        with connection() as conn:
            conn.execute('EXEC dbo.sp_TravelLock ?',p['ProductID'])
            ids=conn.execute("SET NOCOUNT ON; DECLARE @expired TABLE(BookingID int); UPDATE dbo.TravelBookings SET Status='EXPIRED' OUTPUT INSERTED.BookingID INTO @expired WHERE ProductID=? AND Status='HELD' AND ExpiresAt<=SYSUTCDATETIME(); SELECT BookingID FROM @expired;",p['ProductID']).fetchall()
            for row in ids:conn.execute("INSERT dbo.TravelAuditLog(Entity,EntityID,Action) VALUES('BOOKING',?,'EXPIRE')",row[0])
print('Expired flight and travel holds released.')
