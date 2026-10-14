USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Individual report grants; report_id is the portal's report catalogue id (e.g. 'sales').
-- Portal data (people and access rights): create only when missing. Unlike warehouse fact tables this file
-- never drops the table, so re-running it cannot wipe permissions. Deploy changes with a migration.

IF OBJECT_ID(N'[portal].[user_report_grants]', N'U') IS NULL
	CREATE TABLE [portal].[user_report_grants] (
		 [user_id] NVARCHAR(184) NOT NULL
		,[report_id] NVARCHAR(64) NOT NULL
		,CONSTRAINT [PK_portal_user_report_grants] PRIMARY KEY CLUSTERED ([user_id], [report_id])
		,CONSTRAINT [FK_portal_user_report_grants_user] FOREIGN KEY ([user_id]) REFERENCES [portal].[users] ([user_id]) ON DELETE CASCADE
		);

GO
