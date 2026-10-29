"""Check the tables and capabilities actually needed by the sample-data loader."""

REQUIRED_COLUMNS = {
    'Airports': ('CountryCode', 'CountryName', 'RegionCode', 'TimeZoneName', 'IanaTimeZone'),
    'AircraftSeats': ('SeatFee', 'IsPriority'),
    'FareClasses': ('Bundle', 'ChangeAllowed', 'ChangeFee', 'CabinBaggageKg'),
    'PassengerTypes': ('TypeCode', 'PriceFactor'),
    'BookingSegments': ('BookingID', 'JourneyGroup', 'FlightID', 'Status'),
    'Tickets': ('BookingSegmentID', 'FareClassID', 'PassengerType', 'BaseFare', 'TaxAmount', 'SeatFee'),
    'TicketRules': ('TicketID', 'ChangeAllowed'),
    'Services': ('ServiceID', 'UnitPrice'),
    'Routes': ('OriginID', 'DestinationID', 'IsActive'),
}
REQUIRED_OBJECTS = {
    'sp_SaveFlight': 'P', 'sp_SaveFare': 'P', 'sp_CreateItinerary': 'P',
    'sp_CreateBooking': 'P', 'sp_ConfirmPayment': 'P',
    'fn_FlightLocalDate': 'FN', 'vw_FlightAvailability': 'V', 'vw_BookingDetails': 'V',
}


def require_database(conn):
    columns = {tuple(row) for row in conn.execute(
        "SELECT t.name,c.name FROM sys.tables t JOIN sys.columns c ON c.object_id=t.object_id "
        "WHERE t.schema_id=SCHEMA_ID('dbo')").fetchall()}
    objects = {row[0]: row[1].strip() for row in conn.execute(
        "SELECT name,type FROM sys.objects WHERE schema_id=SCHEMA_ID('dbo')").fetchall()}
    missing = [table+'.'+column for table, names in REQUIRED_COLUMNS.items()
               for column in names if (table, column) not in columns]
    missing += [name for name, kind in REQUIRED_OBJECTS.items() if objects.get(name) != kind]
    if missing:
        raise ValueError('Database is not ready: '+', '.join(missing)+
                         '. Create a new, empty database with scripts/init_db.py first.')
