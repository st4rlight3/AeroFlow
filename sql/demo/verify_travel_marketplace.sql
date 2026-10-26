-- Open in SSMS, choose the AeroFlow database, then execute selected statements.
-- All prices below are stored SQL Server values, not frontend constants.
SELECT c.Name LoaiDichVu,d.Name DiemDen,d.CountryName QuocGia,p.Title TenDichVu,k.Name Goi,
 i.ServiceDate NgaySuDung,i.SlotCode KhungGio,k.UnitLabel DonVi,i.UnitPrice GiaDaGomThue,
 a.AvailableQuantity SoLuongCon,i.Capacity SucChua
FROM dbo.TravelProducts p JOIN dbo.TravelCategories c ON c.Code=p.CategoryCode
JOIN dbo.TravelDestinations d ON d.DestinationID=p.DestinationID
JOIN dbo.TravelPackages k ON k.ProductID=p.ProductID
JOIN dbo.TravelInventory i ON i.PackageID=k.PackageID
JOIN dbo.vw_TravelAvailability a ON a.InventoryID=i.InventoryID
WHERE i.ServiceDate='2026-12-15' ORDER BY c.SortOrder,d.Name,k.PackageID;

SELECT c.Name,COUNT(DISTINCT p.ProductID) SoDichVu,COUNT(DISTINCT k.PackageID) SoGoi,COUNT(i.InventoryID) SoLich
FROM dbo.TravelCategories c LEFT JOIN dbo.TravelProducts p ON p.CategoryCode=c.Code
LEFT JOIN dbo.TravelPackages k ON k.ProductID=p.ProductID LEFT JOIN dbo.TravelInventory i ON i.PackageID=k.PackageID
GROUP BY c.SortOrder,c.Name ORDER BY c.SortOrder;

SELECT * FROM dbo.TravelBookings ORDER BY BookingID DESC;
SELECT * FROM dbo.TravelPayments ORDER BY PaymentID DESC;
SELECT * FROM dbo.vw_TravelRevenue ORDER BY RevenueDate;
SELECT * FROM dbo.TravelAuditLog ORDER BY AuditID DESC;
-- Must return zero rows: the stock guard rejects any oversell.
SELECT * FROM dbo.vw_TravelAvailability WHERE AvailableQuantity<0;
DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;
