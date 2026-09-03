USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE IF EXISTS [dbo].[brands]

CREATE TABLE [dbo].[brands] (
	 [brand_id] NVARCHAR(20) NOT NULL
	,[brand_name] NVARCHAR(100) NULL
	,[buying_category] NVARCHAR(100) NULL
	,[brand_group] NVARCHAR(100) NULL
	,[revenue_group] NVARCHAR(100) NULL
	,CONSTRAINT [PK_brands] PRIMARY KEY CLUSTERED ([brand_id])
	);

GO
