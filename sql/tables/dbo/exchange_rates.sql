USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE IF EXISTS [dbo].[exchange_rates];

CREATE TABLE [dbo].[exchange_rates] (
	 [currency_code] NVARCHAR(10) NOT NULL
	,[starting_date] DATE NOT NULL
	,[relational_currency_code] NVARCHAR(10) NOT NULL
	,[exchange_rate_amount] DECIMAL(38, 20) NOT NULL
	,CONSTRAINT [PK_exchange_rates] PRIMARY KEY CLUSTERED (
		 [currency_code]
		,[starting_date]
		,[relational_currency_code]
		)
	);
