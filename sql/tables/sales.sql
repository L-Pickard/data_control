USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE

IF EXISTS [dbo].[sales];
	CREATE TABLE [dbo].[sales] (
		 [date_key]                     AS [dbo].[fnc_date_key]([posting_date]) PERSISTED
		,[date_key_ny]                  AS [dbo].[fnc_date_key](DATEADD(YEAR, 1, [posting_date])) PERSISTED
		,[posting_date]                 DATE NOT NULL
        ,[document_date]                DATE NOT NULL
		,[location_code]                NVARCHAR(10) NOT NULL
        ,[customer_id]                  NVARCHAR(20) NOT NULL
		,[document_no]                  NVARCHAR(20) NOT NULL
        ,[order_no]                     NVARCHAR(20) NOT NULL
        ,[doc_type]                     NVARCHAR(5) NOT NULL
        ,[salesperson_id]               NVARCHAR(20) NOT NULL
        ,[country_id]                   NVARCHAR(10) NOT NULL
        ,[entity]                       NVARCHAR(20) NOT NULL
        ,[is_adjusted]                  BIT NOT NULL
        ,[exclusion]                    BIT NOT NULL
        ,[intercompany]                 BIT NOT NULL
        ,[sales_type]                   NVARCHAR(10) NOT NULL
        ,[brand_id]                     AS CAST(LEFT([item_id], 3) AS NVARCHAR(20)) PERSISTED
        ,[item_id]                      NVARCHAR(20) NOT NULL
        ,[quantity]                     DECIMAL(38, 20) NOT NULL
        ,[gbp_sales]                    DECIMAL(38, 20) NOT NULL
        ,[gbp_cost]                     DECIMAL(38, 20) NOT NULL
        ,[gbp_royalty]                  DECIMAL(38, 20) NOT NULL
        ,[gbp_rebate]                   DECIMAL(38, 20) NOT NULL
        ,[gbp_margin]                   DECIMAL(38, 20) NOT NULL
        ,[gbp_adjusted_margin]          DECIMAL(38, 20) NOT NULL
        ,[eur_sales]                    DECIMAL(38, 20) NOT NULL
        ,[eur_cost]                     DECIMAL(38, 20) NOT NULL
        ,[eur_royalty]                  DECIMAL(38, 20) NOT NULL
        ,[eur_rebate]                   DECIMAL(38, 20) NOT NULL
        ,[eur_margin]                   DECIMAL(38, 20) NOT NULL
        ,[eur_adjusted_margin]          DECIMAL(38, 20) NOT NULL
        ,[usd_sales]                    DECIMAL(38, 20) NOT NULL
        ,[usd_cost]                     DECIMAL(38, 20) NOT NULL
        ,[usd_royalty]                  DECIMAL(38, 20) NOT NULL
        ,[usd_rebate]                   DECIMAL(38, 20) NOT NULL
        ,[usd_margin]                   DECIMAL(38, 20) NOT NULL
        ,[usd_adjusted_margin]          DECIMAL(38, 20) NOT NULL
        ,CONSTRAINT PK_sales PRIMARY KEY CLUSTERED ([posting_date], [location_code], [customer_id], [document_no], [doc_type], [entity], [item_id], [salesperson_id])
        ,CONSTRAINT FK_sales_customers FOREIGN KEY ([customer_id]) REFERENCES [dbo].[customers]([customer_id])
        ,CONSTRAINT FK_sales_sales_people FOREIGN KEY ([salesperson_id]) REFERENCES [dbo].[sales_people](salesperson_id)
        ,CONSTRAINT FK_sales_countries FOREIGN KEY ([country_id]) REFERENCES [dbo].[countries]([country_id])
		,CONSTRAINT FK_sales_brands FOREIGN KEY ([brand_id]) REFERENCES [dbo].[brands]([brand_id])
		,CONSTRAINT FK_sales_entities FOREIGN KEY ([entity]) REFERENCES [dbo].[entities]([entity])
		,CONSTRAINT [FK_sales_dates_date_key] FOREIGN KEY ([date_key]) REFERENCES [dbo].[dates] ([date_key])
		,CONSTRAINT [FK_sales_dates_date_key_ny] FOREIGN KEY ([date_key_ny]) REFERENCES [dbo].[dates] ([date_key])
		)

GO

-- Supports the most common reporting pattern: filtering an entity by a posting
-- date range and then grouping by customer, brand, item or sales type.

CREATE NONCLUSTERED INDEX [IX_sales_entity_posting_date]
ON [dbo].[sales] (
	 [entity]
	,[posting_date]
	)
INCLUDE (
	 [customer_id]
	,[brand_id]
	,[item_id]
	,[sales_type]
	,[exclusion]
	,[intercompany]
	,[gbp_sales]
	,[gbp_adjusted_margin]
	,[eur_sales]
	,[eur_adjusted_margin]
	,[usd_sales]
	,[usd_adjusted_margin]
	);

-- Supports the target/reset side of update_adjusted_margin without indexing
-- entities or document types that the procedure never updates.

CREATE NONCLUSTERED INDEX [IX_sales_adjusted_margin_bv]
ON [dbo].[sales] (
	 [posting_date]
	,[order_no]
	,[item_id]
	,[document_no]
	)
INCLUDE (
	 [customer_id]
	,[quantity]
	,[gbp_margin]
	,[eur_margin]
	,[usd_margin]
	)
WHERE [entity] = N'Example BV'
	AND [doc_type] = N'SI';

-- Supports the fixed Ltd/customer source used by update_adjusted_margin.

CREATE NONCLUSTERED INDEX [IX_sales_adjusted_margin_ltd]
ON [dbo].[sales] (
	 [order_no]
	,[item_id]
	)
INCLUDE (
	 [quantity]
	,[gbp_margin]
	,[eur_margin]
	,[usd_margin]
	)
WHERE [entity] = N'Example Ltd'
	AND [customer_id] = N'CUSTOMER_001'
	AND [doc_type] = N'SI';

GO
