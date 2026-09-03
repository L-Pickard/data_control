WITH ltd_vendors AS (
	SELECT ve.[No_] AS [vendor_id]
		,NULLIF(ve.[Name], '') AS [vendor_name]
		,NULLIF(ve.[Address], '') AS [address]
		,NULLIF(ve.[Address 2], '') AS [address_2]
		,NULLIF(ve.[City], '') AS [city]
		,NULLIF(ve.[County], '') AS [county]
		,NULLIF(ve.[Post Code], '') AS [post_code]
		,NULLIF(ve.[Country_Region Code], '') AS [country_id]
		,NULLIF(ve.[Contact], '') AS [contact_name]
		,NULLIF(ve.[Phone No_], '') AS [phone_no]
		,CAST(NULL AS NVARCHAR(30)) AS [mobile_phone_no]
		,NULLIF(ve.[E-Mail], '') AS [email]
		,NULLIF(ve.[Home Page], '') AS [home_page]
		,NULLIF(ve.[Primary Contact No_], '') AS [primary_contact_no]
		,NULLIF(ve.[Our Account No_], '') AS [our_account_no]
		,NULLIF(ve.[Global Dimension 1 Code], '') AS [country_dimension]
		,NULLIF(ve.[Vendor Posting Group], '') AS [vendor_posting_group]
		,NULLIF(ve.[Gen_ Bus_ Posting Group], '') AS [general_business_posting_group]
		,NULLIF(ve.[VAT Bus_ Posting Group], '') AS [vat_business_posting_group]
		,COALESCE(NULLIF(ve.[Currency Code], ''), 'GBP') AS [currency_code]
		,NULLIF(ve.[Payment Terms Code], '') AS [payment_terms_code]
		,NULLIF(ve.[Payment Method Code], '') AS [payment_method_code]
		,NULLIF(ve.[Purchaser Code], '') AS [purchaser_code]
		,NULLIF(ve.[Shipment Method Code], '') AS [shipment_method_code]
		,NULLIF(ve.[Location Code], '') AS [location_code]
		,NULLIF(ve.[Lead Time Calculation], '') AS [lead_time_calculation]
		,ve.[Blocked] AS [blocked]
		,NULLIF(ve.[Pay-to Vendor No_], '') AS [pay_to_vendor_id]
		,NULLIF(ve.[VAT Registration No_], '') AS [vat_registration_no]
		,CAST(NULL AS NVARCHAR(50)) AS [registration_no]
		,CAST(NULL AS NVARCHAR(40)) AS [eori_no]
		,ve.[Last Date Modified] AS [last_modified]

	FROM [Example$Vendor] AS ve
)

SELECT *
FROM ltd_vendors

UNION ALL

SELECT ve.[No_] AS [vendor_id]
	,NULLIF(ve.[Name], '') AS [vendor_name]
	,NULLIF(ve.[Address], '') AS [address]
	,NULLIF(ve.[Address 2], '') AS [address_2]
	,NULLIF(ve.[City], '') AS [city]
	,NULLIF(ve.[County], '') AS [county]
	,NULLIF(ve.[Post Code], '') AS [post_code]
	,NULLIF(ve.[Country_Region Code], '') AS [country_id]
	,NULLIF(ve.[Contact], '') AS [contact_name]
	,NULLIF(ve.[Phone No_], '') AS [phone_no]
	,CAST(NULL AS NVARCHAR(30)) AS [mobile_phone_no]
	,NULLIF(ve.[E-Mail], '') AS [email]
	,NULLIF(ve.[Home Page], '') AS [home_page]
	,NULLIF(ve.[Primary Contact No_], '') AS [primary_contact_no]
	,NULLIF(ve.[Our Account No_], '') AS [our_account_no]
	,NULLIF(ve.[Global Dimension 1 Code], '') AS [country_dimension]
	,NULLIF(ve.[Vendor Posting Group], '') AS [vendor_posting_group]
	,NULLIF(ve.[Gen_ Bus_ Posting Group], '') AS [general_business_posting_group]
	,NULLIF(ve.[VAT Bus_ Posting Group], '') AS [vat_business_posting_group]
	,COALESCE(NULLIF(ve.[Currency Code], ''), 'EUR') AS [currency_code]
	,NULLIF(ve.[Payment Terms Code], '') AS [payment_terms_code]
	,NULLIF(ve.[Payment Method Code], '') AS [payment_method_code]
	,NULLIF(ve.[Purchaser Code], '') AS [purchaser_code]
	,NULLIF(ve.[Shipment Method Code], '') AS [shipment_method_code]
	,NULLIF(ve.[Location Code], '') AS [location_code]
	,NULLIF(ve.[Lead Time Calculation], '') AS [lead_time_calculation]
	,ve.[Blocked] AS [blocked]
	,NULLIF(ve.[Pay-to Vendor No_], '') AS [pay_to_vendor_id]
	,NULLIF(ve.[VAT Registration No_], '') AS [vat_registration_no]
	,CAST(NULL AS NVARCHAR(50)) AS [registration_no]
	,CAST(NULL AS NVARCHAR(40)) AS [eori_no]
	,ve.[Last Date Modified] AS [last_modified]

FROM [Example BV$Vendor] AS ve

WHERE NOT EXISTS (
	SELECT 1
	FROM ltd_vendors AS ltd
	WHERE ltd.[vendor_id] = ve.[No_]
);
