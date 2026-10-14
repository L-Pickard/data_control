USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Report grants given to a group; every member receives them.
-- Portal data (people and access rights): create only when missing. Unlike warehouse fact tables this file
-- never drops the table, so re-running it cannot wipe permissions. Deploy changes with a migration.

IF OBJECT_ID(N'[portal].[group_report_grants]', N'U') IS NULL
	CREATE TABLE [portal].[group_report_grants] (
		 [group_id] NVARCHAR(64) NOT NULL
		,[report_id] NVARCHAR(64) NOT NULL
		,CONSTRAINT [PK_portal_group_report_grants] PRIMARY KEY CLUSTERED ([group_id], [report_id])
		,CONSTRAINT [FK_portal_group_report_grants_group] FOREIGN KEY ([group_id]) REFERENCES [portal].[groups] ([group_id]) ON DELETE CASCADE
		);

GO
