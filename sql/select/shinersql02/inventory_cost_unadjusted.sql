-- Inventory cost check (Shiner Ltd BRISTOL, Shiner B.V 3PL): the item ledger entries still flagged "Applied Entry to
-- Adjust" (FIFO: Adjust Cost - Item Entries has not reached them), for finance.inventory_cost_unadjusted (the loader adds
-- check_id). A WARNING list, not a blocker, scoped to the dataset location and entries posted in the 12 months up to
-- the as-of date (user decisions, 15 Oct 2026); the same entries as unadjusted_entries in inventory_cost_checks.sql.
-- Parameter: ? = the as-of date. remaining_quantity is the open quantity now.
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);
DECLARE @cut_off AS DATETIME = DATEADD(MONTH, - 12, @day_after);

SELECT N'Shiner Ltd' AS [entity]
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

FROM [Shiner$Item Ledger Entry] AS il

WHERE il.[Applied Entry to Adjust] = 1
	AND il.[Location Code] = N'BRISTOL'
	AND il.[Posting Date] >= @cut_off
	AND il.[Posting Date] < @day_after


UNION ALL

SELECT N'Shiner B.V' AS [entity]
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

FROM [Shiner BV$Item Ledger Entry] AS il

WHERE il.[Applied Entry to Adjust] = 1
	AND il.[Location Code] = N'3PL'
	AND il.[Posting Date] >= @cut_off
	AND il.[Posting Date] < @day_after

ORDER BY [entity]
	,[posting_date]
	,[entry_no];
