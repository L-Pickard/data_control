-- Live integration check: uses an existing snapshot; all fixture changes roll back.
-- Run when inventory operations are idle. Does not read NAV or alter existing snapshots.
USE [data_control];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @lock INT;
EXEC @lock=sys.sp_getapplock @Resource=N'inventory_cost_operation',@LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0;
IF @lock < 0 THROW 50300,'Could not acquire test lock.',1;
BEGIN TRANSACTION;
DECLARE @source INT=(SELECT TOP(1) dataset_id FROM finance.inventory_cost_headers WHERE status=N'complete' ORDER BY dataset_id);
DECLARE @json NVARCHAR(MAX)=(SELECT entity,location_code,item_id,quantity,cost,expected_cost,first_receipt,last_receipt FROM finance.inventory_cost_lines WHERE dataset_id=@source FOR JSON PATH,INCLUDE_NULL_VALUES);
INSERT finance.inventory_cost_headers(description,as_of_date,check_id,status,created_by_id,created_by,cost_adjusted_confirmed_at,posted_to_gl_confirmed_at,reviewed_at,override_reason,override_at,rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,started_at)
SELECT N'Rollback-only build verification '+CONVERT(NVARCHAR(36),NEWID()),as_of_date,check_id,N'loading',created_by_id,created_by,cost_adjusted_confirmed_at,posted_to_gl_confirmed_at,reviewed_at,override_reason,override_at,rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,SYSDATETIME()
FROM finance.inventory_cost_headers WHERE dataset_id=@source;
DECLARE @test INT=CAST(SCOPE_IDENTITY() AS INT);
EXEC finance.build_inventory_cost @dataset_id=@test,@rows_json=@json;
IF EXISTS(
 SELECT entity,item_id,quantity,cost,expected_cost,cost_gbp,cost_eur,cost_usd,first_receipt,last_receipt FROM finance.inventory_cost_lines WHERE dataset_id=@source
 EXCEPT
 SELECT entity,item_id,quantity,cost,expected_cost,cost_gbp,cost_eur,cost_usd,first_receipt,last_receipt FROM finance.inventory_cost_lines WHERE dataset_id=@test
) THROW 50301,'Rebuilt snapshot differs from original.',1;
IF EXISTS(
 SELECT line_count,total_gbp,total_eur,total_usd FROM finance.inventory_cost_headers WHERE dataset_id=@source
 EXCEPT
 SELECT line_count,total_gbp,total_eur,total_usd FROM finance.inventory_cost_headers WHERE dataset_id=@test
) THROW 50302,'Rebuilt totals differ from original.',1;
SELECT N'PASS: direct JSON build matches all original snapshot rows and totals' AS result,line_count FROM finance.inventory_cost_headers WHERE dataset_id=@test;
ROLLBACK TRANSACTION;


-- Duplicate rows must roll back the entire save, including header totals.
DECLARE @before INT=(SELECT COUNT(*) FROM finance.inventory_cost_headers);
BEGIN TRY
    BEGIN TRANSACTION;
INSERT finance.inventory_cost_headers(description,as_of_date,check_id,status,created_by_id,created_by,cost_adjusted_confirmed_at,posted_to_gl_confirmed_at,reviewed_at,override_reason,override_at,rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,started_at)
SELECT N'Rollback-only build verification '+CONVERT(NVARCHAR(36),NEWID()),as_of_date,check_id,N'loading',created_by_id,created_by,cost_adjusted_confirmed_at,posted_to_gl_confirmed_at,reviewed_at,override_reason,override_at,rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,SYSDATETIME()
FROM finance.inventory_cost_headers WHERE dataset_id=@source;
SET @test=CAST(SCOPE_IDENTITY() AS INT);

    DECLARE @duplicate NVARCHAR(MAX)=(
        SELECT entity,location_code,item_id,quantity,cost,expected_cost,first_receipt,last_receipt
        FROM (SELECT TOP(1) * FROM finance.inventory_cost_lines WHERE dataset_id=@source ORDER BY item_id,entity) AS first_line
        CROSS JOIN (VALUES(1),(2)) AS copies(n) FOR JSON PATH,INCLUDE_NULL_VALUES
    );
    EXEC finance.build_inventory_cost @dataset_id=@test,@rows_json=@duplicate;
    THROW 50303,'Duplicate rows were unexpectedly accepted.',1;
END TRY
BEGIN CATCH
    DECLARE @error INT=ERROR_NUMBER();
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    IF @error NOT IN(2601,2627) THROW;
END CATCH;
IF (SELECT COUNT(*) FROM finance.inventory_cost_headers)<>@before
    THROW 50304,'Failed save left a dataset header behind.',1;
IF EXISTS(SELECT 1 FROM finance.inventory_cost_lines WHERE dataset_id=@test)
    THROW 50305,'Failed save left partial lines behind.',1;
PRINT 'PASS: duplicate save rolls back all lines and header changes';
EXEC sys.sp_releaseapplock @Resource=N'inventory_cost_operation',@LockOwner=N'Session';
GO
