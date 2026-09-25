-- One-time migration from three currency bins to one entity-currency bin.
-- Rebuilds dbo.sales so margin_bin is immediately after quantity.
-- Holds writes until commit; validates every existing value, the selected legacy
-- bin, column metadata, indexes and foreign keys. Any error rolls back.
-- Run after 20260924_add_sales_margin_bins.sql and doc_type widening.
USE [data_control];
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;

BEGIN TRY
    BEGIN TRANSACTION;
    IF OBJECT_ID('dbo.sales', 'U') IS NULL
        THROW 51000, 'dbo.sales does not exist.', 1;
    IF COL_LENGTH('dbo.sales', 'margin_bin') IS NOT NULL
        THROW 51000, 'The single margin_bin already exists; this is a one-time migration.', 1;
    IF COL_LENGTH('dbo.sales','gbp_margin_bin') IS NULL OR COL_LENGTH('dbo.sales','eur_margin_bin') IS NULL OR COL_LENGTH('dbo.sales','usd_margin_bin') IS NULL
        THROW 51000, 'Expected the three legacy currency bins.', 1;
    IF OBJECT_ID('dbo.sales_margin_bins', 'V') IS NULL
        THROW 51000, 'Expected the existing reporting view.', 1;

    -- Acquire the lock before inspecting metadata so writers cannot race the copy.
    SELECT [date_key], [date_key_ny], [posting_date], [document_date], [location_code], [customer_id], [document_no], [order_no], [doc_type], [salesperson_id], [country_id], [entity], [is_adjusted], [exclusion], [intercompany], [sales_type], [brand_id], [item_id], [quantity], [gbp_sales], [gbp_cost], [gbp_royalty], [gbp_rebate], [gbp_margin], [gbp_adjusted_margin], [eur_sales], [eur_cost], [eur_royalty], [eur_rebate], [eur_margin], [eur_adjusted_margin], [usd_sales], [usd_cost], [usd_royalty], [usd_rebate], [usd_margin], [usd_adjusted_margin],
        CASE entity WHEN N'Shiner Ltd' THEN gbp_margin_bin WHEN N'Shiner B.V' THEN eur_margin_bin
            WHEN N'Shiner LLC' THEN usd_margin_bin ELSE CONVERT(SMALLINT,127) END AS expected_margin_bin
    INTO #sales_before FROM dbo.sales WITH (TABLOCKX, HOLDLOCK);
    DECLARE @rows BIGINT = (SELECT COUNT_BIG(*) FROM #sales_before);

    -- Fail closed if the live table has acquired features this migration does not script.
    IF (SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID('dbo.sales')) <> 40
        THROW 51000, 'Unexpected sales columns; update the migration before rebuilding.', 1;
    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE referenced_object_id=OBJECT_ID('dbo.sales'))
        OR EXISTS (SELECT 1 FROM sys.sql_expression_dependencies
            WHERE referenced_id=OBJECT_ID('dbo.sales') AND referencing_id<>referenced_id AND is_schema_bound_reference=1)
        THROW 51000, 'Incoming foreign key or schema-bound dependency requires a revised migration.', 1;
    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id=OBJECT_ID('dbo.sales'))
        OR EXISTS (SELECT 1 FROM sys.database_permissions WHERE class=1 AND major_id=OBJECT_ID('dbo.sales'))
        OR EXISTS (SELECT 1 FROM sys.extended_properties WHERE class IN (1,7) AND major_id=OBJECT_ID('dbo.sales'))
        OR EXISTS (SELECT 1 FROM sys.default_constraints WHERE parent_object_id=OBJECT_ID('dbo.sales'))
        OR EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID('dbo.sales'))
        OR EXISTS (SELECT 1 FROM sys.stats WHERE object_id=OBJECT_ID('dbo.sales') AND user_created=1)
        OR EXISTS (SELECT 1 FROM sys.change_tracking_tables WHERE object_id=OBJECT_ID('dbo.sales'))
        OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id=OBJECT_ID('dbo.sales')
            AND (is_tracked_by_cdc=1 OR temporal_type<>0 OR is_memory_optimized=1 OR is_replicated=1
                 OR is_merge_published=1 OR is_sync_tran_subscribed=1 OR principal_id IS NOT NULL))
        THROW 51000, 'Unexpected sales metadata; preserve it explicitly before rebuilding.', 1;

    SELECT * INTO #columns_before FROM (SELECT name, system_type_id, user_type_id, max_length, precision, scale,
    is_nullable, ISNULL(collation_name,N'') AS collation_name, is_computed
FROM sys.columns WHERE object_id=OBJECT_ID('dbo.sales')) AS metadata;
    DELETE FROM #columns_before WHERE name IN ('gbp_margin_bin','eur_margin_bin','usd_margin_bin');
    SELECT * INTO #indexes_before FROM (SELECT i.name AS index_name, i.type, i.is_unique, i.is_primary_key,
    i.is_unique_constraint, i.fill_factor, i.is_padded, i.allow_row_locks, i.allow_page_locks,
    i.is_disabled, ISNULL(i.filter_definition, N'') AS filter_definition,
    ds.name AS data_space, p.partition_number, p.data_compression,
    c.name AS column_name, ic.key_ordinal, ic.is_descending_key, ic.is_included_column
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
JOIN sys.data_spaces ds ON ds.data_space_id=i.data_space_id
JOIN sys.partitions p ON p.object_id=i.object_id AND p.index_id=i.index_id
WHERE i.object_id=OBJECT_ID('dbo.sales')) AS metadata;
    DELETE FROM #indexes_before WHERE index_name='IX_sales_entity_posting_date'
        AND column_name IN ('gbp_margin_bin','eur_margin_bin','usd_margin_bin')
        AND is_included_column=1;
    SELECT * INTO #fks_before FROM (SELECT f.name, c.name AS column_name, fc.constraint_column_id,
    OBJECT_SCHEMA_NAME(f.referenced_object_id) AS target_schema,
    OBJECT_NAME(f.referenced_object_id) AS target_table, rc.name AS target_column,
    f.delete_referential_action, f.update_referential_action,
    f.is_disabled, f.is_not_trusted, f.is_not_for_replication
FROM sys.foreign_keys f
JOIN sys.foreign_key_columns fc ON fc.constraint_object_id=f.object_id
JOIN sys.columns c ON c.object_id=fc.parent_object_id AND c.column_id=fc.parent_column_id
JOIN sys.columns rc ON rc.object_id=fc.referenced_object_id AND rc.column_id=fc.referenced_column_id
WHERE f.parent_object_id=OBJECT_ID('dbo.sales')) AS metadata;

    DROP TABLE [dbo].[sales];
    EXEC sys.sp_executesql N'CREATE TABLE [dbo].[sales] (
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
            WHEN N''Shiner Ltd'' THEN CONVERT(SMALLINT, CASE
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
            WHEN N''Shiner B.V'' THEN CONVERT(SMALLINT, CASE
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
            WHEN N''Shiner LLC'' THEN CONVERT(SMALLINT, CASE
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

';
    EXEC sys.sp_executesql N'INSERT dbo.sales ([posting_date], [document_date], [location_code], [customer_id], [document_no], [order_no], [doc_type], [salesperson_id], [country_id], [entity], [is_adjusted], [exclusion], [intercompany], [sales_type], [item_id], [quantity], [gbp_sales], [gbp_cost], [gbp_royalty], [gbp_rebate], [gbp_margin], [gbp_adjusted_margin], [eur_sales], [eur_cost], [eur_royalty], [eur_rebate], [eur_margin], [eur_adjusted_margin], [usd_sales], [usd_cost], [usd_royalty], [usd_rebate], [usd_margin], [usd_adjusted_margin])
    SELECT [posting_date], [document_date], [location_code], [customer_id], [document_no], [order_no], [doc_type], [salesperson_id], [country_id], [entity], [is_adjusted], [exclusion], [intercompany], [sales_type], [item_id], [quantity], [gbp_sales], [gbp_cost], [gbp_royalty], [gbp_rebate], [gbp_margin], [gbp_adjusted_margin], [eur_sales], [eur_cost], [eur_royalty], [eur_rebate], [eur_margin], [eur_adjusted_margin], [usd_sales], [usd_cost], [usd_royalty], [usd_rebate], [usd_margin], [usd_adjusted_margin] FROM #sales_before;';

    EXEC sys.sp_executesql N'-- One bin per sale: Ltd uses GBP, B.V uses EUR, LLC uses USD.
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
WHERE [entity] = N''Shiner B.V''
	AND [doc_type] = N''SI'';

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
WHERE [entity] = N''Shiner Ltd''
	AND [customer_id] = N''CU109441''
	AND [doc_type] = N''SI'';
';

    EXEC sys.sp_executesql N'IF (SELECT COUNT_BIG(*) FROM dbo.sales) <> (SELECT COUNT_BIG(*) FROM #sales_before)
        THROW 51000, ''Sales row count changed.'', 1;
    IF EXISTS (SELECT [date_key], [date_key_ny], [posting_date], [document_date], [location_code], [customer_id], [document_no], [order_no], [doc_type], [salesperson_id], [country_id], [entity], [is_adjusted], [exclusion], [intercompany], [sales_type], [brand_id], [item_id], [quantity], [gbp_sales], [gbp_cost], [gbp_royalty], [gbp_rebate], [gbp_margin], [gbp_adjusted_margin], [eur_sales], [eur_cost], [eur_royalty], [eur_rebate], [eur_margin], [eur_adjusted_margin], [usd_sales], [usd_cost], [usd_royalty], [usd_rebate], [usd_margin], [usd_adjusted_margin], margin_bin FROM dbo.sales EXCEPT SELECT [date_key], [date_key_ny], [posting_date], [document_date], [location_code], [customer_id], [document_no], [order_no], [doc_type], [salesperson_id], [country_id], [entity], [is_adjusted], [exclusion], [intercompany], [sales_type], [brand_id], [item_id], [quantity], [gbp_sales], [gbp_cost], [gbp_royalty], [gbp_rebate], [gbp_margin], [gbp_adjusted_margin], [eur_sales], [eur_cost], [eur_royalty], [eur_rebate], [eur_margin], [eur_adjusted_margin], [usd_sales], [usd_cost], [usd_royalty], [usd_rebate], [usd_margin], [usd_adjusted_margin], expected_margin_bin FROM #sales_before)
       OR EXISTS (SELECT [date_key], [date_key_ny], [posting_date], [document_date], [location_code], [customer_id], [document_no], [order_no], [doc_type], [salesperson_id], [country_id], [entity], [is_adjusted], [exclusion], [intercompany], [sales_type], [brand_id], [item_id], [quantity], [gbp_sales], [gbp_cost], [gbp_royalty], [gbp_rebate], [gbp_margin], [gbp_adjusted_margin], [eur_sales], [eur_cost], [eur_royalty], [eur_rebate], [eur_margin], [eur_adjusted_margin], [usd_sales], [usd_cost], [usd_royalty], [usd_rebate], [usd_margin], [usd_adjusted_margin], expected_margin_bin FROM #sales_before EXCEPT SELECT [date_key], [date_key_ny], [posting_date], [document_date], [location_code], [customer_id], [document_no], [order_no], [doc_type], [salesperson_id], [country_id], [entity], [is_adjusted], [exclusion], [intercompany], [sales_type], [brand_id], [item_id], [quantity], [gbp_sales], [gbp_cost], [gbp_royalty], [gbp_rebate], [gbp_margin], [gbp_adjusted_margin], [eur_sales], [eur_cost], [eur_royalty], [eur_rebate], [eur_margin], [eur_adjusted_margin], [usd_sales], [usd_cost], [usd_royalty], [usd_rebate], [usd_margin], [usd_adjusted_margin], margin_bin FROM dbo.sales)
        THROW 51000, ''Existing sales values changed.'', 1;';

    SELECT * INTO #columns_after FROM (SELECT name, system_type_id, user_type_id, max_length, precision, scale,
    is_nullable, ISNULL(collation_name,N'') AS collation_name, is_computed
FROM sys.columns WHERE object_id=OBJECT_ID('dbo.sales')) AS metadata;
    DELETE FROM #columns_after WHERE name='margin_bin';
    IF EXISTS (SELECT * FROM #columns_before EXCEPT SELECT * FROM #columns_after)
        OR EXISTS (SELECT * FROM #columns_after EXCEPT SELECT * FROM #columns_before)
        THROW 51000, 'Existing sales column metadata changed.', 1;

    SELECT * INTO #indexes_after FROM (SELECT i.name AS index_name, i.type, i.is_unique, i.is_primary_key,
    i.is_unique_constraint, i.fill_factor, i.is_padded, i.allow_row_locks, i.allow_page_locks,
    i.is_disabled, ISNULL(i.filter_definition, N'') AS filter_definition,
    ds.name AS data_space, p.partition_number, p.data_compression,
    c.name AS column_name, ic.key_ordinal, ic.is_descending_key, ic.is_included_column
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
JOIN sys.data_spaces ds ON ds.data_space_id=i.data_space_id
JOIN sys.partitions p ON p.object_id=i.object_id AND p.index_id=i.index_id
WHERE i.object_id=OBJECT_ID('dbo.sales')) AS metadata;
    -- Only the bin INCLUDE columns change; all other index metadata must match.
    DELETE FROM #indexes_after WHERE index_name='IX_sales_entity_posting_date'
        AND column_name='margin_bin'
        AND is_included_column=1;
    IF EXISTS (SELECT * FROM #indexes_before EXCEPT SELECT * FROM #indexes_after)
        OR EXISTS (SELECT * FROM #indexes_after EXCEPT SELECT * FROM #indexes_before)
        THROW 51000, 'Existing sales index metadata changed.', 1;
    SELECT * INTO #fks_after FROM (SELECT f.name, c.name AS column_name, fc.constraint_column_id,
    OBJECT_SCHEMA_NAME(f.referenced_object_id) AS target_schema,
    OBJECT_NAME(f.referenced_object_id) AS target_table, rc.name AS target_column,
    f.delete_referential_action, f.update_referential_action,
    f.is_disabled, f.is_not_trusted, f.is_not_for_replication
FROM sys.foreign_keys f
JOIN sys.foreign_key_columns fc ON fc.constraint_object_id=f.object_id
JOIN sys.columns c ON c.object_id=fc.parent_object_id AND c.column_id=fc.parent_column_id
JOIN sys.columns rc ON rc.object_id=fc.referenced_object_id AND rc.column_id=fc.referenced_column_id
WHERE f.parent_object_id=OBJECT_ID('dbo.sales')) AS metadata;
    IF EXISTS (SELECT * FROM #fks_before EXCEPT SELECT * FROM #fks_after)
        OR EXISTS (SELECT * FROM #fks_after EXCEPT SELECT * FROM #fks_before)
        THROW 51000, 'Existing foreign key metadata changed.', 1;

    IF (SELECT COUNT(*) FROM sys.computed_columns
        WHERE object_id=OBJECT_ID('dbo.sales') AND name='margin_bin'
          AND is_persisted=1 AND system_type_id=52
          AND COLUMNPROPERTY(object_id,name,'IsDeterministic')=1
          AND COLUMNPROPERTY(object_id,name,'IsPrecise')=1) <> 1
        THROW 51000, 'Expected one precise, deterministic persisted SMALLINT bin.', 1;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.sales')
        AND name IN ('gbp_margin_bin','eur_margin_bin','usd_margin_bin'))
        THROW 51000, 'Legacy bin columns still exist.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns b JOIN sys.columns q ON q.object_id=b.object_id
        WHERE b.object_id=OBJECT_ID('dbo.sales') AND b.name='margin_bin' AND q.name='quantity'
          AND b.column_id=q.column_id+1)
        THROW 51000, 'margin_bin must immediately follow quantity.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM sys.index_columns ic JOIN sys.indexes i
            ON i.object_id=ic.object_id AND i.index_id=ic.index_id
        JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
        WHERE i.object_id=OBJECT_ID('dbo.sales') AND i.name='IX_sales_entity_posting_date'
          AND c.name='margin_bin' AND ic.is_included_column=1)
        THROW 51000, 'Reporting index does not include margin_bin.', 1;

    EXEC sys.sp_executesql N'CREATE OR ALTER VIEW [dbo].[sales_margin_bins]
AS
-- One row per stored sales line; the entity-currency bin is persisted and is its sort key.
-- Keep the supplied report''s external-sales and customer/brand exclusions.
-- Date range is supplied by the caller, rather than fixed in this reusable view.
SELECT s.[date_key]
    ,s.[date_key_ny]
    ,s.[posting_date]
    ,s.[document_date]
    ,s.[location_code]
    ,s.[customer_id]
    ,s.[document_no]
    ,s.[order_no]
    ,s.[doc_type]
    ,s.[salesperson_id]
    ,s.[country_id]
    ,s.[entity]
    ,s.[is_adjusted]
    ,s.[exclusion]
    ,s.[intercompany]
    ,s.[sales_type]
    ,s.[brand_id]
    ,s.[item_id]
    ,s.[quantity]
    ,s.[margin_bin]
    ,CONVERT(VARCHAR(32), CASE
        WHEN s.[margin_bin] = 127 THEN ''Undefined margin''
        WHEN s.[margin_bin] = -10 THEN ''<= -100%''
        WHEN s.[margin_bin] = 11 THEN ''> 100%''
        ELSE CONCAT(''> '', (s.[margin_bin] - 1) * 10, ''% & <= '', s.[margin_bin] * 10, ''%'')
    END) AS [margin_bin_label]
    ,s.[gbp_sales]
    ,s.[gbp_cost]
    ,s.[gbp_royalty]
    ,s.[gbp_rebate]
    ,s.[gbp_margin]
    ,s.[gbp_adjusted_margin]
    ,s.[eur_sales]
    ,s.[eur_cost]
    ,s.[eur_royalty]
    ,s.[eur_rebate]
    ,s.[eur_margin]
    ,s.[eur_adjusted_margin]
    ,s.[usd_sales]
    ,s.[usd_cost]
    ,s.[usd_royalty]
    ,s.[usd_rebate]
    ,s.[usd_margin]
    ,s.[usd_adjusted_margin]
FROM [dbo].[sales] AS s
WHERE s.[intercompany] = 0
    AND s.[exclusion] = 0
    AND NOT (
        s.[customer_id] IN (N''CU100487'', N''CU108312'')
        AND s.[brand_id] IN (N''BSC'', N''BUU'', N''CRE'', N''KRX'', N''MOB'', N''OJW'', N''RIC'', N''SLM'', N''SCR'', N''IND'', N''NHS'')
    );
';
    EXEC sys.sp_refreshview N'planning.external_sales';
    EXEC sys.sp_executesql N'
        IF (SELECT COUNT_BIG(*) FROM dbo.sales_margin_bins) <>
           (SELECT COUNT_BIG(*) FROM dbo.sales
             WHERE intercompany=0 AND exclusion=0
             AND NOT (customer_id IN (N''CU100487'',N''CU108312'')
               AND brand_id IN (N''BSC'',N''BUU'',N''CRE'',N''KRX'',N''MOB'',N''OJW'',N''RIC'',N''SLM'',N''SCR'',N''IND'',N''NHS'')))
            THROW 51000, ''Reporting view row count mismatch.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.sales
           WHERE margin_bin IS NULL OR (margin_bin NOT BETWEEN -10 AND 11 AND margin_bin<>127))
            THROW 51000, ''Invalid persisted bin.'', 1;';
    COMMIT TRANSACTION;
    SELECT 'PASS: one margin_bin after quantity; all sales values, selected bins and metadata preserved' AS result,
        @rows AS preserved_sales_rows;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
