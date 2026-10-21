USE [data_control];

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO

DROP TABLE IF EXISTS [dbo].[potential_sell_through]

BEGIN
	CREATE TABLE [dbo].[potential_sell_through](
          [brand_id] NVARCHAR(20) NOT NULL
         ,[item_id] NVARCHAR(20) NOT NULL
         ,[pst_id] INTEGER NOT NULL
         ,[inventory] DECIMAL(38, 20) NOT NULL
         ,[po_quantity] DECIMAL(38, 20) NOT NULL
         ,[so_quantity] DECIMAL(38, 20) NOT NULL
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
         ,[shipped_6M_30_day_avg] AS CAST([shipped_last_180_days] / 6.0 AS DECIMAL(38, 20)) PERSISTED
         ,[shipped_12M_30_day_avg] AS CAST([shipped_last_360_days] / 12.0 AS DECIMAL(38, 20)) PERSISTED
		,CONSTRAINT [FK_pst_items] FOREIGN KEY ([item_id]) REFERENCES [dbo].[items]([item_id])
		,CONSTRAINT [FK_pst_brands] FOREIGN KEY ([brand_id]) REFERENCES [dbo].[brands]([brand_id])
        ,CONSTRAINT [FK_pst_reports] FOREIGN KEY ([pst_id]) REFERENCES [portal].[pst_reports]([pst_id])
        ,CONSTRAINT [PK_potential_sell_through] PRIMARY KEY CLUSTERED ([pst_id], [item_id])
		);

    CREATE NONCLUSTERED INDEX [IX_pst_report_brand]
        ON [dbo].[potential_sell_through] ([pst_id], [brand_id])
        INCLUDE ([inventory], [po_quantity], [so_quantity],
                 [shipped_last_360_days], [shipped_last_180_days],
                 [shipped_6M_30_day_avg], [shipped_12M_30_day_avg]);

END;

GO
