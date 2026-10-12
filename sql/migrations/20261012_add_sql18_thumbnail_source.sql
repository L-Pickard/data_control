USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

-- Adds SQL18_THUMBNAIL to the image sources dbo.item_image_locations accepts: the thumbnail folder on SHINERSQL18
-- (\\SHINERSQL18\001 Master Thumbnail Images), which holds a copy of marketing's NAS thumbnails plus the thumbnails
-- made from product photos by scripts/make_item_thumbnails.py. The four existing sources are unchanged and no rows
-- are changed. Run this BEFORE the first morning refresh that scans the SQL18 folder, or that refresh fails (and
-- leaves the previous day's rows in place). Safe to run again.
IF OBJECT_ID(N'dbo.item_image_locations', N'U') IS NULL
	THROW 51020, 'dbo.item_image_locations does not exist.', 1;

BEGIN TRANSACTION;

IF EXISTS (
		SELECT 1

		FROM sys.check_constraints

		WHERE [parent_object_id] = OBJECT_ID(N'dbo.item_image_locations')
			AND [name] = N'CK_item_image_locations_source_code'
		)
	ALTER TABLE [dbo].[item_image_locations] DROP CONSTRAINT [CK_item_image_locations_source_code];

ALTER TABLE [dbo].[item_image_locations]
	WITH CHECK ADD CONSTRAINT [CK_item_image_locations_source_code] CHECK (
			[source_code] IN (
				N'SP_PRODUCT'
				,N'SP_THUMBNAIL'
				,N'NAS_ITEM_DOCS'
				,N'NAS_THUMBNAIL'
				,N'SQL18_THUMBNAIL'
				)
			);

COMMIT TRANSACTION;

GO

SELECT cc.[name]
	,cc.[definition]
	,cc.[is_not_trusted]

FROM sys.check_constraints AS cc

WHERE cc.[parent_object_id] = OBJECT_ID(N'dbo.item_image_locations')
	AND cc.[name] = N'CK_item_image_locations_source_code';

GO
