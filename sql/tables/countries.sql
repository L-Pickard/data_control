USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE

IF EXISTS [dbo].[countries]

	CREATE TABLE [dbo].[countries] (
		 [country_id] NVARCHAR(10) NOT NULL
		,[iso_code] NVARCHAR(2) NOT NULL 		CONSTRAINT [DF_countries_iso_code] DEFAULT(N'')
		,[country_name] NVARCHAR(50) NOT NULL 	CONSTRAINT [DF_countries_country_name] DEFAULT(N'')
		,[flag_image_url] NVARCHAR(70) NULL
		,CONSTRAINT [PK_countries] PRIMARY KEY CLUSTERED ([country_id])
		)

CREATE NONCLUSTERED INDEX ix_countries_iso_code ON [dbo].[countries] ([iso_code]);