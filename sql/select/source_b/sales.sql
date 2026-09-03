DECLARE @start DATETIME = CAST(? AS DATETIME)

SELECT CAST(ve.[Posting Date] AS DATE)                                                      AS [posting_date]
	,CAST(ve.[Document Date] AS DATE)														AS [document_date]
	,ve.[Location Code]                                                                     AS [location_code]
	,ve.[Document No_]                                                                      AS [document_no]
	,ve.[Source No_]                                                                        AS [customer_id]
	,CASE ve.[Document Type]
        WHEN 2 THEN sih.[Order No_]
        WHEN 4 THEN CONCAT(cmh.[Return Order No_], '-LLC')
        ELSE '' END                                                                         AS [order_no]
	,CASE ve.[Document Type]
		WHEN 2
			THEN 'SI'
		WHEN 4
			THEN 'CM'
		ELSE ''
	END																						AS [doc_type] 	
	,ve.[Salespers__Purch_ Code]                                                            AS [salesperson_id]
	,COALESCE(NULLIF(sih.[Ship-to Country_Region Code], '')
        ,NULLIF(cmh.[Ship-to Country_Region Code], '')
        ,cus.[Country_Region Code])                                                         AS [country_id]
	,'Example LLC'                                                                           AS [entity]
	,ve.[Item No_]                                                                          AS [item_id]
	,CAST(SUM((ve.[Invoiced Quantity] * - 1)) AS DECIMAL(38, 20))                           AS [quantity]
	,'USD'                                                                                  AS [currency_code]
	,CAST(SUM(ve.[Sales Amount (Actual)]) AS DECIMAL(38, 20))                               AS [sales]
	,CAST(SUM((ve.[Cost Amount (Actual)] * - 1)) AS DECIMAL(38, 20))                        AS [cost]

FROM [Example USA Master Setup$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS ve

LEFT JOIN [Example USA Master Setup$Customer$437dbf0e-84ff-417a-965d-ed2bb9650972] AS cus
	ON ve.[Source No_] = cus.[No_]

LEFT JOIN [Example USA Master Setup$Sales Invoice Header$437dbf0e-84ff-417a-965d-ed2bb9650972] AS sih
	ON ve.[Document No_] = sih.[No_]

LEFT JOIN [Example USA Master Setup$Sales Cr_Memo Header$437dbf0e-84ff-417a-965d-ed2bb9650972] AS cmh
	ON ve.[Document No_] = cmh.[No_]

WHERE ve.[Posting Date] > @start
	AND ve.[Source Type] = 1
	AND ve.[Document Type] IN (2, 4)

GROUP BY CAST(ve.[Posting Date] AS DATE)
	,CAST(ve.[Document Date] AS DATE)
	,ve.[Location Code]
	,ve.[Document No_]
	,ve.[Source No_]
	,CASE ve.[Document Type]
        WHEN 2 THEN sih.[Order No_]
        WHEN 4 THEN CONCAT(cmh.[Return Order No_], '-LLC')
        ELSE '' END
	,CASE ve.[Document Type]
		WHEN 2
			THEN 'SI'
		WHEN 4
			THEN 'CM'
		ELSE ''
	END	
	,ve.[Salespers__Purch_ Code]
	,COALESCE(NULLIF(sih.[Ship-to Country_Region Code], '')
        ,NULLIF(cmh.[Ship-to Country_Region Code], '')
        ,cus.[Country_Region Code])
	,ve.[Item No_]
