DECLARE @DbName AS SYSNAME = N'data_control';

DECLARE @SchemaName AS SYSNAME = N'dbo';

DECLARE @TableName AS SYSNAME = N'items';

DECLARE @sql AS NVARCHAR (MAX) = N'
SELECT
    c.column_id,
    c.name AS ColumnName,

    -- Full type (e.g. nvarchar(50), decimal(18,2), datetime2(7))
    CASE
        WHEN t.name IN (''varchar'',''char'',''varbinary'',''binary'')
            THEN t.name + ''('' + CASE WHEN c.max_length = -1 THEN ''max'' ELSE CONVERT(varchar(10), c.max_length) END + '')''
        WHEN t.name IN (''nvarchar'',''nchar'')
            THEN t.name + ''('' + CASE WHEN c.max_length = -1 THEN ''max'' ELSE CONVERT(varchar(10), c.max_length / 2) END + '')''
        WHEN t.name IN (''decimal'',''numeric'')
            THEN t.name + ''('' + CONVERT(varchar(10), c.precision) + '','' + CONVERT(varchar(10), c.scale) + '')''
        WHEN t.name IN (''datetime2'',''datetimeoffset'',''time'')
            THEN t.name + ''('' + CONVERT(varchar(10), c.scale) + '')''
        ELSE t.name
    END AS FullDataType,

    t.name AS BaseDataType,
    c.max_length AS MaxLengthBytes,
    c.precision,
    c.scale,

    c.is_nullable AS IsNullable,

    dc.definition AS DefaultValue,

    c.is_identity AS IsIdentity,
    ic.seed_value AS IdentitySeed,
    ic.increment_value AS IdentityIncrement,

    c.is_computed AS IsComputed,
    cc.definition AS ComputedDefinition,

    c.collation_name AS CollationName
FROM ' + QUOTENAME(@DbName) + N'.sys.columns c
JOIN ' + QUOTENAME(@DbName) + N'.sys.types t
    ON c.user_type_id = t.user_type_id
JOIN ' + QUOTENAME(@DbName) + N'.sys.tables tb
    ON c.object_id = tb.object_id
JOIN ' + QUOTENAME(@DbName) + N'.sys.schemas s
    ON tb.schema_id = s.schema_id
LEFT JOIN ' + QUOTENAME(@DbName) + N'.sys.default_constraints dc
    ON c.default_object_id = dc.object_id
LEFT JOIN ' + QUOTENAME(@DbName) + N'.sys.computed_columns cc
    ON cc.object_id = c.object_id AND cc.column_id = c.column_id
LEFT JOIN ' + QUOTENAME(@DbName) + N'.sys.identity_columns ic
    ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE tb.name = @TableName
  AND s.name = @SchemaName
ORDER BY c.column_id;
';

EXECUTE sp_executesql @sql, N'@TableName SYSNAME, @SchemaName SYSNAME', @TableName = @TableName, @SchemaName = @SchemaName;
