USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Saved report views ("bookmarks"): one person's named combination of slicer selections for one report.
-- filter_json is the report's own normalised filter (validated by the portal before saving); labels_json keeps display
-- names for selected lookup values. A preset period is stored as its id so it stays relative; only custom dates are fixed.
-- At most one default view per person and report (filtered unique index). Removing a person removes their views.
-- Portal data: create only when missing. This file never drops the table. Deploy changes with a migration.

IF OBJECT_ID(N'[portal].[report_bookmarks]', N'U') IS NULL
BEGIN
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
END

GO
