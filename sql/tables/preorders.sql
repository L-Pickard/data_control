USE [data_control];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

DROP TABLE IF EXISTS [dbo].[preorders]

BEGIN
    CREATE TABLE [dbo].[preorders] (
	     [preorder_id]          BIGINT IDENTITY(1,1) NOT NULL
        ,[date_key]             AS [dbo].[fnc_date_key](CAST([order_timestamp] AS DATE)) PERSISTED
		,[date_key_ny]          AS [dbo].[fnc_date_key](DATEADD(YEAR, 1, CAST([order_timestamp] AS DATE))) PERSISTED
        ,[line_key]             AS CAST(
            CASE
                WHEN NULLIF(LTRIM(RTRIM([item_id])), N'') IS NOT NULL
                    THEN N'I:' + LTRIM(RTRIM([item_id]))
                ELSE N'D:' + ISNULL(LTRIM(RTRIM([description])), N'')
            END AS NVARCHAR(302)
        ) PERSISTED
        ,[file_source]          NVARCHAR(20) NOT NULL
        ,[preorder_code]        NVARCHAR(50) NOT NULL
        ,[item_id]              NVARCHAR(50) NULL
        ,[description]          NVARCHAR(300) NULL
        ,[customer_id]          NVARCHAR(20) NOT NULL
        ,[order_timestamp]      DATETIME2(3) NOT NULL
        ,[order_timestamp_missing] BIT NOT NULL
        ,[season]               NVARCHAR(20) NULL
        ,[type]                 INTEGER NULL
        ,[brand_code]           NVARCHAR(20) NULL
        ,[category_code]        NVARCHAR(20) NULL
        ,[country_id]           NVARCHAR(10) NULL
        ,[quantity]             DECIMAL(38, 20) NULL
        ,[value]                DECIMAL(38, 20) NULL
        ,[currency_code]        NVARCHAR(10) NOT NULL
        ,[start_timestamp]      DATETIME2(3) NULL
        ,[end_timestamp]        DATETIME2(3) NULL
        ,[eta_timestamp]        DATETIME2(3) NULL
        ,[is_current]           BIT NOT NULL
        ,[first_seen_at]        DATETIME2(7) NOT NULL    CONSTRAINT [DF_preorders_first_seen_at] DEFAULT (SYSDATETIME())
        ,[last_seen_at]         DATETIME2(7) NOT NULL    CONSTRAINT [DF_preorders_last_seen_at] DEFAULT (SYSDATETIME())
        ,[last_changed_at]      DATETIME2(7) NOT NULL    CONSTRAINT [DF_preorders_last_changed_at] DEFAULT (SYSDATETIME())
        ,CONSTRAINT [PK_preorders] PRIMARY KEY CLUSTERED ([preorder_id]));

    CREATE UNIQUE NONCLUSTERED INDEX [UX_preorders_business_key]
        ON [dbo].[preorders] (
             [preorder_code]
            ,[line_key]
            ,[customer_id]
            ,[currency_code]
            ,[order_timestamp]
            ,[order_timestamp_missing]
        );

END;
GO
