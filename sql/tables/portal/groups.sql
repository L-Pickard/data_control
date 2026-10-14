USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Groups managed inside the portal (not Active Directory groups).
-- Portal data (people and access rights): create only when missing. Unlike warehouse fact tables this file
-- never drops the table, so re-running it cannot wipe permissions. Deploy changes with a migration.

IF OBJECT_ID(N'[portal].[groups]', N'U') IS NULL
	CREATE TABLE [portal].[groups] (
		 [group_id] NVARCHAR(64) NOT NULL
		,[name] NVARCHAR(100) NOT NULL
		,CONSTRAINT [PK_portal_groups] PRIMARY KEY CLUSTERED ([group_id])
		,CONSTRAINT [UQ_portal_groups_name] UNIQUE ([name])
		);

GO
