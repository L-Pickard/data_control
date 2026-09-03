SELECT [Brand Code] AS [brand_id]
	,NULLIF(LTRIM(RTRIM([Description])), N'') AS [brand_name]

FROM [dbo].[Example$Brand];
