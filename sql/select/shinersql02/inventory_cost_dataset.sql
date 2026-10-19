-- Read-only inventory source query, scoped to selected entities and locations.
-- Parameters: as-of date, then XML scope (SQL02 supports XML, not OPENJSON).
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @scope XML = CAST(? AS XML);
DECLARE @ltd_enabled BIT = @scope.exist('/scope/entity[@name="Shiner Ltd"]');
DECLARE @ltd_all BIT = @scope.exist('/scope/entity[@name="Shiner Ltd" and @all="1"]');
DECLARE @bv_enabled BIT = @scope.exist('/scope/entity[@name="Shiner B.V"]');
DECLARE @bv_all BIT = @scope.exist('/scope/entity[@name="Shiner B.V" and @all="1"]');
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);

SELECT N'Shiner Ltd' AS [entity]
    ,ii.[location_code]
    ,ii.[item_id]
    ,CAST(ii.[quantity] AS DECIMAL(38,20)) AS [quantity]
    ,CAST(ic.[cost] AS DECIMAL(38,20)) AS [cost]
    ,CAST(ic.[expected_cost] AS DECIMAL(38,20)) AS [expected_cost]
    ,COALESCE(ii.[first_purchase],ii.[first_adjustment]) AS [first_receipt]
    ,COALESCE(ii.[last_purchase],ii.[last_adjustment]) AS [last_receipt]
FROM (
    SELECT il.[Location Code] AS [location_code], il.[Item No_] AS [item_id]
        ,SUM(il.[Quantity]) AS [quantity]
        ,MIN(CASE WHEN il.[Quantity]>0 AND il.[Entry Type]=0 AND il.[Document Type]=5 THEN CAST(il.[Posting Date] AS DATE) END) AS [first_purchase]
        ,MAX(CASE WHEN il.[Quantity]>0 AND il.[Entry Type]=0 AND il.[Document Type]=5 THEN CAST(il.[Posting Date] AS DATE) END) AS [last_purchase]
        ,MIN(CASE WHEN il.[Quantity]>0 AND il.[Entry Type]=2 THEN CAST(il.[Posting Date] AS DATE) END) AS [first_adjustment]
        ,MAX(CASE WHEN il.[Quantity]>0 AND il.[Entry Type]=2 THEN CAST(il.[Posting Date] AS DATE) END) AS [last_adjustment]
    FROM [Shiner$Item Ledger Entry] AS il
    WHERE il.[Posting Date]<@day_after AND il.[Drop Shipment]=0 AND (@ltd_enabled=1 AND (@ltd_all=1 OR il.[Location Code] IN (SELECT lc.n.value('@code','nvarchar(10)') FROM @scope.nodes('/scope/entity[@name="Shiner Ltd"]/location') AS lc(n))))
    GROUP BY il.[Location Code],il.[Item No_]
    HAVING SUM(il.[Quantity])>0
) AS ii
LEFT JOIN (
    SELECT ve.[Location Code] AS [location_code],ve.[Item No_] AS [item_id]
        ,SUM(ve.[Cost Amount (Actual)]+ve.[Cost Amount (Expected)]) AS [cost]
        ,SUM(ve.[Cost Amount (Expected)]) AS [expected_cost]
    FROM [Shiner$Value Entry] AS ve
    WHERE ve.[Posting Date]<@day_after AND ve.[Drop Shipment]=0 AND (@ltd_enabled=1 AND (@ltd_all=1 OR ve.[Location Code] IN (SELECT lc.n.value('@code','nvarchar(10)') FROM @scope.nodes('/scope/entity[@name="Shiner Ltd"]/location') AS lc(n))))
    GROUP BY ve.[Location Code],ve.[Item No_]
) AS ic ON ic.[location_code]=ii.[location_code] AND ic.[item_id]=ii.[item_id]
UNION ALL

SELECT N'Shiner B.V' AS [entity]
    ,ii.[location_code]
    ,ii.[item_id]
    ,CAST(ii.[quantity] AS DECIMAL(38,20)) AS [quantity]
    ,CAST(ic.[cost] AS DECIMAL(38,20)) AS [cost]
    ,CAST(ic.[expected_cost] AS DECIMAL(38,20)) AS [expected_cost]
    ,COALESCE(ii.[first_purchase],ii.[first_adjustment]) AS [first_receipt]
    ,COALESCE(ii.[last_purchase],ii.[last_adjustment]) AS [last_receipt]
FROM (
    SELECT il.[Location Code] AS [location_code], il.[Item No_] AS [item_id]
        ,SUM(il.[Quantity]) AS [quantity]
        ,MIN(CASE WHEN il.[Quantity]>0 AND il.[Entry Type]=0 AND il.[Document Type]=5 THEN CAST(il.[Posting Date] AS DATE) END) AS [first_purchase]
        ,MAX(CASE WHEN il.[Quantity]>0 AND il.[Entry Type]=0 AND il.[Document Type]=5 THEN CAST(il.[Posting Date] AS DATE) END) AS [last_purchase]
        ,MIN(CASE WHEN il.[Quantity]>0 AND il.[Entry Type]=2 THEN CAST(il.[Posting Date] AS DATE) END) AS [first_adjustment]
        ,MAX(CASE WHEN il.[Quantity]>0 AND il.[Entry Type]=2 THEN CAST(il.[Posting Date] AS DATE) END) AS [last_adjustment]
    FROM [Shiner BV$Item Ledger Entry] AS il
    WHERE il.[Posting Date]<@day_after AND il.[Drop Shipment]=0 AND (@bv_enabled=1 AND (@bv_all=1 OR il.[Location Code] IN (SELECT lc.n.value('@code','nvarchar(10)') FROM @scope.nodes('/scope/entity[@name="Shiner B.V"]/location') AS lc(n))))
    GROUP BY il.[Location Code],il.[Item No_]
    HAVING SUM(il.[Quantity])>0
) AS ii
LEFT JOIN (
    SELECT ve.[Location Code] AS [location_code],ve.[Item No_] AS [item_id]
        ,SUM(ve.[Cost Amount (Actual)]+ve.[Cost Amount (Expected)]) AS [cost]
        ,SUM(ve.[Cost Amount (Expected)]) AS [expected_cost]
    FROM [Shiner BV$Value Entry] AS ve
    WHERE ve.[Posting Date]<@day_after AND ve.[Drop Shipment]=0 AND (@bv_enabled=1 AND (@bv_all=1 OR ve.[Location Code] IN (SELECT lc.n.value('@code','nvarchar(10)') FROM @scope.nodes('/scope/entity[@name="Shiner B.V"]/location') AS lc(n))))
    GROUP BY ve.[Location Code],ve.[Item No_]
) AS ic ON ic.[location_code]=ii.[location_code] AND ic.[item_id]=ii.[item_id]
OPTION (RECOMPILE, MAXDOP 1);
