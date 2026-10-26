-- A night/day sells exactly one local calendar interval; no hidden extra day of capacity.
CREATE OR ALTER TRIGGER dbo.tr_TravelInventory_LocalCalendar ON dbo.TravelInventory AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i JOIN dbo.TravelPackages k ON k.PackageID=i.PackageID
 JOIN dbo.TravelProducts p ON p.ProductID=k.ProductID JOIN dbo.TravelDestinations d ON d.DestinationID=p.DestinationID
 WHERE CONVERT(date,(i.StartsAt AT TIME ZONE 'UTC') AT TIME ZONE d.TimeZoneName)<>i.ServiceDate
 OR (k.UnitCode IN ('NIGHT','DAY') AND CONVERT(date,(i.EndsAt AT TIME ZONE 'UTC') AT TIME ZONE d.TimeZoneName)<>DATEADD(day,1,i.ServiceDate)))
 THROW 52003,N'Inventory local dates do not match its unit.',1;
END;
