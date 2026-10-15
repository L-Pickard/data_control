USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Inventory cost dataset lines: the facts of each dataset (finance.inventory_cost), one row per company and item
-- with stock at the end of the dataset's as-of date, written once by the build procedure from
-- finance.inventory_cost_staging and never changed afterwards. The Inventory Cost report reads these lines (and
-- joins the live dbo.items and dbo.brands for names, categories and groups); it no longer reads
-- dbo.item_inventory_costs.
--   location_code, currency_code  stored, not computed, so a dataset keeps what applied when it was made
--   quantity                      item ledger quantity posted on or before the as-of date at the company's location
--   cost                          value entry actual plus expected cost with posting date on or before the as-of date,
--                                 in the company's currency (posting date, not valuation date, so it agrees with the
--                                 G/L; expected cost included as NAV values interim inventory: user decisions
--                                 15 Oct 2026)
--   expected_cost                 the part of cost that is expected cost: received but not invoiced by the as-of date
--                                 (0 when everything was invoiced)
--   cost_gbp, cost_eur, cost_usd  cost (actual + expected) converted at the dataset's stored rates (1 when the
--                                 currency is the same)
--   first_receipt, last_receipt   first and last purchase receipt (else positive adjustment) on or before the as-of
--                                 date; both NULL when the item has none
-- Items with stock are never deleted from dbo.items (user, 15 Oct 2026), so item_id references it; brand_id follows
-- the item number as in dbo.item_inventory_costs. Rows are removed with their dataset (ON DELETE CASCADE).
-- Permanent finance data: create only when missing. This file never drops the table. Deploy changes with a migration.

IF OBJECT_ID(N'[finance].[inventory_cost_lines]', N'U') IS NULL
BEGIN
	CREATE TABLE [finance].[inventory_cost_lines] (
		 [dataset_id] INT NOT NULL
		,[entity] NVARCHAR(20) NOT NULL
		,[item_id] NVARCHAR(20) NOT NULL
		,[brand_id] AS CAST(LEFT([item_id], 3) AS NVARCHAR(20)) PERSISTED
		,[location_code] NVARCHAR(10) NOT NULL
		,[currency_code] CHAR(3) NOT NULL
		,[quantity] DECIMAL(38, 20) NOT NULL
		,[cost] DECIMAL(38, 20) NOT NULL
		,[expected_cost] DECIMAL(38, 20) NOT NULL
		,[cost_gbp] DECIMAL(38, 20) NOT NULL
		,[cost_eur] DECIMAL(38, 20) NOT NULL
		,[cost_usd] DECIMAL(38, 20) NOT NULL
		,[first_receipt] DATE NULL
		,[last_receipt] DATE NULL
		,CONSTRAINT [PK_inventory_cost_lines] PRIMARY KEY CLUSTERED ([dataset_id], [entity], [item_id])
		,CONSTRAINT [FK_inventory_cost_lines_dataset] FOREIGN KEY ([dataset_id]) REFERENCES [finance].[inventory_cost] ([dataset_id]) ON DELETE CASCADE
		,CONSTRAINT [FK_inventory_cost_lines_entities] FOREIGN KEY ([entity]) REFERENCES [dbo].[entities] ([entity])
		,CONSTRAINT [FK_inventory_cost_lines_items] FOREIGN KEY ([item_id]) REFERENCES [dbo].[items] ([item_id])
		,CONSTRAINT [FK_inventory_cost_lines_brands] FOREIGN KEY ([brand_id]) REFERENCES [dbo].[brands] ([brand_id])
		,CONSTRAINT [CK_inventory_cost_lines_quantity] CHECK ([quantity] > 0)
		,CONSTRAINT [CK_inventory_cost_lines_receipts] CHECK (
			(
				[first_receipt] IS NULL
				AND [last_receipt] IS NULL
				)
			OR [first_receipt] <= [last_receipt]
			)
		);

	-- The report reads one dataset at a time, by brand and company (as IX_item_inventory_costs_brand_entity).
	CREATE NONCLUSTERED INDEX [IX_inventory_cost_lines_brand_entity]
		ON [finance].[inventory_cost_lines] ([dataset_id], [brand_id], [entity])
		INCLUDE ([quantity], [cost], [expected_cost], [cost_gbp], [cost_eur], [cost_usd], [currency_code], [first_receipt], [last_receipt]);
END

GO
