SELECT 'Example LLC' AS [entity]
	,'BC' AS [system]
	,[Link ID] AS [link_id]
	,[Record ID] AS [record_id]
	,[URL1] AS [url]
	,[Description] AS [description]
	,[Type] AS [type]
	,[Created] AS [created]
	,CASE 
		WHEN [$systemModifiedAt] = '1753-01-01 00:00:00.000'
			THEN [Created]
		ELSE [$systemModifiedAt]
		END AS [modified]

FROM [dbo].[Record Link]

