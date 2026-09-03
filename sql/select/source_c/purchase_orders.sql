WITH purchase_headers AS (
	SELECT 'Example Ltd' AS [entity]
		,ph.*
		,phe.[Afloat$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_afloat]
		,phe.[Container No_$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_container_no]
		,phe.[Waybill No_$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_waybill_no]
		,phe.[Date Afloat$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_date_afloat]
		,phe.[Expected XF Date$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_requested_xf_date]
		,phe.[Promised XF Date$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_promised_xf_date]
		,phe.[Actual XF Date$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_actual_xf_date]
		,phe.[Deposit Payment Date$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_deposit_payment_date]
		,phe.[Balance Payment Date$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_balance_payment_date]
		,phe.[Example Ref_$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_external_reference]
		,phe.[Intercompany Doc No_$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_intercompany_document_no]
		,phe.[3PL Sent$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_sent_to_3pl]
		,phe.[3PL Date Time$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_sent_to_3pl_at]
		,phe.[Last Modified Date Time$7345c412-e77c-4377-90eb-8798f2bfcc1c] AS [extension_last_modified]

	FROM [Example UAT UK$Purchase Header$437dbf0e-84ff-417a-965d-ed2bb9650972] AS ph

	LEFT JOIN [Example UAT UK$Purchase Header$437dbf0e-84ff-417a-965d-ed2bb9650972$ext] AS phe
		ON phe.[Document Type] = ph.[Document Type]
		AND phe.[No_] = ph.[No_]

	WHERE ph.[Document Type] = 1

	UNION ALL

	SELECT 'Example BV' AS [entity]
		,ph.*
		,phe.[Afloat$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[Container No_$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[Waybill No_$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[Date Afloat$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[Expected XF Date$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[Promised XF Date$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[Actual XF Date$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[Deposit Payment Date$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[Balance Payment Date$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[Example Ref_$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[Intercompany Doc No_$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[3PL Sent$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[3PL Date Time$7345c412-e77c-4377-90eb-8798f2bfcc1c]
		,phe.[Last Modified Date Time$7345c412-e77c-4377-90eb-8798f2bfcc1c]

	FROM [Example UAT BV$Purchase Header$437dbf0e-84ff-417a-965d-ed2bb9650972] AS ph

	LEFT JOIN [Example UAT BV$Purchase Header$437dbf0e-84ff-417a-965d-ed2bb9650972$ext] AS phe
		ON phe.[Document Type] = ph.[Document Type]
		AND phe.[No_] = ph.[No_]

	WHERE ph.[Document Type] = 1
),
purchase_lines AS (
	SELECT 'Example Ltd' AS [entity], pl.*
	FROM [Example UAT UK$Purchase Line$437dbf0e-84ff-417a-965d-ed2bb9650972] AS pl
	WHERE pl.[Document Type] = 1

	UNION ALL

	SELECT 'Example BV' AS [entity], pl.*
	FROM [Example UAT BV$Purchase Line$437dbf0e-84ff-417a-965d-ed2bb9650972] AS pl
	WHERE pl.[Document Type] = 1
)

SELECT pl.[entity]
	,pl.[Document Type] AS [document_type]
	,'Order' AS [document_type_name]
	,pl.[Document No_] AS [document_no]
	,pl.[Line No_] AS [line_no]
	,CASE WHEN pl.[Type] = 2 THEN NULLIF(pl.[No_], '') END AS [item_id]
	,NULLIF(pl.[Buy-from Vendor No_], '') AS [vendor_id]
	,NULLIF(pl.[Pay-to Vendor No_], '') AS [pay_to_vendor_id]
	,NULLIF(pl.[Location Code], '') AS [location_code]
	,NULLIF(pl.[Unit of Measure Code], '') AS [unit_of_measure_code]
	,NULLIF(ph.[Purchaser Code], '') AS [purchaser_code]
	,COALESCE(NULLIF(ph.[Currency Code], ''), CASE pl.[entity] WHEN 'Example BV' THEN 'EUR' ELSE 'GBP' END) AS [currency_code]
	,ph.[Currency Factor] AS [currency_factor]
	,ph.[Status] AS [document_status]
	,CASE ph.[Status] WHEN 0 THEN 'Open' WHEN 1 THEN 'Released' WHEN 2 THEN 'Pending Approval' WHEN 3 THEN 'Pending Prepayment' ELSE 'Unknown' END AS [document_status_name]
	,NULLIF(CAST(ph.[Order Date] AS DATE), '17530101') AS [order_date]
	,NULLIF(CAST(ph.[Document Date] AS DATE), '17530101') AS [document_date]
	,NULLIF(CAST(ph.[Posting Date] AS DATE), '17530101') AS [posting_date]
	,NULLIF(CAST(pl.[Expected Receipt Date] AS DATE), '17530101') AS [expected_receipt_date]
	,NULLIF(CAST(pl.[Requested Receipt Date] AS DATE), '17530101') AS [requested_receipt_date]
	,NULLIF(CAST(pl.[Promised Receipt Date] AS DATE), '17530101') AS [promised_receipt_date]
	,NULLIF(CAST(pl.[Planned Receipt Date] AS DATE), '17530101') AS [planned_receipt_date]
	,NULLIF(CAST(ph.[Due Date] AS DATE), '17530101') AS [due_date]
	,NULLIF(ph.[Your Reference], '') AS [your_reference]
	,NULLIF(ph.[Vendor Order No_], '') AS [vendor_order_no]
	,NULLIF(ph.[Vendor Invoice No_], '') AS [vendor_invoice_no]
	,NULLIF(ph.[Shipment Method Code], '') AS [shipment_method_code]
	,NULLIF(pl.[Shortcut Dimension 1 Code], '') AS [country_dimension_code]
	,NULLIF(pl.[Shortcut Dimension 2 Code], '') AS [brand_dimension_code]
	,CAST(pl.[Drop Shipment] AS BIT) AS [drop_shipment]
	,pl.[Quantity] AS [quantity]
	,pl.[Quantity Received] AS [quantity_received]
	,pl.[Quantity Invoiced] AS [quantity_invoiced]
	,pl.[Qty_ to Receive] AS [quantity_to_receive]
	,pl.[Outstanding Quantity] AS [outstanding_quantity]
	,pl.[Direct Unit Cost] AS [direct_unit_cost]
	,pl.[Unit Cost (LCY)] AS [unit_cost_lcy]
	,pl.[Line Discount _] AS [line_discount_percent]
	,pl.[Line Discount Amount] AS [line_discount_amount]
	,pl.[Line Amount] AS [line_amount]
	,pl.[Amount Including VAT] AS [amount_including_vat]
	,pl.[Outstanding Amount] AS [outstanding_amount]
	,pl.[Outstanding Amount (LCY)] AS [outstanding_amount_lcy]
	,CAST(ph.[extension_afloat] AS BIT) AS [afloat]
	,NULLIF(ph.[extension_container_no], '') AS [container_no]
	,NULLIF(ph.[extension_waybill_no], '') AS [waybill_no]
	,NULLIF(CAST(ph.[extension_date_afloat] AS DATE), '17530101') AS [date_afloat]
	,NULLIF(CAST(ph.[extension_requested_xf_date] AS DATE), '17530101') AS [requested_xf_date]
	,NULLIF(CAST(ph.[extension_promised_xf_date] AS DATE), '17530101') AS [promised_xf_date]
	,NULLIF(CAST(ph.[extension_actual_xf_date] AS DATE), '17530101') AS [actual_xf_date]
	,NULLIF(CAST(ph.[extension_deposit_payment_date] AS DATE), '17530101') AS [deposit_payment_date]
	,NULLIF(CAST(ph.[extension_balance_payment_date] AS DATE), '17530101') AS [balance_payment_date]
	,NULLIF(ph.[extension_external_reference], '') AS [external_reference]
	,NULLIF(ph.[extension_intercompany_document_no], '') AS [intercompany_document_no]
	,CAST(ph.[extension_sent_to_3pl] AS BIT) AS [sent_to_3pl]
	,NULLIF(ph.[extension_sent_to_3pl_at], '17530101') AS [sent_to_3pl_at]
	,NULLIF(ph.[extension_last_modified], '17530101') AS [last_modified]

FROM purchase_lines AS pl

INNER JOIN purchase_headers AS ph
	ON ph.[entity] = pl.[entity]
	AND ph.[Document Type] = pl.[Document Type]
	AND ph.[No_] = pl.[Document No_];
