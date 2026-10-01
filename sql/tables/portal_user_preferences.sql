USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- One row per person: their own portal settings (theme, date and number formats, start page, favourites, remembered
-- view choices) as JSON validated by the portal, and their profile picture (a 256 x 256 PNG checked and rebuilt by the
-- portal before saving; at most 600 KB). Only the person themselves reads or changes their row through the portal.
-- Removing a person removes their preferences.
-- Portal data: create only when missing. This file never drops the table. Deploy changes with a migration.

IF OBJECT_ID(N'[portal].[user_preferences]', N'U') IS NULL
BEGIN
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
END

GO
