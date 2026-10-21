-- PST app persistence. Preserve dbo's existing catalogue, IDs and shared exclusion rules.
-- Follow with sql/database/grants_pst_report_builder.sql, run by a db_owner.
USE data_control;
GO
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF OBJECT_ID(N'portal.pst_report_settings',N'U') IS NULL
 CREATE TABLE portal.pst_report_settings
 (
  pst_id int NOT NULL CONSTRAINT PK_portal_pst_report_settings PRIMARY KEY,
  exclude_bv_sales bit NOT NULL CONSTRAINT DF_pst_bv_sales DEFAULT 0,
  exclude_bv_sales_orders bit NOT NULL CONSTRAINT DF_pst_bv_orders DEFAULT 0,
  revision int NOT NULL CONSTRAINT CK_pst_revision CHECK (revision>0),
  updated_at datetime2(3) NOT NULL,
  updated_by nvarchar(184) NOT NULL,
  CONSTRAINT FK_portal_pst_catalogue FOREIGN KEY (pst_id) REFERENCES dbo.pst_reports(pst_id)
 );
IF NOT EXISTS (SELECT 1 FROM portal.schema_versions WHERE version=4)
 INSERT portal.schema_versions(version,description) VALUES(4,N'PST report current settings');
ELSE IF NOT EXISTS (SELECT 1 FROM portal.schema_versions WHERE version=4 AND description=N'PST report current settings')
 THROW 50200,'Portal schema version 4 is already used; review migration numbering.',1;
COMMIT;
GO
CREATE OR ALTER PROCEDURE portal.save_pst_report
 @pst_id int, @revision int, @name nvarchar(100), @exclude_bv_sales bit,
 @exclude_bv_sales_orders bit, @rules nvarchar(max), @actor nvarchar(184)
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 DECLARE @error nvarchar(200)=N'', @lock int;
 SET @name=LTRIM(RTRIM(@name));
 IF ISNULL(@name,N'')=N'' OR @pst_id<0 OR @revision<0 OR (@pst_id=0 AND @revision<>0)
  OR ISNULL(@actor,N'')=N'' OR @exclude_bv_sales IS NULL OR @exclude_bv_sales_orders IS NULL
  OR ISJSON(@rules)<>1 OR LEFT(LTRIM(@rules),1)<>N'[' OR @rules IS NULL
  SET @error=N'Enter valid report settings.';
 IF @error<>N'' BEGIN SELECT 0 AS pst_id,0 AS revision,@error AS error; RETURN; END;
 DECLARE @r TABLE(target_table nvarchar(4000),entity nvarchar(4000),party_id nvarchar(4000));
 INSERT @r SELECT TargetTable,Entity,PartyId FROM OPENJSON(@rules)
 WITH(TargetTable nvarchar(4000),Entity nvarchar(4000),PartyId nvarchar(4000));
 IF (SELECT COUNT(*) FROM @r)>1000 OR EXISTS
 (SELECT 1 FROM @r r WHERE target_table IS NULL OR target_table NOT IN(N'sales',N'sales_orders',N'purchase_orders')
  OR entity IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.entities e WHERE e.entity=r.entity)
  OR NULLIF(LTRIM(RTRIM(party_id)),N'') IS NULL OR LEN(party_id)>20
  OR (target_table=N'purchase_orders' AND NOT EXISTS(SELECT 1 FROM dbo.vendors v WHERE v.vendor_id=r.party_id))
  OR (target_table IN(N'sales',N'sales_orders') AND NOT EXISTS(SELECT 1 FROM dbo.customers c WHERE c.customer_id=r.party_id)))
  SET @error=N'Choose valid companies and customer or vendor numbers.';
 IF EXISTS(SELECT 1 FROM @r GROUP BY target_table,entity,party_id HAVING COUNT(*)>1)
  SET @error=N'Remove duplicate exclusions before saving.';
 IF @error<>N'' BEGIN SELECT @pst_id AS pst_id,@revision AS revision,@error AS error; RETURN; END;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC @lock=sys.sp_getapplock @Resource=N'portal.pst-report-edit',@LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=5000;
  IF @lock<0 THROW 50201,'PST report editor is busy.',1;
  IF @pst_id<>0 AND (NOT EXISTS(SELECT 1 FROM dbo.pst_reports WITH(UPDLOCK,HOLDLOCK) WHERE pst_id=@pst_id)
   OR @revision<>ISNULL((SELECT revision FROM portal.pst_report_settings WITH(UPDLOCK,HOLDLOCK) WHERE pst_id=@pst_id),0))
   SET @error=N'This report has changed. Reload the library before saving.';
  IF EXISTS(SELECT 1 FROM dbo.pst_reports WITH(UPDLOCK,HOLDLOCK) WHERE pst_description=@name AND pst_id<>@pst_id)
   SET @error=N'A report with this name already exists.';
  IF @error<>N'' BEGIN COMMIT; SELECT @pst_id AS pst_id,@revision AS revision,@error AS error; RETURN; END;
  IF @pst_id=0
  BEGIN
   SELECT @pst_id=ISNULL(MAX(pst_id),0)+1 FROM dbo.pst_reports WITH(UPDLOCK,HOLDLOCK);
   INSERT dbo.pst_reports(pst_id,pst_description) VALUES(@pst_id,@name);
  END
  ELSE UPDATE dbo.pst_reports SET pst_description=@name WHERE pst_id=@pst_id;
  -- last_updated belongs to report refresh, so definition edits leave it alone.
  DELETE e FROM dbo.exclusions e WHERE e.rule_scope=N'pst' AND e.pst_id=@pst_id
   AND NOT EXISTS(SELECT 1 FROM @r r WHERE r.target_table=e.target_table AND r.entity=e.entity AND r.party_id=e.id);
  INSERT dbo.exclusions(entity,[type],table_name,id,brand_id,rule_scope,pst_id,target_table)
   SELECT r.entity,N'exclusion',CASE WHEN r.target_table=N'purchase_orders' THEN N'vendors' ELSE N'customers' END,
    r.party_id,N'',N'pst',@pst_id,r.target_table FROM @r r
   WHERE NOT EXISTS(SELECT 1 FROM dbo.exclusions e WHERE e.rule_scope=N'pst' AND e.pst_id=@pst_id
    AND e.target_table=r.target_table AND e.entity=r.entity AND e.id=r.party_id);
  SET @revision=@revision+1;
  UPDATE portal.pst_report_settings SET exclude_bv_sales=@exclude_bv_sales,exclude_bv_sales_orders=@exclude_bv_sales_orders,
   revision=@revision,updated_at=SYSUTCDATETIME(),updated_by=@actor WHERE pst_id=@pst_id;
  IF @@ROWCOUNT=0 INSERT portal.pst_report_settings VALUES(@pst_id,@exclude_bv_sales,@exclude_bv_sales_orders,@revision,SYSUTCDATETIME(),@actor);
  COMMIT;
  SELECT @pst_id AS pst_id,@revision AS revision,N'' AS error;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  THROW;
 END CATCH;
END;
GO
