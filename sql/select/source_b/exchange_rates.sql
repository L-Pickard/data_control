SELECT [Currency Code] AS [currency_code]
    ,CAST([Starting Date] AS DATE) AS [starting_date]
	,'USD' AS [relational_currency_code]
	,[Exchange Rate Amount] AS [exchange_rate_amount]
FROM [Example USA Master Setup$Currency Exchange Rate$437dbf0e-84ff-417a-965d-ed2bb9650972]
WHERE [Relational Exch_ Rate Amount] = 1
AND [Relational Currency Code] = ''