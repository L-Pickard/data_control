-- Inventory cost dataset (Shiner LLC POMONA): the stock and its cost at the end of the as-of date, for
-- finance.inventory_cost_staging. Same rules and columns as shinersql02/inventory_cost_staging.sql. Validated read-only on
-- shinersql04 (15 Oct 2026). Parameter: ? = the as-of date.
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);

WITH item_inventory
AS (
	SELECT N'Shiner LLC' AS [entity]
		,il.[Item No_] AS [item_id]
		,SUM(il.[Quantity]) AS [quantity]

	FROM [Shiner USA Master Setup$Item Ledger Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS il

	WHERE il.[Posting Date] < @day_after
		AND il.[Drop Shipment] = 0
		AND il.[Location Code] = N'POMONA'

	GROUP BY il.[Item No_]

	HAVING SUM(il.[Quantity]) > 0
	)
	,item_costs
AS (
	SELECT N'Shiner LLC' AS [entity]
		,ve.[Item No_] AS [item_id]
		,SUM(ve.[Cost Amount (Actual)] + ve.[Cost Amount (Expected)]) AS [cost]
		,SUM(ve.[Cost Amount (Expected)]) AS [expected_cost]

	FROM [Shiner USA Master Setup$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS ve

	WHERE EXISTS (
			SELECT 1

			FROM item_inventory AS itn

			WHERE itn.[item_id] = ve.[Item No_]
			)
		AND ve.[Posting Date] < @day_after
		AND ve.[Drop Shipment] = 0
		AND ve.[Location Code] = N'POMONA'

	GROUP BY ve.[Item No_]
	)
	,item_receipts
AS (
	-- Receipt history at this location up to the date, including fully consumed entries.
	-- Purchase receipts take priority over positive adjustments for both dates.
	SELECT il.[Item No_] AS [item_id]
		,COALESCE(MIN(CASE
					WHEN il.[Entry Type] = 0
						AND il.[Document Type] = 5
						THEN CAST(il.[Posting Date] AS DATE)
					END), MIN(CASE
					WHEN il.[Entry Type] = 2
						THEN CAST(il.[Posting Date] AS DATE)
					END)) AS [first_receipt]
		,COALESCE(MAX(CASE
					WHEN il.[Entry Type] = 0
						AND il.[Document Type] = 5
						THEN CAST(il.[Posting Date] AS DATE)
					END), MAX(CASE
					WHEN il.[Entry Type] = 2
						THEN CAST(il.[Posting Date] AS DATE)
					END)) AS [last_receipt]

	FROM [Shiner USA Master Setup$Item Ledger Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS il

	WHERE il.[Posting Date] < @day_after
		AND il.[Drop Shipment] = 0
		AND il.[Location Code] = N'POMONA'
		AND il.[Quantity] > 0
		AND (
			(
				il.[Entry Type] = 0
				AND il.[Document Type] = 5
				)
			OR il.[Entry Type] = 2
			)

	GROUP BY il.[Item No_]
	)

SELECT ii.[entity]
	,ii.[item_id]
	,CAST(ii.[quantity] AS DECIMAL(38, 20)) AS [quantity]
	,CAST(ic.[cost] AS DECIMAL(38, 20)) AS [cost]
	,CAST(ic.[expected_cost] AS DECIMAL(38, 20)) AS [expected_cost]
	,ir.[first_receipt]
	,ir.[last_receipt]

FROM item_inventory AS ii

LEFT JOIN item_costs AS ic
	ON ii.[item_id] = ic.[item_id]

LEFT JOIN item_receipts AS ir
	ON ii.[item_id] = ir.[item_id];
