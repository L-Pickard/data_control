USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE IF EXISTS [dbo].[purchase_orders];

-- Grain: one row per entity, purchase document type, document number and line.
-- This table contains current (unposted) purchase documents from BC/NAV.

CREATE TABLE [dbo].[purchase_orders] (
	 [entity] NVARCHAR(20) NOT NULL
	,[document_type] INTEGER NOT NULL
	,[document_type_name] NVARCHAR(20) NOT NULL
	,[document_no] NVARCHAR(20) NOT NULL
	,[line_no] INTEGER NOT NULL
	,[item_id] NVARCHAR(20) NULL
	,[vendor_id] NVARCHAR(20) NULL
	,[pay_to_vendor_id] NVARCHAR(20) NULL
	,[location_code] NVARCHAR(10) NULL
	,[unit_of_measure_code] NVARCHAR(10) NULL
	,[purchaser_code] NVARCHAR(20) NULL
	,[currency_code] NVARCHAR(10) NULL
	,[currency_factor] DECIMAL(38,20) NULL
	,[document_status] INTEGER NULL
	,[document_status_name] NVARCHAR(20) NULL
	,[order_date] DATE NULL
	,[document_date] DATE NULL
	,[posting_date] DATE NULL
	,[expected_receipt_date] DATE NULL
	,[requested_receipt_date] DATE NULL
	,[promised_receipt_date] DATE NULL
	,[planned_receipt_date] DATE NULL
	,[due_date] DATE NULL
	,[your_reference] NVARCHAR(35) NULL
	,[vendor_order_no] NVARCHAR(35) NULL
	,[vendor_invoice_no] NVARCHAR(35) NULL
	,[shipment_method_code] NVARCHAR(10) NULL
	,[country_dimension_code] NVARCHAR(20) NULL -- dimension code 1
	,[brand_dimension_code] NVARCHAR(20) NULL -- dimension code 2
	,[drop_shipment] BIT NULL
	,[quantity] DECIMAL(38,20) NULL
	,[quantity_received] DECIMAL(38,20) NULL
	,[quantity_invoiced] DECIMAL(38,20) NULL
	,[quantity_to_receive] DECIMAL(38,20) NULL
	,[outstanding_quantity] DECIMAL(38,20) NULL
	,[direct_unit_cost] DECIMAL(38,20) NULL
	,[unit_cost_lcy] DECIMAL(38,20) NULL
	,[line_discount_percent] DECIMAL(38,20) NULL
	,[line_discount_amount] DECIMAL(38,20) NULL
	,[line_amount] DECIMAL(38,20) NULL
	,[amount_including_vat] DECIMAL(38,20) NULL
	,[outstanding_amount] DECIMAL(38,20) NULL
	,[outstanding_amount_lcy] DECIMAL(38,20) NULL
	,[afloat] BIT NULL
	,[container_no] NVARCHAR(50) NULL
	,[waybill_no] NVARCHAR(50) NULL
	,[date_afloat] DATE NULL
	,[requested_xf_date] DATE NULL
	,[promised_xf_date] DATE NULL
	,[actual_xf_date] DATE NULL
	,[deposit_payment_date] DATE NULL
	,[balance_payment_date] DATE NULL
	,[external_reference] NVARCHAR(80) NULL
	,[intercompany_document_no] NVARCHAR(20) NULL
	,[sent_to_3pl] BIT NULL
	,[sent_to_3pl_at] DATETIME NULL
	,[last_modified] DATETIME NULL
	,CONSTRAINT [PK_purchase_orders] PRIMARY KEY CLUSTERED (
		 [entity]
		,[document_type]
		,[document_no]
		,[line_no]
	)
	,CONSTRAINT [FK_purchase_orders_vendors] FOREIGN KEY ([vendor_id])
		REFERENCES [dbo].[vendors] ([vendor_id])
	,CONSTRAINT [FK_purchase_orders_items] FOREIGN KEY ([item_id])
		REFERENCES [dbo].[items] ([item_id])
	,CONSTRAINT [FK_purchase_orders_entities] FOREIGN KEY ([entity])
		REFERENCES [dbo].[entities] ([entity])
);

-- Supports open purchase-order and inbound-stock reporting.

CREATE NONCLUSTERED INDEX [IX_purchase_orders_open_receipts]
	ON [dbo].[purchase_orders] (
		 [entity]
		,[expected_receipt_date]
		,[item_id]
	)
	INCLUDE (
		 [document_no]
		,[vendor_id]
		,[location_code]
		,[outstanding_quantity]
		,[outstanding_amount]
		,[outstanding_amount_lcy]
		,[afloat]
		,[container_no]
	)
	WHERE [document_type] = 1
		AND [outstanding_quantity] <> 0;

GO
