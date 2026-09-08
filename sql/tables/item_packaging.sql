USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE

IF EXISTS [dbo].[item_packaging]
	CREATE TABLE [dbo].[item_packaging] (
		 [item_id] NVARCHAR(30) NOT NULL
		,[brand_id] AS CAST(LEFT([item_id], 3) AS NVARCHAR(20)) PERSISTED
		,[category] NVARCHAR(200) NOT NULL
		,[article_type] NVARCHAR(200) NOT NULL
		,[instance] INTEGER NOT NULL
		,[component_type] NVARCHAR(100) NULL
		,[material] NVARCHAR(100) NULL
		,[grading] NVARCHAR(50) NULL
		,[rigid] AS CASE 
			WHEN [category] = 'Secondary Packaging Per Carton'
				AND [article_type] LIKE '%plastic%'
				THEN 'Flexible'
			WHEN [component_type] = 'TUBE'
				OR [component_type] = 'Container'
				OR [component_type] = 'Closure'
				OR [component_type] = 'Inner Blister'
				OR [component_type] = 'Handle'
				OR [component_type] = 'Hook'
				OR [component_type] = 'Insert'
				OR [component_type] = 'Blister Pack'
				THEN 'Rigid'
			WHEN [component_type] = 'Mesh Bag'
				OR [component_type] = 'Tape'
				OR [component_type] = 'Cover'
				OR [component_type] = 'String'
				OR [component_type] = 'Film'
				OR [component_type] = 'Window'
				OR [component_type] = 'Protector'
				OR [component_type] = 'Shrink Wrap'
				OR [component_type] = 'Sheet'
				OR [component_type] = 'Polybag'
				OR [component_type] = 'Kimble'
				OR [component_type] = 'Bag'
				OR [component_type] = 'Cable Tie'
				THEN 'Flexible'
			END
		,[recycled_content] BIT NULL
		,[%_recycled_content] DECIMAL(38, 20) NULL
        ,[avg_carton_qty] DECIMAL(38, 20) NULL
		,[weight_kg] DECIMAL(38, 20) NULL
		);

CREATE CLUSTERED INDEX [IX_item_packaging_item_instance]
	ON [dbo].[item_packaging] ([item_id], [instance]);

-- CREATE NONCLUSTERED INDEX [IX_item_packaging_brand_id]
-- 	ON [dbo].[item_packaging] ([brand_id])
-- 	INCLUDE ([item_id], [category], [article_type], [rigid], [recycled_content], [weight_kg]);

GO
