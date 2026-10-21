USE data_control;
GO
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @lock int;
EXEC @lock=sys.sp_getapplock @Resource=N'portal.pst-report-edit',@LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=10000;
IF @lock<0 THROW 50400,'PST editor is busy.',1;
GO
USE data_control;
GO
-- User-managed report definitions. Never drop/recreate this table during refresh.
IF OBJECT_ID(N'portal.pst_reports',N'U') IS NULL
 CREATE TABLE portal.pst_reports
 (
  pst_id int NOT NULL CONSTRAINT PK_portal_pst_reports PRIMARY KEY,
  pst_description nvarchar(100) NOT NULL,
  exclude_bv_sales bit NOT NULL CONSTRAINT DF_portal_pst_sales DEFAULT 0,
  exclude_bv_sales_orders bit NOT NULL CONSTRAINT DF_portal_pst_orders DEFAULT 0,
  revision int NOT NULL CONSTRAINT DF_portal_pst_revision DEFAULT 0 CONSTRAINT CK_portal_pst_revision CHECK(revision>=0),
  updated_at datetime2(3) NULL,
  updated_by nvarchar(184) NULL,
  last_updated datetime2(0) NOT NULL CONSTRAINT DF_portal_pst_refresh DEFAULT SYSUTCDATETIME()
 );
GO

IF OBJECT_ID(N'dbo.pst_reports',N'U') IS NOT NULL
BEGIN
 IF EXISTS(SELECT 1 FROM dbo.pst_reports WHERE exclusion_entity IS NOT NULL OR exclusion_for IS NOT NULL OR exclusion_id IS NOT NULL)
  THROW 50401,'Legacy catalogue columns contain data; review before consolidating.',1;
 IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE referenced_object_id=OBJECT_ID(N'dbo.pst_reports')
  AND name NOT IN(N'FK_exclusions_pst_reports',N'FK_portal_pst_catalogue'))
  THROW 50402,'Unexpected catalogue foreign key; review before consolidating.',1;
 IF EXISTS(SELECT 1 FROM sys.sql_expression_dependencies WHERE referenced_id=OBJECT_ID(N'dbo.pst_reports')
  AND referencing_id<>OBJECT_ID(N'portal.save_pst_report') AND OBJECTPROPERTY(referencing_id,'IsForeignKey')<>1)
  THROW 50403,'Unexpected catalogue dependency; review before consolidating.',1;
 INSERT portal.pst_reports(pst_id,pst_description,exclude_bv_sales,exclude_bv_sales_orders,revision,updated_at,updated_by,last_updated)
 SELECT p.pst_id,p.pst_description,ISNULL(s.exclude_bv_sales,0),ISNULL(s.exclude_bv_sales_orders,0),ISNULL(s.revision,0),s.updated_at,s.updated_by,p.last_updated
 FROM dbo.pst_reports p LEFT JOIN portal.pst_report_settings s ON s.pst_id=p.pst_id
 WHERE NOT EXISTS(SELECT 1 FROM portal.pst_reports n WHERE n.pst_id=p.pst_id);
 IF EXISTS
 (SELECT p.pst_id,p.pst_description,ISNULL(s.exclude_bv_sales,0),ISNULL(s.exclude_bv_sales_orders,0),ISNULL(s.revision,0),s.updated_at,s.updated_by,p.last_updated
  FROM dbo.pst_reports p LEFT JOIN portal.pst_report_settings s ON s.pst_id=p.pst_id
  EXCEPT SELECT pst_id,pst_description,exclude_bv_sales,exclude_bv_sales_orders,revision,updated_at,updated_by,last_updated FROM portal.pst_reports)
  THROW 50404,'Consolidated report values do not match.',1;
 ALTER TABLE dbo.exclusions DROP CONSTRAINT FK_exclusions_pst_reports;
 ALTER TABLE dbo.exclusions WITH CHECK ADD CONSTRAINT FK_exclusions_pst_reports FOREIGN KEY(pst_id) REFERENCES portal.pst_reports(pst_id);
 -- Both old tables are removed only after every value has been checked and the FK redirected.
 DROP TABLE portal.pst_report_settings;
 DROP TABLE dbo.pst_reports;
END;
IF NOT EXISTS(SELECT 1 FROM portal.schema_versions WHERE version=5)
 INSERT portal.schema_versions(version,description) VALUES(5,N'Consolidate PST catalogue and options into portal.pst_reports');
ELSE IF NOT EXISTS(SELECT 1 FROM portal.schema_versions WHERE version=5 AND description=N'Consolidate PST catalogue and options into portal.pst_reports')
 THROW 50405,'Portal schema version 5 is already used.',1;
GO
USE data_control;
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
  IF @pst_id<>0 AND (NOT EXISTS(SELECT 1 FROM portal.pst_reports WITH(UPDLOCK,HOLDLOCK) WHERE pst_id=@pst_id)
   OR @revision<>ISNULL((SELECT revision FROM portal.pst_reports WITH(UPDLOCK,HOLDLOCK) WHERE pst_id=@pst_id),0))
   SET @error=N'This report has changed. Reload the library before saving.';
  IF EXISTS(SELECT 1 FROM portal.pst_reports WITH(UPDLOCK,HOLDLOCK) WHERE pst_description=@name AND pst_id<>@pst_id)
   SET @error=N'A report with this name already exists.';
  IF @error<>N'' BEGIN COMMIT; SELECT @pst_id AS pst_id,@revision AS revision,@error AS error; RETURN; END;
  IF @pst_id=0
  BEGIN
   SELECT @pst_id=ISNULL(MAX(pst_id),0)+1 FROM portal.pst_reports WITH(UPDLOCK,HOLDLOCK);
   INSERT portal.pst_reports(pst_id,pst_description,exclude_bv_sales,exclude_bv_sales_orders,revision,updated_at,updated_by)
   VALUES(@pst_id,@name,@exclude_bv_sales,@exclude_bv_sales_orders,1,SYSUTCDATETIME(),@actor);
   SET @revision=1;
  END
  ELSE
  BEGIN
   SET @revision=@revision+1;
   UPDATE portal.pst_reports SET pst_description=@name,exclude_bv_sales=@exclude_bv_sales,exclude_bv_sales_orders=@exclude_bv_sales_orders,
    revision=@revision,updated_at=SYSUTCDATETIME(),updated_by=@actor WHERE pst_id=@pst_id;
  END;
  -- last_updated belongs to report refresh, so definition edits leave it alone.
  DELETE e FROM dbo.exclusions e WHERE e.rule_scope=N'pst' AND e.pst_id=@pst_id
   AND NOT EXISTS(SELECT 1 FROM @r r WHERE r.target_table=e.target_table AND r.entity=e.entity AND r.party_id=e.id);
  INSERT dbo.exclusions(entity,[type],table_name,id,brand_id,rule_scope,pst_id,target_table)
   SELECT r.entity,N'exclusion',CASE WHEN r.target_table=N'purchase_orders' THEN N'vendors' ELSE N'customers' END,
    r.party_id,N'',N'pst',@pst_id,r.target_table FROM @r r
   WHERE NOT EXISTS(SELECT 1 FROM dbo.exclusions e WHERE e.rule_scope=N'pst' AND e.pst_id=@pst_id
    AND e.target_table=r.target_table AND e.entity=r.entity AND e.id=r.party_id);
  COMMIT;
  SELECT @pst_id AS pst_id,@revision AS revision,N'' AS error;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  THROW;
 END CATCH;
END;
GO

COMMIT TRANSACTION;
GO
