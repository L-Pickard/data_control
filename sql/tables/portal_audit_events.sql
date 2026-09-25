USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Append-only record of permission changes; actor is the acting user's SID or 'system'.
-- Portal data (people and access rights): create only when missing. Unlike warehouse fact tables this file
-- never drops the table, so re-running it cannot wipe permissions. Deploy changes with a migration.

IF OBJECT_ID(N'[portal].[audit_events]', N'U') IS NULL
	CREATE TABLE [portal].[audit_events] (
		 [audit_id] BIGINT IDENTITY(1, 1) NOT NULL
		,[occurred_at] DATETIMEOFFSET(3) NOT NULL
		,[actor] NVARCHAR(184) NOT NULL
		,[action] NVARCHAR(4000) NOT NULL
		,CONSTRAINT [PK_portal_audit_events] PRIMARY KEY CLUSTERED ([audit_id])
		);

GO
