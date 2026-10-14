USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE IF EXISTS [dbo].[vendors];

CREATE TABLE [dbo].[vendors] (
	 [vendor_id] NVARCHAR(20) NOT NULL
	,[vendor_name] NVARCHAR(100) NULL
	,[address] NVARCHAR(100) NULL
	,[address_2] NVARCHAR(50) NULL
	,[city] NVARCHAR(30) NULL
	,[county] NVARCHAR(30) NULL
	,[post_code] NVARCHAR(20) NULL
	,[country_id] NVARCHAR(10) NULL
	,[contact_name] NVARCHAR(100) NULL
	,[phone_no] NVARCHAR(30) NULL
	,[mobile_phone_no] NVARCHAR(30) NULL
	,[email] NVARCHAR(80) NULL
	,[home_page] NVARCHAR(255) NULL
	,[primary_contact_no] NVARCHAR(20) NULL
	,[our_account_no] NVARCHAR(20) NULL
	,[country_dimension] NVARCHAR(20) NULL
	,[vendor_posting_group] NVARCHAR(20) NULL
	,[general_business_posting_group] NVARCHAR(20) NULL
	,[vat_business_posting_group] NVARCHAR(20) NULL
	,[currency_code] NVARCHAR(10) NULL
	,[payment_terms_code] NVARCHAR(10) NULL
	,[payment_method_code] NVARCHAR(10) NULL
	,[purchaser_code] NVARCHAR(20) NULL
	,[shipment_method_code] NVARCHAR(10) NULL
	,[location_code] NVARCHAR(10) NULL
	,[lead_time_calculation] VARCHAR(32) NULL
	,[blocked] INTEGER NOT NULL CONSTRAINT [DF_vendors_blocked] DEFAULT (0)
	,[pay_to_vendor_id] NVARCHAR(20) NULL
	,[vat_registration_no] NVARCHAR(20) NULL
	,[registration_no] NVARCHAR(50) NULL
	,[eori_no] NVARCHAR(40) NULL
	,[last_modified] DATETIME NULL
	,CONSTRAINT [PK_vendors] PRIMARY KEY CLUSTERED ([vendor_id])
	,CONSTRAINT [FK_vendors_countries] FOREIGN KEY ([country_id]) REFERENCES [dbo].[countries] ([country_id])
	,CONSTRAINT [FK_vendors_sales_people] FOREIGN KEY ([purchaser_code]) REFERENCES [dbo].[sales_people] ([salesperson_id])
	,CONSTRAINT [FK_vendors_pay_to_vendor] FOREIGN KEY ([pay_to_vendor_id]) REFERENCES [dbo].[vendors] ([vendor_id])
);

CREATE NONCLUSTERED INDEX [IX_vendors_country_id]
	ON [dbo].[vendors] ([country_id]);

CREATE NONCLUSTERED INDEX [IX_vendors_pay_to_vendor_id]
	ON [dbo].[vendors] ([pay_to_vendor_id]);

CREATE NONCLUSTERED INDEX [IX_vendors_purchaser_code]
	ON [dbo].[vendors] ([purchaser_code]);

GO
