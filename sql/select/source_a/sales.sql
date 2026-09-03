DECLARE @start_ltd AS DATETIME = CAST(? AS DATETIME)
	,@start_bv AS DATETIME = CAST(? AS DATETIME)

SELECT CAST(ve.[Posting Date] AS DATE) 														AS [posting_date]
	,CAST(ve.[Document Date] AS DATE)                                                       AS [document_date]
	,ve.[Location Code]                                                                     AS [location_code]
	,ve.[Document No_]                                                                      AS [document_no]
	,ve.[Source No_]                                                                        AS [customer_id]
	,CASE 
		WHEN ve.[Document Type] = 4
			THEN cmh.[Return Order No_] + '-Ltd'
		ELSE sih.[Order No_]
		END                                                                                 AS [order_no]
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
	,'Example Ltd'                                                                           AS [entity]
	,ve.[Item No_]                                                                          AS [item_id]
	,CAST(SUM((ve.[Invoiced Quantity] * - 1)) AS DECIMAL(38, 20))                           AS [quantity]
	,'GBP'                                                                                  AS [currency_code]
	,CAST(SUM(ve.[Sales Amount (Actual)]) AS DECIMAL(38, 20))                               AS [sales]
	,CAST(SUM((ve.[Cost Amount (Actual)] * - 1)) AS DECIMAL(38, 20))                        AS [cost]

FROM [Example$Value Entry] AS ve

LEFT JOIN [Example$Sales Cr_Memo Header] AS cmh
	ON ve.[Document No_] = cmh.[No_]

LEFT JOIN [Example$Sales Invoice Header] AS sih
	ON ve.[Document No_] = sih.[No_]

LEFT JOIN [Example$Customer] AS cus
	ON ve.[Source No_] = cus.[No_]

WHERE ve.[Posting Date] > @start_ltd
	AND ve.[Source Type] = 1
	AND ve.[Document Type] IN (2, 4)

GROUP BY CAST(ve.[Posting Date] AS DATE)
	,CAST(ve.[Document Date] AS DATE)
	,ve.[Location Code]
	,ve.[Document No_]
	,ve.[Source No_]
	,CASE 
		WHEN ve.[Document Type] = 4
			THEN cmh.[Return Order No_] + '-Ltd'
		ELSE sih.[Order No_]
	END    
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


UNION ALL

SELECT CAST(ve.[Posting Date] AS DATE)                                                     AS [posting_date]
	,CAST(ve.[Document Date] AS DATE)                                                      AS [document_date]
	,ve.[Location Code]                                                                    AS [location_code]
	,ve.[Document No_]                                                                     AS [document_no]
	,ve.[Source No_]                                                                       AS [customer_id]
	,CASE 
		WHEN ve.[Document Type] = 4
			THEN cmh.[Return Order No_] + '-B.V'
		ELSE sih.[Order No_]
	END  																				   AS [order_no]
	,CASE ve.[Document Type]
		WHEN 2
			THEN 'SI'
		WHEN 4
			THEN 'CM'
		ELSE ''
	END 																				   AS [doc_type]
	,ve.[Salespers__Purch_ Code]                                                            AS [salesperson_id]
	,COALESCE(NULLIF(sih.[Ship-to Country_Region Code], '')
        ,NULLIF(cmh.[Ship-to Country_Region Code], '')
        ,cus.[Country_Region Code])                                                        AS [country_id]
	,'Example BV'                                                                          AS [entity]
	,ve.[Item No_]                                                                         AS [item_id]
	,CAST(SUM((ve.[Invoiced Quantity] * - 1)) AS DECIMAL(38, 20))                          AS [quantity]
	,'EUR'                                                                                 AS [currency_code]
	,CAST(SUM(ve.[Sales Amount (Actual)]) AS DECIMAL(20, 8))                               AS [sales]
	,CAST(SUM((ve.[Cost Amount (Actual)] * - 1)) AS DECIMAL(20, 8))                        AS [cost]

FROM [Example BV$Value Entry] AS ve

LEFT JOIN [Example BV$Sales Cr_Memo Header] AS cmh
	ON ve.[Document No_] = cmh.[No_]

LEFT JOIN [Example BV$Sales Invoice Header] AS sih
	ON ve.[Document No_] = sih.[No_]

LEFT JOIN [Example BV$Customer] AS cus
	ON ve.[Source No_] = cus.[No_]

LEFT JOIN [Example BV$Item] AS it
	ON ve.[Item No_] = it.[No_]

WHERE ve.[Posting Date] > @start_bv
	AND ve.[Source Type] = 1
	AND ve.[Document Type] IN (2, 4)

GROUP BY CAST(ve.[Posting Date] AS DATE)
	,CAST(ve.[Document Date] AS DATE)
	,ve.[Location Code]
	,ve.[Document No_]
	,ve.[Source No_]
	,CASE 
		WHEN ve.[Document Type] = 4
			THEN cmh.[Return Order No_] + '-B.V'
		ELSE sih.[Order No_]
	END
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
	,ve.[Item No_];
