SELECT ISNULL(it.[No_], bt.[No_])                                           AS [item_id]
	,ISNULL(it.[Vendor Reference], bt.[Vendor Reference])                   AS [vendor_reference]
	,ISNULL(LEFT(it.[No_], 3), LEFT(bt.[No_], 3))                           AS [brand_id]
	,ISNULL(it.[Description], bt.[Description])                             AS [description]
	,ISNULL(it.[Description 2], bt.[Description 2])                         AS [description_2]
	,ISNULL(it.[Colours], bt.[Colours])                                     AS [colours]
	,ISNULL(it.[Size 1], bt.[Size 1])                                       AS [size_1]
	,ISNULL(it.[Size 1 Unit], bt.[Size 1 Unit])                             AS [size_1_unit]
	,ISNULL(it.[EU Size], bt.[EU Size])                                     AS [eu_size]
	,ISNULL(it.[EU Size Unit], bt.[EU Size Unit])                           AS [eu_size_unit]
	,ISNULL(it.[US Size], bt.[US Size])                                     AS [us_size]
	,ISNULL(it.[US Size Unit], bt.[US Size Unit])                           AS [us_size_unit]
	,ISNULL(CASE it.[Season Code]
			WHEN 0
				THEN ''
			WHEN 1
				THEN 'SP'
			WHEN 2
				THEN 'SU'
			WHEN 3
				THEN 'FA'
			WHEN 4
				THEN 'HO'
			ELSE CAST(it.[Season Code] AS VARCHAR(2))
			END + CASE it.[Season Year]
			WHEN 0
				THEN ''
			WHEN 1
				THEN '23'
			WHEN 2
				THEN '24'
			WHEN 3
				THEN '25'
			WHEN 4
				THEN '26'
			WHEN 5
				THEN '27'
			WHEN 6
				THEN '28'
			ELSE CAST(it.[Season Year] AS VARCHAR(2))
			END, CASE bt.[Season Code]
			WHEN 0
				THEN ''
			WHEN 1
				THEN 'SP'
			WHEN 2
				THEN 'SU'
			WHEN 3
				THEN 'FA'
			WHEN 4
				THEN 'HO'
			ELSE CAST(bt.[Season Code] AS VARCHAR(2))
			END + CASE bt.[Season Year]
			WHEN 0
				THEN ''
			WHEN 1
				THEN '23'
			WHEN 2
				THEN '24'
			WHEN 3
				THEN '25'
			WHEN 4
				THEN '26'
			WHEN 5
				THEN '27'
			WHEN 6
				THEN '28'
			ELSE CAST(it.[Season Year] AS VARCHAR(2))
			END)                                                            AS [season]
	,ISNULL(it.[Item Info], 'B.V Item Only')                                AS [item_info]
	,it.[Item Category Code]                                                AS [category_code]
	,it.[Product Group Code]                                                AS [group_code]
	,it.[EAN Barcode]                                                       AS [ean_barcode]
	,it.[Tariff No_]                                                        AS [tariff_no]
	,ISNULL(it.[Unit Cost], 0)                                              AS [gbp_cost]
	,ISNULL(it.[Unit Price], 0)                                             AS [gbp_trade]
	,ISNULL(it.[SRP], 0)                                                    AS [gbp_srp]
	,ISNULL(bt.[Unit Cost], 0)                                              AS [eur_cost]
	,ISNULL((
			SELECT TOP 1 [Unit Price]
			
			FROM [Example$Sales Price]
			
			WHERE [Sales Type] = 2
				AND [Currency Code] = 'EUR'
				AND [Minimum Quantity] = 1
				AND [Item No_] = it.[No_]
			), 0)                                                           AS [eur_trade]
	,ISNULL(it.[Euro SRP], bt.[Euro SRP])                                   AS [eur_srp]
	,ISNULL((
			SELECT TOP 1 [Unit Price]
			
			FROM [Example$Sales Price]
			
			WHERE [Sales Type] = 2
				AND [Currency Code] = 'USD'
				AND [Minimum Quantity] = 1
				AND [Item No_] = it.[No_]
			), 0)                                                           AS [usd_trade]
	,ISNULL(it.[USD SRP], bt.[USD SRP])                                     AS [usd_srp]
	,ISNULL(it.[Royalty %], bt.[Royalty %])                                 AS [royalty]
	,ISNULL(it.[Vendor No_], bt.[Vendor No_])                               AS [uk_eu_vendor_no]
	,it.[Blocked]                                                           AS [ltd_blocked]
	,bt.[Blocked]                                                           AS [bv_blocked]
	,ISNULL(it.[Preferential Sale], bt.[Preferential Sale])                 AS [pref_sale]
	,ISNULL(it.[Country_Region of Origin Code], 
                bt.[Country_Region of Origin Code])                         AS [coo]
	,ISNULL(it.[Base Unit of Measure], bt.[Base Unit of Measure])           AS [unit_of_measure]
	,ISNULL(it.[Hot Product], bt.[Hot Product])                             AS [hot_product]
	,30 AS [lead_time_days] -- call a function to extract lead time days
	,ISNULL(it.[Bread & Butter], bt.[Bread & Butter])                       AS [bread_butter]
	,CAST(ISNULL(it.[Buffer Stock], 0) AS INTEGER)                          AS [ltd_buffer_stock]
	,CAST(ISNULL(bt.[Buffer Stock], 0) AS INTEGER)                          AS [bv_buffer_stock]
	,COALESCE(
		 NULLIF(LTRIM(RTRIM(it.[Common Item No_])), N'')
		,NULLIF(LTRIM(RTRIM(bt.[Common Item No_])), N'')
	)                                                                      AS [common_item_no]
	,ISNULL(it.[D2C Master SKU], bt.[D2C Master SKU])                       AS [d2c_master_sku]
	,ISNULL(it.[D2C Web Item], bt.[D2C Web Item])                           AS [d2c_web_item]
	,ISNULL(it.[Owtanet Export], bt.[Owtanet Export])                       AS [owtanet_export]
	,ISNULL(it.[Web Item], bt.[Web Item])                                   AS [web_item]
	,ISNULL(it.[Record ID], it.[Record ID])                                 AS [record_id]

FROM [example$Item] AS it

FULL OUTER JOIN [example BV$Item] AS bt
	ON it.[No_] = bt.[No_]

LEFT JOIN [Example$Vendor] AS vn
	ON ISNULL(it.[Vendor No_], bt.[Vendor No_]) = vn.[No_]

LEFT JOIN [Example$Item Category] AS ct
	ON it.[Item Category Code] = ct.[Code]

LEFT JOIN [Example$Product Group] AS pg
	ON it.[Item Category Code] = pg.[Item Category Code]
		AND it.[Product Group Code] = pg.[Code]

WHERE LEN(ISNULL(it.[No_], bt.[No_])) <= 30;
