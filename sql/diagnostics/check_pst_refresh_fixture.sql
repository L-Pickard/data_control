-- Fixture tables only. The PowerShell runner rewrites every warehouse reference.
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
CREATE TABLE #fixture_reports(pst_id int PRIMARY KEY,include_ltd bit,include_bv bit,include_llc bit,
 exclude_bv_sales bit,exclude_bv_sales_orders bit,last_updated datetime2(0));
INSERT #fixture_reports VALUES
 (1,1,0,0,0,0,'20000101'),(2,0,0,1,0,0,'20000101'),(3,0,1,0,0,0,'20000101'),
 (4,1,1,0,1,1,'20000101'),(5,0,1,0,1,0,'20000101'),(6,0,0,0,1,1,'20000101'),(7,0,1,0,0,1,'20000101');
CREATE TABLE #fixture_exclusions(rule_scope nvarchar(10),pst_id int,target_table nvarchar(30),entity nvarchar(20),id nvarchar(20));
INSERT #fixture_exclusions
SELECT N'pst',rp.pst_id,scope.target_table,scope.entity,scope.party_id FROM #fixture_reports rp
CROSS JOIN(VALUES(N'sales',N'Shiner Ltd',N'BAD'),(N'sales',N'Shiner B.V',N'BAD'),
 (N'purchase_orders',N'Shiner Ltd',N'BAD'),(N'purchase_orders',N'Shiner B.V',N'BAD'),
 (N'sales_orders',N'Shiner Ltd',N'BAD'),(N'sales_orders',N'Shiner B.V',N'BAD'))scope(target_table,entity,party_id);
-- A global rule must not leak into report-specific exclusions.
INSERT #fixture_exclusions VALUES(N'global',NULL,N'',N'Shiner Ltd',N'GOOD');
CREATE TABLE #fixture_brands(brand_id nvarchar(20) PRIMARY KEY);
INSERT #fixture_brands VALUES(N'ABC');
CREATE TABLE #fixture_items(item_id nvarchar(20) PRIMARY KEY,brand_id nvarchar(20));
INSERT #fixture_items VALUES(N'MAIN',N'ABC'),(N'LLC_ONLY',N'ABC'),(N'LTD_ONLY',N'ABC'),
 (N'BOUNDARY',N'ABC'),(N'EXCLUDED_ONLY',N'ABC'),(N'BAD_BRAND',N'MISSING'),(N'WRONG_TYPE',N'ABC');
CREATE TABLE #fixture_sales(item_id nvarchar(20),entity nvarchar(20),posting_date date,
 quantity decimal(38,20),customer_id nvarchar(20),order_no nvarchar(20));
INSERT #fixture_sales VALUES
 (N'MAIN',N'Shiner Ltd','20261020',10.25,N'GOOD',N'MATCH'),
 (N'MAIN',N'Shiner Ltd','20261020',3,N'GOOD',N''),
 (N'MAIN',N'Shiner Ltd','20261020',-0.25,N'GOOD',N'RETURN'),
 (N'MAIN',N'Shiner B.V','20261020',20,N'GOOD',N'MATCH'),
 (N'MAIN',N'Shiner B.V','20261020',5,N'GOOD',N'OTHER'),
 (N'MAIN',N'Shiner B.V','20261020',7,N'GOOD',N''),
 (N'MAIN',N'Shiner B.V','20261020',3,N'GOOD',NULL),
 (N'MAIN',N'Shiner LLC','20261020',100,N'GOOD',N'MATCH'),
 (N'MAIN',N'Shiner Ltd','20261020',1000,N'BAD',N'EXCLUDED'),
 (N'MAIN',N'Shiner B.V','20261020',1000,N'BAD',N'EXCLUDED'),
 (N'EXCLUDED_ONLY',N'Shiner Ltd','20261020',1000,N'BAD',N'EXCLUDED');
;WITH days AS(SELECT 0 AS n UNION ALL SELECT n+1 FROM days WHERE n<361)
INSERT #fixture_sales SELECT N'BOUNDARY',N'Shiner Ltd',DATEADD(day,-n,'20261021'),1,N'GOOD',N'DAYS' FROM days OPTION(MAXRECURSION 400);
INSERT #fixture_sales VALUES(N'BOUNDARY',N'Shiner Ltd','20261020',-0.25,N'GOOD',N'RETURN');
CREATE TABLE #fixture_inventory(item_id nvarchar(20),entity nvarchar(20),inventory decimal(38,20));
INSERT #fixture_inventory VALUES(N'MAIN',N'Shiner Ltd',50),(N'MAIN',N'Shiner B.V',60),(N'MAIN',N'Shiner LLC',70),
 (N'LTD_ONLY',N'Shiner Ltd',2),(N'LLC_ONLY',N'Shiner LLC',9),(N'UNKNOWN',N'Shiner Ltd',99),(N'BAD_BRAND',N'Shiner Ltd',88);
CREATE TABLE #fixture_purchase_orders(item_id nvarchar(20),entity nvarchar(20),document_type int,
 outstanding_quantity decimal(38,20),vendor_id nvarchar(20));
INSERT #fixture_purchase_orders VALUES(N'MAIN',N'Shiner Ltd',1,4,N'GOOD'),(N'MAIN',N'Shiner B.V',1,5,N'GOOD'),
 (N'MAIN',N'Shiner LLC',1,6,N'GOOD'),(N'MAIN',N'Shiner Ltd',1,1000,N'BAD'),(N'MAIN',N'Shiner Ltd',2,1000,N'GOOD'),
 (NULL,N'Shiner Ltd',1,1000,N'GOOD'),(N'',N'Shiner Ltd',1,1000,N'GOOD'),(N'WRONG_TYPE',N'Shiner Ltd',0,1000,N'GOOD');
CREATE TABLE #fixture_sales_orders(item_id nvarchar(20),entity nvarchar(20),document_type int,line_type int,
 outstanding_quantity decimal(38,20),sell_to_customer_id nvarchar(20),document_no nvarchar(20));
INSERT #fixture_sales_orders VALUES
 (N'MAIN',N'Shiner Ltd',1,2,8,N'GOOD',N'MATCH'),(N'MAIN',N'Shiner B.V',1,2,9,N'GOOD',N'MATCH'),
 (N'MAIN',N'Shiner B.V',1,2,2,N'GOOD',N'OTHER'),(N'MAIN',N'Shiner B.V',1,2,1,N'GOOD',N''),
 (N'MAIN',N'Shiner LLC',1,2,12,N'GOOD',N'MATCH'),(N'MAIN',N'Shiner Ltd',1,2,1000,N'BAD',N'EXCLUDED'),
 (N'MAIN',N'Shiner Ltd',0,2,1000,N'GOOD',N'QUOTE'),(N'MAIN',N'Shiner Ltd',1,1,1000,N'GOOD',N'GL'),
 (NULL,N'Shiner Ltd',1,1,1000,N'GOOD',N'GL');
GO
