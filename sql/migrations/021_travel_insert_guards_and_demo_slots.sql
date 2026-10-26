-- Reject a direct insert that would bypass the hold -> payment -> confirmation workflow.
CREATE OR ALTER TRIGGER dbo.tr_TravelBooking_Insert ON dbo.TravelBookings AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i JOIN dbo.TravelPackages p ON p.PackageID=i.PackageID
 WHERE i.Status<>'HELD' OR i.ServiceStartsAt<=SYSUTCDATETIME() OR i.GuestCount>i.Quantity*p.MaxGuests)
 THROW 52003,N'New reservations must begin with a valid future hold.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_TravelItems_Slot ON dbo.TravelBookingItems AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted x JOIN dbo.TravelBookings b ON b.BookingID=x.BookingID JOIN dbo.TravelInventory i ON i.InventoryID=x.InventoryID WHERE i.SlotCode<>b.SlotCode)
 THROW 52003,N'Inventory slot does not match the booked slot.',1;
END;
GO
-- Correct only the project's own unused demo tour slots, retaining every historical item.
UPDATE i SET EndsAt=DATEADD(hour,8,StartsAt)
FROM dbo.TravelInventory i JOIN dbo.TravelPackages k ON k.PackageID=i.PackageID JOIN dbo.TravelProducts p ON p.ProductID=k.ProductID
WHERE p.Slug LIKE 'demo-tours-%' AND i.EndsAt=DATEADD(hour,18,i.StartsAt)
AND NOT EXISTS(SELECT 1 FROM dbo.TravelBookingItems bi WHERE bi.InventoryID=i.InventoryID);
UPDATE dbo.TravelProducts SET DurationMinutes=480 WHERE Slug LIKE 'demo-tours-%' AND DurationMinutes=1080;
UPDATE dbo.TravelProducts SET FeaturesJson=JSON_MODIFY(JSON_MODIFY(FeaturesJson,'$.ValidityDays',7),'$.DataGB',5) WHERE Slug LIKE 'demo-esim-%';
