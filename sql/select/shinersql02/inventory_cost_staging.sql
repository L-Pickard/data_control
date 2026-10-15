-- Inventory cost dataset (Shiner Ltd BRISTOL, Shiner B.V 3PL): the stock and its cost at the end of the as-of date,
-- for finance.inventory_cost_staging (the loader adds dataset_id). Validated read-only on shinersql02 (15 Oct 2026).
-- Parameter: ? = the as-of date. Built from item_inventory_costs.sql (same locations,
-- drop shipments left out, same receipt rules), but as at the date instead of now:
--   quantity       item ledger quantity posted on or before the date (Remaining Quantity is today's state, so it
--                  cannot be used for a past date); items with a positive quantity only
--   cost           value entry actual cost plus expected cost posted on or before the date, for those items at the
--                  location (posting date, not valuation date, so the dataset agrees with the G/L; expected cost so
--                  stock received but not invoiced by the date is valued as NAV values interim inventory: user
--                  decisions 15 Oct 2026). An invoice after the date reverses the expected cost after the date too,
--                  so it does not change the figure for the date.
--   expected_cost  the expected part of cost (received, not invoiced by the date)
--   first/last_receipt  purchase receipts (else positive adjustments) posted on or before the date
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);

WITH item_inventory
AS (
	SELECT N'Shiner Ltd' AS [entity]
		,il.[Item No_] AS [item_id]
		,SUM(il.[Quantity]) AS [quantity]

	FROM [Shiner$Item Ledger Entry] AS il

	WHERE il.[Posting Date] < @day_after
		AND il.[Drop Shipment] = 0
		AND il.[Location Code] = N'BRISTOL'

	GROUP BY il.[Item No_]

	HAVING SUM(il.[Quantity]) > 0


	UNION ALL

	SELECT N'Shiner B.V' AS [entity]
		,il.[Item No_] AS [item_id]
		,SUM(il.[Quantity]) AS [quantity]

	FROM [Shiner BV$Item Ledger Entry] AS il

	WHERE il.[Posting Date] < @day_after
		AND il.[Drop Shipment] = 0
		AND il.[Location Code] = N'3PL'

	GROUP BY il.[Item No_]

	HAVING SUM(il.[Quantity]) > 0
	)
	,item_costs
AS (
	SELECT N'Shiner Ltd' AS [entity]
		,ve.[Item No_] AS [item_id]
		,SUM(ve.[Cost Amount (Actual)] + ve.[Cost Amount (Expected)]) AS [cost]
		,SUM(ve.[Cost Amount (Expected)]) AS [expected_cost]

	FROM [Shiner$Value Entry] AS ve

	WHERE EXISTS (
			SELECT 1

			FROM item_inventory AS itn

			WHERE itn.[item_id] = ve.[Item No_]
				AND itn.[entity] = N'Shiner Ltd'
			)
		AND ve.[Posting Date] < @day_after
		AND ve.[Drop Shipment] = 0
		AND ve.[Location Code] = N'BRISTOL'

	GROUP BY ve.[Item No_]


	UNION ALL

	SELECT N'Shiner B.V' AS [entity]
		,ve.[Item No_] AS [item_id]
		,SUM(ve.[Cost Amount (Actual)] + ve.[Cost Amount (Expected)]) AS [cost]
		,SUM(ve.[Cost Amount (Expected)]) AS [expected_cost]

	FROM [Shiner BV$Value Entry] AS ve

	WHERE EXISTS (
			SELECT 1

			FROM item_inventory AS itn

			WHERE itn.[item_id] = ve.[Item No_]
				AND itn.[entity] = N'Shiner B.V'
			)
		AND ve.[Posting Date] < @day_after
		AND ve.[Drop Shipment] = 0
		AND ve.[Location Code] = N'3PL'

	GROUP BY ve.[Item No_]
	)
	,item_receipts
AS (
	-- Receipt history at this location up to the date, including fully consumed entries.
	-- Purchase receipts take priority over positive adjustments for both dates.
	SELECT N'Shiner Ltd' AS [entity]
		,il.[Item No_] AS [item_id]
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

	FROM [Shiner$Item Ledger Entry] AS il

	WHERE il.[Posting Date] < @day_after
		AND il.[Drop Shipment] = 0
		AND il.[Location Code] = N'BRISTOL'
		AND il.[Quantity] > 0
		AND (
			(
				il.[Entry Type] = 0
				AND il.[Document Type] = 5
				)
			OR il.[Entry Type] = 2
			)

	GROUP BY il.[Item No_]


	UNION ALL

	SELECT N'Shiner B.V' AS [entity]
		,il.[Item No_] AS [item_id]
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

	FROM [Shiner BV$Item Ledger Entry] AS il

	WHERE il.[Posting Date] < @day_after
		AND il.[Drop Shipment] = 0
		AND il.[Location Code] = N'3PL'
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
		AND ii.[entity] = ic.[entity]

LEFT JOIN item_receipts AS ir
	ON ii.[item_id] = ir.[item_id]
		AND ii.[entity] = ir.[entity];
