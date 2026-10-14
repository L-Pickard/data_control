USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE

IF EXISTS [dbo].[item_inventory_costs];
	CREATE TABLE [dbo].[item_inventory_costs] (
		 [entity] NVARCHAR(20) NOT NULL
		,[item_id] NVARCHAR(20) NOT NULL
		,[brand_id] AS CAST(LEFT([item_id], 3) AS NVARCHAR(20)) PERSISTED
		,[location_code] AS CAST(CASE [entity]
				WHEN 'Shiner Ltd'
					THEN 'BRISTOL'
				WHEN 'Shiner B.V'
					THEN '3PL'
				WHEN 'Shiner LLC'
					THEN 'POMONA'
				ELSE NULL
				END AS NVARCHAR(10)) PERSISTED
		,[first_receipt] DATE NULL
		,[last_receipt] DATE NULL
		,[currency] AS CAST(CASE [entity]
				WHEN 'Shiner Ltd'
					THEN 'GBP'
				WHEN 'Shiner B.V'
					THEN 'EUR'
				WHEN 'Shiner LLC'
					THEN 'USD'
				ELSE NULL
				END AS NVARCHAR(10)) PERSISTED
		,[quantity] DECIMAL(38, 20) NOT NULL
		,[cost] DECIMAL(38, 20) NOT NULL

		,CONSTRAINT [PK_item_inventory_costs] PRIMARY KEY CLUSTERED (
			[entity]
			,[item_id]
			)
		,CONSTRAINT [FK_item_inventory_costs_items] FOREIGN KEY ([item_id]) REFERENCES [dbo].[items]([item_id])
		,CONSTRAINT [FK_item_inventory_costs_brands] FOREIGN KEY ([brand_id]) REFERENCES [dbo].[brands]([brand_id])
		);

GO

DROP INDEX

IF EXISTS [IX_item_inventory_costs_brand_entity]
	ON [dbo].[item_inventory_costs];
	CREATE NONCLUSTERED INDEX [IX_item_inventory_costs_brand_entity] ON [dbo].[item_inventory_costs] (
		[brand_id]
		,[entity]
		) INCLUDE (
		[quantity]
		,[cost]
		,[currency]
		,[location_code]
		);

GO

DROP INDEX

IF EXISTS [IX_item_inventory_costs_location_brand]
	ON [dbo].[item_inventory_costs];
	CREATE NONCLUSTERED INDEX [IX_item_inventory_costs_location_brand] ON [dbo].[item_inventory_costs] (
		[location_code]
		,[brand_id]
		) INCLUDE (
		[quantity]
		,[cost]
		,[currency]
		);

GO
