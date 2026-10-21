# Compile the migration and exercise persistence inside a transaction that is always rolled back.
# No source-server queries, real report edits or grants.
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
$migration = Get-Content (Join-Path $workspace 'sql/migrations/20261021_pst_report_companies.sql') -Raw
$checks = @'
DECLARE @original_global int=(SELECT COUNT(*) FROM dbo.exclusions WHERE rule_scope=N'global');
DECLARE @original_reports int=(SELECT COUNT(*) FROM portal.pst_reports);
DECLARE @out TABLE(pst_id int,revision int,error nvarchar(200));
DECLARE @rules nvarchar(max)=(SELECT TOP(1) N'sales' AS TargetTable,N'Shiner Ltd' AS Entity,customer_id AS PartyId FROM dbo.customers WHERE customer_id<>N'' ORDER BY customer_id FOR JSON PATH);
INSERT @out EXEC portal.save_pst_report 0,0,N'__PST rollback verification__',1,0,@rules,N'rollback-verification';
IF NOT EXISTS(SELECT 1 FROM @out WHERE pst_id>0 AND revision=1 AND error=N'') THROW 50301,'Create failed.',1;
DECLARE @id int=(SELECT pst_id FROM @out);
IF NOT EXISTS(SELECT 1 FROM portal.pst_reports WHERE pst_id=@id AND exclude_bv_sales=1 AND exclude_bv_sales_orders=0) THROW 50302,'Independent flags failed.',1;
IF (SELECT COUNT(*) FROM dbo.exclusions WHERE pst_id=@id AND rule_scope=N'pst')<>1 THROW 50303,'Exclusion missing.',1;
DELETE @out;
INSERT @out EXEC portal.save_pst_report @id,1,N'__PST rollback verification renamed__',0,1,N'[]',N'rollback-verification';
IF NOT EXISTS(SELECT 1 FROM @out WHERE revision=2 AND error=N'') THROW 50304,'Update failed.',1;
IF EXISTS(SELECT 1 FROM dbo.exclusions WHERE pst_id=@id AND rule_scope=N'pst') THROW 50305,'Rule removal failed.',1;
IF (SELECT COUNT(*) FROM dbo.exclusions WHERE rule_scope=N'global')<>@original_global THROW 50307,'Global rules changed.',1;
IF (SELECT COUNT(*) FROM portal.pst_reports)<>@original_reports+1 THROW 50308,'Catalogue changed unexpectedly.',1;
-- Invalid requests refuse before beginning a transaction: they leave this rollback harness intact.
DELETE @out;
INSERT @out EXEC portal.save_pst_report @id,2,N'__PST invalid__',0,0,N'[{"TargetTable":"unexpected","Entity":"Shiner Ltd","PartyId":"x"}]',N'rollback-verification';
IF NOT EXISTS(SELECT 1 FROM @out WHERE error<>N'') THROW 50309,'Invalid target accepted.',1;
DELETE @out;
INSERT @out EXEC portal.save_pst_report @id,1,N'__PST stale overwrite__',1,1,N'[]',N'rollback-verification';
IF NOT EXISTS(SELECT 1 FROM @out WHERE error LIKE N'This report has changed%') THROW 50310,'Stale edit accepted.',1;
IF NOT EXISTS(SELECT 1 FROM portal.pst_reports WHERE pst_id=@id AND pst_description=N'__PST rollback verification renamed__') THROW 50311,'Stale edit changed the report.',1;
-- Editing an existing definition keeps its ID, refresh timestamp and every original rule.
DECLARE @existing int=(SELECT TOP(1) pst_id FROM portal.pst_reports WHERE pst_id<>@id ORDER BY pst_id);
IF @existing IS NOT NULL
BEGIN
 DECLARE @name nvarchar(100),@refreshed datetime2(0),@existing_revision int;
 SELECT @name=p.pst_description,@refreshed=p.last_updated,@existing_revision=p.revision
 FROM portal.pst_reports p WHERE p.pst_id=@existing;
 SET @rules=(SELECT target_table AS TargetTable,entity AS Entity,id AS PartyId FROM dbo.exclusions WHERE rule_scope=N'pst' AND pst_id=@existing FOR JSON PATH);
 DELETE @out;
 INSERT @out EXEC portal.save_pst_report @existing,@existing_revision,@name,0,0,@rules,N'rollback-verification';
 IF NOT EXISTS(SELECT 1 FROM @out WHERE pst_id=@existing AND error=N'') THROW 50312,'Existing report edit failed.',1;
 IF NOT EXISTS(SELECT 1 FROM portal.pst_reports WHERE pst_id=@existing AND last_updated=@refreshed) THROW 50313,'Refresh timestamp changed.',1;
END;
IF NOT EXISTS(SELECT 1 FROM portal.pst_reports WHERE pst_id=@id AND include_ltd=1 AND include_bv=1 AND include_llc=1) THROW 50501,'Company defaults failed.',1;
DELETE @out;
INSERT @out EXEC portal.save_pst_report @id,2,N'__PST rollback verification renamed__',0,1,N'[]',N'rollback-verification',0,1,0;
IF NOT EXISTS(SELECT 1 FROM @out WHERE revision=3 AND error=N'') THROW 50502,'Company selection save failed.',1;
IF NOT EXISTS(SELECT 1 FROM portal.pst_reports WHERE pst_id=@id AND include_ltd=0 AND include_bv=1 AND include_llc=0) THROW 50503,'Independent company flags failed.',1;
SELECT N'PASS: company defaults and independent save, create, edit, independent flags, scoped removal, global preservation, invalid target and stale edit refusal; all rolled back' AS result;
ROLLBACK TRANSACTION;
GO
'@
$tempFile = Join-Path ([IO.Path]::GetTempPath()) ('pst-rollback-' + [guid]::NewGuid().ToString('N') + '.sql')
try {
    "BEGIN TRANSACTION;`r`nGO`r`n$migration`r`n$checks" | Set-Content -LiteralPath $tempFile -Encoding utf8
    & (Join-Path $PSScriptRoot 'db-query.ps1') -InputFile $tempFile
} finally { Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue }

