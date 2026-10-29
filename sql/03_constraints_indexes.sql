USE AeroFlow;
GO
-- 03 - Foreign keys and secondary indexes for the final schema.
-- Consolidated schema through migration 017. For a NEW database only.
-- Existing installations use scripts/migrate.py and the unchanged sql/migrations history.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
SET XACT_ABORT ON;
BEGIN TRANSACTION;
ALTER TABLE dbo.[Aircraft] WITH CHECK ADD CONSTRAINT [FK_Aircraft_Airlines] FOREIGN KEY ([AirlineID]) REFERENCES dbo.[Airlines] ([AirlineID]);
ALTER TABLE dbo.[AircraftSeats] WITH CHECK ADD CONSTRAINT [FK_Seats_Aircraft] FOREIGN KEY ([AircraftID]) REFERENCES dbo.[Aircraft] ([AircraftID]);
ALTER TABLE dbo.[AuditLogs] WITH CHECK ADD CONSTRAINT [FK_Audit_User] FOREIGN KEY ([ActorID]) REFERENCES dbo.[Users] ([UserID]);
ALTER TABLE dbo.[BookingChanges] WITH CHECK ADD CONSTRAINT [FK_BookingChanges_Bookings_BookingID_77ae6dc7] FOREIGN KEY ([BookingID]) REFERENCES dbo.[Bookings] ([BookingID]);
ALTER TABLE dbo.[BookingChanges] WITH CHECK ADD CONSTRAINT [FK_BookingChanges_BookingSegments_NewSegmentID_1a814f80] FOREIGN KEY ([NewSegmentID]) REFERENCES dbo.[BookingSegments] ([BookingSegmentID]);
ALTER TABLE dbo.[BookingChanges] WITH CHECK ADD CONSTRAINT [FK_BookingChanges_BookingSegments_OldSegmentID_568ce457] FOREIGN KEY ([OldSegmentID]) REFERENCES dbo.[BookingSegments] ([BookingSegmentID]);
ALTER TABLE dbo.[BookingChanges] WITH CHECK ADD CONSTRAINT [FK_BookingChanges_Payments_PaymentID_4f6d301d] FOREIGN KEY ([PaymentID]) REFERENCES dbo.[Payments] ([PaymentID]);
ALTER TABLE dbo.[BookingDiscounts] WITH CHECK ADD CONSTRAINT [FK_BookingDiscounts_Bookings_BookingID_77ae6dc7] FOREIGN KEY ([BookingID]) REFERENCES dbo.[Bookings] ([BookingID]);
ALTER TABLE dbo.[BookingDiscounts] WITH CHECK ADD CONSTRAINT [FK_BookingDiscounts_DiscountCodes_DiscountCodeID_166ef03a] FOREIGN KEY ([DiscountCodeID]) REFERENCES dbo.[DiscountCodes] ([DiscountCodeID]);
ALTER TABLE dbo.[BookingExtras] WITH CHECK ADD CONSTRAINT [FK_BookingExtras_Services_ServiceID_2c5e9056] FOREIGN KEY ([ServiceID]) REFERENCES dbo.[Services] ([ServiceID]);
ALTER TABLE dbo.[BookingExtras] WITH CHECK ADD CONSTRAINT [FK_BookingExtras_Tickets_TicketID_0a8a93d1] FOREIGN KEY ([TicketID]) REFERENCES dbo.[Tickets] ([TicketID]);
ALTER TABLE dbo.[BookingPassengers] WITH CHECK ADD CONSTRAINT [FK_BP_Booking] FOREIGN KEY ([BookingID]) REFERENCES dbo.[Bookings] ([BookingID]);
ALTER TABLE dbo.[BookingPassengers] WITH CHECK ADD CONSTRAINT [FK_BP_Class] FOREIGN KEY ([FareClassID]) REFERENCES dbo.[FareClasses] ([FareClassID]);
ALTER TABLE dbo.[BookingPassengers] WITH CHECK ADD CONSTRAINT [FK_BP_Passenger] FOREIGN KEY ([PassengerID]) REFERENCES dbo.[Passengers] ([PassengerID]);
ALTER TABLE dbo.[Bookings] WITH CHECK ADD CONSTRAINT [FK_Bookings_Flight] FOREIGN KEY ([FlightID]) REFERENCES dbo.[Flights] ([FlightID]);
ALTER TABLE dbo.[Bookings] WITH CHECK ADD CONSTRAINT [FK_Bookings_User] FOREIGN KEY ([UserID]) REFERENCES dbo.[Users] ([UserID]);
ALTER TABLE dbo.[BookingSegments] WITH CHECK ADD CONSTRAINT [FK_Segments_Booking] FOREIGN KEY ([BookingID]) REFERENCES dbo.[Bookings] ([BookingID]);
ALTER TABLE dbo.[BookingSegments] WITH CHECK ADD CONSTRAINT [FK_Segments_Flight] FOREIGN KEY ([FlightID]) REFERENCES dbo.[Flights] ([FlightID]);
ALTER TABLE dbo.[CheckIns] WITH CHECK ADD CONSTRAINT [FK_CheckIns_Tickets_TicketID_0a8a93d1] FOREIGN KEY ([TicketID]) REFERENCES dbo.[Tickets] ([TicketID]);
ALTER TABLE dbo.[FlightFares] WITH CHECK ADD CONSTRAINT [FK_Fares_Class] FOREIGN KEY ([FareClassID]) REFERENCES dbo.[FareClasses] ([FareClassID]);
ALTER TABLE dbo.[FlightFares] WITH CHECK ADD CONSTRAINT [FK_Fares_Flight] FOREIGN KEY ([FlightID]) REFERENCES dbo.[Flights] ([FlightID]);
ALTER TABLE dbo.[Flights] WITH CHECK ADD CONSTRAINT [FK_Flights_Aircraft] FOREIGN KEY ([AircraftID]) REFERENCES dbo.[Aircraft] ([AircraftID]);
ALTER TABLE dbo.[Flights] WITH CHECK ADD CONSTRAINT [FK_Flights_Destination] FOREIGN KEY ([DestinationID]) REFERENCES dbo.[Airports] ([AirportID]);
ALTER TABLE dbo.[Flights] WITH CHECK ADD CONSTRAINT [FK_Flights_Origin] FOREIGN KEY ([OriginID]) REFERENCES dbo.[Airports] ([AirportID]);
ALTER TABLE dbo.[FlightSeatAssignments] WITH CHECK ADD CONSTRAINT [FK_Assignments_Flight] FOREIGN KEY ([FlightID]) REFERENCES dbo.[Flights] ([FlightID]);
ALTER TABLE dbo.[FlightSeatAssignments] WITH CHECK ADD CONSTRAINT [FK_Assignments_Seat] FOREIGN KEY ([SeatID]) REFERENCES dbo.[AircraftSeats] ([SeatID]);
ALTER TABLE dbo.[LoyaltyLedger] WITH CHECK ADD CONSTRAINT [FK_LoyaltyLedger_Payments_PaymentID_4f6d301d] FOREIGN KEY ([PaymentID]) REFERENCES dbo.[Payments] ([PaymentID]);
ALTER TABLE dbo.[LoyaltyLedger] WITH CHECK ADD CONSTRAINT [FK_LoyaltyLedger_Users_UserID_e2273973] FOREIGN KEY ([UserID]) REFERENCES dbo.[Users] ([UserID]);
ALTER TABLE dbo.[LoyaltySpends] WITH CHECK ADD CONSTRAINT [FK_LoyaltySpends_Bookings_BookingID_77ae6dc7] FOREIGN KEY ([BookingID]) REFERENCES dbo.[Bookings] ([BookingID]);
ALTER TABLE dbo.[LoyaltySpends] WITH CHECK ADD CONSTRAINT [FK_LoyaltySpends_Users_UserID_e2273973] FOREIGN KEY ([UserID]) REFERENCES dbo.[Users] ([UserID]);
ALTER TABLE dbo.[NotificationDeliveries] WITH CHECK ADD CONSTRAINT [FK_NotificationDeliveries_Notifications_NotificationID_54c6b2f8] FOREIGN KEY ([NotificationID]) REFERENCES dbo.[Notifications] ([NotificationID]);
ALTER TABLE dbo.[Notifications] WITH CHECK ADD CONSTRAINT [FK_Notifications_Bookings_BookingID_77ae6dc7] FOREIGN KEY ([BookingID]) REFERENCES dbo.[Bookings] ([BookingID]);
ALTER TABLE dbo.[Notifications] WITH CHECK ADD CONSTRAINT [FK_Notifications_Users_UserID_e2273973] FOREIGN KEY ([UserID]) REFERENCES dbo.[Users] ([UserID]);
ALTER TABLE dbo.[PasswordResetTokens] WITH CHECK ADD CONSTRAINT [FK_PasswordResetTokens_Users_UserID_e2273973] FOREIGN KEY ([UserID]) REFERENCES dbo.[Users] ([UserID]);
ALTER TABLE dbo.[Payments] WITH CHECK ADD CONSTRAINT [FK_Payments_Booking] FOREIGN KEY ([BookingID]) REFERENCES dbo.[Bookings] ([BookingID]);
ALTER TABLE dbo.[Routes] WITH CHECK ADD CONSTRAINT [FK_Routes_Airports_DestinationID_f8e8c779] FOREIGN KEY ([DestinationID]) REFERENCES dbo.[Airports] ([AirportID]);
ALTER TABLE dbo.[Routes] WITH CHECK ADD CONSTRAINT [FK_Routes_Airports_OriginID_b178992e] FOREIGN KEY ([OriginID]) REFERENCES dbo.[Airports] ([AirportID]);
ALTER TABLE dbo.[SavedTravellers] WITH CHECK ADD CONSTRAINT [FK_SavedTravellers_Users_UserID_e2273973] FOREIGN KEY ([UserID]) REFERENCES dbo.[Users] ([UserID]);
ALTER TABLE dbo.[TicketDiscounts] WITH CHECK ADD CONSTRAINT [FK_TicketDiscounts_Tickets_TicketID_0a8a93d1] FOREIGN KEY ([TicketID]) REFERENCES dbo.[Tickets] ([TicketID]);
ALTER TABLE dbo.[TicketRefunds] WITH CHECK ADD CONSTRAINT [FK_TicketRefunds_Payments_PaymentID_4f6d301d] FOREIGN KEY ([PaymentID]) REFERENCES dbo.[Payments] ([PaymentID]);
ALTER TABLE dbo.[TicketRefunds] WITH CHECK ADD CONSTRAINT [FK_TicketRefunds_Tickets_TicketID_0a8a93d1] FOREIGN KEY ([TicketID]) REFERENCES dbo.[Tickets] ([TicketID]);
ALTER TABLE dbo.[TicketRules] WITH CHECK ADD CONSTRAINT [FK_TicketRules_Tickets_TicketID_0a8a93d1] FOREIGN KEY ([TicketID]) REFERENCES dbo.[Tickets] ([TicketID]);
ALTER TABLE dbo.[Tickets] WITH CHECK ADD CONSTRAINT [FK_Tickets_Assignment] FOREIGN KEY ([AssignmentID]) REFERENCES dbo.[FlightSeatAssignments] ([AssignmentID]);
ALTER TABLE dbo.[Tickets] WITH CHECK ADD CONSTRAINT [FK_Tickets_BP] FOREIGN KEY ([BookingPassengerID]) REFERENCES dbo.[BookingPassengers] ([BookingPassengerID]);
ALTER TABLE dbo.[Tickets] WITH CHECK ADD CONSTRAINT [FK_Tickets_FareClass] FOREIGN KEY ([FareClassID]) REFERENCES dbo.[FareClasses] ([FareClassID]);
ALTER TABLE dbo.[Tickets] WITH CHECK ADD CONSTRAINT [FK_Tickets_PassengerType] FOREIGN KEY ([PassengerType]) REFERENCES dbo.[PassengerTypes] ([TypeCode]);
ALTER TABLE dbo.[Tickets] WITH CHECK ADD CONSTRAINT [FK_Tickets_Segment] FOREIGN KEY ([BookingSegmentID]) REFERENCES dbo.[BookingSegments] ([BookingSegmentID]);
ALTER TABLE dbo.[TravelCreditLedger] WITH CHECK ADD CONSTRAINT [FK_TravelCreditLedger_Payments_PaymentID_4f6d301d] FOREIGN KEY ([PaymentID]) REFERENCES dbo.[Payments] ([PaymentID]);
ALTER TABLE dbo.[TravelCreditLedger] WITH CHECK ADD CONSTRAINT [FK_TravelCreditLedger_Users_UserID_e2273973] FOREIGN KEY ([UserID]) REFERENCES dbo.[Users] ([UserID]);
ALTER TABLE dbo.[UserPreferences] WITH CHECK ADD CONSTRAINT [FK_UserPreferences_Users_UserID_e2273973] FOREIGN KEY ([UserID]) REFERENCES dbo.[Users] ([UserID]);
ALTER TABLE dbo.[Users] WITH CHECK ADD CONSTRAINT [FK_Users_Roles] FOREIGN KEY ([RoleID]) REFERENCES dbo.[Roles] ([RoleID]);

CREATE NONCLUSTERED INDEX [IX_Audit_Created] ON dbo.[AuditLogs] ([CreatedAt] DESC);

CREATE NONCLUSTERED INDEX [IX_BookingDiscount_Code] ON dbo.[BookingDiscounts] ([DiscountCodeID] ASC, [BookingID] ASC);

CREATE NONCLUSTERED INDEX [IX_BP_Booking] ON dbo.[BookingPassengers] ([BookingID] ASC) INCLUDE ([PassengerID], [FareClassID]);

CREATE NONCLUSTERED INDEX [IX_Bookings_Expiry] ON dbo.[Bookings] ([FlightID] ASC, [Status] ASC, [ExpiresAt] ASC) INCLUDE ([UserID]);

CREATE NONCLUSTERED INDEX [IX_Bookings_User] ON dbo.[Bookings] ([UserID] ASC, [CreatedAt] DESC);

CREATE NONCLUSTERED INDEX [IX_Segments_Flight] ON dbo.[BookingSegments] ([FlightID] ASC, [Status] ASC) INCLUDE ([BookingID]);

CREATE UNIQUE NONCLUSTERED INDEX [UX_Segments_ActiveOrder] ON dbo.[BookingSegments] ([BookingID] ASC, [SegmentOrder] ASC) WHERE ([Status]='ACTIVE');

CREATE NONCLUSTERED INDEX [IX_Flights_Search] ON dbo.[Flights] ([OriginID] ASC, [DestinationID] ASC, [DepartureTime] ASC) INCLUDE ([ArrivalTime], [Status], [AircraftID], [FlightNumber]);

CREATE UNIQUE NONCLUSTERED INDEX [UX_Assignments_ActiveSeat] ON dbo.[FlightSeatAssignments] ([FlightID] ASC, [SeatID] ASC) WHERE ([IsActive]=(1));

CREATE NONCLUSTERED INDEX [IX_Loyalty_User] ON dbo.[LoyaltyLedger] ([UserID] ASC, [LoyaltyID] ASC);

CREATE UNIQUE NONCLUSTERED INDEX [UX_LoyaltyTierID] ON dbo.[LoyaltyTiers] ([LoyaltyTierID] ASC);

CREATE NONCLUSTERED INDEX [IX_Notifications_User] ON dbo.[Notifications] ([UserID] ASC, [NotificationID] DESC);

CREATE UNIQUE NONCLUSTERED INDEX [UX_Notifications_Event] ON dbo.[Notifications] ([EventKey] ASC) WHERE ([EventKey] IS NOT NULL);

CREATE NONCLUSTERED INDEX [IX_ResetTokens_User] ON dbo.[PasswordResetTokens] ([UserID] ASC, [ExpiresAt] ASC);

CREATE NONCLUSTERED INDEX [IX_Payments_Report] ON dbo.[Payments] ([CreatedAt] ASC, [Status] ASC, [Kind] ASC) INCLUDE ([Amount], [BookingID]);

CREATE UNIQUE NONCLUSTERED INDEX [UX_Payments_SuccessCharge] ON dbo.[Payments] ([BookingID] ASC) WHERE ([Kind]='CHARGE' AND [Status]='SUCCESS' AND [Purpose]='BOOKING');

CREATE UNIQUE NONCLUSTERED INDEX [UX_Tickets_PassengerSegment] ON dbo.[Tickets] ([BookingPassengerID] ASC, [BookingSegmentID] ASC) WHERE ([BookingSegmentID] IS NOT NULL);

CREATE NONCLUSTERED INDEX [IX_Credit_User] ON dbo.[TravelCreditLedger] ([UserID] ASC, [CreditID] ASC);

COMMIT TRANSACTION;
GO
