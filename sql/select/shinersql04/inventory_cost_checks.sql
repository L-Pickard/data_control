-- Inventory cost check (Shiner LLC): the counts of entries for finance.inventory_cost_checks.
-- Same rules and columns as shinersql02/inventory_cost_checks.sql. Validated read-only on shinersql04 (15 Oct 2026).
-- Parameter: ? = the as-of date.
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);
DECLARE @cut_off AS DATETIME = DATEADD(MONTH, - 12, @day_after);

SELECT N'Shiner LLC' AS [entity]
	,(
		SELECT COUNT(*)

		FROM [Shiner USA Master Setup$Item Ledger Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS il

		WHERE il.[Applied Entry to Adjust] = 1
			AND il.[Location Code] = N'POMONA'
			AND il.[Posting Date] >= @cut_off
			AND il.[Posting Date] < @day_after
			-- Only items with stock at the location at the end of the as-of date: an item with none is not in the dataset,
			-- so its entries cannot change it (user, 15 Oct 2026).
			AND EXISTS (
				SELECT 1

				FROM [Shiner USA Master Setup$Item Ledger Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS st

				WHERE st.[Item No_] = il.[Item No_]
					AND st.[Location Code] = N'POMONA'
					AND st.[Drop Shipment] = 0
					AND st.[Posting Date] < @day_after

				HAVING SUM(st.[Quantity]) > 0
				)
		) AS [unadjusted_entries]
	,(
		SELECT COUNT(*)

		FROM [Shiner USA Master Setup$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS ve

		WHERE ve.[Cost Amount (Actual)] <> ve.[Cost Posted to G_L]
			AND ve.[Posting Date] < @day_after
		) AS [unposted_entries];
