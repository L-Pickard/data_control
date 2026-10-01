USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Workspace-wide portal settings chosen by an application administrator, one row per setting. The first is
-- 'default-theme': the theme people see until they choose their own. updated_by is the administrator's user id
-- (not a foreign key, so the record stays if that person is later removed). Changes are also written to
-- [portal].[audit_events] by the portal.
-- Portal data: create only when missing. This file never drops the table. Deploy changes with a migration.

IF OBJECT_ID(N'[portal].[settings]', N'U') IS NULL
BEGIN
	CREATE TABLE [portal].[settings] (
		 [name] NVARCHAR(64) NOT NULL
		,[value] NVARCHAR(400) NOT NULL
		,[updated_at] DATETIMEOFFSET(3) NOT NULL
		,[updated_by] NVARCHAR(184) NOT NULL
		,CONSTRAINT [PK_portal_settings] PRIMARY KEY CLUSTERED ([name])
		);
END

GO
