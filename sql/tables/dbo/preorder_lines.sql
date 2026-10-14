USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

DROP TABLE IF EXISTS [dbo].[preorder_lines];
GO

CREATE TABLE [dbo].[preorder_lines] (
		[row_no] INTEGER IDENTITY(1, 1) NOT NULL
	,[preorder_code] NVARCHAR(50) NULL
	,[region] NVARCHAR(10) NULL
	,[brand_code] NVARCHAR(10) NULL
	,[type] INTEGER NULL
	,[season] NVARCHAR(20) NULL
	,[item_id] NVARCHAR(50) NULL
	,[description] NVARCHAR(300) NULL
	,[price_string] NVARCHAR(50) NULL
	,[currency_code] AS CAST(CASE
			WHEN LEFT([price_string], 2) = N'C_'
				AND CHARINDEX(N'=', [price_string]) > 3
				THEN SUBSTRING([price_string], 3, CHARINDEX(N'=', [price_string]) - 3)
			END AS NVARCHAR(10)) PERSISTED
	,[trade_price] AS TRY_CONVERT(DECIMAL(38, 20), CASE 
			WHEN CHARINDEX(N'=', [price_string]) > 0
				AND CHARINDEX(N' SRP=', [price_string]) > CHARINDEX(N'=', [price_string]) + 1
				THEN SUBSTRING([price_string], CHARINDEX(N'=', [price_string]) + 1, CHARINDEX(N' SRP=', [price_string]) - CHARINDEX(N'=', [price_string]) - 1)
			END) PERSISTED
	,[srp_price] AS TRY_CONVERT(DECIMAL(38, 20), CASE 
			WHEN CHARINDEX(N' SRP=', [price_string]) > 0
				AND CHARINDEX(N' SRP=', [price_string]) + LEN(N' SRP=') <= LEN([price_string])
				THEN SUBSTRING([price_string], CHARINDEX(N' SRP=', [price_string]) + LEN(N' SRP='), LEN([price_string]))
			END) PERSISTED
	,CONSTRAINT [PK_preorder_lines] PRIMARY KEY CLUSTERED ([row_no])
	);


GO

CREATE NONCLUSTERED INDEX [IX_preorder_lines_preorder_currency_item] ON [dbo].[preorder_lines] (
	 [preorder_code]
	,[currency_code]
	,[item_id]
	) INCLUDE (
	[trade_price]
	,[srp_price]
	);

GO

CREATE NONCLUSTERED INDEX [IX_preorder_lines_item] ON [dbo].[preorder_lines] ([item_id]) INCLUDE (
	[preorder_code]
	,[currency_code]
	,[trade_price]
	,[srp_price]
	);

GO
