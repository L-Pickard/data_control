USE [data_control];
GO
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

-- Exercise the actual refresh without retaining the synthetic sale or staging.
IF OBJECT_ID(N'dbo.sales_staging', N'U') IS NOT NULL
    THROW 51000, 'Existing sales staging must not be overwritten by this test.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    SELECT TOP (1)
        posting_date, document_date, location_code, customer_id,
        CAST(N'CODEX_NULL_ORDER' AS NVARCHAR(20)) AS document_no,
        CAST(NULL AS NVARCHAR(20)) AS order_no,
        doc_type, salesperson_id, country_id, entity, item_id,
        CAST(N'GBP' AS NVARCHAR(10)) AS currency_code,
        quantity, gbp_sales AS sales, gbp_cost AS cost,
        gbp_royalty AS royalty_value, gbp_rebate AS customer_rebate_value,
        gbp_sales, gbp_cost, gbp_royalty, gbp_rebate, gbp_margin,
        eur_sales, eur_cost, eur_royalty, eur_rebate, eur_margin,
        usd_sales, usd_cost, usd_royalty, usd_rebate, usd_margin
    INTO dbo.sales_staging
    FROM dbo.sales
    WHERE entity = N'Shiner Ltd'
        AND posting_date = (SELECT MAX(posting_date) FROM dbo.sales WHERE entity = N'Shiner Ltd');

    IF @@ROWCOUNT <> 1
        THROW 51001, 'Test requires an existing Ltd sale.', 1;

    EXEC dbo.update_sales_table;

    IF NOT EXISTS (SELECT 1 FROM dbo.sales
                   WHERE document_no = N'CODEX_NULL_ORDER' AND order_no = N'')
        THROW 51002, 'NULL order was not inserted as a blank order.', 1;

    IF OBJECT_ID(N'dbo.sales_staging', N'U') IS NOT NULL
        THROW 51003, 'Refresh did not complete staging cleanup.', 1;

    ROLLBACK TRANSACTION;
    SELECT N'PASS: NULL-order sale loaded; all test changes rolled back.' AS result;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

