USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

DROP TABLE

IF EXISTS [dbo].[preorder_totals]
BEGIN
	CREATE TABLE [dbo].[preorder_totals] (
		 [deadline] DATETIME2(3) NULL
		,[eta] DATETIME2(3) NULL
		,[timestamp] DATETIME2(3) NOT NULL
		,[preorder_code] NVARCHAR(50) NOT NULL
		,[customer_id] NVARCHAR(20) NOT NULL
		,[customer_name] NVARCHAR(100) NULL
		,[salesperson_id] NVARCHAR(20) NOT NULL
		,[email] NVARCHAR(100) NOT NULL
		,[entries] INTEGER NOT NULL
		,[quantity] DECIMAL(38, 20) NULL
		,[currency_code] NVARCHAR(10) NOT NULL
		,[value] DECIMAL(38, 20) NULL
		,CONSTRAINT [PK_preorder_totals] PRIMARY KEY CLUSTERED (
			[preorder_code]
			,[customer_id]
			,[currency_code]
			)
		)

END

