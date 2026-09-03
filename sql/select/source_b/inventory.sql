WITH physical_inventory AS (
	SELECT ile.[Item No_] AS [item_id], SUM(ile.[Quantity]) AS [inventory]
	FROM [Example USA Master Setup$Item Ledger Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS ile
	WHERE ile.[Location Code] = N'POMONA' AND LEN(ile.[Item No_]) <= 20
	GROUP BY ile.[Item No_]
), reservations AS (
	SELECT re.[Item No_] AS [item_id], SUM(re.[Quantity]) AS [reserved_quantity]
	FROM [Example USA Master Setup$Reservation Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS re
	WHERE re.[Location Code] = N'POMONA' AND re.[Source Type] = 32
		AND re.[Source Subtype] = 0 AND re.[Reservation Status] = 0
	GROUP BY re.[Item No_]
)
SELECT N'Example LLC' AS [entity], p.[item_id]
	,CAST(p.[inventory] AS DECIMAL(38, 20)) AS [inventory]
	,CAST(0 AS DECIMAL(38, 20)) AS [buffer_stock]
	,CAST(COALESCE(r.[reserved_quantity], 0) AS DECIMAL(38, 20)) AS [reserved_quantity]
	,CAST(0 AS DECIMAL(38, 20)) AS [unavailable_quantity]
FROM physical_inventory AS p
LEFT JOIN reservations AS r ON r.[item_id] = p.[item_id]
WHERE p.[inventory] > 0;
