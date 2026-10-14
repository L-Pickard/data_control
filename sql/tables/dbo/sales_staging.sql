USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE

IF EXISTS [dbo].[sales_staging];
	CREATE TABLE [dbo].[sales_staging] (
		 [posting_date] DATE NULL
        ,[document_date] DATE NULL
		,[location_code] NVARCHAR(10) NULL
        ,[customer_id] NVARCHAR(20) NULL
		,[document_no] NVARCHAR(20) NULL
        ,[order_no] NVARCHAR(20) NULL
		,[doc_type] NVARCHAR(5) NULL
        ,[salesperson_id] NVARCHAR(20) NULL
        ,[country_id] NVARCHAR(10) NULL
        ,[entity] NVARCHAR(20) NULL
        ,[item_id] NVARCHAR(20) NULL
        ,[currency_code] NVARCHAR(10) NULL
		,[quantity] DECIMAL(38, 20) NULL
		,[sales] DECIMAL(38, 20) NULL
		,[cost] DECIMAL(38, 20) NULL
		,[royalty_value] DECIMAL(38, 20) NULL
		,[customer_rebate_value] DECIMAL(38, 20) NULL
		,[gbp_sales] DECIMAL(38, 20) NULL
		,[gbp_cost] DECIMAL(38, 20) NULL
		,[gbp_royalty] DECIMAL(38, 20) NULL
		,[gbp_rebate] DECIMAL(38, 20) NULL
		,[gbp_margin] DECIMAL(38, 20) NULL
		,[eur_sales] DECIMAL(38, 20) NULL
		,[eur_cost] DECIMAL(38, 20) NULL
		,[eur_royalty] DECIMAL(38, 20) NULL
		,[eur_rebate] DECIMAL(38, 20) NULL
		,[eur_margin] DECIMAL(38, 20) NULL
		,[usd_sales] DECIMAL(38, 20) NULL
		,[usd_cost] DECIMAL(38, 20) NULL
		,[usd_royalty] DECIMAL(38, 20) NULL
		,[usd_rebate] DECIMAL(38, 20) NULL
		,[usd_margin] DECIMAL(38, 20) NULL
		)

