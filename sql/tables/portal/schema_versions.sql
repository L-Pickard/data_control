USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Applied portal schema versions.
-- Portal data (people and access rights): create only when missing. Unlike warehouse fact tables this file
-- never drops the table, so re-running it cannot wipe permissions. Deploy changes with a migration.

IF OBJECT_ID(N'[portal].[schema_versions]', N'U') IS NULL
	CREATE TABLE [portal].[schema_versions] (
		 [version] INT NOT NULL
		,[description] NVARCHAR(200) NOT NULL
		,[applied_at] DATETIMEOFFSET(0) NOT NULL	CONSTRAINT [DF_portal_schema_versions_applied_at] DEFAULT(SYSDATETIMEOFFSET())
		,CONSTRAINT [PK_portal_schema_versions] PRIMARY KEY CLUSTERED ([version])
		);

GO
