-- One-time, self-contained migration for shinersql18.data_control.
-- Adds [portal].[user_preferences] (each person's own portal settings and profile picture) and [portal].[settings]
-- (workspace settings chosen by an administrator, starting with the default theme). The table DDL below is a snapshot
-- of sql/tables/portal_user_preferences.sql and sql/tables/portal_settings.sql.
-- Adds two new tables only: no existing object or data is changed or dropped. Finance is not touched.
-- The runtime login needs no new grant: shiner_reports already holds SELECT/INSERT/UPDATE/DELETE on SCHEMA::portal.
-- Until this has run, the portal works with its standard settings and My Preferences says it cannot save.
-- Stops without changes if either table already exists or schema version 2 is missing. Any error rolls everything back.
-- Run as a db_owner Windows login:
--   sqlcmd -S tcp:shinersql18 -d data_control -E -N -C -b -i sql/migrations/20261001_add_portal_user_preferences.sql
USE [data_control];
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;

BEGIN TRY
    BEGIN TRANSACTION;
    IF NOT EXISTS (SELECT 1 FROM [portal].[schema_versions] WHERE [version] = 2)
        THROW 51000, 'Portal schema version 2 is missing; run 20260925_add_portal_report_bookmarks.sql first.', 1;
    IF OBJECT_ID(N'[portal].[user_preferences]', N'U') IS NOT NULL OR OBJECT_ID(N'[portal].[settings]', N'U') IS NOT NULL
        OR EXISTS (SELECT 1 FROM [portal].[schema_versions] WHERE [version] = 3)
        THROW 51000, '[portal].[user_preferences] or [portal].[settings] already exists; this is a one-time migration.', 1;

    CREATE TABLE [portal].[user_preferences] (
         [user_id] NVARCHAR(184) NOT NULL
        ,[preferences_json] NVARCHAR(MAX) NOT NULL
        ,[picture] VARBINARY(MAX) NULL
        ,[picture_updated_at] DATETIMEOFFSET(3) NULL
        ,[updated_at] DATETIMEOFFSET(3) NOT NULL
        ,CONSTRAINT [PK_portal_user_preferences] PRIMARY KEY CLUSTERED ([user_id])
        ,CONSTRAINT [FK_portal_user_preferences_user] FOREIGN KEY ([user_id]) REFERENCES [portal].[users] ([user_id]) ON DELETE CASCADE
        ,CONSTRAINT [CK_portal_user_preferences_json] CHECK (ISJSON([preferences_json]) = 1)
        ,CONSTRAINT [CK_portal_user_preferences_picture] CHECK ([picture] IS NULL OR DATALENGTH([picture]) <= 614400)
        );

    CREATE TABLE [portal].[settings] (
         [name] NVARCHAR(64) NOT NULL
        ,[value] NVARCHAR(400) NOT NULL
        ,[updated_at] DATETIMEOFFSET(3) NOT NULL
        ,[updated_by] NVARCHAR(184) NOT NULL
        ,CONSTRAINT [PK_portal_settings] PRIMARY KEY CLUSTERED ([name])
        );

    INSERT INTO [portal].[schema_versions] ([version], [description])
    VALUES (3, N'User preferences and workspace settings');

    COMMIT TRANSACTION;
    SELECT N'portal.user_preferences and portal.settings created' AS result,
        (SELECT COUNT(*) FROM sys.tables WHERE schema_id = SCHEMA_ID(N'portal')) AS portal_tables,
        (SELECT MAX([version]) FROM [portal].[schema_versions]) AS schema_version;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
