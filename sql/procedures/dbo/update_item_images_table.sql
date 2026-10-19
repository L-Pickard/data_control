USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

CREATE
	OR

ALTER PROCEDURE [dbo].[update_item_images_table]
AS
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	IF OBJECT_ID(N'dbo.item_image_locations_staging', N'U') IS NULL THROW 50001
		,'The item_image_locations_staging table does not exist.'
		,1;
		IF NOT EXISTS (
				SELECT 1
				
				FROM [dbo].[item_image_locations_staging]
				) THROW 50002
			,'The item image staging table is empty.'
			,1;
			IF EXISTS (
					SELECT 1
					
					FROM [dbo].[item_image_locations_staging]
					
					WHERE [item_id] IS NULL
						OR [image_key] IS NULL
						OR [image_type] IS NULL
						OR [file_name] IS NULL
						OR [display_order] IS NULL
						OR [is_primary] IS NULL
						OR [source_code] IS NULL
						OR [location_type] IS NULL
						OR [location_uri] IS NULL
						OR [location_hash] IS NULL
					) THROW 50003
				,'A required item image staging value is NULL.'
				,1;
				IF EXISTS (
						SELECT 1
						
						FROM [dbo].[item_image_locations_staging] AS st
						
						LEFT JOIN [dbo].[items] AS i
							ON i.[item_id] = st.[item_id]
						
						WHERE i.[item_id] IS NULL
						) THROW 50004
					,'The item image staging table contains an unknown item.'
					,1;
					IF EXISTS (
							SELECT 1
							
							FROM [dbo].[item_image_locations_staging]
							
							GROUP BY [item_id]
								,[image_type]
								,[image_key]
								,[source_code]
								,[location_hash]
							
							HAVING COUNT(*) > 1
							) THROW 50005
						,'The item image staging table contains duplicate locations.'
						,1;
						DECLARE @transaction_started BIT = 0;

	DECLARE @image_rows INTEGER;

	DECLARE @location_rows INTEGER;

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;
		
		END;

		DELETE
		
		FROM [dbo].[item_images];

		INSERT INTO [dbo].[item_images] (
			[item_id]
			,[image_key]
			,[image_type]
			,[file_name]
			,[display_order]
			,[is_primary]
			,[source_modified_at]
			)
		
		SELECT [item_id]
			,[image_key]
			,[image_type]
			,MIN([file_name])
			,MIN([display_order])
			,CAST(MAX(CAST([is_primary] AS TINYINT)) AS BIT)
			,MAX([last_modified])
		
		FROM [dbo].[item_image_locations_staging]
		
		GROUP BY [item_id]
			,[image_key]
			,[image_type];

		SET @image_rows = @@ROWCOUNT;

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
			,st.[source_code]
			,st.[source_file_id]
			,st.[location_type]
			,st.[location_uri]
			,st.[location_hash]
			,st.[file_size]
			,st.[width]
			,st.[height]
			,st.[last_modified]
		
		FROM [dbo].[item_image_locations_staging] AS st
		
		INNER JOIN [dbo].[item_images] AS ii
			ON ii.[item_id] = st.[item_id]
				AND ii.[image_type] = st.[image_type]
				AND ii.[image_key] = st.[image_key];

		SET @location_rows = @@ROWCOUNT;

		DROP TABLE [dbo].[item_image_locations_staging];

		IF @transaction_started = 1
			COMMIT TRANSACTION;

		SELECT @image_rows AS [image_rows]
			,@location_rows AS [location_rows];
	
	END TRY

	BEGIN CATCH
		IF @transaction_started = 1
			AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		THROW;
	
	END CATCH;

END;

GO
