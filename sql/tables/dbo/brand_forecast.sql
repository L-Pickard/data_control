USE [data_control];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[brand_forecast]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[brand_forecast] (
         [date_key] AS [dbo].[fnc_date_key]([date]) PERSISTED
        ,[entity] NVARCHAR(20) NOT NULL
        ,[brand_code] NVARCHAR(20) NOT NULL
        ,[sales_type] NVARCHAR(3) NOT NULL
        ,[date] DATE NOT NULL
        ,[currency_code] NVARCHAR(3) NOT NULL
        ,[revenue] DECIMAL(38, 20) NOT NULL
        ,[gbp_revenue] DECIMAL(38, 20) NOT NULL
        ,[eur_revenue] DECIMAL(38, 20) NOT NULL
        ,[usd_revenue] DECIMAL(38, 20) NOT NULL
        ,CONSTRAINT [PK_brand_forecast] PRIMARY KEY CLUSTERED (
             [entity]
            ,[brand_code]
            ,[sales_type]
            ,[date]
        )
        ,CONSTRAINT [CK_brand_forecast_sales_type]
            CHECK ([sales_type] IN (N'B2B', N'D2C'))
        ,CONSTRAINT [CK_brand_forecast_currency_code]
            CHECK ([currency_code] IN (N'GBP', N'EUR', N'USD'))
        ,CONSTRAINT [FK_brand_forecast_brands]
            FOREIGN KEY ([brand_code]) REFERENCES [dbo].[brands] ([brand_id])
        ,CONSTRAINT [FK_brand_forecast_entities]
            FOREIGN KEY ([entity]) REFERENCES [dbo].[entities] ([entity])
        ,CONSTRAINT [FK_brand_forecast_dates_date_key]
            FOREIGN KEY ([date_key]) REFERENCES [dbo].[dates] ([date_key])
    );

    CREATE NONCLUSTERED INDEX [IX_brand_forecast_date_currency]
        ON [dbo].[brand_forecast] ([date], [currency_code])
        INCLUDE ([revenue], [gbp_revenue], [eur_revenue], [usd_revenue]);

    CREATE NONCLUSTERED INDEX [IX_brand_forecast_brand_code]
        ON [dbo].[brand_forecast] ([brand_code])
        INCLUDE ([entity], [sales_type], [date], [revenue]);

    CREATE NONCLUSTERED INDEX [IX_brand_forecast_date_key]
        ON [dbo].[brand_forecast] ([date_key])
        INCLUDE ([entity], [brand_code], [sales_type], [revenue]);
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE [name] = N'FK_brand_forecast_dates_date_key'
      AND [parent_object_id] = OBJECT_ID(N'dbo.brand_forecast')
)
BEGIN
    ALTER TABLE [dbo].[brand_forecast] WITH CHECK
        ADD CONSTRAINT [FK_brand_forecast_dates_date_key]
        FOREIGN KEY ([date_key]) REFERENCES [dbo].[dates] ([date_key]);
END;
GO

IF COL_LENGTH(N'dbo.brand_forecast', N'entity') < 40
BEGIN
    ALTER TABLE [dbo].[brand_forecast]
        ALTER COLUMN [entity] NVARCHAR(20) NOT NULL;
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE [name] = N'FK_brand_forecast_entities'
      AND [parent_object_id] = OBJECT_ID(N'dbo.brand_forecast')
)
BEGIN
    ALTER TABLE [dbo].[brand_forecast] WITH CHECK
        ADD CONSTRAINT [FK_brand_forecast_entities]
        FOREIGN KEY ([entity]) REFERENCES [dbo].[entities] ([entity]);
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE [name] = N'FK_brand_forecast_brands'
      AND [parent_object_id] = OBJECT_ID(N'dbo.brand_forecast')
)
BEGIN
    ALTER TABLE [dbo].[brand_forecast] WITH CHECK
        ADD CONSTRAINT [FK_brand_forecast_brands]
        FOREIGN KEY ([brand_code]) REFERENCES [dbo].[brands] ([brand_id]);
END;
GO
