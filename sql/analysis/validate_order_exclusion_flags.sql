USE [data_control];
GO
-- Compare every current order row directly with the live Finance expressions.
-- Finance definitions and data are read-only throughout.
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql = @sql + N'SELECT N''' + target.table_name + N''' AS table_name, N'''
    + cc.name + N''' AS flag, COUNT_BIG(*) AS rows_checked, '
    + N'SUM(CONVERT(bigint, CASE WHEN [' + cc.name + N'] = '
    + REPLACE(REPLACE(cc.definition, N'[Customer No]', N'[sell_to_customer_id]'),
        N'[Vendor No]', N'[vendor_id]')
    + N' THEN 0 ELSE 1 END)) AS mismatches FROM dbo.'
    + QUOTENAME(target.table_name) + N';'
FROM Finance.sys.computed_columns AS cc
JOIN Finance.sys.tables AS t ON t.object_id = cc.object_id
JOIN (VALUES (N'fOrderbook', N'sales_orders'), (N'fPurchases', N'purchase_orders'))
    AS target(finance_table, table_name) ON target.finance_table = t.name
WHERE cc.name IN (N'Intercompany', N'Exclusion');
-- Each GO batch returns one result set for tools/db-query.ps1.
CREATE TABLE #results (table_name NVARCHAR(128), flag NVARCHAR(128),
    rows_checked BIGINT, mismatches BIGINT);
INSERT INTO #results EXEC sys.sp_executesql @sql;
SELECT * FROM #results ORDER BY table_name, flag;
IF (SELECT COUNT(*) FROM #results) <> 4
    THROW 50001, 'Expected four Finance order flag definitions.', 1;
IF EXISTS (SELECT 1 FROM #results WHERE mismatches <> 0)
    THROW 50002, 'Order flags differ from Finance rules.', 1;
GO
SELECT t.name AS table_name, c.name AS column_name, ty.name AS data_type,
    c.is_persisted, c.definition
FROM sys.computed_columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE t.name IN (N'sales_orders', N'purchase_orders')
    AND c.name IN (N'intercompany', N'exclusion');
GO
SELECT N'sales_orders' AS table_name, entity, COUNT_BIG(*) AS rows,
    SUM(CONVERT(BIGINT, intercompany)) AS intercompany_rows,
    SUM(CONVERT(BIGINT, exclusion)) AS exclusion_rows
FROM dbo.sales_orders GROUP BY entity
UNION ALL
SELECT N'purchase_orders', entity, COUNT_BIG(*),
    SUM(CONVERT(BIGINT, intercompany)), SUM(CONVERT(BIGINT, exclusion))
FROM dbo.purchase_orders GROUP BY entity;
GO
