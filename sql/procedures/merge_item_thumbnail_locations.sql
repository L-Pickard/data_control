USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

-- Adds thumbnail files in the SQL18 thumbnail folder to the image catalogue, between the morning refreshes.
-- scripts/make_item_thumbnails.py writes the files it copied or made to dbo.item_thumbnail_locations_staging
-- (one row per file: item, file name and key, path and its hash, size, dimensions, modified time) and runs this.
--   * A file whose logical image is not in dbo.item_images yet gets one (image type THUMBNAIL). It becomes the
--     item's primary thumbnail only when the item has none.
--   * Its SQL18_THUMBNAIL location is inserted, or refreshed when the file was written again.
-- Nothing is deleted and no other source's rows are touched. The morning refresh (update_item_images_table)
-- rebuilds both tables from the folders themselves, so these rows only need to be right until then.
CREATE OR ALTER PROCEDURE [dbo].[merge_item_thumbnail_locations]
AS
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	IF OBJECT_ID(N'dbo.item_thumbnail_locations_staging', N'U') IS NULL
		THROW 50011, 'The item_thumbnail_locations_staging table does not exist.', 1;

	IF EXISTS (
			SELECT 1

			FROM [dbo].[item_thumbnail_locations_staging]

			WHERE [item_id] IS NULL
				OR [image_key] IS NULL
				OR [file_name] IS NULL
				OR [location_uri] IS NULL
				OR [location_hash] IS NULL
			)
		THROW 50012, 'A required item thumbnail staging value is NULL.', 1;

	IF EXISTS (
			SELECT 1

			FROM [dbo].[item_thumbnail_locations_staging] AS st

			LEFT JOIN [dbo].[items] AS i
				ON i.[item_id] = st.[item_id]

			WHERE i.[item_id] IS NULL
			)
		THROW 50013, 'The item thumbnail staging table contains an unknown item.', 1;

	IF EXISTS (
			SELECT 1

			FROM [dbo].[item_thumbnail_locations_staging]

			GROUP BY [item_id]
				,[image_key]

			HAVING COUNT(*) > 1
			)
		THROW 50014, 'The item thumbnail staging table contains the same file twice.', 1;

	DECLARE @image_rows INTEGER;

	DECLARE @location_rows INTEGER;

	BEGIN TRANSACTION;

	-- New logical images. Within an item they follow its existing thumbnails, in file-name order.
	INSERT INTO [dbo].[item_images] (
		[item_id]
		,[image_key]
		,[image_type]
		,[file_name]
		,[display_order]
		,[is_primary]
		,[source_modified_at]
		)

	SELECT n.[item_id]
		,n.[image_key]
		,N'THUMBNAIL'
		,n.[file_name]
		,n.[existing_images] + n.[row_no]
		,CASE
			WHEN n.[existing_images] = 0
				AND n.[row_no] = 1
				THEN 1
			ELSE 0
			END
		,n.[last_modified]

	FROM (
		SELECT st.[item_id]
			,st.[image_key]
			,st.[file_name]
			,st.[last_modified]
			,ROW_NUMBER() OVER (
				PARTITION BY st.[item_id] ORDER BY st.[image_key]
				) AS [row_no]
			,(
				SELECT ISNULL(MAX(e.[display_order]), 0)

				FROM [dbo].[item_images] AS e

				WHERE e.[item_id] = st.[item_id]
					AND e.[image_type] = N'THUMBNAIL'
				) AS [existing_images]

		FROM [dbo].[item_thumbnail_locations_staging] AS st

		WHERE NOT EXISTS (
				SELECT 1

				FROM [dbo].[item_images] AS ii

				WHERE ii.[item_id] = st.[item_id]
					AND ii.[image_type] = N'THUMBNAIL'
					AND ii.[image_key] = st.[image_key]
				)
		) AS n;

	SET @image_rows = @@ROWCOUNT;

	-- A file written again (a generated thumbnail made again, or a marketing thumbnail replaced).
	UPDATE il

	SET il.[location_uri] = st.[location_uri]
		,il.[file_size] = st.[file_size]
		,il.[width] = st.[width]
		,il.[height] = st.[height]
		,il.[last_modified] = st.[last_modified]
		,il.[scanned_at] = SYSUTCDATETIME()

	FROM [dbo].[item_image_locations] AS il

	INNER JOIN [dbo].[item_images] AS ii
		ON ii.[item_image_id] = il.[item_image_id]

	INNER JOIN [dbo].[item_thumbnail_locations_staging] AS st
		ON st.[item_id] = ii.[item_id]
			AND st.[image_key] = ii.[image_key]
			AND st.[location_hash] = il.[location_hash]

	WHERE ii.[image_type] = N'THUMBNAIL'
		AND il.[source_code] = N'SQL18_THUMBNAIL';

	SET @location_rows = @@ROWCOUNT;

	INSERT INTO [dbo].[item_image_locations] (
		[item_image_id]
		,[source_code]
		,[source_file_id]
		,[location_type]
		,[location_uri]
		,[location_hash]
		,[file_size]
		,[width]
		,[height]
		,[last_modified]
		)

	SELECT ii.[item_image_id]
		,N'SQL18_THUMBNAIL'
		,NULL
		,N'UNC'
		,st.[location_uri]
		,st.[location_hash]
		,st.[file_size]
		,st.[width]
		,st.[height]
		,st.[last_modified]

	FROM [dbo].[item_thumbnail_locations_staging] AS st

	INNER JOIN [dbo].[item_images] AS ii
		ON ii.[item_id] = st.[item_id]
			AND ii.[image_type] = N'THUMBNAIL'
			AND ii.[image_key] = st.[image_key]

	WHERE NOT EXISTS (
			SELECT 1

			FROM [dbo].[item_image_locations] AS il

			WHERE il.[item_image_id] = ii.[item_image_id]
				AND il.[source_code] = N'SQL18_THUMBNAIL'
				AND il.[location_hash] = st.[location_hash]
			);

	SET @location_rows += @@ROWCOUNT;

	DROP TABLE [dbo].[item_thumbnail_locations_staging];

	COMMIT TRANSACTION;

	SELECT @image_rows AS [image_rows]
		,@location_rows AS [location_rows];

END;

GO
