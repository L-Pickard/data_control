USE [data_control];

GO

-- [portal] holds the Shiner web portal's own data (people, app-managed groups, report grants, audit and saved
-- bookmarks), separate from the warehouse objects in [dbo] and [planning].
-- The portal's runtime identity needs SELECT, INSERT, UPDATE and DELETE on this schema only (see the portal repo's
-- docs/deployment/iis.md); it should stay read-only on [dbo].
IF SCHEMA_ID(N'portal') IS NULL
	EXEC (N'CREATE SCHEMA [portal] AUTHORIZATION [dbo];');

GO
