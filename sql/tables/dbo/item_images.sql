USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

IF OBJECT_ID(N'dbo.item_images', N'U') IS NULL
BEGIN
	CREATE TABLE [dbo].[item_images] (
		 [item_image_id] BIGINT IDENTITY(1, 1) NOT NULL
		,[item_id] NVARCHAR(20) NOT NULL
		,[image_key] NVARCHAR(255) NOT NULL
		,[image_type] NVARCHAR(20) NOT NULL
		,[file_name] NVARCHAR(255) NOT NULL
		,[display_order] INTEGER NOT NULL CONSTRAINT [DF_item_images_display_order] DEFAULT (1)
		,[is_primary] BIT NOT NULL CONSTRAINT [DF_item_images_is_primary] DEFAULT (0)
		,[source_modified_at] DATETIME2(3) NULL
		,[created_at] DATETIME2(3) NOT NULL CONSTRAINT [DF_item_images_created_at] DEFAULT (SYSUTCDATETIME())
		,[updated_at] DATETIME2(3) NOT NULL CONSTRAINT [DF_item_images_updated_at] DEFAULT (SYSUTCDATETIME())
		,CONSTRAINT [PK_item_images] PRIMARY KEY CLUSTERED ([item_image_id])
		,CONSTRAINT [UQ_item_images_business_key] UNIQUE (
			 [item_id]
			,[image_type]
			,[image_key]
		)
		,CONSTRAINT [FK_item_images_items] FOREIGN KEY ([item_id])
			REFERENCES [dbo].[items] ([item_id])
		,CONSTRAINT [CK_item_images_image_type]
			CHECK ([image_type] IN (N'PRODUCT', N'THUMBNAIL'))
		,CONSTRAINT [CK_item_images_display_order]
			CHECK ([display_order] > 0)
	);

	CREATE NONCLUSTERED INDEX [IX_item_images_item_lookup]
		ON [dbo].[item_images] (
			 [item_id]
			,[image_type]
			,[is_primary]
			,[display_order]
		)
		INCLUDE ([item_image_id], [file_name], [image_key], [source_modified_at]);
END;

GO

IF EXISTS (
	SELECT 1
	FROM sys.check_constraints
	WHERE [parent_object_id] = OBJECT_ID(N'dbo.item_images')
		AND [name] = N'CK_item_images_dimensions'
)
	ALTER TABLE [dbo].[item_images] DROP CONSTRAINT [CK_item_images_dimensions];

IF COL_LENGTH(N'dbo.item_images', N'width') IS NOT NULL
	ALTER TABLE [dbo].[item_images] DROP COLUMN [width];

IF COL_LENGTH(N'dbo.item_images', N'height') IS NOT NULL
	ALTER TABLE [dbo].[item_images] DROP COLUMN [height];

GO

IF NOT EXISTS (
	SELECT 1
	FROM sys.indexes
	WHERE [object_id] = OBJECT_ID(N'dbo.item_images')
		AND [name] = N'UX_item_images_primary'
)
BEGIN
	CREATE UNIQUE NONCLUSTERED INDEX [UX_item_images_primary]
		ON [dbo].[item_images] ([item_id], [image_type])
		WHERE [is_primary] = 1;
END;

GO
