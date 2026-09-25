-- Run after deployment. The single-row write smoke test always rolls back.
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
    IF EXISTS (SELECT 1 FROM dbo.sales WHERE document_no=N'__BIN_TEST_20260924')
        THROW 51000, 'Test document already exists; choose a different fixture ID.', 1;
    INSERT dbo.sales ([posting_date], [document_date], [location_code], [customer_id], [document_no], [order_no], [doc_type], [salesperson_id], [country_id], [entity], [is_adjusted], [exclusion], [intercompany], [sales_type], [item_id], [quantity], [gbp_sales], [gbp_cost], [gbp_royalty], [gbp_rebate], [gbp_margin], [gbp_adjusted_margin], [eur_sales], [eur_cost], [eur_royalty], [eur_rebate], [eur_margin], [eur_adjusted_margin], [usd_sales], [usd_cost], [usd_royalty], [usd_rebate], [usd_margin], [usd_adjusted_margin])
    SELECT TOP (1) [posting_date], [document_date], [location_code], [customer_id], N'__BIN_TEST_20260924', [order_no], [doc_type], [salesperson_id], [country_id], [entity], [is_adjusted], [exclusion], [intercompany], [sales_type], [item_id], [quantity], [gbp_sales], [gbp_cost], [gbp_royalty], [gbp_rebate], [gbp_margin], [gbp_adjusted_margin], [eur_sales], [eur_cost], [eur_royalty], [eur_rebate], [eur_margin], [eur_adjusted_margin], [usd_sales], [usd_cost], [usd_royalty], [usd_rebate], [usd_margin], [usd_adjusted_margin] FROM dbo.sales;
    IF @@ROWCOUNT<>1 THROW 51000, 'No sales row available for the smoke test.', 1;
    UPDATE dbo.sales SET doc_type=N'TEST5' WHERE document_no=N'__BIN_TEST_20260924';
    IF NOT EXISTS (SELECT 1 FROM dbo.sales WHERE document_no=N'__BIN_TEST_20260924' AND doc_type=N'TEST5')
        THROW 51000, 'Five-character document type was not preserved.', 1;
    UPDATE dbo.sales
    SET entity=N'Shiner Ltd', doc_type=N'SI', gbp_sales=100, gbp_adjusted_margin=30,
        eur_sales=-100, eur_adjusted_margin=-34,
        usd_sales=0, usd_adjusted_margin=10
    WHERE document_no=N'__BIN_TEST_20260924';
    IF NOT EXISTS (
        SELECT 1 FROM dbo.sales WITH (INDEX(IX_sales_entity_posting_date))
        WHERE document_no=N'__BIN_TEST_20260924'
          AND margin_bin=3)
        THROW 51000, 'Live indexed bin maintenance failed.', 1;
    UPDATE dbo.sales SET entity=N'Shiner B.V' WHERE document_no=N'__BIN_TEST_20260924';
    IF NOT EXISTS (SELECT 1 FROM dbo.sales WHERE document_no=N'__BIN_TEST_20260924' AND margin_bin=4)
        THROW 51000, 'Entity change did not select EUR margin.', 1;
    UPDATE dbo.sales SET entity=N'Shiner LLC' WHERE document_no=N'__BIN_TEST_20260924';
    IF NOT EXISTS (SELECT 1 FROM dbo.sales WHERE document_no=N'__BIN_TEST_20260924' AND margin_bin=127)
        THROW 51000, 'Entity change did not select USD zero-sales bin.', 1;
    UPDATE dbo.sales SET entity=N'Shiner Ltd' WHERE document_no=N'__BIN_TEST_20260924';
    UPDATE dbo.sales SET gbp_adjusted_margin=34
    WHERE document_no=N'__BIN_TEST_20260924';
    IF NOT EXISTS (SELECT 1 FROM dbo.sales WHERE document_no=N'__BIN_TEST_20260924' AND margin_bin=4)
        THROW 51000, 'Live adjusted-margin update did not maintain its bin.', 1;
    UPDATE dbo.sales SET gbp_sales=200
    WHERE document_no=N'__BIN_TEST_20260924';
    IF NOT EXISTS (SELECT 1 FROM dbo.sales WHERE document_no=N'__BIN_TEST_20260924' AND margin_bin=2)
        THROW 51000, 'Live sales-only update did not maintain its bin.', 1;
    DELETE dbo.sales WHERE document_no=N'__BIN_TEST_20260924';
    IF @@ROWCOUNT<>1 THROW 51000, 'Live test delete failed.', 1;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
SELECT 'PASS: live insert, entity/margin/sales updates, index maintenance and delete; all writes rolled back' AS result;
GO
SELECT c.column_id,c.name,c.is_persisted,
    COLUMNPROPERTY(c.object_id,c.name,'IsDeterministic') AS deterministic,
    COLUMNPROPERTY(c.object_id,c.name,'IsPrecise') AS precise
FROM sys.computed_columns c WHERE c.object_id=OBJECT_ID('dbo.sales')
    AND c.name = 'margin_bin';
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id IN (OBJECT_ID('dbo.sales'),OBJECT_ID('dbo.sales_margin_bins'))
    AND name IN ('gbp_margin_bin','eur_margin_bin','usd_margin_bin','gbp_margin_bin_label','eur_margin_bin_label','usd_margin_bin_label'))
    THROW 51000, 'Legacy currency-bin columns remain.', 1;
IF NOT EXISTS (
    SELECT 1 FROM sys.columns b JOIN sys.columns q ON b.object_id=q.object_id
    WHERE b.object_id=OBJECT_ID('dbo.sales') AND b.name='margin_bin' AND q.name='quantity'
        AND b.column_id=q.column_id+1)
    THROW 51000, 'margin_bin must immediately follow quantity.', 1;
-- Representative app query: one entity and a date range, aggregating stored bins.
DECLARE @started DATETIME2=SYSUTCDATETIME();
SELECT margin_bin, margin_bin_label, COUNT_BIG(*) AS sales_line_count,
    SUM(gbp_sales) AS sales, SUM(gbp_adjusted_margin) AS adjusted_margin
INTO #app_bins
FROM dbo.sales_margin_bins
WHERE entity=N'Shiner Ltd' AND posting_date>='20260501' AND posting_date<'20270501'
GROUP BY margin_bin,margin_bin_label;
DECLARE @elapsed_ms INT=DATEDIFF(MILLISECOND,@started,SYSUTCDATETIME());
IF EXISTS (
    SELECT SUM(sales_line_count),SUM(sales),SUM(adjusted_margin) FROM #app_bins
    EXCEPT
    SELECT COUNT_BIG(*),SUM(gbp_sales),SUM(gbp_adjusted_margin) FROM dbo.sales
    WHERE entity=N'Shiner Ltd' AND posting_date>='20260501' AND posting_date<'20270501'
      AND intercompany=0 AND exclusion=0
      AND NOT (customer_id IN (N'CU100487',N'CU108312')
        AND brand_id IN (N'BSC',N'BUU',N'CRE',N'KRX',N'MOB',N'OJW',N'RIC',N'SLM',N'SCR',N'IND',N'NHS'))
) THROW 51000, 'App aggregate differs from the source totals.', 1;
SELECT 'PASS: app aggregate matches source totals' AS result,
    SUM(sales_line_count) AS sales_lines,COUNT(*) AS bins,@elapsed_ms AS elapsed_ms
FROM #app_bins;
GO
SELECT margin_bin,margin_bin_label,sales_line_count,
    CONVERT(DECIMAL(20,2),sales) AS sales,
    CONVERT(DECIMAL(20,2),adjusted_margin) AS adjusted_margin
FROM #app_bins ORDER BY margin_bin;
