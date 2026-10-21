-- Apply the revised result columns/indexes in place, preserving table permissions.
-- This migration deliberately refuses a populated result table: no averaging conversion is inferred.
USE data_control;
GO
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF EXISTS(SELECT 1 FROM dbo.potential_sell_through WITH(TABLOCKX,HOLDLOCK))
 THROW 50600,'PST results contain data. Review conversion before deploying.',1;
DROP INDEX IF EXISTS IX_pst_brand_entity ON dbo.potential_sell_through;
DROP INDEX IF EXISTS IX_pst_item ON dbo.potential_sell_through;
DROP INDEX IF EXISTS IX_pst_entity_item ON dbo.potential_sell_through;
IF COL_LENGTH(N'dbo.potential_sell_through',N'shipped_30_day_avg') IS NOT NULL
 ALTER TABLE dbo.potential_sell_through DROP COLUMN shipped_30_day_avg;
ALTER TABLE dbo.potential_sell_through ALTER COLUMN pst_id int NOT NULL;
IF COL_LENGTH(N'dbo.potential_sell_through',N'shipped_6M_30_day_avg') IS NULL
 ALTER TABLE dbo.potential_sell_through ADD shipped_6M_30_day_avg decimal(38,20) NOT NULL;
IF COL_LENGTH(N'dbo.potential_sell_through',N'shipped_12M_30_day_avg') IS NULL
 ALTER TABLE dbo.potential_sell_through ADD shipped_12M_30_day_avg decimal(38,20) NOT NULL;
GO
IF NOT EXISTS(SELECT 1 FROM sys.key_constraints WHERE parent_object_id=OBJECT_ID(N'dbo.potential_sell_through') AND type=N'PK')
 ALTER TABLE dbo.potential_sell_through ADD CONSTRAINT PK_potential_sell_through PRIMARY KEY CLUSTERED(pst_id,item_id);
IF OBJECT_ID(N'dbo.FK_pst_reports',N'F') IS NULL
 ALTER TABLE dbo.potential_sell_through WITH CHECK ADD CONSTRAINT FK_pst_reports FOREIGN KEY(pst_id) REFERENCES portal.pst_reports(pst_id);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.potential_sell_through') AND name=N'IX_pst_report_brand')
 CREATE NONCLUSTERED INDEX IX_pst_report_brand ON dbo.potential_sell_through(pst_id,brand_id)
 INCLUDE(inventory,po_quantity,so_quantity,shipped_last_360_days,shipped_last_180_days,shipped_6M_30_day_avg,shipped_12M_30_day_avg);
COMMIT TRANSACTION;
GO
