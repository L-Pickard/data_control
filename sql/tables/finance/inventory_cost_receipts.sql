USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- The purchase receipt lines a check (finance.inventory_cost_checks) found not fully invoiced at its as-of date, for the
-- portal to list by company and vendor as a WARNING (user decision, 15 Oct 2026: a dataset includes their expected
-- cost, so they do not block it). One row per NAV receipt line (company, receipt document and line). Quantities
-- are as at the end of the check's as-of date: quantity_invoiced counts only invoices posted on or before it, and
-- quantity_not_invoiced = quantity - quantity_invoiced (> 0). Text is NAV's at the time of the check; vendors and items
-- are not foreign keys, so a line shows even if the warehouse tables do not yet hold its vendor or item.
-- direct_unit_cost is in the receipt's own currency (currency_code; NULL = the company's currency).
-- Rows are removed with their check (ON DELETE CASCADE).
-- Permanent finance data: create only when missing. This file never drops the table. Deploy changes with a migration.

IF OBJECT_ID(N'[finance].[inventory_cost_receipts]', N'U') IS NULL
BEGIN
	CREATE TABLE [finance].[inventory_cost_receipts] (
		 [check_id] INT NOT NULL
		,[entity] NVARCHAR(20) NOT NULL
        ,[location_code] NVARCHAR(10) NOT NULL
		,[document_no] NVARCHAR(20) NOT NULL
		,[document_line_no] INT NOT NULL
		,[order_no] NVARCHAR(20) NULL
		,[posting_date] DATE NOT NULL
		,[vendor_id] NVARCHAR(20) NOT NULL
		,[vendor_name] NVARCHAR(100) NULL
		,[item_id] NVARCHAR(20) NOT NULL
		,[description] NVARCHAR(100) NULL
		,[description_2] NVARCHAR(50) NULL
		,[colours] NVARCHAR(120) NULL
		,[size_1] NVARCHAR(10) NULL
		,[size_1_unit] NVARCHAR(5) NULL
		,[currency_code] NVARCHAR(10) NULL
		,[direct_unit_cost] DECIMAL(38, 20) NULL
		,[quantity] DECIMAL(38, 20) NOT NULL
		,[quantity_invoiced] DECIMAL(38, 20) NOT NULL
		,[quantity_not_invoiced] DECIMAL(38, 20) NOT NULL
		,CONSTRAINT [PK_inventory_cost_receipts] PRIMARY KEY CLUSTERED ([check_id], [entity], [document_no], [document_line_no])
		,CONSTRAINT [FK_inventory_cost_receipts_check] FOREIGN KEY ([check_id]) REFERENCES [finance].[inventory_cost_checks] ([check_id]) ON DELETE CASCADE
		,CONSTRAINT [FK_inventory_cost_receipts_entities] FOREIGN KEY ([entity]) REFERENCES [dbo].[entities] ([entity])
		,CONSTRAINT [CK_inventory_cost_receipts_quantities] CHECK (
			[quantity_not_invoiced] > 0
			AND [quantity_invoiced] >= 0
			)
		);
END

GO
