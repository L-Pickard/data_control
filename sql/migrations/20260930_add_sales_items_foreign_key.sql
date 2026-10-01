USE [data_control];
GO
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 5000;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET QUOTED_IDENTIFIER ON;

-- Deploy sql/procedures/update_items_table.sql first. It preserves sales item references
-- and disables/rechecks this FK inside the existing refresh transaction.
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.update_items_table')) NOT LIKE N'%FK_sales_items%'
    THROW 50001, 'Deploy the updated update_items_table procedure before this migration.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_sales_items' AND parent_object_id = OBJECT_ID(N'dbo.sales'))
    ALTER TABLE [dbo].[sales] WITH CHECK
        ADD CONSTRAINT [FK_sales_items] FOREIGN KEY ([item_id]) REFERENCES [dbo].[items] ([item_id]);

ALTER TABLE [dbo].[sales] WITH CHECK CHECK CONSTRAINT [FK_sales_items];

SELECT [name], [is_disabled], [is_not_trusted]
FROM sys.foreign_keys
WHERE [name] = N'FK_sales_items' AND parent_object_id = OBJECT_ID(N'dbo.sales');
GO
