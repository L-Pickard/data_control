USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE

IF EXISTS [dbo].[customers]
	CREATE TABLE [dbo].[customers] (
		[customer_id] NVARCHAR(20) NOT NULL
		,[customer_name] NVARCHAR(100) NULL
		,[address] NVARCHAR(100) NULL
		,[address_2] NVARCHAR(50) NULL
		,[city] NVARCHAR(30) NULL
		,[county] NVARCHAR(30) NULL
		,[country_id] NVARCHAR(10) NULL
		,[post_code] NVARCHAR(20) NULL
		,[territory_code] NVARCHAR(10) NULL
		,[contact_name] NVARCHAR(100) NULL
		,[phone_no] NVARCHAR(30) NULL
		,[mobile_phone_no] NVARCHAR(30) NULL
		,[email] NVARCHAR(80) NULL
		,[home_page] NVARCHAR(255) NULL
		,[primary_contact_no] NVARCHAR(20) NULL
		,[our_account_no] NVARCHAR(20) NULL
		,[currency_code] NVARCHAR(10) NULL
		,[credit_limit_lcy] DECIMAL(38, 20) NULL
		,[customer_posting_group] NVARCHAR(20) NULL
		,[general_business_posting_group] NVARCHAR(20) NULL
		,[vat_business_posting_group] NVARCHAR(20) NULL
		,[customer_price_group] NVARCHAR(10) NULL
		,[customer_discount_group] NVARCHAR(20) NULL
		,[payment_terms_code] NVARCHAR(10) NULL
		,[payment_method_code] NVARCHAR(10) NULL
		,[shipment_method_code] NVARCHAR(10) NULL
		,[shipping_agent_code] NVARCHAR(10) NULL
		,[location_code] NVARCHAR(10) NULL
		,[type_of_supply_code] NVARCHAR(10) NULL
		,[type_of_supply_description] NVARCHAR(30) NULL
		,[salesperson_id] NVARCHAR(20) NULL
		,[blocked] INTEGER NOT NULL CONSTRAINT [DF_customers_blocked] DEFAULT(0)
		,[bill_to_customer_id] NVARCHAR(20) NULL
		,[prices_including_vat] TINYINT NULL
		,[vat_reg_no] NVARCHAR(20) NULL
		,[registration_no] NVARCHAR(50) NULL
		,[eori_no] NVARCHAR(50) NULL
		,[last_modified] DATETIME NULL
		,CONSTRAINT PK_customers PRIMARY KEY CLUSTERED ([customer_id])
		,CONSTRAINT FK_customers_countries FOREIGN KEY ([country_id]) REFERENCES [dbo].[countries]([country_id])
		,CONSTRAINT FK_customers_sales_people FOREIGN KEY ([salesperson_id]) REFERENCES [dbo].[sales_people]([salesperson_id])
		,CONSTRAINT FK_customers_bill_to_customer FOREIGN KEY ([bill_to_customer_id]) REFERENCES [dbo].[customers]([customer_id])
		);

CREATE NONCLUSTERED INDEX IX_customers_country_id ON [dbo].[customers] ([country_id]);

CREATE NONCLUSTERED INDEX IX_customers_salesperson_id ON [dbo].[customers] ([salesperson_id]);

CREATE NONCLUSTERED INDEX IX_customers_bill_to_customer_id ON [dbo].[customers] ([bill_to_customer_id]);

GO



