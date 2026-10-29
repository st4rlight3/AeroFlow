USE AeroFlow;
GO
-- 06_functions - Final definitions, including all historical dynamic patches.
-- Complete schema. Install into a new, empty database.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- dbo.fn_CalculateTicketPrice
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER FUNCTION dbo.fn_CalculateTicketPrice(@Base decimal(14,2),@Tax decimal(5,4))
RETURNS decimal(14,2) WITH SCHEMABINDING AS
BEGIN RETURN CONVERT(decimal(14,2),ROUND(@Base*(1+@Tax),2)); END;
GO

-- dbo.fn_FlightLocalDate
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER FUNCTION dbo.fn_FlightLocalDate(@FlightID int) RETURNS date AS
BEGIN
 DECLARE @zone nvarchar(64),@departure datetime2(0);
 SELECT @zone=a.TimeZoneName,@departure=f.DepartureTime FROM dbo.Flights f JOIN dbo.Airports a ON a.AirportID=f.OriginID WHERE f.FlightID=@FlightID;
 RETURN CONVERT(date,(@departure AT TIME ZONE 'UTC') AT TIME ZONE @zone);
END;
GO

-- dbo.fn_GetFlightOccupancyRate
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER FUNCTION dbo.fn_GetFlightOccupancyRate(@FlightID int)
RETURNS decimal(5,2) AS
BEGIN
 DECLARE @Rate decimal(5,2);
 SELECT @Rate=CONVERT(decimal(5,2),100.0*SoldSeats/NULLIF(TotalSeats,0)) FROM dbo.vw_FlightOccupancy WHERE FlightID=@FlightID;
 RETURN COALESCE(@Rate,0);
END;
GO

-- dbo.fn_TicketPaidValue
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER FUNCTION dbo.fn_TicketPaidValue(@TicketID int) RETURNS decimal(14,2) AS
BEGIN
 DECLARE @amount decimal(14,2);
 SELECT @amount=t.Amount+COALESCE((SELECT SUM(e.Quantity*e.UnitPrice) FROM dbo.BookingExtras e WHERE e.TicketID=t.TicketID),0)-COALESCE(d.Amount,0)
 FROM dbo.Tickets t LEFT JOIN dbo.TicketDiscounts d ON d.TicketID=t.TicketID WHERE t.TicketID=@TicketID;
 RETURN @amount;
END;
GO

-- dbo.fn_TicketRefundValue
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER FUNCTION dbo.fn_TicketRefundValue(@TicketID int) RETURNS decimal(14,2) AS
BEGIN
 DECLARE @refund decimal(14,2);
 SELECT @refund=ROUND((t.Amount*t.RefundPercent/100+COALESCE(e.Refundable,0))*(t.Amount+COALESCE(e.Total,0)-COALESCE(d.Amount,0))/(t.Amount+COALESCE(e.Total,0)),2)
 FROM dbo.Tickets t LEFT JOIN dbo.TicketDiscounts d ON d.TicketID=t.TicketID
 OUTER APPLY(SELECT SUM(Quantity*UnitPrice) Total,SUM(Quantity*UnitPrice*RefundPercent/100) Refundable FROM dbo.BookingExtras WHERE TicketID=t.TicketID) e WHERE t.TicketID=@TicketID;
 RETURN @refund;
END;
GO
