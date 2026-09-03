WITH current_preorders AS (
    SELECT
         UPPER([Preorder Code]) AS [preorder_code]
        ,UPPER([Item No]) AS [item_no]
        ,UPPER([Customer No]) AS [customer_no]
        ,[Order Timestamp] AS [order_timestamp]
        ,UPPER(MAX([Season])) AS [season]
        ,MAX([Type]) AS [type]
        ,UPPER(MAX([Brand Code])) AS [brand_code]
        ,UPPER(MAX([Category Code])) AS [category_code]
        ,UPPER(MAX([Country Code])) AS [country_code]
        ,SUM(CAST([Quantity] AS DECIMAL(38, 20))) AS [quantity]
        ,SUM(CAST([Value] AS DECIMAL(38, 20))) AS [value]
        ,UPPER(MAX([Currency])) AS [currency_code]
        ,MAX([Start Timestamp]) AS [start_timestamp]
        ,MAX([End Timestamp]) AS [end_timestamp]
        ,MAX([ETA Timestamp]) AS [eta_timestamp]
        ,CAST(1 AS BIT) AS [is_current]
        ,1 AS [source_priority]
    FROM [dbo].[fPreorder]
    GROUP BY
         [Preorder Code]
        ,[Item No]
        ,[Customer No]
        ,[Order Timestamp]
),
history_preorders AS (
    SELECT
         UPPER([Preorder Code]) AS [preorder_code]
        ,UPPER([Item No]) AS [item_no]
        ,UPPER([Customer No]) AS [customer_no]
        ,[Order Timestamp] AS [order_timestamp]
        ,UPPER([Season]) AS [season]
        ,[Type] AS [type]
        ,UPPER([Brand Code]) AS [brand_code]
        ,UPPER([Category Code]) AS [category_code]
        ,UPPER([Country Code]) AS [country_code]
        ,CAST([Quantity] AS DECIMAL(38, 20)) AS [quantity]
        ,CAST([Value] AS DECIMAL(38, 20)) AS [value]
        ,UPPER([Currency]) AS [currency_code]
        ,[Start Timestamp] AS [start_timestamp]
        ,[End Timestamp] AS [end_timestamp]
        ,[ETA Timestamp] AS [eta_timestamp]
        ,CAST(0 AS BIT) AS [is_current]
        ,2 AS [source_priority]
    FROM [dbo].[fPreorder History]
),
combined AS (
    SELECT * FROM current_preorders
    UNION ALL
    SELECT * FROM history_preorders
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY [preorder_code], [item_no], [customer_no], [order_timestamp]
        ORDER BY [source_priority]
    ) AS [source_rank]
    FROM combined
)
SELECT
     [preorder_code]
    ,[item_no]
    ,[customer_no]
    ,[order_timestamp]
    ,[season]
    ,[type]
    ,[brand_code]
    ,[category_code]
    ,[country_code]
    ,[quantity]
    ,[value]
    ,[currency_code]
    ,[start_timestamp]
    ,[end_timestamp]
    ,[eta_timestamp]
    ,[is_current]
FROM ranked
WHERE [source_rank] = 1;
