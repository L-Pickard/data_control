-- Inventory cost check (Shiner LLC POMONA): the item ledger entries still flagged "Applied Entry to Adjust", for
-- finance.inventory_cost_unadjusted. Same rules and columns as shinersql02/inventory_cost_unadjusted.sql (a warning list,
-- dataset location, 12 months up to the as-of date). Parameter: ? = the as-of date.
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);
DECLARE @cut_off AS DATETIME = DATEADD(MONTH, - 12, @day_after);

SELECT N'Shiner LLC' AS [entity]
	,il.[Entry No_] AS [entry_no]
	,CAST(il.[Posting Date] AS DATE) AS [posting_date]
	,CASE il.[Entry Type]
		WHEN 0
			THEN N'Purchase'
		WHEN 1
			THEN N'Sale'
		WHEN 2
			THEN N'Positive Adjmt.'
		WHEN 3
			THEN N'Negative Adjmt.'
		WHEN 4
			THEN N'Transfer'
		ELSE CAST(il.[Entry Type] AS NVARCHAR(20))
		END AS [entry_type]
	,NULLIF(il.[Document No_], N'') AS [document_no]
	,il.[Item No_] AS [item_id]
	,CAST(il.[Quantity] AS DECIMAL(38, 20)) AS [quantity]
	,CAST(il.[Remaining Quantity] AS DECIMAL(38, 20)) AS [remaining_quantity]

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

ORDER BY [posting_date]
	,[entry_no];
