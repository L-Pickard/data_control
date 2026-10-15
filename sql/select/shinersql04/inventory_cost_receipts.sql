-- Inventory cost check (Shiner LLC POMONA): purchase receipt lines posted on or before the as-of date whose quantity
-- was not fully invoiced by the end of that date (a warning list, not a blocker). Same rules and columns as
-- shinersql02/inventory_cost_receipts.sql; LLC items have no colours or sizes (as in items.sql). Validated read-only
-- on shinersql04 (15 Oct 2026). Parameter: ? = the as-of date.
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);

WITH receipts
AS (
	SELECT N'Shiner LLC' AS [entity]
		,il.[Entry No_] AS [entry_no]
		,il.[Document No_] AS [document_no]
		,il.[Document Line No_] AS [document_line_no]
		,CAST(il.[Posting Date] AS DATE) AS [posting_date]
		,il.[Item No_] AS [item_id]
		,il.[Quantity] AS [quantity]
		,(
			SELECT ISNULL(SUM(ve.[Invoiced Quantity]), 0)

			FROM [Shiner USA Master Setup$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS ve

			WHERE ve.[Item Ledger Entry No_] = il.[Entry No_]
				AND ve.[Posting Date] < @day_after
			) AS [quantity_invoiced]

	FROM [Shiner USA Master Setup$Item Ledger Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS il

	WHERE il.[Entry Type] = 0
		AND il.[Document Type] = 5
		AND il.[Correction] = 0
		AND il.[Drop Shipment] = 0
		AND il.[Location Code] = N'POMONA'
		AND il.[Quantity] > 0
		AND il.[Posting Date] < @day_after
	)

SELECT rc.[entity]
	,rc.[document_no]
	,rc.[document_line_no]
	,rl.[Order No_] AS [order_no]
	,rc.[posting_date]
	,rl.[Buy-from Vendor No_] AS [vendor_id]
	,vn.[Name] AS [vendor_name]
	,rc.[item_id]
	,it.[Description] AS [description]
	,it.[Description 2] AS [description_2]
	,CAST(NULL AS NVARCHAR(120)) AS [colours]
	,CAST(NULL AS NVARCHAR(10)) AS [size_1]
	,CAST(NULL AS NVARCHAR(5)) AS [size_1_unit]
	,NULLIF(rh.[Currency Code], N'') AS [currency_code]
	,CAST(rl.[Direct Unit Cost] AS DECIMAL(38, 20)) AS [direct_unit_cost]
	,CAST(rc.[quantity] AS DECIMAL(38, 20)) AS [quantity]
	,CAST(rc.[quantity_invoiced] AS DECIMAL(38, 20)) AS [quantity_invoiced]
	,CAST(rc.[quantity] - rc.[quantity_invoiced] AS DECIMAL(38, 20)) AS [quantity_not_invoiced]

FROM receipts AS rc

LEFT JOIN [Shiner USA Master Setup$Purch_ Rcpt_ Line$437dbf0e-84ff-417a-965d-ed2bb9650972] AS rl
	ON rl.[Document No_] = rc.[document_no]
		AND rl.[Line No_] = rc.[document_line_no]

LEFT JOIN [Shiner USA Master Setup$Purch_ Rcpt_ Header$437dbf0e-84ff-417a-965d-ed2bb9650972] AS rh
	ON rh.[No_] = rc.[document_no]

LEFT JOIN [Shiner USA Master Setup$Vendor$437dbf0e-84ff-417a-965d-ed2bb9650972] AS vn
	ON vn.[No_] = rl.[Buy-from Vendor No_]

LEFT JOIN [Shiner USA Master Setup$Item$437dbf0e-84ff-417a-965d-ed2bb9650972] AS it
	ON it.[No_] = rc.[item_id]

WHERE rc.[quantity] > rc.[quantity_invoiced]

ORDER BY rl.[Buy-from Vendor No_]
	,rc.[document_no]
	,rc.[document_line_no];
