USE [data_control];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
-- Finance fOrderbook/fPurchases rules verified on 2026-09-10.
-- This migration only changes data_control. Existing order rows are preserved.
CREATE TABLE #finance_order_rules (
    entity NVARCHAR(20) NOT NULL,
    type NVARCHAR(20) NOT NULL,
    table_name NVARCHAR(20) NOT NULL,
    id NVARCHAR(20) NOT NULL,
    PRIMARY KEY (entity, type, table_name, id)
);

INSERT INTO #finance_order_rules(
     [entity]
    ,[type]
    ,[table_name]
    ,[id]
)

VALUES
     ('Shiner Ltd', 'exclusion', 'customers', 'CU110025') -- Shiner BV - NPD Samples EUR
    ,('Shiner Ltd', 'exclusion', 'customers', 'CU110036') -- Shiner LLC (Management Recharge)
    ,('Shiner Ltd', 'exclusion', 'customers', 'CU110040') -- Shiner BV (Management Recharge)
    ,('Shiner Ltd', 'exclusion', 'customers', 'CU110083') -- Shiner BV - NPD Samples USD
    ,('Shiner Ltd', 'exclusion', 'customers', 'CU109989') -- Sales Sets Distributed - EU BV
    ,('Shiner Ltd', 'exclusion', 'customers', 'CU109330') -- Seeding Marketing PR162

    ,('Shiner B.V', 'exclusion', 'customers', 'CU110025') -- Shiner BV - NPD Samples EUR
    ,('Shiner B.V', 'exclusion', 'customers', 'CU109506') -- NPD Samples EU
    ,('Shiner B.V', 'exclusion', 'customers', 'CU109989') -- Sales Sets Distributed - EU BV
    ,('Shiner B.V', 'exclusion', 'customers', 'CU109330') -- Seeding Marketing PR162

    ,('Shiner LLC', 'exclusion', 'customers', 'UC000650') -- Management Recharge Shiner Ltd
    ,('Shiner LLC', 'exclusion', 'customers', 'UC000653') -- Management recharge Shiner EU BV
    ,('Shiner LLC', 'exclusion', 'customers', 'UC000340') -- Shiner Marketing
    ,('Shiner LLC', 'exclusion', 'customers', 'CU109989') -- Sales Sets Distributed - EU BV
    ,('Shiner LLC', 'exclusion', 'customers', 'CU109330') -- Seeding Marketing PR162
   
   -- Intercompany

   ,('Shiner Ltd', 'intercompany', 'customers', 'CU103500') -- Shiner Limited
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU109221') -- Shiner EU B.V.Replen
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU109441') -- Shiner EU BV BTB
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU109444') -- Shiner EU BV Replen DONT USE
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU109525') -- Shiner EU Riga B2B
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU110077') -- Shiner LLC
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU110744') -- Shiner EU B.V. Redwood Replen

   ,('Shiner B.V', 'intercompany', 'customers', 'CU103500') -- Shiner Limited
   ,('Shiner B.V', 'intercompany', 'customers', 'CU109221') -- Shiner EU B.V.Replen
   ,('Shiner B.V', 'intercompany', 'customers', 'CU109441') -- Shiner EU BV BTB
   ,('Shiner B.V', 'intercompany', 'customers', 'CU109444') -- Shiner EU BV Replen DONT USE
   ,('Shiner B.V', 'intercompany', 'customers', 'CU109525') -- Shiner EU Riga B2B
   ,('Shiner B.V', 'intercompany', 'customers', 'CU110077') -- Shiner LLC

   ,('Shiner LLC', 'intercompany', 'customers', 'UC000458'); -- Shiner Ltd

-- The legacy purchase rules apply to every entity. Materialise one row for
-- each entity instead of storing '*' so the foreign key remains enforceable.

INSERT INTO #finance_order_rules (
     [entity]
    ,[type]
    ,[table_name]
    ,[id]
)
SELECT
     en.[entity]
    ,rules.[type]
    ,N'vendors'
    ,rules.[id]
FROM [dbo].[entities] AS en
CROSS JOIN (
    VALUES
         (N'exclusion', N'UV000199') -- Management Recharge Shiner Ltd
        ,(N'exclusion', N'UV000200') -- Management Recharge Shiner EU BV
        ,(N'exclusion', N'VE100194') -- Shiner Properties Limited
        ,(N'exclusion', N'VE100890') -- Shiner LLC (Management Recharge)
        ,(N'intercompany', N'UV000081') -- Shiner Ltd
        ,(N'intercompany', N'UV000195') -- Shiner EU BV
        ,(N'intercompany', N'VE100520') -- Shiner Ltd - Replen
        ,(N'intercompany', N'VE100927') -- Shiner Ltd
        ,(N'intercompany', N'VE100934') -- Shiner LLC
        ,(N'intercompany', N'VE100952') -- Shiner EU B.V.
) AS rules ([type], [id]);



INSERT INTO dbo.exclusions (entity, type, table_name, id)
SELECT r.entity, r.type, r.table_name, r.id
FROM #finance_order_rules AS r
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.exclusions AS e WITH (UPDLOCK, HOLDLOCK)
    WHERE e.entity = r.entity AND e.type = r.type
      AND e.table_name = r.table_name AND e.id = r.id
);
SELECT @@ROWCOUNT AS exclusion_records_inserted;

EXEC sys.sp_executesql N'CREATE OR ALTER FUNCTION [dbo].[fnc_is_vendor_exclusion] (
	 @entity NVARCHAR(20)
	,@vendor_id NVARCHAR(20)
	)
RETURNS BIT
AS
/*===============================================================================================================================================
Returns 1 when the entity/vendor combination is configured as a vendor
exclusion in dbo.exclusions; otherwise returns 0.
===============================================================================================================================================*/
BEGIN
	DECLARE @is_exclusion BIT = 0;

	IF EXISTS (
			SELECT 1
			FROM [dbo].[exclusions]
			WHERE [entity] = @entity
				AND [type] = ''exclusion''
				AND [table_name] = ''vendors''
				AND [id] = @vendor_id
			)
	BEGIN
		SET @is_exclusion = 1;
	END;

	RETURN @is_exclusion;
END;';

EXEC sys.sp_executesql N'CREATE OR ALTER FUNCTION [dbo].[fnc_is_vendor_intercompany] (
	 @entity NVARCHAR(20)
	,@vendor_id NVARCHAR(20)
	)
RETURNS BIT
AS
/*===============================================================================================================================================
Returns 1 when the entity/vendor combination is configured as an intercompany
vendor in dbo.exclusions; otherwise returns 0.
===============================================================================================================================================*/
BEGIN
	DECLARE @is_intercompany BIT = 0;

	IF EXISTS (
			SELECT 1
			FROM [dbo].[exclusions]
			WHERE [entity] = @entity
				AND [type] = ''intercompany''
				AND [table_name] = ''vendors''
				AND [id] = @vendor_id
			)
	BEGIN
		SET @is_intercompany = 1;
	END;

	RETURN @is_intercompany;
END;';

IF COL_LENGTH(N'dbo.sales_orders', N'exclusion') IS NULL

    EXEC sys.sp_executesql N'ALTER TABLE dbo.sales_orders ADD [exclusion] AS dbo.fnc_is_customer_exclusion([entity], [sell_to_customer_id]);';

IF COL_LENGTH(N'dbo.sales_orders', N'intercompany') IS NULL

    EXEC sys.sp_executesql N'ALTER TABLE dbo.sales_orders ADD [intercompany] AS dbo.fnc_is_customer_intercompany([entity], [sell_to_customer_id]);';

IF COL_LENGTH(N'dbo.purchase_orders', N'exclusion') IS NULL

    EXEC sys.sp_executesql N'ALTER TABLE dbo.purchase_orders ADD [exclusion] AS dbo.fnc_is_vendor_exclusion([entity], [vendor_id]);';

IF COL_LENGTH(N'dbo.purchase_orders', N'intercompany') IS NULL

    EXEC sys.sp_executesql N'ALTER TABLE dbo.purchase_orders ADD [intercompany] AS dbo.fnc_is_vendor_intercompany([entity], [vendor_id]);';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
