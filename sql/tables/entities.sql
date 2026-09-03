USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE

IF EXISTS [dbo].[entities]
	CREATE TABLE [dbo].[entities] (
		 [entity] NVARCHAR(20) NOT NULL
		,[short_name] NVARCHAR(10) NOT NULL
		,[display_order] INT NOT NULL
		,[currency_code] CHAR(3) NOT NULL
		,[sales_increment] DATE NOT NULL CONSTRAINT [DF_entities_sales_increment] DEFAULT ('2025-04-30')
		,[logo_image] VARCHAR(MAX) NULL
		,CONSTRAINT [PK_entities] PRIMARY KEY CLUSTERED ([entity])
		,CONSTRAINT [UQ_entities_display_order] UNIQUE ([display_order])
		,CONSTRAINT [CK_entities_display_order] CHECK ([display_order] > 0)
		,CONSTRAINT [CK_entities_currency_code] CHECK ([currency_code] COLLATE Latin1_General_100_BIN2 LIKE '[A-Z][A-Z][A-Z]')
		);

GO

INSERT INTO [dbo].[entities] (
	 [entity]
	,[short_name]
	,[display_order]
	,[currency_code]
	,[sales_increment]
	,[logo_image]
	)


VALUES
	 (N'Example Ltd', N'Ltd', 1, 'GBP', '2025-04-30', NULL)
	,(N'Example BV', N'B.V', 2, 'EUR', '2025-04-30', NULL)
	,(N'Example LLC', N'LLC', 3, 'USD', '2025-04-30', NULL);

GO
