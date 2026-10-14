USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Group membership; removed automatically with the group or user.
-- Portal data (people and access rights): create only when missing. Unlike warehouse fact tables this file
-- never drops the table, so re-running it cannot wipe permissions. Deploy changes with a migration.

IF OBJECT_ID(N'[portal].[group_members]', N'U') IS NULL
	CREATE TABLE [portal].[group_members] (
		 [group_id] NVARCHAR(64) NOT NULL
		,[user_id] NVARCHAR(184) NOT NULL
		,CONSTRAINT [PK_portal_group_members] PRIMARY KEY CLUSTERED ([group_id], [user_id])
		,CONSTRAINT [FK_portal_group_members_group] FOREIGN KEY ([group_id]) REFERENCES [portal].[groups] ([group_id]) ON DELETE CASCADE
		,CONSTRAINT [FK_portal_group_members_user] FOREIGN KEY ([user_id]) REFERENCES [portal].[users] ([user_id]) ON DELETE CASCADE
		);

GO
