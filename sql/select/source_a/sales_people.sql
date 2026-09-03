SELECT [Code] AS [salesperson_id]
	,[Name] AS [name]
	,[E-Mail] AS [email]

FROM [Example$Salesperson_Purchaser]

UNION ALL

SELECT bv.[Code] AS [salesperson_id]
	,bv.[Name] AS [name]
	,bv.[E-Mail] AS [email]

FROM [Example BV$Salesperson_Purchaser] AS bv

WHERE NOT EXISTS (
		SELECT 1
		
		FROM [Example$Salesperson_Purchaser] AS ltd
		
		WHERE ltd.[Code] = bv.[Code]
		)

UNION ALL

SELECT
    h.[salesperson_id],
    h.[name],
    h.[email]

FROM (

    VALUES
         ('', 'Blank', '')
        ,('BARTL', 'Bart L', '')
        ,('CORALIEC', 'Coralie C', '')
        ,('FRANCESCAB', 'Francesca B', '')
        ,('JAMESC', 'James C', '')
        ,('N/A', 'Not Available', '')
        ,('GEMO', 'Not Available', '')
        ,('ALEXM', 'Not Available', '')
        ,('JAMESK', 'Not Available', '')
        ,('BECKYP', 'Not Available', '')

) AS h([salesperson_id], [name], [email])

WHERE NOT EXISTS (
    SELECT 1
    FROM [Example$Salesperson_Purchaser] AS ltd
    WHERE ltd.[Code] = h.[salesperson_id]
)

AND NOT EXISTS (
    SELECT 1
    FROM [Example BV$Salesperson_Purchaser] AS bv
    WHERE bv.[Code] = h.[salesperson_id]
);