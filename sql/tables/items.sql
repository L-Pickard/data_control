USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE

IF EXISTS [dbo].[items]
		CREATE TABLE [dbo].[items] (
		 [item_id] NVARCHAR(20) NOT NULL
		,[is_placeholder] BIT NOT NULL CONSTRAINT [DF_items_is_placeholder] DEFAULT (0)
		,[vendor_reference] NVARCHAR(30) NULL
		,[brand_id] AS CAST(LEFT([item_id], 3) AS NVARCHAR(20)) PERSISTED
		,[description] NVARCHAR(100) NULL
		,[description_2] NVARCHAR(50) NULL
		,[colours] NVARCHAR(120) NULL
		,[size_1] NVARCHAR(10) NULL
		,[size_1_unit] NVARCHAR(5) NULL
		,[eu_size] NVARCHAR(7) NULL
		,[eu_size_unit] NVARCHAR(5) NULL
		,[us_size] NVARCHAR(7) NULL
		,[us_size_unit] NVARCHAR(5) NULL
		,[season] NVARCHAR(10) NULL
		,[item_info] NVARCHAR(100) NULL
		,[category_code] NVARCHAR(20) NULL
		,[group_code] NVARCHAR(20) NULL
		,[ean_barcode] NVARCHAR(13) NULL
		,[tariff_no] NVARCHAR(20) NULL
		,[hts_no] NVARCHAR(20) NULL
		,[gbp_cost] DECIMAL(38, 20) NULL
		,[gbp_trade] DECIMAL(38, 20) NULL
		,[gbp_srp] DECIMAL(38, 20) NULL
		,[eur_cost] DECIMAL(38, 20) NULL
		,[eur_trade] DECIMAL(38, 20) NULL
		,[eur_srp] DECIMAL(38, 20) NULL
		,[usd_cost] DECIMAL(38, 20) NULL
		,[usd_trade] DECIMAL(38, 20) NULL
		,[usd_srp] DECIMAL(38, 20) NULL
		,[royalty] DECIMAL(38, 20) NULL
		,[uk_eu_vendor_no] NVARCHAR(20) NULL
		,[us_vendor_no] NVARCHAR(20) NULL
		,[ltd_blocked] BIT NULL
		,[bv_blocked] BIT NULL
		,[llc_blocked] BIT NULL
		,[pref_sale] BIT NULL
		,[coo] NVARCHAR(10) NULL
		,[unit_of_measure] NVARCHAR(10) NULL
		,[hot_product] BIT NULL
		,[lead_time_days] INTEGER NULL
		,[bread_butter] BIT NULL
		,[ltd_buffer_stock] DECIMAL(38, 20) NULL
		,[bv_buffer_stock] DECIMAL(38, 20) NULL
		,[common_item_no] NVARCHAR(30) NULL
		,[d2c_master_sku] NVARCHAR(30) NULL
		,[d2c_web_item] NVARCHAR(20) NULL
		,[owtanet_export] BIT NULL
		,[web_item] BIT NULL
		,[record_id] VARBINARY(60) NULL
		,CONSTRAINT PK_items PRIMARY KEY CLUSTERED ([item_id])
		,CONSTRAINT FK_items_brand FOREIGN KEY ([brand_id]) REFERENCES [dbo].[brands]([brand_id])
		)

CREATE NONCLUSTERED INDEX [IX_items_brand_id] ON [dbo].[items] ([brand_id]);
