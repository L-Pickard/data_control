-- Least-privilege access for [shiner_reports] as the Shiner web portal's runtime SQL login.
-- Run after sql/migrations/20260925_create_portal_schema.sql. Safe to run again (GRANT is idempotent).
-- Run as a db_owner Windows login (the codex_assistant helper cannot grant), e.g.:
--   sqlcmd -S tcp:shinersql18 -d data_control -E -N -C -b -i sql/database/grants_shiner_reports_portal.sql
-- Reads only the warehouse objects the portal's report and slicer SQL uses; reads and writes only [portal].
USE [data_control];

GO

IF USER_ID(N'shiner_reports') IS NULL
	THROW 51000, 'Database user shiner_reports is missing; run sql/database/users.sql first.', 1;

IF SCHEMA_ID(N'portal') IS NULL
	THROW 51000, 'Schema portal is missing; run sql/migrations/20260925_create_portal_schema.sql first.', 1;

GO

-- Warehouse objects used by the portal (sql/reports/**, sql/slicers/*, reporting calendar). Keep in step with the
-- portal repo when reports add new objects.
GRANT SELECT ON [dbo].[sales] TO [shiner_reports];
GRANT SELECT ON [dbo].[sales_margin_bins] TO [shiner_reports];
GRANT SELECT ON [dbo].[brand_forecast] TO [shiner_reports];
GRANT SELECT ON [dbo].[brands] TO [shiner_reports];
GRANT SELECT ON [dbo].[countries] TO [shiner_reports];
GRANT SELECT ON [dbo].[customers] TO [shiner_reports];
GRANT SELECT ON [dbo].[items] TO [shiner_reports];
GRANT SELECT ON [dbo].[sales_people] TO [shiner_reports];
GRANT SELECT ON [dbo].[dates] TO [shiner_reports];
GRANT SELECT ON [dbo].[date_catalogue] TO [shiner_reports];
-- Customer Sales orderbook, converted to the report currency at today's rate (a scalar function needs EXECUTE).
GRANT SELECT ON [dbo].[sales_orders] TO [shiner_reports];
GRANT EXECUTE ON [dbo].[fnc_convert_currency] TO [shiner_reports];
-- Item Sales style and item images (a dbo view over dbo.items, item_images and item_image_locations).
GRANT SELECT ON [dbo].[item_image_catalogue] TO [shiner_reports];
-- Data Export app (My Apps): the other tables in its catalogue (the portal's Data/export-catalog.json). The app
-- exposes every column of these tables, including customer and vendor contact details, to people granted the app.
GRANT SELECT ON [dbo].[entities] TO [shiner_reports];
GRANT SELECT ON [dbo].[exchange_rates] TO [shiner_reports];
GRANT SELECT ON [dbo].[inventory] TO [shiner_reports];
GRANT SELECT ON [dbo].[item_packaging] TO [shiner_reports];
GRANT SELECT ON [dbo].[preorders] TO [shiner_reports];
GRANT SELECT ON [dbo].[purchase_orders] TO [shiner_reports];
GRANT SELECT ON [dbo].[vendors] TO [shiner_reports];

-- The portal's own data: people, groups, grants, audit (and later bookmarks).
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::[portal] TO [shiner_reports];

GO

-- No database-wide EXECUTE: the portal runs no procedures, and some procedures change data. It needs EXECUTE only on
-- dbo.fnc_convert_currency (granted above). users.sql used to grant EXECUTE on the whole database; this removes it
-- (the object-level grant above is kept). Revoked 1 October 2026 at the user's request.
REVOKE EXECUTE TO [shiner_reports];

GO

SELECT dp.[permission_name], dp.[class_desc]
	,CASE dp.[class]
		WHEN 0 THEN DB_NAME()
		WHEN 1 THEN OBJECT_SCHEMA_NAME(dp.[major_id]) + N'.' + OBJECT_NAME(dp.[major_id])
		WHEN 3 THEN SCHEMA_NAME(dp.[major_id])
		END AS [securable]
FROM sys.database_permissions AS dp
WHERE dp.[grantee_principal_id] = USER_ID(N'shiner_reports') AND dp.[state] = 'G'
ORDER BY [securable], dp.[permission_name];
