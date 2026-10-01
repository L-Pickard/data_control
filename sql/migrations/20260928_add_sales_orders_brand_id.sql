-- Recreate sales_orders with item-derived brand_id immediately before item_id.
-- Preserve all stored values and existing indexes/constraints; rollback on failure.
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
    IF OBJECT_ID('dbo.sales_orders','U') IS NULL
        THROW 51000, 'sales_orders does not exist.', 1;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.sales_orders') AND name='brand_id')
        THROW 51000, 'brand_id already exists; this is a one-time migration.', 1;
    SELECT [entity], [document_type], [document_no], [line_no], [sell_to_customer_id], [bill_to_customer_id], [your_reference], [ship_to_country_id], [ship_to_code], [document_date], [order_date], [posting_date], [shipment_date], [payment_terms_code], [due_date], [shipment_method_code], [location_code], [country_dimension_code], [brand_dimension_code], [customer_posting_group], [currency_code], [currency_factor], [customer_price_group], [prices_including_vat], [salesperson_id], [vat_country_id], [intercompany_document_no], [shiner_reference], [last_modified], [preorder], [purchase_order_id], [purchase_order_line_no], [drop_shipment], [document_status], [line_type], [gl_account_id], [item_id], [quantity], [outstanding_quantity], [unit_price], [unit_cost], [unit_cost_lcy], [vat_percentage], [line_discount_percentage], [amount], [amount_including_vat], [outstanding_amount], [quantity_shipped], [quantity_invoiced] INTO #orders_before FROM dbo.sales_orders WITH (TABLOCKX,HOLDLOCK);
    DECLARE @rows bigint = (SELECT COUNT_BIG(*) FROM #orders_before);
    IF (SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID('dbo.sales_orders')) <> 54
        THROW 51000, 'Unexpected existing columns.', 1;
    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE referenced_object_id=OBJECT_ID('dbo.sales_orders'))
       OR EXISTS (SELECT 1 FROM sys.sql_expression_dependencies d JOIN sys.objects o ON o.object_id=d.referencing_id
                  WHERE d.referenced_id=OBJECT_ID('dbo.sales_orders') AND d.is_schema_bound_reference=1
                  AND d.referencing_id<>d.referenced_id AND o.parent_object_id<>d.referenced_id)
       OR EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id=OBJECT_ID('dbo.sales_orders'))
       OR EXISTS (SELECT 1 FROM sys.database_permissions WHERE class=1 AND major_id=OBJECT_ID('dbo.sales_orders'))
       OR EXISTS (SELECT 1 FROM sys.extended_properties WHERE class IN (1,7) AND major_id=OBJECT_ID('dbo.sales_orders'))
       OR EXISTS (SELECT 1 FROM sys.default_constraints WHERE parent_object_id=OBJECT_ID('dbo.sales_orders'))
       OR EXISTS (SELECT 1 FROM sys.stats WHERE object_id=OBJECT_ID('dbo.sales_orders') AND user_created=1)
       OR EXISTS (SELECT 1 FROM sys.change_tracking_tables WHERE object_id=OBJECT_ID('dbo.sales_orders'))
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id=OBJECT_ID('dbo.sales_orders')
                  AND (is_tracked_by_cdc=1 OR temporal_type<>0 OR is_memory_optimized=1 OR is_replicated=1
                       OR is_merge_published=1 OR is_sync_tran_subscribed=1 OR principal_id IS NOT NULL))
        THROW 51000, 'Unexpected table features require explicit preservation.', 1;
SELECT * INTO #columns_before FROM (SELECT name, system_type_id, user_type_id, max_length, precision, scale,
    is_nullable, ISNULL(collation_name,N'') AS collation_name, is_computed
FROM sys.columns WHERE object_id=OBJECT_ID('dbo.sales_orders')) AS metadata;
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
WHERE i.object_id=OBJECT_ID('dbo.sales_orders')) AS metadata;
SELECT * INTO #fks_before FROM (SELECT f.name, c.name AS column_name, fc.constraint_column_id,
    OBJECT_SCHEMA_NAME(f.referenced_object_id) AS target_schema,
    OBJECT_NAME(f.referenced_object_id) AS target_table, rc.name AS target_column,
    f.delete_referential_action, f.update_referential_action,
    f.is_disabled, f.is_not_trusted, f.is_not_for_replication
FROM sys.foreign_keys f
JOIN sys.foreign_key_columns fc ON fc.constraint_object_id=f.object_id
JOIN sys.columns c ON c.object_id=fc.parent_object_id AND c.column_id=fc.parent_column_id
JOIN sys.columns rc ON rc.object_id=fc.referenced_object_id AND rc.column_id=fc.referenced_column_id
WHERE f.parent_object_id=OBJECT_ID('dbo.sales_orders')) AS metadata;
SELECT name, definition, is_disabled, is_not_trusted, is_not_for_replication INTO #checks_before FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID('dbo.sales_orders');
    DROP TABLE dbo.sales_orders;
    EXEC sys.sp_executesql N'CREATE TABLE [dbo].[sales_orders] (
	 [order_date_key] AS [dbo].[fnc_date_key]([order_date]) PERSISTED
	,[posting_date_key] AS [dbo].[fnc_date_key]([posting_date]) PERSISTED
	,[shipment_date_key] AS [dbo].[fnc_date_key]([shipment_date]) PERSISTED
	,[entity] NVARCHAR(20) NOT NULL
	-- Finance orderbook rules use the sell-to customer.
	-- Non-persisted flags also reflect subsequent dbo.exclusions changes.
	,[exclusion] AS [dbo].[fnc_is_customer_exclusion]([entity], [sell_to_customer_id])
	,[intercompany] AS [dbo].[fnc_is_customer_intercompany]([entity], [sell_to_customer_id])
	,[document_type] INTEGER NOT NULL
	,[document_no] NVARCHAR(20) NOT NULL
	,[line_no] INTEGER NOT NULL
	,[sell_to_customer_id] NVARCHAR(20) NOT NULL
	,[bill_to_customer_id] NVARCHAR(20) NOT NULL
	,[your_reference] NVARCHAR(35) NULL
	,[ship_to_country_id] NVARCHAR(10) NULL
	,[ship_to_code] NVARCHAR(10) NULL
	,[document_date] DATE NULL
	,[order_date] DATE NULL
	,[posting_date] DATE NULL
	,[shipment_date] DATE NULL
	,[payment_terms_code] NVARCHAR(10) NULL
	,[due_date] DATE NULL
	,[shipment_method_code] NVARCHAR(10) NULL
	,[location_code] NVARCHAR(10) NULL
	,[country_dimension_code] NVARCHAR(20) NULL
	,[brand_dimension_code] NVARCHAR(20) NULL
	,[customer_posting_group] NVARCHAR(20) NULL
	,[currency_code] NVARCHAR(10) NOT NULL
	,[currency_factor] DECIMAL(38,20) NULL
	,[customer_price_group] NVARCHAR(10) NULL
	,[prices_including_vat] BIT NOT NULL
	,[salesperson_id] NVARCHAR(20) NULL
	,[vat_country_id] NVARCHAR(10) NULL
	,[intercompany_document_no] NVARCHAR(20) NULL
	,[shiner_reference] NVARCHAR(80) NULL
	,[last_modified] DATETIME NULL
	,[preorder] BIT NOT NULL
	,[purchase_order_id] NVARCHAR(20) NULL
	,[purchase_order_line_no] INTEGER NULL
	,[drop_shipment] BIT NOT NULL
	,[document_status] INTEGER NOT NULL
	,[line_type] INTEGER NOT NULL
	,[gl_account_id] NVARCHAR(20) NULL
	,[brand_id] AS CAST(LEFT([item_id], 3) AS NVARCHAR(20)) PERSISTED
	,[item_id] NVARCHAR(20) NULL
	,[quantity] DECIMAL(38,20) NOT NULL
	,[outstanding_quantity] DECIMAL(38,20) NOT NULL
	,[unit_price] DECIMAL(38,20) NOT NULL
	,[unit_cost] DECIMAL(38,20) NOT NULL
	,[unit_cost_lcy] DECIMAL(38,20) NOT NULL
	,[vat_percentage] DECIMAL(38,20) NOT NULL
	,[line_discount_percentage] DECIMAL(38,20) NOT NULL
	,[amount] DECIMAL(38,20) NOT NULL
	,[amount_including_vat] DECIMAL(38,20) NOT NULL
	,[outstanding_amount] DECIMAL(38,20) NOT NULL
	,[quantity_shipped] DECIMAL(38,20) NOT NULL
	,[quantity_invoiced] DECIMAL(38,20) NOT NULL
	,CONSTRAINT [PK_sales_orders] PRIMARY KEY CLUSTERED (
		 [entity]
		,[document_type]
		,[document_no]
		,[line_no]
	)
	,CONSTRAINT [FK_sales_orders_entities] FOREIGN KEY ([entity]) REFERENCES [dbo].[entities] ([entity])
	,CONSTRAINT [FK_sales_orders_sell_to_customers] FOREIGN KEY ([sell_to_customer_id]) REFERENCES [dbo].[customers] ([customer_id])
	,CONSTRAINT [FK_sales_orders_bill_to_customers] FOREIGN KEY ([bill_to_customer_id]) REFERENCES [dbo].[customers] ([customer_id])
	,CONSTRAINT [FK_sales_orders_sales_people] FOREIGN KEY ([salesperson_id]) REFERENCES [dbo].[sales_people] ([salesperson_id])
	,CONSTRAINT [FK_sales_orders_ship_to_countries] FOREIGN KEY ([ship_to_country_id]) REFERENCES [dbo].[countries] ([country_id])
	,CONSTRAINT [FK_sales_orders_vat_countries] FOREIGN KEY ([vat_country_id]) REFERENCES [dbo].[countries] ([country_id])
	,CONSTRAINT [FK_sales_orders_brands] FOREIGN KEY ([brand_dimension_code]) REFERENCES [dbo].[brands] ([brand_id])
	,CONSTRAINT [FK_sales_orders_items] FOREIGN KEY ([item_id]) REFERENCES [dbo].[items] ([item_id])
	,CONSTRAINT [FK_sales_orders_dates_order_date_key] FOREIGN KEY ([order_date_key]) REFERENCES [dbo].[dates] ([date_key])
	,CONSTRAINT [FK_sales_orders_dates_posting_date_key] FOREIGN KEY ([posting_date_key]) REFERENCES [dbo].[dates] ([date_key])
	,CONSTRAINT [FK_sales_orders_dates_shipment_date_key] FOREIGN KEY ([shipment_date_key]) REFERENCES [dbo].[dates] ([date_key])
	,CONSTRAINT [CK_sales_orders_purchase_order_line] CHECK (
		([purchase_order_id] IS NULL AND [purchase_order_line_no] IS NULL)
		OR ([purchase_order_id] IS NOT NULL AND [purchase_order_line_no] IS NOT NULL)
	)
);

-- Supports customer order-history and customer-service lookups.
CREATE NONCLUSTERED INDEX [IX_sales_orders_customer_order_date]
	ON [dbo].[sales_orders] ([sell_to_customer_id], [order_date], [entity])
	INCLUDE ([document_no], [document_status], [currency_code], [outstanding_amount]);

-- Supports open-order, availability and expected-shipment reporting.
CREATE NONCLUSTERED INDEX [IX_sales_orders_open_item_shipment]
	ON [dbo].[sales_orders] ([item_id], [shipment_date], [entity])
	INCLUDE ([document_no], [line_no], [sell_to_customer_id], [location_code], [outstanding_quantity], [outstanding_amount])
	WHERE [document_type] = 1 AND [outstanding_quantity] <> 0;

-- Supports tracing drop-shipment sales lines back to purchase-order lines.
CREATE NONCLUSTERED INDEX [IX_sales_orders_purchase_order]
	ON [dbo].[sales_orders] ([entity], [purchase_order_id], [purchase_order_line_no])
	INCLUDE ([document_no], [line_no], [item_id], [drop_shipment])
	WHERE [purchase_order_id] IS NOT NULL;

-- Supports bill-to customer lookups and the corresponding foreign key.
CREATE NONCLUSTERED INDEX [IX_sales_orders_bill_to_customer]
	ON [dbo].[sales_orders] ([bill_to_customer_id]);

-- Supports filtering and joining order lines by their item''s brand.
CREATE NONCLUSTERED INDEX [IX_sales_orders_brand_id]
	ON [dbo].[sales_orders] ([brand_id]);

-- Supports financial-period reporting independently of the customer indexes.
CREATE NONCLUSTERED INDEX [IX_sales_orders_posting_date]
	ON [dbo].[sales_orders] ([posting_date_key], [entity])
	INCLUDE ([document_no], [sell_to_customer_id], [item_id], [amount], [amount_including_vat]);';
    INSERT dbo.sales_orders ([entity], [document_type], [document_no], [line_no], [sell_to_customer_id], [bill_to_customer_id], [your_reference], [ship_to_country_id], [ship_to_code], [document_date], [order_date], [posting_date], [shipment_date], [payment_terms_code], [due_date], [shipment_method_code], [location_code], [country_dimension_code], [brand_dimension_code], [customer_posting_group], [currency_code], [currency_factor], [customer_price_group], [prices_including_vat], [salesperson_id], [vat_country_id], [intercompany_document_no], [shiner_reference], [last_modified], [preorder], [purchase_order_id], [purchase_order_line_no], [drop_shipment], [document_status], [line_type], [gl_account_id], [item_id], [quantity], [outstanding_quantity], [unit_price], [unit_cost], [unit_cost_lcy], [vat_percentage], [line_discount_percentage], [amount], [amount_including_vat], [outstanding_amount], [quantity_shipped], [quantity_invoiced]) SELECT [entity], [document_type], [document_no], [line_no], [sell_to_customer_id], [bill_to_customer_id], [your_reference], [ship_to_country_id], [ship_to_code], [document_date], [order_date], [posting_date], [shipment_date], [payment_terms_code], [due_date], [shipment_method_code], [location_code], [country_dimension_code], [brand_dimension_code], [customer_posting_group], [currency_code], [currency_factor], [customer_price_group], [prices_including_vat], [salesperson_id], [vat_country_id], [intercompany_document_no], [shiner_reference], [last_modified], [preorder], [purchase_order_id], [purchase_order_line_no], [drop_shipment], [document_status], [line_type], [gl_account_id], [item_id], [quantity], [outstanding_quantity], [unit_price], [unit_cost], [unit_cost_lcy], [vat_percentage], [line_discount_percentage], [amount], [amount_including_vat], [outstanding_amount], [quantity_shipped], [quantity_invoiced] FROM #orders_before;
    IF (SELECT COUNT_BIG(*) FROM dbo.sales_orders) <> @rows
       OR EXISTS (SELECT [entity], [document_type], [document_no], [line_no], [sell_to_customer_id], [bill_to_customer_id], [your_reference], [ship_to_country_id], [ship_to_code], [document_date], [order_date], [posting_date], [shipment_date], [payment_terms_code], [due_date], [shipment_method_code], [location_code], [country_dimension_code], [brand_dimension_code], [customer_posting_group], [currency_code], [currency_factor], [customer_price_group], [prices_including_vat], [salesperson_id], [vat_country_id], [intercompany_document_no], [shiner_reference], [last_modified], [preorder], [purchase_order_id], [purchase_order_line_no], [drop_shipment], [document_status], [line_type], [gl_account_id], [item_id], [quantity], [outstanding_quantity], [unit_price], [unit_cost], [unit_cost_lcy], [vat_percentage], [line_discount_percentage], [amount], [amount_including_vat], [outstanding_amount], [quantity_shipped], [quantity_invoiced] FROM dbo.sales_orders EXCEPT SELECT [entity], [document_type], [document_no], [line_no], [sell_to_customer_id], [bill_to_customer_id], [your_reference], [ship_to_country_id], [ship_to_code], [document_date], [order_date], [posting_date], [shipment_date], [payment_terms_code], [due_date], [shipment_method_code], [location_code], [country_dimension_code], [brand_dimension_code], [customer_posting_group], [currency_code], [currency_factor], [customer_price_group], [prices_including_vat], [salesperson_id], [vat_country_id], [intercompany_document_no], [shiner_reference], [last_modified], [preorder], [purchase_order_id], [purchase_order_line_no], [drop_shipment], [document_status], [line_type], [gl_account_id], [item_id], [quantity], [outstanding_quantity], [unit_price], [unit_cost], [unit_cost_lcy], [vat_percentage], [line_discount_percentage], [amount], [amount_including_vat], [outstanding_amount], [quantity_shipped], [quantity_invoiced] FROM #orders_before)
       OR EXISTS (SELECT [entity], [document_type], [document_no], [line_no], [sell_to_customer_id], [bill_to_customer_id], [your_reference], [ship_to_country_id], [ship_to_code], [document_date], [order_date], [posting_date], [shipment_date], [payment_terms_code], [due_date], [shipment_method_code], [location_code], [country_dimension_code], [brand_dimension_code], [customer_posting_group], [currency_code], [currency_factor], [customer_price_group], [prices_including_vat], [salesperson_id], [vat_country_id], [intercompany_document_no], [shiner_reference], [last_modified], [preorder], [purchase_order_id], [purchase_order_line_no], [drop_shipment], [document_status], [line_type], [gl_account_id], [item_id], [quantity], [outstanding_quantity], [unit_price], [unit_cost], [unit_cost_lcy], [vat_percentage], [line_discount_percentage], [amount], [amount_including_vat], [outstanding_amount], [quantity_shipped], [quantity_invoiced] FROM #orders_before EXCEPT SELECT [entity], [document_type], [document_no], [line_no], [sell_to_customer_id], [bill_to_customer_id], [your_reference], [ship_to_country_id], [ship_to_code], [document_date], [order_date], [posting_date], [shipment_date], [payment_terms_code], [due_date], [shipment_method_code], [location_code], [country_dimension_code], [brand_dimension_code], [customer_posting_group], [currency_code], [currency_factor], [customer_price_group], [prices_including_vat], [salesperson_id], [vat_country_id], [intercompany_document_no], [shiner_reference], [last_modified], [preorder], [purchase_order_id], [purchase_order_line_no], [drop_shipment], [document_status], [line_type], [gl_account_id], [item_id], [quantity], [outstanding_quantity], [unit_price], [unit_cost], [unit_cost_lcy], [vat_percentage], [line_discount_percentage], [amount], [amount_including_vat], [outstanding_amount], [quantity_shipped], [quantity_invoiced] FROM dbo.sales_orders)
        THROW 51000, 'Restored rows do not match original data.', 1;
SELECT * INTO #columns_after FROM (SELECT name, system_type_id, user_type_id, max_length, precision, scale,
    is_nullable, ISNULL(collation_name,N'') AS collation_name, is_computed
FROM sys.columns WHERE object_id=OBJECT_ID('dbo.sales_orders')) AS metadata;
    DELETE #columns_after WHERE name='brand_id';
    IF EXISTS (SELECT * FROM #columns_before EXCEPT SELECT * FROM #columns_after)
       OR EXISTS (SELECT * FROM #columns_after EXCEPT SELECT * FROM #columns_before)
        THROW 51000, 'Existing columns metadata changed.', 1;
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
WHERE i.object_id=OBJECT_ID('dbo.sales_orders')) AS metadata;
    DELETE #indexes_after WHERE index_name='IX_sales_orders_brand_id';
    IF EXISTS (SELECT * FROM #indexes_before EXCEPT SELECT * FROM #indexes_after)
       OR EXISTS (SELECT * FROM #indexes_after EXCEPT SELECT * FROM #indexes_before)
        THROW 51000, 'Existing indexes metadata changed.', 1;
SELECT * INTO #fks_after FROM (SELECT f.name, c.name AS column_name, fc.constraint_column_id,
    OBJECT_SCHEMA_NAME(f.referenced_object_id) AS target_schema,
    OBJECT_NAME(f.referenced_object_id) AS target_table, rc.name AS target_column,
    f.delete_referential_action, f.update_referential_action,
    f.is_disabled, f.is_not_trusted, f.is_not_for_replication
FROM sys.foreign_keys f
JOIN sys.foreign_key_columns fc ON fc.constraint_object_id=f.object_id
JOIN sys.columns c ON c.object_id=fc.parent_object_id AND c.column_id=fc.parent_column_id
JOIN sys.columns rc ON rc.object_id=fc.referenced_object_id AND rc.column_id=fc.referenced_column_id
WHERE f.parent_object_id=OBJECT_ID('dbo.sales_orders')) AS metadata;
    IF EXISTS (SELECT * FROM #fks_before EXCEPT SELECT * FROM #fks_after)
       OR EXISTS (SELECT * FROM #fks_after EXCEPT SELECT * FROM #fks_before)
        THROW 51000, 'Existing fks metadata changed.', 1;
SELECT name, definition, is_disabled, is_not_trusted, is_not_for_replication INTO #checks_after FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID('dbo.sales_orders');
    IF EXISTS (SELECT * FROM #checks_before EXCEPT SELECT * FROM #checks_after)
       OR EXISTS (SELECT * FROM #checks_after EXCEPT SELECT * FROM #checks_before)
        THROW 51000, 'Existing checks metadata changed.', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.computed_columns b JOIN sys.columns i
                   ON i.object_id=b.object_id AND i.column_id=b.column_id+1
                   WHERE b.object_id=OBJECT_ID('dbo.sales_orders') AND b.name='brand_id'
                     AND b.is_persisted=1 AND i.name='item_id')
        THROW 51000, 'brand_id is not persisted immediately before item_id.', 1;
    EXEC sys.sp_executesql N'
        IF EXISTS (SELECT 1 FROM dbo.sales_orders WHERE brand_id <> LEFT(item_id,3)
                   OR (item_id IS NOT NULL AND brand_id IS NULL) OR (item_id IS NULL AND brand_id IS NOT NULL))
            THROW 51000, ''Incorrect brand values.'', 1;';
    IF NOT EXISTS (SELECT 1 FROM sys.indexes i JOIN sys.index_columns ic
                   ON ic.object_id=i.object_id AND ic.index_id=i.index_id
                   JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
                   WHERE i.object_id=OBJECT_ID('dbo.sales_orders') AND i.name='IX_sales_orders_brand_id'
                     AND i.is_disabled=0 AND ic.key_ordinal=1 AND c.name='brand_id')
        THROW 51000, 'Missing brand index.', 1;
    COMMIT TRANSACTION;
    SELECT @rows AS restored_rows, N'brand_id added and indexed' AS result;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
