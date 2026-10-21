USE data_control;
GO
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
BEGIN TRANSACTION;
-- Existing totals remain unchanged; both averages are recalculated from those totals.
DROP INDEX IF EXISTS IX_pst_report_brand ON dbo.potential_sell_through;
ALTER TABLE dbo.potential_sell_through DROP COLUMN shipped_6M_30_day_avg,shipped_12M_30_day_avg;
ALTER TABLE dbo.potential_sell_through ADD
 shipped_6M_30_day_avg AS CAST(shipped_last_180_days / 6.0 AS DECIMAL(38,20)) PERSISTED,
 shipped_12M_30_day_avg AS CAST(shipped_last_360_days / 12.0 AS DECIMAL(38,20)) PERSISTED;
GO
CREATE NONCLUSTERED INDEX IX_pst_report_brand ON dbo.potential_sell_through(pst_id,brand_id)
 INCLUDE(inventory,po_quantity,so_quantity,shipped_last_360_days,shipped_last_180_days,shipped_6M_30_day_avg,shipped_12M_30_day_avg);
COMMIT TRANSACTION;
GO
