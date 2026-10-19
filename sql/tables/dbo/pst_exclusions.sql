-- Historical filename: this defines the PST report catalogue, not exclusion rules.
-- Create this before dbo.exclusions on a fresh database. Never drop an existing catalogue.
USE data_control;
GO
IF OBJECT_ID(N'dbo.pst_reports', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.pst_reports
    (
         pst_id INT NOT NULL CONSTRAINT PK_pst_reports PRIMARY KEY CLUSTERED
        ,pst_description NVARCHAR(100) NOT NULL
        ,last_updated DATETIME2(0) NOT NULL CONSTRAINT DF_pst_reports_last_updated DEFAULT SYSUTCDATETIME()
    );
END;
GO
