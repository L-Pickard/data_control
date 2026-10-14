USE [data_control];

GO

DROP TABLE IF EXISTS [dbo].[inventory]

BEGIN
	CREATE TABLE [dbo].[inventory] (
		 [entity] NVARCHAR(20) NOT NULL
		,[item_id] NVARCHAR(20) NOT NULL
		,[brand_id] AS CAST(LEFT([item_id], 3) AS NVARCHAR(20)) PERSISTED
		,[inventory] DECIMAL(38, 20) NOT NULL
		,[buffer_stock] DECIMAL(38, 20) NOT NULL
		,[reserved_quantity] DECIMAL(38, 20) NOT NULL
		,[unavailable_quantity] DECIMAL(38, 20) NOT NULL
		,[free_stock] AS CAST([inventory] - [buffer_stock] - [reserved_quantity] - [unavailable_quantity] AS DECIMAL(38, 20)) PERSISTED
		,[refreshed_at] DATETIME2(7) NOT NULL CONSTRAINT [DF_inventory_refreshed_at] DEFAULT(SYSDATETIME())
		,CONSTRAINT [PK_inventory] PRIMARY KEY CLUSTERED (
			 [entity]
			,[item_id]
			)
		,CONSTRAINT [FK_inventory_entities] FOREIGN KEY ([entity]) REFERENCES [dbo].[entities]([entity])
		,CONSTRAINT [FK_inventory_items] FOREIGN KEY ([item_id]) REFERENCES [dbo].[items]([item_id])
		,CONSTRAINT [FK_inventory_brands] FOREIGN KEY ([brand_id]) REFERENCES [dbo].[brands]([brand_id])
		,CONSTRAINT [CK_inventory_nonnegative_inventory] CHECK ([inventory] >= 0)
		,CONSTRAINT [CK_inventory_nonnegative_deductions] CHECK (
			[buffer_stock] >= 0
			AND [reserved_quantity] >= 0
			AND [unavailable_quantity] >= 0
			)
		);

	CREATE NONCLUSTERED INDEX [IX_inventory_brand_entity] ON [dbo].[inventory] (
		 [brand_id]
		,[entity]
		) INCLUDE (
		[item_id]
		,[inventory]
		,[free_stock]
		);

	CREATE NONCLUSTERED INDEX [IX_inventory_free_stock] ON [dbo].[inventory] (
		 [entity]
		,[free_stock]
		) INCLUDE (
		 [item_id]
		,[brand_id]
		,[inventory]
		);

END;

GO