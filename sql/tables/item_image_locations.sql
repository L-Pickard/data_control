USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

IF OBJECT_ID(N'dbo.item_image_locations', N'U') IS NULL
BEGIN
	CREATE TABLE [dbo].[item_image_locations] (
		 [image_location_id] BIGINT IDENTITY(1, 1) NOT NULL
		,[item_image_id] BIGINT NOT NULL
		,[source_code] NVARCHAR(30) NOT NULL
		,[source_file_id] NVARCHAR(255) NULL
		,[location_type] NVARCHAR(10) NOT NULL
		,[location_uri] NVARCHAR(2048) NOT NULL
		,[location_hash] BINARY(32) NOT NULL
		,[file_size] BIGINT NULL
		,[width] INTEGER NULL
		,[height] INTEGER NULL
		,[last_modified] DATETIME2(3) NULL
		,[scanned_at] DATETIME2(3) NOT NULL CONSTRAINT [DF_item_image_locations_scanned_at] DEFAULT (SYSUTCDATETIME())
		,CONSTRAINT [PK_item_image_locations] PRIMARY KEY CLUSTERED ([image_location_id])
		,CONSTRAINT [UQ_item_image_locations_business_key] UNIQUE (
			 [item_image_id]
			,[source_code]
			,[location_hash]
		)
		,CONSTRAINT [FK_item_image_locations_item_images] FOREIGN KEY ([item_image_id])
			REFERENCES [dbo].[item_images] ([item_image_id]) ON DELETE CASCADE
		,CONSTRAINT [CK_item_image_locations_source_code]
			CHECK ([source_code] IN (
				 N'SP_PRODUCT'
				,N'SP_THUMBNAIL'
				,N'NAS_ITEM_DOCS'
				,N'NAS_THUMBNAIL'
			))
		,CONSTRAINT [CK_item_image_locations_location_type]
			CHECK ([location_type] IN (N'WEB', N'UNC'))
		,CONSTRAINT [CK_item_image_locations_file_size]
			CHECK ([file_size] IS NULL OR [file_size] >= 0)
		,CONSTRAINT [CK_item_image_locations_dimensions]
			CHECK (
				([width] IS NULL OR [width] > 0)
				AND ([height] IS NULL OR [height] > 0)
			)
	);

	CREATE NONCLUSTERED INDEX [IX_item_image_locations_image_source]
		ON [dbo].[item_image_locations] ([item_image_id], [source_code])
		INCLUDE (
			 [source_file_id]
			,[location_type]
			,[location_uri]
			,[file_size]
			,[width]
			,[height]
			,[last_modified]
		);

	CREATE NONCLUSTERED INDEX [IX_item_image_locations_source_modified]
		ON [dbo].[item_image_locations] ([source_code], [last_modified])
		INCLUDE ([item_image_id], [source_file_id], [file_size]);

	CREATE NONCLUSTERED INDEX [IX_item_image_locations_source_file_id]
		ON [dbo].[item_image_locations] ([source_code], [source_file_id])
		INCLUDE ([item_image_id], [last_modified])
		WHERE [source_file_id] IS NOT NULL;
END;

GO
