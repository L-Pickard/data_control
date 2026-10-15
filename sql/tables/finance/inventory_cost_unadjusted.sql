USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- The item ledger entries a check (finance.inventory_cost_checks) found still flagged "Applied Entry to Adjust" (FIFO:
-- Adjust Cost - Item Entries has not reached them), shown in the portal as a WARNING, not a blocker (user decision,
-- 15 Oct 2026: NAV keeps a few such entries every month and never clears them). Scoped to what can affect the
-- dataset (user decision): the company's dataset location (Ltd BRISTOL, B.V 3PL, LLC POMONA) and entries posted in
-- the 12 months up to the check's as-of date. remaining_quantity is the entry's open quantity now (> 0 = stock from
-- this entry is still held, so its cost is in the dataset). entry_type is NAV's: Purchase, Sale, Positive Adjmt.,
-- Negative Adjmt., Transfer, or the number for any other. Rows are removed with their check (ON DELETE CASCADE).
-- Permanent finance data: create only when missing. This file never drops the table. Deploy changes with a migration.

IF OBJECT_ID(N'[finance].[inventory_cost_unadjusted]', N'U') IS NULL
BEGIN
	CREATE TABLE [finance].[inventory_cost_unadjusted] (
		 [check_id] INT NOT NULL
		,[entity] NVARCHAR(20) NOT NULL
		,[entry_no] INT NOT NULL
		,[posting_date] DATE NOT NULL
		,[entry_type] NVARCHAR(20) NOT NULL
		,[document_no] NVARCHAR(20) NULL
		,[item_id] NVARCHAR(20) NOT NULL
		,[quantity] DECIMAL(38, 20) NOT NULL
		,[remaining_quantity] DECIMAL(38, 20) NOT NULL
		,CONSTRAINT [PK_inventory_cost_unadjusted] PRIMARY KEY CLUSTERED ([check_id], [entity], [entry_no])
		,CONSTRAINT [FK_inventory_cost_unadjusted_check] FOREIGN KEY ([check_id]) REFERENCES [finance].[inventory_cost_checks] ([check_id]) ON DELETE CASCADE
		,CONSTRAINT [FK_inventory_cost_unadjusted_entities] FOREIGN KEY ([entity]) REFERENCES [dbo].[entities] ([entity])
		);
END

GO
