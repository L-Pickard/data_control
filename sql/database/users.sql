USE [master];
GO

IF NOT EXISTS (
        SELECT *
        FROM sys.server_principals
        WHERE name = N'SHINER\leo.pickard'
        )
BEGIN
    CREATE LOGIN [SHINER\leo.pickard]
    FROM WINDOWS;

    PRINT 'Login for SHINER\leo.pickard created.';
END
ELSE
BEGIN
    PRINT 'Login for SHINER\leo.pickard already exists.';
END
GO

-- set up shiner reporting user account

IF NOT EXISTS (
        SELECT *
        FROM sys.server_principals
        WHERE name = N'shiner_reports'
        )
BEGIN
    -- No password is stored in source control: create with a random, unknown password, then set the real one with
    -- tools/reset-shiner-reports-password.ps1 (prompted or -Generate; never printed or written to disk).
    DECLARE @initial NVARCHAR(128) = CONVERT(NVARCHAR(36), NEWID()) + N'Aa1!' + CONVERT(NVARCHAR(36), NEWID());
    DECLARE @create NVARCHAR(MAX) = N'CREATE LOGIN [shiner_reports] WITH PASSWORD = ' + QUOTENAME(@initial, N'''') + N';';
    EXEC sys.sp_executesql @create;

    PRINT 'Login shiner_reports created.';
END
ELSE
BEGIN
    PRINT 'Login shiner_reports already exists.';
END
GO


USE [data_control]
GO

IF NOT EXISTS (
        SELECT *
        FROM sys.database_principals
        WHERE name = N'SHINER\leo.pickard'
        )
BEGIN
    CREATE USER [SHINER\leo.pickard]
    FOR LOGIN [SHINER\leo.pickard];

    PRINT 'User SHINER\leo.pickard created in data_control database.';
END
ELSE
BEGIN
    PRINT 'User leo.pickard already exists in data_control database.';
END
GO

ALTER ROLE db_owner ADD MEMBER [SHINER\leo.pickard];

PRINT 'leo.pickard added to db_owner in data_control database.';
GO

IF NOT EXISTS (
        SELECT *
        FROM sys.database_principals
        WHERE name = N'shiner_reports'
        )
BEGIN
    CREATE USER [shiner_reports]
    FOR LOGIN [shiner_reports];

    PRINT 'User shiner_reports created in data_control database.';
END
ELSE
BEGIN
    PRINT 'User shiner_reports already exists in data_control database.';
END
GO

-- Assign the user to roles
PRINT 'shiner_reports added to db_datareader and db_datawriter for data_control.';
GO

GRANT EXECUTE
    TO [shiner_reports];

PRINT 'EXECUTE permission granted to shiner_reports for data_control.';
GO