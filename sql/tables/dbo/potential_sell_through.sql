USE [data_control];

GO

DROP TABLE IF EXISTS [dbo].[potential_sell_through]

BEGIN
	CREATE TABLE [dbo].[potential_sell_through](
		  [entity] NVARCHAR(20) NOT NULL
         ,[brand_id] NVARCHAR(20) NOT NULL
         ,[item_id] NVARCHAR(20) NOT NULL
         ,[pst_description] NVARCHAR(50) NOT NULL
         ,[shipped_last_360_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_last_180_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_331-360_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_301-330_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_271-300_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_241-270_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_211-240_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_181-210_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_151-180_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_121-150_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_91-120_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_61-90_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_31-60_days] DECIMAL(38, 20) NOT NULL
         ,[shipped_1-30_days]  DECIMAL(38, 20) NOT NULL
         ,[shipped_30_day_avg] DECIMAL(38, 20) NOT NULL
		,CONSTRAINT [FK_pst_entities] FOREIGN KEY ([entity]) REFERENCES [dbo].[entities]([entity])
		,CONSTRAINT [FK_pst_items] FOREIGN KEY ([item_id]) REFERENCES [dbo].[items]([item_id])
		,CONSTRAINT [FK_pst_brands] FOREIGN KEY ([brand_id]) REFERENCES [dbo].[brands]([brand_id])
		);

	CREATE CLUSTERED INDEX [IX_pst_entity_item]
		ON [dbo].[potential_sell_through] ([entity], [item_id]);

	CREATE NONCLUSTERED INDEX [IX_pst_brand_entity]
		ON [dbo].[potential_sell_through] ([brand_id], [entity])
		INCLUDE ([shipped_last_360_days], [shipped_last_180_days], [shipped_30_day_avg]);

	CREATE NONCLUSTERED INDEX [IX_pst_item]
		ON [dbo].[potential_sell_through] ([item_id]);

END;

GO
