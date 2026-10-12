SELECT [Code] AS [country_id]
    ,[ISO-2 Code] AS [iso_code]
    ,[Name] AS [country_name]
FROM [dbo].[Shiner$Country_Region]
WHERE [Code] <> ''

UNION ALL

SELECT '' AS [country_id]
    ,'' AS [iso_code]
    ,'not assigned' AS [country_name];
