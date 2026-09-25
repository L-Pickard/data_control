-- Least-privilege access for [shiner_reports] as the Shiner web portal's runtime SQL login.
-- Run after sql/migrations/20260925_create_portal_schema.sql. Safe to run again (GRANT is idempotent).
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

-- The portal's own data: people, groups, grants, audit (and later bookmarks).
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::[portal] TO [shiner_reports];

GO

-- Review: users.sql also grants EXECUTE on every procedure in data_control to shiner_reports. The portal does not
-- need it (it runs no procedures), and some procedures change data. If nothing else uses this login for procedures,
-- remove it with:
--   REVOKE EXECUTE TO [shiner_reports];

SELECT dp.[permission_name], dp.[class_desc], COALESCE(OBJECT_SCHEMA_NAME(dp.[major_id]) + N'.' + OBJECT_NAME(dp.[major_id]), SCHEMA_NAME(dp.[major_id])) AS [securable]
FROM sys.database_permissions AS dp
WHERE dp.[grantee_principal_id] = USER_ID(N'shiner_reports') AND dp.[state] = 'G'
ORDER BY [securable], dp.[permission_name];
