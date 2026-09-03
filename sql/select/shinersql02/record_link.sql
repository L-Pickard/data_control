SELECT 'Shiner Ltd' AS [entity]
    ,'NAV' AS [system]
    ,[Link ID] AS [link_id]
    ,[Record ID] AS [record_id]
    ,[URL1] AS [url]
    ,[Description] AS [description]
    ,[Type] AS [type]
    ,[Created] AS [created]
    ,[Created] AS [modified]

FROM [Record Link]
WHERE [Company] = 'Shiner'

UNION ALL

SELECT 'Shiner B.V' AS [entity]
    ,'NAV' AS [system]
    ,[Link ID] AS [link_id]
    ,[Record ID] AS [record_id]
    ,[URL1] AS [url]
    ,[Description] AS [description]
    ,[Type] AS [type]
    ,[Created] AS [created]
    ,[Created] AS [modified]

FROM [Record Link]
WHERE [Company] = 'Shiner BV'