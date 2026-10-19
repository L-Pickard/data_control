-- Read-only inventory source query, scoped to selected entities and locations.
-- Parameters: as-of date, then XML scope (SQL02 supports XML, not OPENJSON).
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @scope XML = CAST(? AS XML);
DECLARE @llc_enabled BIT = @scope.exist('/scope/entity[@name="Shiner LLC"]');
DECLARE @llc_all BIT = @scope.exist('/scope/entity[@name="Shiner LLC" and @all="1"]');
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);
DECLARE @cut_off AS DATETIME = DATEADD(MONTH, - 12, @day_after);

;WITH [llc_stock] AS (
    SELECT st.[Location Code] AS [location_code], st.[Item No_] AS [item_id]
    FROM [Shiner USA Master Setup$Item Ledger Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS st
    WHERE (@llc_enabled=1 AND (@llc_all=1 OR st.[Location Code] IN (SELECT lc.n.value('@code','nvarchar(10)') FROM @scope.nodes('/scope/entity[@name="Shiner LLC"]/location') AS lc(n))))
        AND st.[Drop Shipment] = 0
        AND st.[Posting Date] < @day_after
    GROUP BY st.[Location Code], st.[Item No_]
    HAVING SUM(st.[Quantity]) > 0
)

SELECT N'Shiner LLC' AS [entity]
	,il.[Location Code] AS [location_code]
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

INNER JOIN [llc_stock] AS stock ON stock.[item_id] = il.[Item No_] AND stock.[location_code] = il.[Location Code]

WHERE il.[Applied Entry to Adjust] = 1
	AND (@llc_enabled=1 AND (@llc_all=1 OR il.[Location Code] IN (SELECT lc.n.value('@code','nvarchar(10)') FROM @scope.nodes('/scope/entity[@name="Shiner LLC"]/location') AS lc(n))))
	AND il.[Posting Date] >= @cut_off
	AND il.[Posting Date] < @day_after


ORDER BY [posting_date]
	,[entry_no]
OPTION (RECOMPILE, MAXDOP 1);
