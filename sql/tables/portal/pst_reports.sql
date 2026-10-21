USE data_control;
GO
-- User-managed report definitions. Never drop/recreate this table during refresh.
IF OBJECT_ID(N'portal.pst_reports',N'U') IS NULL
 CREATE TABLE portal.pst_reports
 (
  pst_id int NOT NULL CONSTRAINT PK_portal_pst_reports PRIMARY KEY,
  pst_description nvarchar(100) NOT NULL,
  include_ltd bit NOT NULL CONSTRAINT DF_portal_pst_include_ltd DEFAULT 1,
  include_bv bit NOT NULL CONSTRAINT DF_portal_pst_include_bv DEFAULT 1,
  include_llc bit NOT NULL CONSTRAINT DF_portal_pst_include_llc DEFAULT 1,
  exclude_bv_sales bit NOT NULL CONSTRAINT DF_portal_pst_sales DEFAULT 0,
  exclude_bv_sales_orders bit NOT NULL CONSTRAINT DF_portal_pst_orders DEFAULT 0,
  revision int NOT NULL CONSTRAINT DF_portal_pst_revision DEFAULT 0 CONSTRAINT CK_portal_pst_revision CHECK(revision>=0),
  updated_at datetime2(3) NULL,
  updated_by nvarchar(184) NULL,
  last_updated datetime2(0) NOT NULL CONSTRAINT DF_portal_pst_refresh DEFAULT SYSUTCDATETIME()
 );
GO
