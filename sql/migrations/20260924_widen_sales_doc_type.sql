-- Widen doc_type without rebuilding the sales table. Filtered indexes are
-- recreated transactionally; all index definitions and document counts are checked.
USE [data_control];
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
SET NOCOUNT ON;
SET LOCK_TIMEOUT 15000;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.sales')
    AND name='doc_type' AND system_type_id=231 AND max_length=10 AND is_nullable=0)
BEGIN
    SELECT 'PASS: doc_type is already nvarchar(5)' AS result;
    RETURN;
END;
BEGIN TRY
    BEGIN TRANSACTION;
    SELECT doc_type,COUNT_BIG(*) AS rows INTO #documents_before
    FROM dbo.sales WITH (TABLOCKX,HOLDLOCK) GROUP BY doc_type;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.sales')
        AND name='doc_type' AND system_type_id=231 AND max_length=4 AND is_nullable=0)
        THROW 51000, 'Expected existing doc_type nvarchar(2) NOT NULL.', 1;
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
    DROP INDEX [IX_sales_adjusted_margin_bv] ON [dbo].[sales];
    DROP INDEX [IX_sales_adjusted_margin_ltd] ON [dbo].[sales];
    ALTER TABLE [dbo].[sales] ALTER COLUMN [doc_type] NVARCHAR(5) NOT NULL;
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
    IF EXISTS (SELECT * FROM #indexes_before EXCEPT SELECT * FROM #indexes_after)
        OR EXISTS (SELECT * FROM #indexes_after EXCEPT SELECT * FROM #indexes_before)
        THROW 51000, 'Index metadata changed while widening doc_type.', 1;
    SELECT doc_type,COUNT_BIG(*) AS rows INTO #documents_after FROM dbo.sales GROUP BY doc_type;
    IF EXISTS (SELECT * FROM #documents_before EXCEPT SELECT * FROM #documents_after)
        OR EXISTS (SELECT * FROM #documents_after EXCEPT SELECT * FROM #documents_before)
        THROW 51000, 'Document counts or values changed.', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.sales')
        AND name='doc_type' AND system_type_id=231 AND max_length=10 AND is_nullable=0)
        THROW 51000, 'doc_type was not widened correctly.', 1;
    IF OBJECT_ID('dbo.sales_margin_bins','V') IS NOT NULL
        EXEC sys.sp_refreshview N'dbo.sales_margin_bins';
    COMMIT;
    SELECT 'PASS: doc_type widened to nvarchar(5), data and indexes preserved' AS result;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    THROW;
END CATCH;
