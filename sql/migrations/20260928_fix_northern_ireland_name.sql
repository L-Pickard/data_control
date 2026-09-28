-- Data fix: correct the spelling of country NI in dbo.countries ('Nothern Ireland' -> 'Northern Ireland').
-- One row. The load procedures (update_sales_table, update_sales_orders_table) only insert missing countries and never
-- overwrite names, so the correction is permanent. Safe to re-run: it changes nothing once the name is correct.
-- Any result other than one changed row (on first run) rolls back.
USE [data_control];
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 5000;

BEGIN TRANSACTION;

UPDATE [dbo].[countries]
SET [country_name] = N'Northern Ireland'
WHERE [country_id] = N'NI'
	AND [country_name] = N'Nothern Ireland';

DECLARE @changed INT = @@ROWCOUNT;
IF @changed > 1
BEGIN
	ROLLBACK TRANSACTION;
	THROW 51000, 'More than one row matched; nothing changed.', 1;
END

COMMIT TRANSACTION;

SELECT @changed AS rows_changed, [country_id], [iso_code], [country_name]
FROM [dbo].[countries]
WHERE [country_id] = N'NI';
