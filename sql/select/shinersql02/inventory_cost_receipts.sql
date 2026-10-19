-- Read-only inventory source query, scoped to selected entities and locations.
-- Parameters: as-of date, then XML scope (SQL02 supports XML, not OPENJSON).
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @scope XML = CAST(? AS XML);
DECLARE @ltd_enabled BIT = @scope.exist('/scope/entity[@name="Shiner Ltd"]');
DECLARE @ltd_all BIT = @scope.exist('/scope/entity[@name="Shiner Ltd" and @all="1"]');
DECLARE @bv_enabled BIT = @scope.exist('/scope/entity[@name="Shiner B.V"]');
DECLARE @bv_all BIT = @scope.exist('/scope/entity[@name="Shiner B.V" and @all="1"]');
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);

WITH receipts
AS (
	SELECT N'Shiner Ltd' AS [entity]
		,il.[Location Code] AS [location_code]
		,il.[Entry No_] AS [entry_no]
		,il.[Document No_] AS [document_no]
		,il.[Document Line No_] AS [document_line_no]
		,CAST(il.[Posting Date] AS DATE) AS [posting_date]
		,il.[Item No_] AS [item_id]
		,il.[Quantity] AS [quantity]
		,(
			SELECT ISNULL(SUM(ve.[Invoiced Quantity]), 0)

			FROM [Shiner$Value Entry] AS ve

			WHERE ve.[Item Ledger Entry No_] = il.[Entry No_]
				AND ve.[Posting Date] < @day_after
			) AS [quantity_invoiced]

	FROM [Shiner$Item Ledger Entry] AS il

	WHERE il.[Entry Type] = 0
		AND il.[Document Type] = 5
		AND il.[Correction] = 0
		AND il.[Drop Shipment] = 0
		AND (@ltd_enabled=1 AND (@ltd_all=1 OR il.[Location Code] IN (SELECT lc.n.value('@code','nvarchar(10)') FROM @scope.nodes('/scope/entity[@name="Shiner Ltd"]/location') AS lc(n))))
		AND il.[Quantity] > 0
		AND il.[Posting Date] < @day_after


	UNION ALL

	SELECT N'Shiner B.V' AS [entity]
		,il.[Location Code] AS [location_code]
		,il.[Entry No_] AS [entry_no]
		,il.[Document No_] AS [document_no]
		,il.[Document Line No_] AS [document_line_no]
		,CAST(il.[Posting Date] AS DATE) AS [posting_date]
		,il.[Item No_] AS [item_id]
		,il.[Quantity] AS [quantity]
		,(
			SELECT ISNULL(SUM(ve.[Invoiced Quantity]), 0)

			FROM [Shiner BV$Value Entry] AS ve

			WHERE ve.[Item Ledger Entry No_] = il.[Entry No_]
				AND ve.[Posting Date] < @day_after
			) AS [quantity_invoiced]

	FROM [Shiner BV$Item Ledger Entry] AS il

	WHERE il.[Entry Type] = 0
		AND il.[Document Type] = 5
		AND il.[Correction] = 0
		AND il.[Drop Shipment] = 0
		AND (@bv_enabled=1 AND (@bv_all=1 OR il.[Location Code] IN (SELECT lc.n.value('@code','nvarchar(10)') FROM @scope.nodes('/scope/entity[@name="Shiner B.V"]/location') AS lc(n))))
		AND il.[Quantity] > 0
		AND il.[Posting Date] < @day_after
	)

SELECT rc.[entity]
	,rc.[location_code]
	,rc.[document_no]
	,rc.[document_line_no]
	,rl.[Order No_] AS [order_no]
	,rc.[posting_date]
	,rl.[Buy-from Vendor No_] AS [vendor_id]
	,vn.[Name] AS [vendor_name]
	,rc.[item_id]
	,it.[Description] AS [description]
	,it.[Description 2] AS [description_2]
	,it.[Colours] AS [colours]
	,it.[Size 1] AS [size_1]
	,it.[Size 1 Unit] AS [size_1_unit]
	,NULLIF(rh.[Currency Code], N'') AS [currency_code]
	,CAST(rl.[Direct Unit Cost] AS DECIMAL(38, 20)) AS [direct_unit_cost]
	,CAST(rc.[quantity] AS DECIMAL(38, 20)) AS [quantity]
	,CAST(rc.[quantity_invoiced] AS DECIMAL(38, 20)) AS [quantity_invoiced]
	,CAST(rc.[quantity] - rc.[quantity_invoiced] AS DECIMAL(38, 20)) AS [quantity_not_invoiced]

FROM receipts AS rc

LEFT JOIN [Shiner$Purch_ Rcpt_ Line] AS rl
	ON rl.[Document No_] = rc.[document_no]
		AND rl.[Line No_] = rc.[document_line_no]

LEFT JOIN [Shiner$Purch_ Rcpt_ Header] AS rh
	ON rh.[No_] = rc.[document_no]

LEFT JOIN [Shiner$Vendor] AS vn
	ON vn.[No_] = rl.[Buy-from Vendor No_]

LEFT JOIN [Shiner$Item] AS it
	ON it.[No_] = rc.[item_id]

WHERE rc.[entity] = N'Shiner Ltd'
	AND rc.[quantity] > rc.[quantity_invoiced]


UNION ALL

SELECT rc.[entity]
	,rc.[location_code]
	,rc.[document_no]
	,rc.[document_line_no]
	,rl.[Order No_] AS [order_no]
	,rc.[posting_date]
	,rl.[Buy-from Vendor No_] AS [vendor_id]
	,vn.[Name] AS [vendor_name]
	,rc.[item_id]
	,it.[Description] AS [description]
	,it.[Description 2] AS [description_2]
	,it.[Colours] AS [colours]
	,it.[Size 1] AS [size_1]
	,it.[Size 1 Unit] AS [size_1_unit]
	,NULLIF(rh.[Currency Code], N'') AS [currency_code]
	,CAST(rl.[Direct Unit Cost] AS DECIMAL(38, 20)) AS [direct_unit_cost]
	,CAST(rc.[quantity] AS DECIMAL(38, 20)) AS [quantity]
	,CAST(rc.[quantity_invoiced] AS DECIMAL(38, 20)) AS [quantity_invoiced]
	,CAST(rc.[quantity] - rc.[quantity_invoiced] AS DECIMAL(38, 20)) AS [quantity_not_invoiced]

FROM receipts AS rc

LEFT JOIN [Shiner BV$Purch_ Rcpt_ Line] AS rl
	ON rl.[Document No_] = rc.[document_no]
		AND rl.[Line No_] = rc.[document_line_no]

LEFT JOIN [Shiner BV$Purch_ Rcpt_ Header] AS rh
	ON rh.[No_] = rc.[document_no]

LEFT JOIN [Shiner BV$Vendor] AS vn
	ON vn.[No_] = rl.[Buy-from Vendor No_]

LEFT JOIN [Shiner BV$Item] AS it
	ON it.[No_] = rc.[item_id]

WHERE rc.[entity] = N'Shiner B.V'
	AND rc.[quantity] > rc.[quantity_invoiced]

ORDER BY [entity]
	,[vendor_id]
	,[document_no]
	,[document_line_no]
OPTION (RECOMPILE, MAXDOP 1);
