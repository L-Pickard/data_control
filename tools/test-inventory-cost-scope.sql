-- SQL18-only integration checks. Every fixture is rolled back; no NAV reads or jobs.
USE data_control;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @lock INT;
EXEC @lock=sys.sp_getapplock @Resource=N'inventory_cost_operation',@LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0;
IF @lock<0 THROW 50310,'Inventory operation in progress.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @source INT=(SELECT TOP(1) dataset_id FROM finance.inventory_cost_headers WHERE status=N'complete' ORDER BY dataset_id);
 INSERT finance.inventory_cost_checks(as_of_date,requested_by_id,requested_by,scope_json)
 SELECT as_of_date,N'rollback-scope-test',N'Rollback scope test',N'[{"entity":"Shiner Ltd","locations":null}]'
 FROM finance.inventory_cost_headers WHERE dataset_id=@source;
 DECLARE @check INT=CAST(SCOPE_IDENTITY() AS INT);
 INSERT finance.inventory_cost_headers(description,as_of_date,check_id,status,created_by_id,created_by,reviewed_at,rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,started_at)
 SELECT N'Rollback-only scope test '+CONVERT(NVARCHAR(36),NEWID()),as_of_date,@check,N'loading',created_by_id,created_by,SYSDATETIME(),rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,SYSDATETIME()
 FROM finance.inventory_cost_headers WHERE dataset_id=@source;
 DECLARE @test INT=CAST(SCOPE_IDENTITY() AS INT);
 DECLARE @json NVARCHAR(MAX)=(SELECT entity,copies.location_code,item_id,quantity,cost,expected_cost,first_receipt,last_receipt
 FROM (SELECT TOP(1) * FROM finance.inventory_cost_lines WHERE dataset_id=@source AND entity=N'Shiner Ltd' ORDER BY item_id) line
 CROSS JOIN(VALUES(N'BRISTOL'),(N'TEST-LOC')) copies(location_code) FOR JSON PATH,INCLUDE_NULL_VALUES);
 EXEC finance.build_inventory_cost @dataset_id=@test,@rows_json=@json;
 IF (SELECT COUNT(*) FROM finance.inventory_cost_lines WHERE dataset_id=@test)<>2 THROW 50311,'Same item at two locations was not preserved.',1;
 IF (SELECT line_count FROM finance.inventory_cost_headers WHERE dataset_id=@test)<>2 THROW 50312,'Incorrect scoped line count.',1;
 PRINT 'PASS: one item at two locations saves as separate lines under All locations.';
 ROLLBACK;

 BEGIN TRANSACTION;
 INSERT finance.inventory_cost_headers(description,as_of_date,check_id,status,created_by_id,created_by,reviewed_at,rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,started_at)
 SELECT N'Rollback-only scope refusal '+CONVERT(NVARCHAR(36),NEWID()),as_of_date,check_id,N'loading',created_by_id,created_by,SYSDATETIME(),rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,SYSDATETIME()
 FROM finance.inventory_cost_headers WHERE dataset_id=@source;
 SET @test=CAST(SCOPE_IDENTITY() AS INT);
 BEGIN TRY
  EXEC finance.build_inventory_cost @dataset_id=@test,@rows_json=@json;
  THROW 50313,'Out-of-scope location was accepted.',1;
 END TRY
 BEGIN CATCH
  IF ERROR_NUMBER()<>50165 THROW;
  PRINT 'PASS: location outside the original checked scope is refused.';
 END CATCH;
 IF XACT_STATE()<>0 ROLLBACK;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 EXEC sys.sp_releaseapplock @Resource=N'inventory_cost_operation',@LockOwner=N'Session';
 THROW;
END CATCH;
EXEC sys.sp_releaseapplock @Resource=N'inventory_cost_operation',@LockOwner=N'Session';
GO
