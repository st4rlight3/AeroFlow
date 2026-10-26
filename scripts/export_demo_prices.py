"""Read-only SQL export for viewing demo routes and prices on GitHub/Excel.

These CSVs are documentation snapshots, never the web application's data source.
No customer, passenger or payment information is exported.
"""
import csv
from datetime import datetime,timezone
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app.db import query


def main():
    folder=Path(__file__).resolve().parents[1]/'data';folder.mkdir(exist_ok=True)
    rows=query('''SELECT f.FlightNumber,al.Name Airline,o.City Origin,d.City Destination,o.Code OriginCode,d.Code DestinationCode,
     o.CountryName OriginCountry,d.CountryName DestinationCountry,
     CONVERT(varchar(16),(f.DepartureTime AT TIME ZONE 'UTC') AT TIME ZONE o.TimeZoneName,120) DepartureLocal,
     CONVERT(varchar(16),(f.ArrivalTime AT TIME ZONE 'UTC') AT TIME ZONE d.TimeZoneName,120) ArrivalLocal,
     DATEDIFF(minute,f.DepartureTime,f.ArrivalTime) DurationMinutes,
     MIN(CASE WHEN c.Cabin='ECONOMY' THEN dbo.fn_CalculateTicketPrice(ff.BasePrice,ff.TaxRate) END) Economy,
     MIN(CASE WHEN c.Cabin='PREMIUM' THEN dbo.fn_CalculateTicketPrice(ff.BasePrice,ff.TaxRate) END) Premium,
     MIN(CASE WHEN c.Cabin='BUSINESS' THEN dbo.fn_CalculateTicketPrice(ff.BasePrice,ff.TaxRate) END) Business,
     MIN(CASE WHEN c.Cabin='FIRST' THEN dbo.fn_CalculateTicketPrice(ff.BasePrice,ff.TaxRate) END) FirstClass
     FROM dbo.Flights f JOIN dbo.Aircraft a ON a.AircraftID=f.AircraftID JOIN dbo.Airlines al ON al.AirlineID=a.AirlineID
     JOIN dbo.Airports o ON o.AirportID=f.OriginID JOIN dbo.Airports d ON d.AirportID=f.DestinationID
     JOIN dbo.FlightFares ff ON ff.FlightID=f.FlightID JOIN dbo.FareClasses c ON c.FareClassID=ff.FareClassID
     WHERE (a.Registration LIKE 'DEMO-%' OR a.Registration IN ('VN-AF1','VN-AF2','VN-AF3','VN-AF4'))
     GROUP BY f.FlightID,f.FlightNumber,al.Name,o.City,d.City,o.Code,d.Code,o.CountryName,d.CountryName,
      f.DepartureTime,f.ArrivalTime,o.TimeZoneName,d.TimeZoneName
     ORDER BY f.DepartureTime,f.FlightNumber''')
    def cell(x):
        s='' if x is None else str(x)
        return "'"+s if isinstance(x,str) and s.startswith(('=','+','-','@')) else s
    with (folder/'demo_flight_prices.csv').open('w',encoding='utf-8-sig',newline='') as file:
        writer=csv.writer(file)
        writer.writerow(['Chuyến bay','Hãng bay','Điểm đi','Điểm đến','Mã đi','Mã đến','Quốc gia đi','Quốc gia đến','Khởi hành giờ địa phương','Đến giờ địa phương','Thời gian bay (phút)','Phổ thông gồm thuế (VND)','Phổ thông đặc biệt gồm thuế (VND)','Thương gia gồm thuế (VND)','Hạng nhất gồm thuế (VND)'])
        for row in rows:writer.writerow([cell(v) for v in row.values()])
    routes={}
    for r in rows:
        key=(r['OriginCode'],r['DestinationCode'])
        route=routes.setdefault(key,dict(origin=r['Origin'],destination=r['Destination'],country=r['DestinationCountry'],prices=[],dates=[]))
        if r['Economy'] is not None:route['prices'].append(r['Economy'])
        route['dates'].append(r['DepartureLocal'][:10])
    with (folder/'demo_route_prices.csv').open('w',encoding='utf-8-sig',newline='') as file:
        writer=csv.writer(file)
        writer.writerow(['Điểm đi','Điểm đến','Mã đi','Mã đến','Quốc gia đến','Giá phổ thông thấp nhất gồm thuế (VND)','Giá phổ thông cao nhất gồm thuế (VND)','Ngày bay đầu','Ngày bay cuối','Số chuyến'])
        for (origin,destination),r in sorted(routes.items()):
            writer.writerow([cell(v) for v in (r['origin'],r['destination'],origin,destination,r['country'],min(r['prices']) if r['prices'] else '',max(r['prices']) if r['prices'] else '',min(r['dates']),max(r['dates']),len(r['dates']))])
    print(f'Exported {len(rows)} flights and {len(routes)} routes from SQL Server; VND demo fares include simulated tax, exclude seat/service fees.')


if __name__=='__main__':main()
