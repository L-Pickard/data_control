USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- People who use the portal, identified by Windows SID; display_name is DOMAIN
ame as last seen.
-- Portal data (people and access rights): create only when missing. Unlike warehouse fact tables this file
-- never drops the table, so re-running it cannot wipe permissions. Deploy changes with a migration.

IF OBJECT_ID(N'[portal].[users]', N'U') IS NULL
	CREATE TABLE [portal].[users] (
		 [user_id] NVARCHAR(184) NOT NULL
		,[display_name] NVARCHAR(256) NOT NULL
		,[is_enabled] BIT NOT NULL
		,[is_admin] BIT NOT NULL
		,[last_seen_at] DATETIMEOFFSET(0) NULL
		,[created_at] DATETIMEOFFSET(0) NOT NULL	CONSTRAINT [DF_portal_users_created_at] DEFAULT(SYSDATETIMEOFFSET())
		,CONSTRAINT [PK_portal_users] PRIMARY KEY CLUSTERED ([user_id])
		);

GO
