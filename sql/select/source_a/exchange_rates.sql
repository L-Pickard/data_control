SELECT [Currency Code] AS [currency_code]
	,CAST([Starting Date]  AS DATE) AS [starting_date]
	,'GBP' AS [relational_currency_code]
	,[Exchange Rate Amount] AS [exchange_rate_amount]

FROM [dbo].[Example$Currency Exchange Rate]

WHERE [Relational Exch_ Rate Amount] = 1
	AND [Relational Currency Code] = ''

UNION ALL

SELECT [Currency Code] AS [currency_code]
	,CAST([Starting Date] AS DATE) AS [starting_date]
	,'EUR' AS [relational_currency_code]
	,[Exchange Rate Amount] AS [exchange_rate_amount]

FROM [dbo].[Example BV$Currency Exchange Rate]

WHERE [Relational Exch_ Rate Amount] = 1
	AND [Relational Currency Code] = ''