USE [data_control];
GO

SET XACT_ABORT ON;
GO

IF COL_LENGTH('dbo.customers', 'our_account_no') IS NULL
    ALTER TABLE [dbo].[customers] ADD [our_account_no] NVARCHAR(20) NULL;
IF COL_LENGTH('dbo.customers', 'credit_limit_lcy') IS NULL
    ALTER TABLE [dbo].[customers] ADD [credit_limit_lcy] DECIMAL(38, 20) NULL;
IF COL_LENGTH('dbo.customers', 'customer_posting_group') IS NULL
    ALTER TABLE [dbo].[customers] ADD [customer_posting_group] NVARCHAR(20) NULL;
IF COL_LENGTH('dbo.customers', 'general_business_posting_group') IS NULL
    ALTER TABLE [dbo].[customers] ADD [general_business_posting_group] NVARCHAR(20) NULL;
IF COL_LENGTH('dbo.customers', 'vat_business_posting_group') IS NULL
    ALTER TABLE [dbo].[customers] ADD [vat_business_posting_group] NVARCHAR(20) NULL;
IF COL_LENGTH('dbo.customers', 'customer_price_group') IS NULL
    ALTER TABLE [dbo].[customers] ADD [customer_price_group] NVARCHAR(10) NULL;
IF COL_LENGTH('dbo.customers', 'customer_discount_group') IS NULL
    ALTER TABLE [dbo].[customers] ADD [customer_discount_group] NVARCHAR(20) NULL;
IF COL_LENGTH('dbo.customers', 'payment_terms_code') IS NULL
    ALTER TABLE [dbo].[customers] ADD [payment_terms_code] NVARCHAR(10) NULL;
IF COL_LENGTH('dbo.customers', 'payment_method_code') IS NULL
    ALTER TABLE [dbo].[customers] ADD [payment_method_code] NVARCHAR(10) NULL;
IF COL_LENGTH('dbo.customers', 'shipment_method_code') IS NULL
    ALTER TABLE [dbo].[customers] ADD [shipment_method_code] NVARCHAR(10) NULL;
IF COL_LENGTH('dbo.customers', 'shipping_agent_code') IS NULL
    ALTER TABLE [dbo].[customers] ADD [shipping_agent_code] NVARCHAR(10) NULL;
IF COL_LENGTH('dbo.customers', 'location_code') IS NULL
    ALTER TABLE [dbo].[customers] ADD [location_code] NVARCHAR(10) NULL;
IF COL_LENGTH('dbo.customers', 'blocked') IS NULL
    ALTER TABLE [dbo].[customers] ADD [blocked] INTEGER NOT NULL
        CONSTRAINT [DF_customers_blocked] DEFAULT (0);
IF COL_LENGTH('dbo.customers', 'bill_to_customer_id') IS NULL
    ALTER TABLE [dbo].[customers] ADD [bill_to_customer_id] NVARCHAR(20) NULL;
IF COL_LENGTH('dbo.customers', 'prices_including_vat') IS NULL
    ALTER TABLE [dbo].[customers] ADD [prices_including_vat] TINYINT NULL;
IF COL_LENGTH('dbo.customers', 'registration_no') IS NULL
    ALTER TABLE [dbo].[customers] ADD [registration_no] NVARCHAR(50) NULL;
IF COL_LENGTH('dbo.customers', 'eori_no') IS NULL
    ALTER TABLE [dbo].[customers] ADD [eori_no] NVARCHAR(50) NULL;
IF COL_LENGTH('dbo.customers', 'last_modified') IS NULL
    ALTER TABLE [dbo].[customers] ADD [last_modified] DATETIME NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE [name] = N'FK_customers_bill_to_customer'
)
    ALTER TABLE [dbo].[customers] WITH CHECK
        ADD CONSTRAINT [FK_customers_bill_to_customer]
        FOREIGN KEY ([bill_to_customer_id])
        REFERENCES [dbo].[customers] ([customer_id]);
GO
