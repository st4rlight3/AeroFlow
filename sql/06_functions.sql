USE AeroFlow;
GO
CREATE OR ALTER FUNCTION dbo.fn_CalculateTicketPrice(@Base decimal(14,2),@Tax decimal(5,4))
RETURNS decimal(14,2) WITH SCHEMABINDING AS
BEGIN RETURN CONVERT(decimal(14,2),ROUND(@Base*(1+@Tax),2)); END;
GO
CREATE OR ALTER FUNCTION dbo.fn_GetFlightOccupancyRate(@FlightID int)
RETURNS decimal(5,2) AS
BEGIN
 DECLARE @Rate decimal(5,2);
 SELECT @Rate=CONVERT(decimal(5,2),100.0*SoldSeats/NULLIF(TotalSeats,0)) FROM dbo.vw_FlightOccupancy WHERE FlightID=@FlightID;
 RETURN COALESCE(@Rate,0);
END;
GO
