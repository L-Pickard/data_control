# Tests repository computed expressions on session-local tables.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$table = Get-Content (Join-Path $repoRoot 'sql/tables/sales.sql') -Raw
$start = $table.IndexOf('CREATE TABLE [dbo].[sales]')
$end = $table.IndexOf(',CONSTRAINT PK_sales', $start)
$create = $table.Substring($start, $end - $start).TrimEnd() + ');'
$create = $create.Replace('[dbo].[sales]', '#sales_bins_test')
# Local temp tables resolve UDFs in tempdb; these unrelated date columns are fixtures.
$create = $create.Replace('[dbo].[fnc_date_key](DATEADD(YEAR, 1, [posting_date]))', 'CONVERT(INT, CONVERT(CHAR(8), DATEADD(YEAR, 1, [posting_date]), 112))')
$create = $create.Replace('[dbo].[fnc_date_key]([posting_date])', 'CONVERT(INT, CONVERT(CHAR(8), [posting_date], 112))')
$query = @'
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
'@ + [Environment]::NewLine + $create + @'

CREATE INDEX IX_test_bins ON #sales_bins_test(margin_bin);
DECLARE @columns NVARCHAR(MAX), @query NVARCHAR(MAX);
SELECT @columns = STRING_AGG(CONVERT(NVARCHAR(MAX), QUOTENAME(name)), ',')
    WITHIN GROUP (ORDER BY column_id)
FROM tempdb.sys.columns
WHERE object_id = OBJECT_ID('tempdb..#sales_bins_test') AND is_computed = 0;
SET @query = N'INSERT #sales_bins_test (' + @columns + N')
    SELECT TOP (1) ' + @columns + N' FROM dbo.sales;';
EXEC sys.sp_executesql @query;
IF (SELECT COUNT(*) FROM #sales_bins_test) <> 1
    THROW 51000, 'A source sales row is required for the test fixture.', 1;

UPDATE #sales_bins_test SET entity=N'Shiner Ltd',document_no=N'bin_ltd';
SET @query = N'INSERT #sales_bins_test (' + @columns + N') SELECT '
    + REPLACE(REPLACE(@columns,'[entity]',N'N''Shiner B.V'''),'[document_no]',N'N''bin_bv''')
    + N' FROM #sales_bins_test WHERE document_no=N''bin_ltd'';';
EXEC sys.sp_executesql @query;
SET @query = N'INSERT #sales_bins_test (' + @columns + N') SELECT '
    + REPLACE(REPLACE(@columns,'[entity]',N'N''Shiner LLC'''),'[document_no]',N'N''bin_llc''')
    + N' FROM #sales_bins_test WHERE document_no=N''bin_ltd'';';
EXEC sys.sp_executesql @query;
IF (SELECT COUNT(*) FROM #sales_bins_test)<>3 THROW 51000,'Expected one fixture per entity.',1;

DECLARE @cases TABLE (
    id INT IDENTITY, sales DECIMAL(38,20), margin DECIMAL(38,20), expected SMALLINT
);
INSERT @cases(sales, margin, expected) VALUES
    (0, 0, 127), (0, 25, 127), (0, -25, 127),
    (100, -101, -10), (100, -100, -10),
    (100, -99.999999, -9), (100, -90, -9), (100, -89.999999, -8),
    (100, -10, -1), (100, -0.000001, 0), (100, 0, 0),
    (100, 0.000001, 1), (100, 10, 1), (100, 10.000001, 2),
    (100, 26, 3), (100, 30, 3), (100, 30.000001, 4), (100, 34, 4),
    (100, 90, 9), (100, 90.000001, 10), (100, 100, 10), (100, 100.000001, 11),
    (-100, -30, 3), (-100, -30.000001, 4), (-100, 10, -1),
    (-100, 100, -10), (-100, -101, 11),
    (0.000001, 0.0000003, 3), (0.000001, 0.00000030000001, 4),
    (999999999999999999, 999999999999999999, 10);

DECLARE @band INT = -10;
WHILE @band <= 10
BEGIN
    INSERT @cases(sales, margin, expected)
    VALUES (100, @band * 10, @band),
           (-100, -@band * 10, @band),
           (100, @band * 10 + 0.000001, @band + 1),
           (-100, -(@band * 10 + 0.000001), @band + 1),
           (100, @band * 10 - 0.000001, @band),
           (-100, -(@band * 10 - 0.000001), @band);
    SET @band += 1;
END;

DECLARE @id INT = 1, @sales DECIMAL(38,20), @margin DECIMAL(38,20), @expected SMALLINT;
WHILE @id <= (SELECT MAX(id) FROM @cases)
BEGIN
    SELECT @sales = sales, @margin = margin, @expected = expected FROM @cases WHERE id = @id;
    UPDATE #sales_bins_test
    SET gbp_sales = @sales, eur_sales = @sales, usd_sales = @sales,
        gbp_adjusted_margin = @margin, eur_adjusted_margin = @margin, usd_adjusted_margin = @margin;
    IF EXISTS (
        SELECT 1 FROM #sales_bins_test
        WHERE margin_bin <> @expected OR margin_bin IS NULL
    )
    BEGIN
        DECLARE @error NVARCHAR(2048) = CONCAT('Margin bin test failed: case ', @id);
        THROW 51000, @error, 1;
    END;
    SET @id += 1;
END;

-- Deliberately different currency margins prove entity selection.
UPDATE #sales_bins_test SET gbp_sales=100,gbp_adjusted_margin=30,
    eur_sales=100,eur_adjusted_margin=45,usd_sales=100,usd_adjusted_margin=65;
IF EXISTS (SELECT 1 FROM #sales_bins_test WHERE margin_bin<>CASE entity
    WHEN N'Shiner Ltd' THEN 3 WHEN N'Shiner B.V' THEN 5 WHEN N'Shiner LLC' THEN 7 END)
    THROW 51000,'The bin did not use the entity currency.',1;
UPDATE #sales_bins_test SET entity=N'Shiner LLC' WHERE document_no=N'bin_ltd';
IF NOT EXISTS(SELECT 1 FROM #sales_bins_test WHERE document_no=N'bin_ltd' AND margin_bin=7)
    THROW 51000,'Entity-only update did not recalculate the bin.',1;
UPDATE #sales_bins_test SET entity=N'Unknown' WHERE document_no=N'bin_ltd';
IF NOT EXISTS(SELECT 1 FROM #sales_bins_test WHERE document_no=N'bin_ltd' AND margin_bin=127)
    THROW 51000,'Unmapped entity must be undefined.',1;
UPDATE #sales_bins_test SET entity=N'Shiner Ltd' WHERE document_no=N'bin_ltd';
UPDATE #sales_bins_test SET eur_adjusted_margin=99 WHERE document_no=N'bin_ltd';
IF NOT EXISTS(SELECT 1 FROM #sales_bins_test WHERE document_no=N'bin_ltd' AND margin_bin=3)
    THROW 51000,'An unrelated reporting currency changed the bin.',1;
UPDATE #sales_bins_test SET gbp_adjusted_margin=34 WHERE document_no=N'bin_ltd';
IF NOT EXISTS (SELECT 1 FROM #sales_bins_test WITH (INDEX(IX_test_bins)) WHERE document_no=N'bin_ltd' AND margin_bin=4)
    THROW 51000, 'Margin-only update did not maintain the computed index.', 1;
UPDATE #sales_bins_test SET gbp_sales=200 WHERE document_no=N'bin_ltd';
IF NOT EXISTS (SELECT 1 FROM #sales_bins_test WITH (INDEX(IX_test_bins)) WHERE document_no=N'bin_ltd' AND margin_bin=2)
    THROW 51000, 'Sales-only update did not maintain the computed index.', 1;
SET @query = N'INSERT #sales_bins_test (' + @columns + N') SELECT ' + @columns + N' FROM #sales_bins_test;';
EXEC sys.sp_executesql @query;
IF (SELECT COUNT(*) FROM #sales_bins_test WHERE margin_bin = 2) <> 2
    THROW 51000, 'Insert did not compute the bins.', 1;
DELETE FROM #sales_bins_test;
SELECT 'PASS' AS result, COUNT(*) AS boundary_cases, 3 AS entities,
    'insert, currency routing, entity/margin/sales updates, index, delete' AS operations
FROM @cases;
'@
& (Join-Path $repoRoot 'tools/db-query.ps1') -Query $query -TimeoutSeconds 120
