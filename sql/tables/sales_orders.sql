USE [data_control];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

DROP TABLE IF EXISTS [dbo].[sales_orders];

-- Grain: one row per entity, sales document type, document number and line.
-- The source query should convert NAV/BC blank strings and sentinel dates to NULL.

CREATE TABLE [dbo].[sales_orders] (
	 [order_date_key] AS [dbo].[fnc_date_key]([order_date]) PERSISTED
	,[posting_date_key] AS [dbo].[fnc_date_key]([posting_date]) PERSISTED
	,[shipment_date_key] AS [dbo].[fnc_date_key]([shipment_date]) PERSISTED
	,[entity] NVARCHAR(20) NOT NULL
	,[document_type] INTEGER NOT NULL
	,[document_no] NVARCHAR(20) NOT NULL
	,[line_no] INTEGER NOT NULL
	,[sell_to_customer_id] NVARCHAR(20) NOT NULL
	,[bill_to_customer_id] NVARCHAR(20) NOT NULL
	,[your_reference] NVARCHAR(35) NULL
	,[ship_to_country_id] NVARCHAR(10) NULL
	,[ship_to_code] NVARCHAR(10) NULL
	,[document_date] DATE NULL
	,[order_date] DATE NULL
	,[posting_date] DATE NULL
	,[shipment_date] DATE NULL
	,[payment_terms_code] NVARCHAR(10) NULL
	,[due_date] DATE NULL
	,[shipment_method_code] NVARCHAR(10) NULL
	,[location_code] NVARCHAR(10) NULL
	,[country_dimension_code] NVARCHAR(20) NULL
	,[brand_dimension_code] NVARCHAR(20) NULL
	,[customer_posting_group] NVARCHAR(20) NULL
	,[currency_code] NVARCHAR(10) NOT NULL
	,[currency_factor] DECIMAL(38,20) NULL
	,[customer_price_group] NVARCHAR(10) NULL
	,[prices_including_vat] BIT NOT NULL
	,[salesperson_id] NVARCHAR(20) NULL
	,[vat_country_id] NVARCHAR(10) NULL
	,[intercompany_document_no] NVARCHAR(20) NULL
	,[external_reference] NVARCHAR(80) NULL
	,[last_modified] DATETIME NULL
	,[preorder] BIT NOT NULL
	,[purchase_order_id] NVARCHAR(20) NULL
	,[purchase_order_line_no] INTEGER NULL
	,[drop_shipment] BIT NOT NULL
	,[document_status] INTEGER NOT NULL
	,[line_type] INTEGER NOT NULL
	,[gl_account_id] NVARCHAR(20) NULL
	,[item_id] NVARCHAR(20) NULL
	,[quantity] DECIMAL(38,20) NOT NULL
	,[outstanding_quantity] DECIMAL(38,20) NOT NULL
	,[unit_price] DECIMAL(38,20) NOT NULL
	,[unit_cost] DECIMAL(38,20) NOT NULL
	,[unit_cost_lcy] DECIMAL(38,20) NOT NULL
	,[vat_percentage] DECIMAL(38,20) NOT NULL
	,[line_discount_percentage] DECIMAL(38,20) NOT NULL
	,[amount] DECIMAL(38,20) NOT NULL
	,[amount_including_vat] DECIMAL(38,20) NOT NULL
	,[outstanding_amount] DECIMAL(38,20) NOT NULL
	,[quantity_shipped] DECIMAL(38,20) NOT NULL
	,[quantity_invoiced] DECIMAL(38,20) NOT NULL
	,CONSTRAINT [PK_sales_orders] PRIMARY KEY CLUSTERED (
		 [entity]
		,[document_type]
		,[document_no]
		,[line_no]
	)
	,CONSTRAINT [FK_sales_orders_entities] FOREIGN KEY ([entity]) REFERENCES [dbo].[entities] ([entity])
	,CONSTRAINT [FK_sales_orders_sell_to_customers] FOREIGN KEY ([sell_to_customer_id]) REFERENCES [dbo].[customers] ([customer_id])
	,CONSTRAINT [FK_sales_orders_bill_to_customers] FOREIGN KEY ([bill_to_customer_id]) REFERENCES [dbo].[customers] ([customer_id])
	,CONSTRAINT [FK_sales_orders_sales_people] FOREIGN KEY ([salesperson_id]) REFERENCES [dbo].[sales_people] ([salesperson_id])
	,CONSTRAINT [FK_sales_orders_ship_to_countries] FOREIGN KEY ([ship_to_country_id]) REFERENCES [dbo].[countries] ([country_id])
	,CONSTRAINT [FK_sales_orders_vat_countries] FOREIGN KEY ([vat_country_id]) REFERENCES [dbo].[countries] ([country_id])
	,CONSTRAINT [FK_sales_orders_brands] FOREIGN KEY ([brand_dimension_code]) REFERENCES [dbo].[brands] ([brand_id])
	,CONSTRAINT [FK_sales_orders_items] FOREIGN KEY ([item_id]) REFERENCES [dbo].[items] ([item_id])
	,CONSTRAINT [FK_sales_orders_dates_order_date_key] FOREIGN KEY ([order_date_key]) REFERENCES [dbo].[dates] ([date_key])
	,CONSTRAINT [FK_sales_orders_dates_posting_date_key] FOREIGN KEY ([posting_date_key]) REFERENCES [dbo].[dates] ([date_key])
	,CONSTRAINT [FK_sales_orders_dates_shipment_date_key] FOREIGN KEY ([shipment_date_key]) REFERENCES [dbo].[dates] ([date_key])
	,CONSTRAINT [CK_sales_orders_purchase_order_line] CHECK (
		([purchase_order_id] IS NULL AND [purchase_order_line_no] IS NULL)
		OR ([purchase_order_id] IS NOT NULL AND [purchase_order_line_no] IS NOT NULL)
	)
);

-- Supports customer order-history and customer-service lookups.
CREATE NONCLUSTERED INDEX [IX_sales_orders_customer_order_date]
	ON [dbo].[sales_orders] ([sell_to_customer_id], [order_date], [entity])
	INCLUDE ([document_no], [document_status], [currency_code], [outstanding_amount]);

-- Supports open-order, availability and expected-shipment reporting.
CREATE NONCLUSTERED INDEX [IX_sales_orders_open_item_shipment]
	ON [dbo].[sales_orders] ([item_id], [shipment_date], [entity])
	INCLUDE ([document_no], [line_no], [sell_to_customer_id], [location_code], [outstanding_quantity], [outstanding_amount])
	WHERE [document_type] = 1 AND [outstanding_quantity] <> 0;

-- Supports tracing drop-shipment sales lines back to purchase-order lines.
CREATE NONCLUSTERED INDEX [IX_sales_orders_purchase_order]
	ON [dbo].[sales_orders] ([entity], [purchase_order_id], [purchase_order_line_no])
	INCLUDE ([document_no], [line_no], [item_id], [drop_shipment])
	WHERE [purchase_order_id] IS NOT NULL;

-- Supports bill-to customer lookups and the corresponding foreign key.
CREATE NONCLUSTERED INDEX [IX_sales_orders_bill_to_customer]
	ON [dbo].[sales_orders] ([bill_to_customer_id]);

-- Supports financial-period reporting independently of the customer indexes.
CREATE NONCLUSTERED INDEX [IX_sales_orders_posting_date]
	ON [dbo].[sales_orders] ([posting_date_key], [entity])
	INCLUDE ([document_no], [sell_to_customer_id], [item_id], [amount], [amount_including_vat]);

GO
