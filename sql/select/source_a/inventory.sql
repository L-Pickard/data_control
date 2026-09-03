WITH inventory_components AS (
	SELECT N'Example Ltd' AS [entity]
		,ile.[Item No_] AS [item_id]
		,SUM(ile.[Quantity]) AS [inventory]
		,CAST(COALESCE(MAX(i.[Buffer Stock]), 0) AS DECIMAL(38, 20)) AS [buffer_stock]
		,CAST(0 AS DECIMAL(38, 20)) AS [reserved_quantity]
		,CAST(0 AS DECIMAL(38, 20)) AS [unavailable_quantity]
	FROM [Example$Item Ledger Entry] AS ile
	LEFT JOIN [Example$Item] AS i ON i.[No_] = ile.[Item No_]
	WHERE ile.[Location Code] = N'BRISTOL'
		AND LEN(ile.[Item No_]) <= 20
	GROUP BY ile.[Item No_]

	UNION ALL

	SELECT N'Example BV'
		,ile.[Item No_]
		,SUM(ile.[Quantity])
		,CAST(COALESCE(MAX(i.[Buffer Stock]), 0) AS DECIMAL(38, 20))
		,CAST(0 AS DECIMAL(38, 20))
		,CAST(0 AS DECIMAL(38, 20))
	FROM [Example BV$Item Ledger Entry] AS ile
	LEFT JOIN [Example BV$Item] AS i ON i.[No_] = ile.[Item No_]
	WHERE ile.[Location Code] = N'3PL'
		AND LEN(ile.[Item No_]) <= 20
	GROUP BY ile.[Item No_]
), reservations AS (
	SELECT N'Example Ltd' AS [entity], [Item No_] AS [item_id], SUM([Quantity]) AS [reserved_quantity]
	FROM [Example$Reservation Entry]
	WHERE [Location Code] = N'BRISTOL' AND [Source Type] = 32
		AND [Source Subtype] = 0 AND [Reservation Status] = 0
	GROUP BY [Item No_]
	UNION ALL
	SELECT N'Example BV', [Item No_], SUM([Quantity])
	FROM [Example BV$Reservation Entry]
	WHERE [Location Code] = N'3PL' AND [Source Type] = 32
		AND [Source Subtype] = 0 AND [Reservation Status] = 0
	GROUP BY [Item No_]
), unavailable AS (
	SELECT N'Example Ltd' AS [entity], [Item No_] AS [item_id], SUM([Quantity]) AS [unavailable_quantity]
	FROM [Example$Warehouse Entry]
	WHERE [Location Code] = N'BRISTOL'
		AND [Bin Code] IN (N'FAULTY', N'REWORK', N'RECEIPT', N'SAMPLE ROOM')
	GROUP BY [Item No_]
)
SELECT c.[entity], c.[item_id]
	,CAST(c.[inventory] AS DECIMAL(38, 20)) AS [inventory]
	,c.[buffer_stock]
	,CAST(COALESCE(r.[reserved_quantity], 0) AS DECIMAL(38, 20)) AS [reserved_quantity]
	,CAST(COALESCE(u.[unavailable_quantity], 0) AS DECIMAL(38, 20)) AS [unavailable_quantity]
FROM inventory_components AS c
LEFT JOIN reservations AS r ON r.[entity] = c.[entity] AND r.[item_id] = c.[item_id]
LEFT JOIN unavailable AS u ON u.[entity] = c.[entity] AND u.[item_id] = c.[item_id]
WHERE c.[inventory] > 0;
