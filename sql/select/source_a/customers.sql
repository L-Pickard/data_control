WITH ltd_customers AS (
	SELECT cu.[No_] AS [customer_id]
		,NULLIF(cu.[Name], '') AS [customer_name]
		,NULLIF(cu.[Address], '') AS [address]
		,NULLIF(cu.[Address 2], '') AS [address_2]
		,NULLIF(cu.[City], '') AS [city]
		,NULLIF(cu.[County], '') AS [county]
		,NULLIF(cu.[Country_Region Code], '') AS [country_id]
		,NULLIF(cu.[Post Code], '') AS [post_code]
		,NULLIF(cu.[Territory Code], '') AS [territory_code]
		,NULLIF(cu.[Contact], '') AS [contact_name]
		,NULLIF(cu.[Phone No_], '') AS [phone_no]
		,CAST(NULL AS NVARCHAR(30)) AS [mobile_phone_no]
		,NULLIF(cu.[E-Mail], '') AS [email]
		,NULLIF(cu.[Home Page], '') AS [home_page]
		,NULLIF(cu.[Primary Contact No_], '') AS [primary_contact_no]
		,NULLIF(cu.[Our Account No_], '') AS [our_account_no]
		,COALESCE(NULLIF(cu.[Currency Code], ''), 'GBP') AS [currency_code]
		,cu.[Credit Limit (LCY)] AS [credit_limit_lcy]
		,NULLIF(cu.[Customer Posting Group], '') AS [customer_posting_group]
		,NULLIF(cu.[Gen_ Bus_ Posting Group], '') AS [general_business_posting_group]
		,NULLIF(cu.[VAT Bus_ Posting Group], '') AS [vat_business_posting_group]
		,NULLIF(cu.[Customer Price Group], '') AS [customer_price_group]
		,NULLIF(cu.[Customer Disc_ Group], '') AS [customer_discount_group]
		,NULLIF(cu.[Payment Terms Code], '') AS [payment_terms_code]
		,NULLIF(cu.[Payment Method Code], '') AS [payment_method_code]
		,NULLIF(cu.[Shipment Method Code], '') AS [shipment_method_code]
		,NULLIF(cu.[Shipping Agent Code], '') AS [shipping_agent_code]
		,NULLIF(cu.[Location Code], '') AS [location_code]
		,NULLIF(cu.[Type of Supply Code], '') AS [type_of_supply_code]
		,NULLIF(ts.[Description], '') AS [type_of_supply_description]
		,NULLIF(cu.[Salesperson Code], '') AS [salesperson_id]
		,cu.[Blocked] AS [blocked]
		,NULLIF(cu.[Bill-to Customer No_], '') AS [bill_to_customer_id]
		,cu.[Prices Including VAT] AS [prices_including_vat]
		,NULLIF(cu.[VAT Registration No_], '') AS [vat_reg_no]
		,NULLIF(cu.[Registration No], '') AS [registration_no]
		,NULLIF(cu.[EORI No_], '') AS [eori_no]
		,cu.[Last Date Modified] AS [last_modified]

	FROM [Example$Customer] AS cu

	LEFT JOIN [Example$Type of Supply] AS ts
		ON cu.[Type of Supply Code] = ts.[Code]
),
all_customers AS (
	SELECT *
	FROM ltd_customers

	UNION ALL

	SELECT cu.[No_] AS [customer_id]
		,NULLIF(cu.[Name], '') AS [customer_name]
		,NULLIF(cu.[Address], '') AS [address]
		,NULLIF(cu.[Address 2], '') AS [address_2]
		,NULLIF(cu.[City], '') AS [city]
		,NULLIF(cu.[County], '') AS [county]
		,NULLIF(cu.[Country_Region Code], '') AS [country_id]
		,NULLIF(cu.[Post Code], '') AS [post_code]
		,NULLIF(cu.[Territory Code], '') AS [territory_code]
		,NULLIF(cu.[Contact], '') AS [contact_name]
		,NULLIF(cu.[Phone No_], '') AS [phone_no]
		,CAST(NULL AS NVARCHAR(30)) AS [mobile_phone_no]
		,NULLIF(cu.[E-Mail], '') AS [email]
		,NULLIF(cu.[Home Page], '') AS [home_page]
		,NULLIF(cu.[Primary Contact No_], '') AS [primary_contact_no]
		,NULLIF(cu.[Our Account No_], '') AS [our_account_no]
		,COALESCE(NULLIF(cu.[Currency Code], ''), 'EUR') AS [currency_code]
		,cu.[Credit Limit (LCY)] AS [credit_limit_lcy]
		,NULLIF(cu.[Customer Posting Group], '') AS [customer_posting_group]
		,NULLIF(cu.[Gen_ Bus_ Posting Group], '') AS [general_business_posting_group]
		,NULLIF(cu.[VAT Bus_ Posting Group], '') AS [vat_business_posting_group]
		,NULLIF(cu.[Customer Price Group], '') AS [customer_price_group]
		,NULLIF(cu.[Customer Disc_ Group], '') AS [customer_discount_group]
		,NULLIF(cu.[Payment Terms Code], '') AS [payment_terms_code]
		,NULLIF(cu.[Payment Method Code], '') AS [payment_method_code]
		,NULLIF(cu.[Shipment Method Code], '') AS [shipment_method_code]
		,NULLIF(cu.[Shipping Agent Code], '') AS [shipping_agent_code]
		,NULLIF(cu.[Location Code], '') AS [location_code]
		,NULLIF(cu.[Type of Supply Code], '') AS [type_of_supply_code]
		,NULLIF(ts.[Description], '') AS [type_of_supply_description]
		,NULLIF(cu.[Salesperson Code], '') AS [salesperson_id]
		,cu.[Blocked] AS [blocked]
		,NULLIF(cu.[Bill-to Customer No_], '') AS [bill_to_customer_id]
		,cu.[Prices Including VAT] AS [prices_including_vat]
		,NULLIF(cu.[VAT Registration No_], '') AS [vat_reg_no]
		,NULLIF(cu.[Registration No], '') AS [registration_no]
		,NULLIF(cu.[EORI No_], '') AS [eori_no]
		,cu.[Last Date Modified] AS [last_modified]

	FROM [Example BV$Customer] AS cu

	LEFT JOIN [Example BV$Type of Supply] AS ts
		ON cu.[Type of Supply Code] = ts.[Code]

	WHERE NOT EXISTS (
		SELECT 1
		FROM ltd_customers AS ltd
		WHERE ltd.[customer_id] = cu.[No_]
	)
),
missing_customer_ids AS (
	SELECT [customer_id]
	FROM (VALUES
		 ('CUSTOMER_001')
		,('CUSTOMER_001')
		,('CUSTOMER_001')
		,('CUSTOMER_001')
		,('CUSTOMER_001')
		,('CUSTOMER_001')
		,('')
	) AS missing ([customer_id])
)

SELECT *
FROM all_customers

UNION ALL

SELECT missing.[customer_id]
	,'Unknown Old Customer' AS [customer_name]
	,NULL AS [address]
	,NULL AS [address_2]
	,NULL AS [city]
	,NULL AS [county]
	,'GB' AS [country_id]
	,NULL AS [post_code]
	,NULL AS [territory_code]
	,NULL AS [contact_name]
	,NULL AS [phone_no]
	,NULL AS [mobile_phone_no]
	,NULL AS [email]
	,NULL AS [home_page]
	,NULL AS [primary_contact_no]
	,NULL AS [our_account_no]
	,'GBP' AS [currency_code]
	,NULL AS [credit_limit_lcy]
	,NULL AS [customer_posting_group]
	,NULL AS [general_business_posting_group]
	,NULL AS [vat_business_posting_group]
	,NULL AS [customer_price_group]
	,NULL AS [customer_discount_group]
	,NULL AS [payment_terms_code]
	,NULL AS [payment_method_code]
	,NULL AS [shipment_method_code]
	,NULL AS [shipping_agent_code]
	,NULL AS [location_code]
	,NULL AS [type_of_supply_code]
	,NULL AS [type_of_supply_description]
	,NULL AS [salesperson_id]
	,0 AS [blocked]
	,NULL AS [bill_to_customer_id]
	,NULL AS [prices_including_vat]
	,NULL AS [vat_reg_no]
	,NULL AS [registration_no]
	,NULL AS [eori_no]
	,NULL AS [last_modified]

FROM missing_customer_ids AS missing

WHERE NOT EXISTS (
	SELECT 1
	FROM all_customers AS existing
	WHERE existing.[customer_id] = missing.[customer_id]
);
