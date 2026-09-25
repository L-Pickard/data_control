-- One-time, self-contained migration for shinersql18.data_control.
-- Adds [portal].[report_bookmarks]: each person's saved report views (named slicer combinations, optional dates,
-- one default per report). The table DDL below is a snapshot of sql/tables/portal_report_bookmarks.sql.
-- Adds one new table and index only: no existing object or data is changed or dropped. Finance is not touched.
-- The runtime login needs no new grant: shiner_reports already holds SELECT/INSERT/UPDATE/DELETE on SCHEMA::portal.
-- Stops without changes if the table already exists or schema version 1 is missing. Any error rolls everything back.
-- Run as a db_owner Windows login:
--   sqlcmd -S tcp:shinersql18 -d data_control -E -N -C -b -i sql/migrations/20260925_add_portal_report_bookmarks.sql
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
    IF NOT EXISTS (SELECT 1 FROM [portal].[schema_versions] WHERE [version] = 1)
        THROW 51000, 'Portal schema version 1 is missing; run 20260925_create_portal_schema.sql first.', 1;
    IF OBJECT_ID(N'[portal].[report_bookmarks]', N'U') IS NOT NULL OR EXISTS (SELECT 1 FROM [portal].[schema_versions] WHERE [version] = 2)
        THROW 51000, '[portal].[report_bookmarks] already exists; this is a one-time migration.', 1;

    CREATE TABLE [portal].[report_bookmarks] (
         [bookmark_id] NVARCHAR(32) NOT NULL
        ,[user_id] NVARCHAR(184) NOT NULL
        ,[report_id] NVARCHAR(64) NOT NULL
        ,[name] NVARCHAR(80) NOT NULL
        ,[include_dates] BIT NOT NULL
        ,[is_default] BIT NOT NULL
        ,[filter_json] NVARCHAR(MAX) NOT NULL
        ,[labels_json] NVARCHAR(MAX) NOT NULL
        ,[created_at] DATETIMEOFFSET(3) NOT NULL
        ,[updated_at] DATETIMEOFFSET(3) NOT NULL
        ,CONSTRAINT [PK_portal_report_bookmarks] PRIMARY KEY CLUSTERED ([bookmark_id])
        ,CONSTRAINT [UQ_portal_report_bookmarks_name] UNIQUE ([user_id], [report_id], [name])
        ,CONSTRAINT [FK_portal_report_bookmarks_user] FOREIGN KEY ([user_id]) REFERENCES [portal].[users] ([user_id]) ON DELETE CASCADE
        ,CONSTRAINT [CK_portal_report_bookmarks_filter_json] CHECK (ISJSON([filter_json]) = 1)
        ,CONSTRAINT [CK_portal_report_bookmarks_labels_json] CHECK (ISJSON([labels_json]) = 1)
        );

    CREATE UNIQUE NONCLUSTERED INDEX [UX_portal_report_bookmarks_default]
        ON [portal].[report_bookmarks] ([user_id], [report_id])
        WHERE [is_default] = 1;

    INSERT INTO [portal].[schema_versions] ([version], [description])
    VALUES (2, N'Report bookmarks (saved views)');

    COMMIT TRANSACTION;
    SELECT N'portal.report_bookmarks created' AS result,
        (SELECT COUNT(*) FROM sys.tables WHERE schema_id = SCHEMA_ID(N'portal')) AS portal_tables,
        (SELECT MAX([version]) FROM [portal].[schema_versions]) AS schema_version;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
