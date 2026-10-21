EXEC #pst_refresh;
IF EXISTS(
 SELECT * FROM(VALUES(1,50,4,8,13),(2,70,6,12,100),(3,60,5,12,35),
 (4,110,9,11,28),(5,60,5,12,15),(7,60,5,3,35)) expected(pst_id,inventory,po_quantity,so_quantity,shipped)
 WHERE NOT EXISTS(SELECT 1 FROM #fixture_results r WHERE r.pst_id=expected.pst_id AND r.item_id=N'MAIN'
  AND r.brand_id=N'ABC' AND r.inventory=expected.inventory AND r.po_quantity=expected.po_quantity
  AND r.so_quantity=expected.so_quantity AND r.shipped_last_360_days=expected.shipped))
 THROW 50900,'Company/exclusion/document-type/duplicate flag calculation failed.',1;
IF EXISTS(SELECT 1 FROM #fixture_results WHERE pst_id=6 OR item_id IN(N'UNKNOWN',N'BAD_BRAND',N'WRONG_TYPE',N'EXCLUDED_ONLY'))
 THROW 50901,'Invalid or excluded-only items leaked into a report.',1;
IF EXISTS(SELECT 1 FROM #fixture_results WHERE (pst_id=1 AND item_id=N'LLC_ONLY') OR (pst_id=2 AND item_id=N'LTD_ONLY'))
 THROW 50902,'Item list leaked across companies.',1;
IF NOT EXISTS(SELECT 1 FROM #fixture_results WHERE pst_id=1 AND item_id=N'BOUNDARY'
 AND shipped_last_360_days=359.75 AND shipped_last_180_days=179.75
 AND [shipped_1-30_days]=29.75 AND [shipped_31-60_days]=30 AND [shipped_61-90_days]=30
 AND [shipped_91-120_days]=30 AND [shipped_121-150_days]=30 AND [shipped_151-180_days]=30
 AND [shipped_181-210_days]=30 AND [shipped_211-240_days]=30 AND [shipped_241-270_days]=30
 AND [shipped_271-300_days]=30 AND [shipped_301-330_days]=30 AND [shipped_331-360_days]=30
 AND shipped_6M_30_day_avg=CAST(CAST(179.75 AS decimal(38,20))/6.0 AS decimal(38,20))
 AND shipped_12M_30_day_avg=CAST(CAST(359.75 AS decimal(38,20))/12.0 AS decimal(38,20)))
 THROW 50903,'Shipped bands, fractions, boundaries or computed averages failed.',1;
IF EXISTS(SELECT 1 FROM #fixture_reports WHERE last_updated='20000101')
 THROW 50904,'Successful refresh timestamp missing.',1;
SELECT * INTO #first_results FROM #fixture_results;
EXEC #pst_refresh;
IF EXISTS(SELECT * FROM #first_results EXCEPT SELECT * FROM #fixture_results)
 OR EXISTS(SELECT * FROM #fixture_results EXCEPT SELECT * FROM #first_results)
 THROW 50905,'Repeat refresh changed the results.',1;
-- An error after DELETE must restore previous rows and leave refresh timestamps unchanged.
SELECT pst_id,last_updated INTO #first_times FROM #fixture_reports;
ALTER TABLE #fixture_results ADD CHECK(inventory<9999);
UPDATE #fixture_inventory SET inventory=10000 WHERE item_id=N'MAIN' AND entity=N'Shiner Ltd';
DECLARE @failed bit=0;
BEGIN TRY
 EXEC #pst_refresh;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>547 THROW;
 SET @failed=1;
END CATCH;
IF @failed=0 THROW 50906,'Expected failure was not raised.',1;
IF EXISTS(SELECT * FROM #first_results EXCEPT SELECT * FROM #fixture_results)
 OR EXISTS(SELECT * FROM #fixture_results EXCEPT SELECT * FROM #first_results)
 OR EXISTS(SELECT * FROM #first_times EXCEPT SELECT pst_id,last_updated FROM #fixture_reports)
 THROW 50907,'Failed refresh did not preserve results/timestamps.',1;
UPDATE #fixture_inventory SET inventory=50 WHERE item_id=N'MAIN' AND entity=N'Shiner Ltd';
-- A caller-owned transaction remains caller-owned.
BEGIN TRANSACTION;
EXEC #pst_refresh;
IF @@TRANCOUNT<>1 THROW 50908,'Caller transaction was committed.',1;
ROLLBACK TRANSACTION;
SELECT N'PASS: company scope, master items/brands, all PST exclusions, order types, independent B.V flags, blank orders, all date bands, fractions/averages, repeat run, timestamps, failure rollback and caller transaction' AS result;
