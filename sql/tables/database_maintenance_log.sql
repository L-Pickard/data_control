USE [data_control];
GO
IF OBJECT_ID(N'dbo.database_maintenance_log', N'U') IS NULL
CREATE TABLE dbo.database_maintenance_log (
    log_id BIGINT IDENTITY PRIMARY KEY,
    run_id UNIQUEIDENTIFIER NOT NULL,
    started_at DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    finished_at DATETIME2(3) NULL,
    mode VARCHAR(20) NOT NULL,
    action VARCHAR(20) NOT NULL,
    schema_name SYSNAME NOT NULL,
    table_name SYSNAME NOT NULL,
    target_name SYSNAME NOT NULL,
    command NVARCHAR(MAX) NOT NULL,
    page_count BIGINT NULL,
    fragmentation_before FLOAT NULL,
    density_before FLOAT NULL,
    modifications_before BIGINT NULL,
    status VARCHAR(20) NOT NULL,
    error_message NVARCHAR(2048) NULL
);
GO
