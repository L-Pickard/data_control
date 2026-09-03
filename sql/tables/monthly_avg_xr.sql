USE [data_control];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[monthly_avg_xr]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[monthly_avg_xr] (
         [start_date]            DATE NOT NULL
        ,[end_date]              DATE NOT NULL
        ,[from_currency_code]    NVARCHAR(3) NOT NULL
        ,[to_currency_code]      NVARCHAR(3) NOT NULL
        ,[currency_pair_code]    NVARCHAR(7) NOT NULL
        ,[exchange_rate_value]   DECIMAL(38, 20) NOT NULL
        ,CONSTRAINT [PK_monthly_avg_xr]
            PRIMARY KEY CLUSTERED ([end_date], [currency_pair_code])
        ,CONSTRAINT [CK_monthly_avg_xr_date_range]
            CHECK (
                [start_date] = DATEFROMPARTS(
                    YEAR([start_date]), MONTH([start_date]), 1
                )
                AND [end_date] = EOMONTH([start_date])
            )
        ,CONSTRAINT [CK_monthly_avg_xr_currency_pair]
            CHECK (
                [from_currency_code] <> [to_currency_code]
                AND [currency_pair_code] = CONCAT(
                    [from_currency_code], N'/', [to_currency_code]
                )
            )
        ,CONSTRAINT [CK_monthly_avg_xr_positive_value]
            CHECK ([exchange_rate_value] > 0)
    );

    CREATE NONCLUSTERED INDEX
        [IX_monthly_avg_xr_currency_date_range]
    ON [dbo].[monthly_avg_xr] (
         [from_currency_code]
        ,[to_currency_code]
        ,[end_date]
    )
    INCLUDE ([start_date], [exchange_rate_value]);
END;
GO
