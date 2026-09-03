WITH sales_headers AS (
	SELECT N'Example Ltd' AS [entity], h.[Document Type], h.[No_], h.[Sell-to Customer No_],
		h.[Bill-to Customer No_], h.[Your Reference], h.[Ship-to Country_Region Code],
		h.[Ship-to Code], h.[Document Date], h.[Order Date], h.[Posting Date],
		h.[Payment Terms Code], h.[Due Date], h.[Shipment Method Code],
		h.[Customer Posting Group], h.[Currency Code], h.[Currency Factor],
		h.[Prices Including VAT], h.[Salesperson Code], h.[VAT Country_Region Code],
		h.[Intercompany Doc No_], h.[Example Ref_], h.[Last Modified Date Time],
		h.[Pre Order], h.[Order Status]
	FROM [Example$Sales Header] AS h
	WHERE h.[Document Type] = 1

	UNION ALL

	SELECT N'Example BV' AS [entity], h.[Document Type], h.[No_], h.[Sell-to Customer No_],
		h.[Bill-to Customer No_], h.[Your Reference], h.[Ship-to Country_Region Code],
		h.[Ship-to Code], h.[Document Date], h.[Order Date], h.[Posting Date],
		h.[Payment Terms Code], h.[Due Date], h.[Shipment Method Code],
		h.[Customer Posting Group], h.[Currency Code], h.[Currency Factor],
		h.[Prices Including VAT], h.[Salesperson Code], h.[VAT Country_Region Code],
		h.[Intercompany Doc No_], h.[Example Ref_], h.[Last Modified Date Time],
		h.[Pre Order], h.[Order Status]
	FROM [Example BV$Sales Header] AS h
	WHERE h.[Document Type] = 1
),
sales_lines AS (
	SELECT N'Example Ltd' AS [entity], l.[Document Type], l.[Document No_], l.[Line No_],
		l.[Type], l.[No_], l.[Shipment Date], l.[Location Code],
		l.[Shortcut Dimension 1 Code], l.[Shortcut Dimension 2 Code],
		l.[Customer Price Group], l.[Purchase Order No_], l.[Purch_ Order Line No_],
		l.[Drop Shipment], l.[Quantity], l.[Outstanding Quantity], l.[Unit Price],
		l.[Unit Cost], l.[Unit Cost (LCY)], l.[VAT %], l.[Line Discount %],
		l.[Amount], l.[Amount Including VAT], l.[Outstanding Amount],
		l.[Quantity Shipped], l.[Quantity Invoiced]
	FROM [Example$Sales Line] AS l
	WHERE l.[Document Type] = 1

	UNION ALL

	SELECT N'Example BV' AS [entity], l.[Document Type], l.[Document No_], l.[Line No_],
		l.[Type], l.[No_], l.[Shipment Date], l.[Location Code],
		l.[Shortcut Dimension 1 Code], l.[Shortcut Dimension 2 Code],
		l.[Customer Price Group], l.[Purchase Order No_], l.[Purch_ Order Line No_],
		l.[Drop Shipment], l.[Quantity], l.[Outstanding Quantity], l.[Unit Price],
		l.[Unit Cost], l.[Unit Cost (LCY)], l.[VAT %], l.[Line Discount %],
		l.[Amount], l.[Amount Including VAT], l.[Outstanding Amount],
		l.[Quantity Shipped], l.[Quantity Invoiced]
	FROM [Example BV$Sales Line] AS l
	WHERE l.[Document Type] = 1
)
SELECT l.[entity]
	,l.[Document Type] AS [document_type]
	,l.[Document No_] AS [document_no]
	,l.[Line No_] AS [line_no]
	,h.[Sell-to Customer No_] AS [sell_to_customer_id]
	,h.[Bill-to Customer No_] AS [bill_to_customer_id]
	,NULLIF(h.[Your Reference], N'') AS [your_reference]
	,NULLIF(h.[Ship-to Country_Region Code], N'') AS [ship_to_country_id]
	,NULLIF(h.[Ship-to Code], N'') AS [ship_to_code]
	,NULLIF(CAST(h.[Document Date] AS DATE), '17530101') AS [document_date]
	,NULLIF(CAST(h.[Order Date] AS DATE), '17530101') AS [order_date]
	,NULLIF(CAST(h.[Posting Date] AS DATE), '17530101') AS [posting_date]
	,NULLIF(CAST(l.[Shipment Date] AS DATE), '17530101') AS [shipment_date]
	,NULLIF(h.[Payment Terms Code], N'') AS [payment_terms_code]
	,NULLIF(CAST(h.[Due Date] AS DATE), '17530101') AS [due_date]
	,NULLIF(h.[Shipment Method Code], N'') AS [shipment_method_code]
	,NULLIF(l.[Location Code], N'') AS [location_code]
	,NULLIF(l.[Shortcut Dimension 1 Code], N'') AS [country_dimension_code]
	,NULLIF(l.[Shortcut Dimension 2 Code], N'') AS [brand_dimension_code]
	,NULLIF(h.[Customer Posting Group], N'') AS [customer_posting_group]
	,COALESCE(NULLIF(h.[Currency Code], N''), CASE l.[entity] WHEN N'Example BV' THEN N'EUR' ELSE N'GBP' END) AS [currency_code]
	,h.[Currency Factor] AS [currency_factor]
	,NULLIF(l.[Customer Price Group], N'') AS [customer_price_group]
	,CAST(h.[Prices Including VAT] AS BIT) AS [prices_including_vat]
	,NULLIF(h.[Salesperson Code], N'') AS [salesperson_id]
	,NULLIF(h.[VAT Country_Region Code], N'') AS [vat_country_id]
	,NULLIF(h.[Intercompany Doc No_], N'') AS [intercompany_document_no]
	,NULLIF(h.[Example Ref_], N'') AS [external_reference]
	,NULLIF(h.[Last Modified Date Time], '17530101') AS [last_modified]
	,CAST(h.[Pre Order] AS BIT) AS [preorder]
	,NULLIF(l.[Purchase Order No_], N'') AS [purchase_order_id]
	,CASE WHEN l.[Purchase Order No_] = N'' THEN NULL ELSE l.[Purch_ Order Line No_] END AS [purchase_order_line_no]
	,CAST(l.[Drop Shipment] AS BIT) AS [drop_shipment]
	,h.[Order Status] AS [document_status]
	,l.[Type] AS [line_type]
	,CASE WHEN l.[Type] = 1 THEN NULLIF(l.[No_], N'') END AS [gl_account_id]
	,CASE WHEN l.[Type] = 2 THEN NULLIF(l.[No_], N'') END AS [item_id]
	,l.[Quantity] AS [quantity]
	,l.[Outstanding Quantity] AS [outstanding_quantity]
	,l.[Unit Price] AS [unit_price]
	,l.[Unit Cost] AS [unit_cost]
	,l.[Unit Cost (LCY)] AS [unit_cost_lcy]
	,l.[VAT %] AS [vat_percentage]
	,l.[Line Discount %] AS [line_discount_percentage]
	,l.[Amount] AS [amount]
	,l.[Amount Including VAT] AS [amount_including_vat]
	,l.[Outstanding Amount] AS [outstanding_amount]
	,l.[Quantity Shipped] AS [quantity_shipped]
	,l.[Quantity Invoiced] AS [quantity_invoiced]
FROM sales_lines AS l
INNER JOIN sales_headers AS h
	ON h.[entity] = l.[entity]
	AND h.[Document Type] = l.[Document Type]
	AND h.[No_] = l.[Document No_];
