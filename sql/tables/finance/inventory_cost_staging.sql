USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Staging for one inventory cost dataset (finance.inventory_cost), like dbo.sales_staging: the dataset job writes the
-- rows it reads from NAV for the dataset's as-of date (replacing any previous staging table), in each company's own
-- currency: cost = actual + expected cost, expected_cost = the part not yet invoiced by the date. The build procedure
-- then checks them (dataset_id must be the dataset being built; items must exist in dbo.items), inserts them into
-- finance.inventory_cost_lines with the GBP, EUR and USD costs in one transaction, and drops this table after the
-- successful insert. Only one dataset job runs at a time (one SQL Agent job), so one
-- staging table is enough.

DROP TABLE

IF EXISTS [finance].[inventory_cost_staging];
	CREATE TABLE [finance].[inventory_cost_staging] (
		 [dataset_id] INT NULL
		,[entity] NVARCHAR(20) NULL
		,[item_id] NVARCHAR(20) NULL
		,[quantity] DECIMAL(38, 20) NULL
		,[cost] DECIMAL(38, 20) NULL
		,[expected_cost] DECIMAL(38, 20) NULL
		,[first_receipt] DATE NULL
		,[last_receipt] DATE NULL
		)

GO
