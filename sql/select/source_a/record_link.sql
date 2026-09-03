SELECT 'Example Ltd' AS [entity]
    ,'NAV' AS [system]
    ,[Link ID] AS [link_id]
    ,[Record ID] AS [record_id]
    ,[URL1] AS [url]
    ,[Description] AS [description]
    ,[Type] AS [type]
    ,[Created] AS [created]
    ,[Created] AS [modified]

FROM [Record Link]
WHERE [Company] = 'Example'

UNION ALL

SELECT 'Example BV' AS [entity]
    ,'NAV' AS [system]
    ,[Link ID] AS [link_id]
    ,[Record ID] AS [record_id]
    ,[URL1] AS [url]
    ,[Description] AS [description]
    ,[Type] AS [type]
    ,[Created] AS [created]
    ,[Created] AS [modified]

FROM [Record Link]
WHERE [Company] = 'Example BV'