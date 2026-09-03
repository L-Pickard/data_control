USE [data_control]
GO

SET XACT_ABORT ON;


DROP TABLE IF EXISTS [dbo].[sales_people]


	CREATE TABLE [dbo].[sales_people] (
		 [salesperson_id] NVARCHAR(20)
		,[name] NVARCHAR(100) NOT NULL CONSTRAINT df_sales_people_name DEFAULT ('')
		,[email] NVARCHAR(100) NOT NULL CONSTRAINT df_sales_people_email DEFAULT ('')
		,[active] BIT NOT NULL CONSTRAINT df_sales_people_active DEFAULT (0)
		,CONSTRAINT pk_sales_people PRIMARY KEY CLUSTERED ([salesperson_id])
	);

	CREATE NONCLUSTERED INDEX idx_salesperson_name
	ON [dbo].[sales_people] ([name])
	INCLUDE ([salesperson_id], [email]);

	CREATE NONCLUSTERED INDEX idx_salesperson_email
	ON [dbo].[sales_people] ([email])
	INCLUDE ([salesperson_id], [name]);

