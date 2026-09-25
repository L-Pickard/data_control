USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
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
        ,[margin_bin] AS (CASE [entity]
            WHEN N'Shiner Ltd' THEN CONVERT(SMALLINT, CASE
            WHEN [gbp_sales] = 0 THEN 127
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= -ABS([gbp_sales]) THEN -10
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * -0.9 THEN -9
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * -0.8 THEN -8
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * -0.7 THEN -7
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * -0.6 THEN -6
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * -0.5 THEN -5
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * -0.4 THEN -4
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * -0.3 THEN -3
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * -0.2 THEN -2
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * -0.1 THEN -1
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= 0 THEN 0
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * 0.1 THEN 1
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * 0.2 THEN 2
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * 0.3 THEN 3
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * 0.4 THEN 4
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * 0.5 THEN 5
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * 0.6 THEN 6
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * 0.7 THEN 7
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * 0.8 THEN 8
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) * 0.9 THEN 9
            WHEN (CASE WHEN [gbp_sales] < 0 THEN -[gbp_adjusted_margin] ELSE [gbp_adjusted_margin] END) <= ABS([gbp_sales]) THEN 10
            ELSE 11 END)
            WHEN N'Shiner B.V' THEN CONVERT(SMALLINT, CASE
            WHEN [eur_sales] = 0 THEN 127
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= -ABS([eur_sales]) THEN -10
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * -0.9 THEN -9
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * -0.8 THEN -8
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * -0.7 THEN -7
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * -0.6 THEN -6
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * -0.5 THEN -5
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * -0.4 THEN -4
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * -0.3 THEN -3
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * -0.2 THEN -2
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * -0.1 THEN -1
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= 0 THEN 0
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * 0.1 THEN 1
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * 0.2 THEN 2
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * 0.3 THEN 3
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * 0.4 THEN 4
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * 0.5 THEN 5
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * 0.6 THEN 6
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * 0.7 THEN 7
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * 0.8 THEN 8
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) * 0.9 THEN 9
            WHEN (CASE WHEN [eur_sales] < 0 THEN -[eur_adjusted_margin] ELSE [eur_adjusted_margin] END) <= ABS([eur_sales]) THEN 10
            ELSE 11 END)
            WHEN N'Shiner LLC' THEN CONVERT(SMALLINT, CASE
            WHEN [usd_sales] = 0 THEN 127
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= -ABS([usd_sales]) THEN -10
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * -0.9 THEN -9
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * -0.8 THEN -8
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * -0.7 THEN -7
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * -0.6 THEN -6
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * -0.5 THEN -5
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * -0.4 THEN -4
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * -0.3 THEN -3
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * -0.2 THEN -2
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * -0.1 THEN -1
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= 0 THEN 0
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * 0.1 THEN 1
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * 0.2 THEN 2
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * 0.3 THEN 3
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * 0.4 THEN 4
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * 0.5 THEN 5
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * 0.6 THEN 6
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * 0.7 THEN 7
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * 0.8 THEN 8
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) * 0.9 THEN 9
            WHEN (CASE WHEN [usd_sales] < 0 THEN -[usd_adjusted_margin] ELSE [usd_adjusted_margin] END) <= ABS([usd_sales]) THEN 10
            ELSE 11 END)
            ELSE CONVERT(SMALLINT, 127)
        END) PERSISTED
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

-- One bin per sale: Ltd uses GBP, B.V uses EUR, LLC uses USD.
-- Adjusted margin / sales, with upper-inclusive 10-point bands.
-- -10 = <= -100%; -9..10 = (previous boundary, upper boundary];
-- 11 = > 100%; 127 = undefined (zero sales or unmapped entity). The bin is also its sort key.
-- Compare amounts rather than a rounded percentage; returns use the sales sign.

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
	,[margin_bin]
	);

-- Supports same-calendar-date previous-year sales and adjusted margin cards.

CREATE NONCLUSTERED INDEX [IX_sales_card_date_key_ny_entity]
ON [dbo].[sales] (
	 [date_key_ny]
	,[entity]
	)
INCLUDE (
	 [brand_id]
	,[country_id]
	,[sales_type]
	,[gbp_sales]
	,[eur_sales]
	,[usd_sales]
	,[gbp_adjusted_margin]
	,[eur_adjusted_margin]
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
WHERE [entity] = N'Shiner B.V'
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
WHERE [entity] = N'Shiner Ltd'
	AND [customer_id] = N'CU109441'
	AND [doc_type] = N'SI';

GO
