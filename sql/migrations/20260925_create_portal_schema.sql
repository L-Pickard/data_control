-- One-time, self-contained migration for shinersql18.data_control.
-- Creates the [portal] schema and its tables for the Shiner web portal: people (Windows SIDs), app-managed groups,
-- report grants and the permission audit trail. The table DDL below is a snapshot of sql/tables/portal_*.sql.
-- Adds new objects only: no existing object or data is changed or dropped. Finance is not touched.
-- Stops without changes if [portal] already exists. Any error rolls everything back.
-- Run as a db_owner Windows login (making [dbo] the schema owner needs more than the codex_assistant helper has):
--   sqlcmd -S tcp:shinersql18 -d data_control -E -N -C -b -i sql/migrations/20260925_create_portal_schema.sql
-- Applied 25 September 2026.
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
    IF SCHEMA_ID(N'portal') IS NOT NULL
        THROW 51000, 'Schema [portal] already exists; this is a one-time migration.', 1;

    EXEC (N'CREATE SCHEMA [portal] AUTHORIZATION [dbo];');

    CREATE TABLE [portal].[schema_versions] (
         [version] INT NOT NULL
        ,[description] NVARCHAR(200) NOT NULL
        ,[applied_at] DATETIMEOFFSET(0) NOT NULL CONSTRAINT [DF_portal_schema_versions_applied_at] DEFAULT(SYSDATETIMEOFFSET())
        ,CONSTRAINT [PK_portal_schema_versions] PRIMARY KEY CLUSTERED ([version])
        );

    CREATE TABLE [portal].[users] (
         [user_id] NVARCHAR(184) NOT NULL
        ,[display_name] NVARCHAR(256) NOT NULL
        ,[is_enabled] BIT NOT NULL
        ,[is_admin] BIT NOT NULL
        ,[last_seen_at] DATETIMEOFFSET(0) NULL
        ,[created_at] DATETIMEOFFSET(0) NOT NULL CONSTRAINT [DF_portal_users_created_at] DEFAULT(SYSDATETIMEOFFSET())
        ,CONSTRAINT [PK_portal_users] PRIMARY KEY CLUSTERED ([user_id])
        );

    CREATE TABLE [portal].[groups] (
         [group_id] NVARCHAR(64) NOT NULL
        ,[name] NVARCHAR(100) NOT NULL
        ,CONSTRAINT [PK_portal_groups] PRIMARY KEY CLUSTERED ([group_id])
        ,CONSTRAINT [UQ_portal_groups_name] UNIQUE ([name])
        );

    CREATE TABLE [portal].[group_members] (
         [group_id] NVARCHAR(64) NOT NULL
        ,[user_id] NVARCHAR(184) NOT NULL
        ,CONSTRAINT [PK_portal_group_members] PRIMARY KEY CLUSTERED ([group_id], [user_id])
        ,CONSTRAINT [FK_portal_group_members_group] FOREIGN KEY ([group_id]) REFERENCES [portal].[groups] ([group_id]) ON DELETE CASCADE
        ,CONSTRAINT [FK_portal_group_members_user] FOREIGN KEY ([user_id]) REFERENCES [portal].[users] ([user_id]) ON DELETE CASCADE
        );

    CREATE TABLE [portal].[user_report_grants] (
         [user_id] NVARCHAR(184) NOT NULL
        ,[report_id] NVARCHAR(64) NOT NULL
        ,CONSTRAINT [PK_portal_user_report_grants] PRIMARY KEY CLUSTERED ([user_id], [report_id])
        ,CONSTRAINT [FK_portal_user_report_grants_user] FOREIGN KEY ([user_id]) REFERENCES [portal].[users] ([user_id]) ON DELETE CASCADE
        );

    CREATE TABLE [portal].[group_report_grants] (
         [group_id] NVARCHAR(64) NOT NULL
        ,[report_id] NVARCHAR(64) NOT NULL
        ,CONSTRAINT [PK_portal_group_report_grants] PRIMARY KEY CLUSTERED ([group_id], [report_id])
        ,CONSTRAINT [FK_portal_group_report_grants_group] FOREIGN KEY ([group_id]) REFERENCES [portal].[groups] ([group_id]) ON DELETE CASCADE
        );

    CREATE TABLE [portal].[audit_events] (
         [audit_id] BIGINT IDENTITY(1, 1) NOT NULL
        ,[occurred_at] DATETIMEOFFSET(3) NOT NULL
        ,[actor] NVARCHAR(184) NOT NULL
        ,[action] NVARCHAR(4000) NOT NULL
        ,CONSTRAINT [PK_portal_audit_events] PRIMARY KEY CLUSTERED ([audit_id])
        );

    INSERT INTO [portal].[schema_versions] ([version], [description])
    VALUES (1, N'People, app-managed groups, report grants and audit');

    -- Verify before commit: exactly the seven expected tables exist in [portal].
    IF (SELECT COUNT(*) FROM sys.tables WHERE schema_id = SCHEMA_ID(N'portal')) <> 7
        THROW 51000, 'Unexpected [portal] table count; rolling back.', 1;

    COMMIT TRANSACTION;
    SELECT N'portal schema created' AS result, (SELECT COUNT(*) FROM sys.tables WHERE schema_id = SCHEMA_ID(N'portal')) AS tables_created;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
