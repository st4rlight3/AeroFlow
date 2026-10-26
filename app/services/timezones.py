"""Civil search dates converted by SQL Server's installed time zone rules.

Never subtract a fixed offset: Sydney, Paris and New York observe seasonal
rules, and several Asian zones use half-hour offsets. Storage remains UTC.
"""
from datetime import datetime, time, timedelta
from ..db import query
from ..errors import ApiError


def airport_day_bounds(airport_id, day):
    start=datetime.combine(day,time.min)
    row=query("""SELECT
     CONVERT(datetime2(0),(CAST(? AS datetime2(0)) AT TIME ZONE TimeZoneName) AT TIME ZONE 'UTC') StartUTC,
     CONVERT(datetime2(0),(CAST(? AS datetime2(0)) AT TIME ZONE TimeZoneName) AT TIME ZONE 'UTC') EndUTC
     FROM dbo.Airports WHERE AirportID=? AND IsActive=1""",
     (start,start+timedelta(days=1),airport_id),one=True)
    if not row:raise ApiError('Sân bay không tồn tại hoặc đã ngừng hoạt động.',404)
    return row['StartUTC'],row['EndUTC']
