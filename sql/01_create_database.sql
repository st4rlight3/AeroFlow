-- SQL Server 2019+ / Express. Non-destructive: preserve an existing database.
USE master;
GO
IF DB_ID(N'AeroFlow') IS NULL CREATE DATABASE AeroFlow;
GO
USE AeroFlow;
GO
IF (SELECT compatibility_level FROM sys.databases WHERE name=DB_NAME()) < 150
    ALTER DATABASE AeroFlow SET COMPATIBILITY_LEVEL = 150;
GO
