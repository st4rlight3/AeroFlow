-- Vancouver adopted permanent UTC-7 in March 2026. SQL Pacific remains US rules.
-- Prefer the updated Windows identifier; Microsoft's interim fallback is Yukon.
-- Correct metadata only: never change UTC flight instants or ticket amounts.
DECLARE @zone nvarchar(64);
SELECT @zone=CASE WHEN EXISTS(SELECT 1 FROM sys.time_zone_info WHERE name=N'British Columbia Standard Time')
 THEN N'British Columbia Standard Time' WHEN EXISTS(SELECT 1 FROM sys.time_zone_info WHERE name=N'Yukon Standard Time')
 THEN N'Yukon Standard Time' END;
IF @zone IS NULL THROW 51004,N'Install the British Columbia or Yukon Windows time zone before migration.',1;
IF EXISTS(SELECT 1 FROM dbo.Airports WHERE Code='YVR' AND
 (CountryCode<>'CA' OR IanaTimeZone<>N'America/Vancouver' OR TimeZoneName NOT IN (N'Pacific Standard Time',N'Yukon Standard Time',N'British Columbia Standard Time')))
 THROW 51004,N'YVR contains custom metadata. Review it before migration; no overwrite performed.',1;
UPDATE dbo.Airports SET TimeZoneName=@zone WHERE Code='YVR' AND CountryCode='CA' AND IanaTimeZone=N'America/Vancouver';
