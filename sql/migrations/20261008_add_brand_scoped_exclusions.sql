USE data_control;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
BEGIN TRY
    BEGIN TRANSACTION;
    SELECT entity, [type], table_name, id INTO #original_rules FROM dbo.exclusions;
    IF COL_LENGTH(N'dbo.exclusions', N'brand_id') IS NULL
    BEGIN
        ALTER TABLE dbo.exclusions ADD brand_id NVARCHAR(20) NOT NULL
            CONSTRAINT DF_exclusions_brand_id DEFAULT (N'') WITH VALUES;
        ALTER TABLE dbo.exclusions DROP CONSTRAINT PK_exclusions;
        EXEC sys.sp_executesql N'ALTER TABLE dbo.exclusions ADD CONSTRAINT PK_exclusions
            PRIMARY KEY CLUSTERED (entity, [type], table_name, id, brand_id);
        ALTER TABLE dbo.exclusions ADD CONSTRAINT CK_exclusions_brand_scope
            CHECK (brand_id = N'''' OR ([type] = N''exclusion'' AND table_name = N''customers''));';
    END;
    -- Recreate only this computed column to change the function signature.
    DECLARE @computed TABLE (row_id INT IDENTITY, schema_name SYSNAME, table_name SYSNAME,
        column_name SYSNAME, definition NVARCHAR(MAX));
    INSERT @computed (schema_name, table_name, column_name, definition)
    SELECT OBJECT_SCHEMA_NAME(object_id), OBJECT_NAME(object_id), name, definition
    FROM sys.computed_columns
    WHERE definition LIKE N'%fnc_is_customer_exclusion%'
       OR definition LIKE N'%fnc_is_customer_intercompany%'
       OR definition LIKE N'%fnc_is_vendor_exclusion%'
       OR definition LIKE N'%fnc_is_vendor_intercompany%';
    DECLARE @i INT = 1, @last INT = (SELECT MAX(row_id) FROM @computed), @ddl NVARCHAR(MAX);
    WHILE @i <= @last
    BEGIN
        SELECT @ddl = N'ALTER TABLE ' + QUOTENAME(schema_name) + N'.' + QUOTENAME(table_name)
            + N' DROP COLUMN ' + QUOTENAME(column_name) FROM @computed WHERE row_id = @i;
        EXEC sys.sp_executesql @ddl;
        SET @i += 1;
    END;
    EXEC sys.sp_executesql N'CREATE OR ALTER FUNCTION [dbo].[fnc_is_customer_exclusion] (
	 @entity NVARCHAR(20)
	,@customer_id NVARCHAR(20)
	,@brand_id NVARCHAR(20)
	)
RETURNS BIT
AS
/*===============================================================================================================================================
Returns 1 when the entity/customer combination is configured as a customer
exclusion in dbo.exclusions for all brands (blank brand_id) or the supplied brand; otherwise returns 0.
===============================================================================================================================================*/
BEGIN
	DECLARE @is_exclusion BIT = 0;

	IF EXISTS (
			SELECT 1
			FROM [dbo].[exclusions]
			WHERE [entity] = @entity
				AND [type] = ''exclusion''
				AND [table_name] = ''customers''
				AND [id] = @customer_id
				AND ([brand_id] = N'''' OR [brand_id] = @brand_id)
			)
	BEGIN
		SET @is_exclusion = 1;
	END;

	RETURN @is_exclusion;
END;';
    EXEC sys.sp_executesql N'CREATE OR ALTER FUNCTION [dbo].[fnc_is_customer_intercompany] (
	 @entity NVARCHAR(20)
	,@customer_id NVARCHAR(20)
	)
RETURNS BIT
AS
/*===============================================================================================================================================
Returns 1 when the entity/customer combination is configured as an intercompany
customer in dbo.exclusions; otherwise returns 0.
===============================================================================================================================================*/
BEGIN
	DECLARE @is_intercompany BIT = 0;

	IF EXISTS (
			SELECT 1
			FROM [dbo].[exclusions]
			WHERE [entity] = @entity
				AND [type] = ''intercompany''
				AND [table_name] = ''customers''
				AND [id] = @customer_id
				AND [brand_id] = N''''
			)
	BEGIN
		SET @is_intercompany = 1;
	END;

	RETURN @is_intercompany;
END;';
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
				AND [brand_id] = N''''
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
				AND [brand_id] = N''''
			)
	BEGIN
		SET @is_intercompany = 1;
	END;

	RETURN @is_intercompany;
END;';
    EXEC sys.sp_executesql N'-- Blank brand_id preserves whole-customer/vendor rules. These rules are brand-specific.
INSERT dbo.exclusions (entity, [type], table_name, id, brand_id)
SELECT en.entity, N''exclusion'', N''customers'', cu.id, br.brand_id
FROM dbo.entities AS en
CROSS JOIN (VALUES (N''CU100487''), (N''CU108312'')) AS cu(id)
CROSS JOIN (VALUES (N''BSC''), (N''BUU''), (N''CRE''), (N''KRX''), (N''MOB''),
                   (N''OJW''), (N''RIC''), (N''SLM''), (N''SCR''), (N''IND''), (N''NHS'')) AS br(brand_id)
WHERE NOT EXISTS (SELECT 1 FROM dbo.exclusions AS ex
    WHERE ex.entity = en.entity AND ex.[type] = N''exclusion''
      AND ex.table_name = N''customers'' AND ex.id = cu.id AND ex.brand_id = br.brand_id);
';
    UPDATE @computed SET definition = N'dbo.fnc_is_customer_exclusion(entity, sell_to_customer_id, CAST(LEFT(item_id, 3) AS NVARCHAR(20)))'
    WHERE schema_name=N'dbo' AND table_name=N'sales_orders' AND column_name=N'exclusion';
    SET @i = 1;
    WHILE @i <= @last
    BEGIN
        SELECT @ddl = N'ALTER TABLE ' + QUOTENAME(schema_name) + N'.' + QUOTENAME(table_name)
            + N' ADD ' + QUOTENAME(column_name) + N' AS ' + definition
        FROM @computed WHERE row_id = @i;
        EXEC sys.sp_executesql @ddl;
        SET @i += 1;
    END;
    -- Preserve the deployed procedure, changing only its exclusion call.
    DECLARE @loader NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.update_sales_table'));
    DECLARE @old NVARCHAR(MAX) = N'[dbo].[fnc_is_customer_exclusion](st.[entity], st.[customer_id])';
    DECLARE @new NVARCHAR(MAX) = N'[dbo].[fnc_is_customer_exclusion](st.[entity], st.[customer_id], CAST(LEFT(st.[item_id], 3) AS NVARCHAR(20)))';
    IF CHARINDEX(@old, @loader) > 0
    BEGIN
        SET @loader = REPLACE(@loader, @old, @new);
        -- OBJECT_DEFINITION may contain arbitrary whitespace between CREATE and PROCEDURE.
        DECLARE @procedure_at INT = CHARINDEX(N'PROCEDURE', @loader);
        IF @procedure_at = 0 THROW 51000, 'Cannot find procedure declaration.', 1;
        SET @loader = N'ALTER ' + SUBSTRING(@loader, @procedure_at, LEN(@loader));
        EXEC sys.sp_executesql @loader;
    END
    ELSE IF @loader IS NULL OR CHARINDEX(@new, @loader) = 0
        THROW 51000, 'Unexpected sales loader definition; migration rolled back.', 1;
    EXEC sys.sp_executesql N'
        UPDATE s SET exclusion = dbo.fnc_is_customer_exclusion(s.entity, s.customer_id, s.brand_id)
        FROM dbo.sales AS s
        WHERE s.customer_id IN (N''CU100487'', N''CU108312'')
          AND s.exclusion <> dbo.fnc_is_customer_exclusion(s.entity, s.customer_id, s.brand_id);
        SELECT @@ROWCOUNT AS sales_flags_updated;';
    IF EXISTS (SELECT entity, [type], table_name, id FROM #original_rules
        EXCEPT SELECT entity, [type], table_name, id FROM dbo.exclusions)
        THROW 51000, 'An existing exclusion record was lost.', 1;
    EXEC sys.sp_executesql N'-- Check all 66 customer/brand combinations and preservation of whole-customer rules.
IF EXISTS (
    SELECT 1 FROM dbo.entities AS en
    CROSS JOIN (VALUES (N''CU100487''), (N''CU108312'')) AS cu(id)
    CROSS JOIN (VALUES (N''BSC''), (N''BUU''), (N''CRE''), (N''KRX''), (N''MOB''),
                       (N''OJW''), (N''RIC''), (N''SLM''), (N''SCR''), (N''IND''), (N''NHS'')) AS br(id)
    WHERE dbo.fnc_is_customer_exclusion(en.entity, cu.id, br.id) <> 1
) THROW 51000, ''A customer-brand rule did not match.'', 1;
IF EXISTS (
    SELECT 1 FROM dbo.exclusions AS ex
    WHERE ex.[type] = N''exclusion'' AND ex.table_name = N''customers'' AND ex.brand_id = N''''
      AND (dbo.fnc_is_customer_exclusion(ex.entity, ex.id, N''__OTHER__'') <> 1
           OR dbo.fnc_is_customer_exclusion(ex.entity, ex.id, NULL) <> 1)
) THROW 51000, ''An existing whole-customer rule failed.'', 1;
IF EXISTS (
    SELECT 1 FROM dbo.entities AS en
    CROSS JOIN (VALUES (N''CU100487''), (N''CU108312'')) AS cu(id)
    WHERE dbo.fnc_is_customer_exclusion(en.entity, cu.id, N''__OTHER__'') <>
        CASE WHEN EXISTS (SELECT 1 FROM dbo.exclusions AS ex
            WHERE ex.entity=en.entity AND ex.[type]=N''exclusion''
              AND ex.table_name=N''customers'' AND ex.id=cu.id AND ex.brand_id=N'''') THEN 1 ELSE 0 END
       OR dbo.fnc_is_customer_exclusion(en.entity, N''__OTHER_CUSTOMER__'', N''BSC'') <> 0
) THROW 51000, ''The brand rules excluded an unrelated combination.'', 1;
IF EXISTS (
    SELECT 1 FROM dbo.sales
    WHERE customer_id IN (N''CU100487'', N''CU108312'')
      AND exclusion <> dbo.fnc_is_customer_exclusion(entity, customer_id, brand_id)
) THROW 51000, ''Existing sales flags do not match the new rules.'', 1;
IF EXISTS (
    SELECT 1 FROM dbo.sales_orders
    WHERE sell_to_customer_id IN (N''CU100487'', N''CU108312'')
      AND exclusion <> dbo.fnc_is_customer_exclusion(entity, sell_to_customer_id, brand_id)
) THROW 51000, ''Sales order flags do not match the new rules.'', 1;
SELECT N''Passed'' AS brand_exclusion_validation;
';
    DROP TABLE #original_rules;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
