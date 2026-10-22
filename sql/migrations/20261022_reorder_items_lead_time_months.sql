USE [data_control];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
SET LOCK_TIMEOUT 15000;

-- Rebuild the trailing columns without replacing the table object. This keeps
-- incoming foreign keys and table permissions attached to the same object.
-- Set to 1 only for a rollback rehearsal. The backup is retained on success.
DECLARE @rehearsal BIT = 0;
DECLARE @object_id INT = OBJECT_ID(N'dbo.items');
DECLARE @days_id INT = COLUMNPROPERTY(@object_id, N'lead_time_days', 'ColumnId');
DECLARE @sql NVARCHAR(MAX), @columns NVARCHAR(MAX), @tail NVARCHAR(MAX);
DECLARE @add NVARCHAR(MAX), @defaults NVARCHAR(MAX), @assign NVARCHAR(MAX);
DECLARE @rows BIGINT;

BEGIN TRY
    BEGIN TRANSACTION;
    SELECT @rows = COUNT_BIG(*) FROM dbo.items WITH (TABLOCKX, HOLDLOCK);

    IF @days_id IS NULL OR COL_LENGTH(N'dbo.items', N'lead_time_months') IS NULL
        THROW 50001, 'Expected lead-time columns are missing.', 1;
    IF EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id=@object_id AND name=N'lead_time_months'
          AND column_id=(SELECT MIN(column_id) FROM sys.columns WHERE object_id=@object_id AND column_id>@days_id)
    )
    BEGIN
        COMMIT;
        PRINT 'lead_time_months is already immediately after lead_time_days.';
        RETURN;
    END;
    IF OBJECT_ID(N'dbo.items_column_order_backup_20261022', N'U') IS NOT NULL
        THROW 50002, 'The retained column-order backup already exists; inspect it before retrying.', 1;

    -- Refuse unexpected dependencies instead of silently losing metadata.
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=@object_id AND column_id>@days_id
               AND (is_computed=1 OR is_identity=1 OR is_sparse=1 OR is_filestream=1 OR generated_always_type<>0))
        THROW 50003, 'Unsupported trailing column metadata.', 1;
    IF EXISTS (SELECT 1 FROM sys.foreign_key_columns WHERE
        (parent_object_id=@object_id AND parent_column_id>@days_id) OR
        (referenced_object_id=@object_id AND referenced_column_id>@days_id))
        THROW 50004, 'A foreign key references a trailing column.', 1;
    IF EXISTS (SELECT 1 FROM sys.sql_expression_dependencies WHERE referenced_id=@object_id
               AND is_schema_bound_reference=1 AND referencing_id<>@object_id)
        THROW 50005, 'A schema-bound object references items.', 1;
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=@object_id)
       OR EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id=@object_id)
       OR EXISTS (SELECT 1 FROM sys.database_permissions WHERE major_id=@object_id AND minor_id>@days_id)
       OR EXISTS (SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=@object_id AND minor_id>@days_id)
        THROW 50006, 'Unexpected constraints, triggers or column metadata require review.', 1;
    IF EXISTS (SELECT 1 FROM sys.stats s JOIN sys.stats_columns sc ON sc.object_id=s.object_id AND sc.stats_id=s.stats_id
               WHERE s.object_id=@object_id AND s.user_created=1 AND sc.column_id>@days_id)
        THROW 50007, 'User-created trailing-column statistics require review.', 1;
    IF EXISTS (SELECT 1 FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
               WHERE i.object_id=@object_id AND ic.column_id>@days_id AND i.name<>N'IX_items_common_item_no')
        THROW 50008, 'An unexpected index uses a trailing column.', 1;

    SELECT @columns=STUFF((SELECT N','+QUOTENAME(name) FROM sys.columns WHERE object_id=@object_id ORDER BY column_id FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N'');
    SELECT @tail=STUFF((SELECT N','+QUOTENAME(name) FROM sys.columns WHERE object_id=@object_id AND column_id>@days_id ORDER BY column_id FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N'');
    SELECT @assign=STUFF((SELECT N',t.'+QUOTENAME(name)+N'=b.'+QUOTENAME(name) FROM sys.columns WHERE object_id=@object_id AND column_id>@days_id ORDER BY column_id FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N'');
    SELECT @defaults=(SELECT N'ALTER TABLE dbo.items DROP CONSTRAINT '+QUOTENAME(d.name)+N';'
        FROM sys.default_constraints d WHERE d.parent_object_id=@object_id AND d.parent_column_id>@days_id FOR XML PATH(''),TYPE).value('.','nvarchar(max)');
    SELECT @add=(SELECT N'ALTER TABLE dbo.items ADD '+QUOTENAME(c.name)+N' '+QUOTENAME(TYPE_NAME(c.user_type_id))+
        CASE WHEN TYPE_NAME(c.user_type_id) IN ('decimal','numeric') THEN N'('+CONVERT(NVARCHAR(10),c.precision)+N','+CONVERT(NVARCHAR(10),c.scale)+N')'
             WHEN TYPE_NAME(c.user_type_id) IN ('nvarchar','nchar') THEN N'('+CASE WHEN c.max_length=-1 THEN N'max' ELSE CONVERT(NVARCHAR(10),c.max_length/2) END+N')'
             WHEN TYPE_NAME(c.user_type_id) IN ('varchar','char','varbinary','binary') THEN N'('+CASE WHEN c.max_length=-1 THEN N'max' ELSE CONVERT(NVARCHAR(10),c.max_length) END+N')' ELSE N'' END+
        CASE WHEN c.collation_name IS NOT NULL THEN N' COLLATE '+c.collation_name ELSE N'' END+
        CASE WHEN c.is_nullable=1 THEN N' NULL' ELSE N' NOT NULL' END+
        CASE WHEN d.object_id IS NOT NULL THEN N' CONSTRAINT '+QUOTENAME(d.name)+N' DEFAULT '+d.definition+N' WITH VALUES' ELSE N'' END+N';'
        FROM sys.columns c LEFT JOIN sys.default_constraints d ON d.object_id=c.default_object_id
        WHERE c.object_id=@object_id AND c.column_id>@days_id
        ORDER BY CASE WHEN c.name=N'lead_time_months' THEN 0 ELSE 1 END,c.column_id
        FOR XML PATH(''),TYPE).value('.','nvarchar(max)');

    SELECT * INTO dbo.items_column_order_backup_20261022 FROM dbo.items;
    DROP INDEX IX_items_common_item_no ON dbo.items;
    EXEC sys.sp_executesql @defaults;
    SET @sql=N'ALTER TABLE dbo.items DROP COLUMN '+@tail+N';';
    EXEC sys.sp_executesql @sql;
    EXEC sys.sp_executesql @add;
    SET @sql=N'UPDATE t SET '+@assign+N' FROM dbo.items t JOIN dbo.items_column_order_backup_20261022 b ON b.item_id=t.item_id;';
    EXEC sys.sp_executesql @sql;
    CREATE NONCLUSTERED INDEX IX_items_common_item_no ON dbo.items(common_item_no) INCLUDE(description,brand_id);

    SET @sql=N'IF EXISTS(SELECT '+@columns+N' FROM dbo.items EXCEPT SELECT '+@columns+N' FROM dbo.items_column_order_backup_20261022)
        OR EXISTS(SELECT '+@columns+N' FROM dbo.items_column_order_backup_20261022 EXCEPT SELECT '+@columns+N' FROM dbo.items)
        THROW 50009, ''Full row comparison failed.'', 1;';
    EXEC sys.sp_executesql @sql;
    IF (SELECT COUNT_BIG(*) FROM dbo.items)<>@rows OR OBJECT_ID(N'dbo.items')<>@object_id
        THROW 50010, 'Row count or table identity changed.', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=@object_id AND name=N'lead_time_months'
        AND column_id=(SELECT MIN(column_id) FROM sys.columns WHERE object_id=@object_id AND column_id>@days_id))
        THROW 50011, 'Physical column order verification failed.', 1;

    IF @rehearsal=1 ROLLBACK TRANSACTION;
    ELSE COMMIT TRANSACTION;
    SELECT @rows AS verified_rows, @rehearsal AS rolled_back;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

