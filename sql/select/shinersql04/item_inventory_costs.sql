
WITH item_inventory
AS (
	SELECT N'Shiner LLC' AS [entity]
		,il.[Item No_] AS [item_id]
		,SUM(il.[Remaining Quantity]) AS [quantity]
	
	FROM [dbo].[Shiner USA Master Setup$Item Ledger Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS il
	
	WHERE il.[Remaining Quantity] > 0
		AND il.[Drop Shipment] = 0
		AND il.[Location Code] = N'POMONA'
	
	GROUP BY il.[Item No_]
	)
	,item_costs
AS (
	SELECT N'Shiner LLC' AS [entity]
		,ve.[Item No_] AS [item_id]
		,SUM(ve.[Cost Amount (Actual)]) AS [cost]
	
	FROM [dbo].[Shiner USA Master Setup$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS ve
	
	WHERE EXISTS (
			SELECT 1
			
			FROM item_inventory AS itn
			
			WHERE itn.[item_id] = ve.[Item No_]
				AND itn.[entity] = N'Shiner LLC'
			)
		AND ve.[Drop Shipment] = 0
		AND ve.[Location Code] = N'POMONA'
	
	GROUP BY ve.[Item No_]
	), item_receipts AS (
    -- All receipt history at this location, including fully consumed entries.
    -- Purchase receipts take priority over positive adjustments for both dates.
    SELECT N'Shiner LLC' AS [entity]
        ,il.[Item No_] AS [item_id]
        ,COALESCE(
            MIN(CASE WHEN il.[Entry Type] = 0 AND il.[Document Type] = 5 THEN CAST(il.[Posting Date] AS date) END),
            MIN(CASE WHEN il.[Entry Type] = 2 THEN CAST(il.[Posting Date] AS date) END)
        ) AS [first_receipt]
        ,COALESCE(
            MAX(CASE WHEN il.[Entry Type] = 0 AND il.[Document Type] = 5 THEN CAST(il.[Posting Date] AS date) END),
            MAX(CASE WHEN il.[Entry Type] = 2 THEN CAST(il.[Posting Date] AS date) END)
        ) AS [last_receipt]
    FROM [dbo].[Shiner USA Master Setup$Item Ledger Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS il
    WHERE il.[Drop Shipment] = 0
        AND il.[Location Code] = N'POMONA'
        AND il.[Quantity] > 0
        AND ((il.[Entry Type] = 0 AND il.[Document Type] = 5) OR il.[Entry Type] = 2)
    GROUP BY il.[Item No_]
)

SELECT ii.[entity]
	,ii.[item_id]
	,ii.[quantity]
	,ic.[cost]
    ,ir.[first_receipt]
    ,ir.[last_receipt]

FROM item_inventory AS ii

LEFT JOIN item_costs AS ic
	ON ii.[item_id] = ic.[item_id]
		AND ii.[entity] = ic.[entity]
LEFT JOIN item_receipts AS ir
    ON ii.[item_id] = ir.[item_id]
    AND ii.[entity] = ir.[entity];
