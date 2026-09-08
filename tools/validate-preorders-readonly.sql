SET NOCOUNT ON;
SELECT 'current' source,COUNT_BIG(*) rows,SUM(CAST([Quantity] AS bigint)) quantity FROM Finance.dbo.fPreorder
UNION ALL SELECT 'history',COUNT_BIG(*),SUM(CAST([Quantity] AS bigint)) FROM Finance.dbo.[fPreorder History];
GO
SELECT name,create_date,modify_date FROM Finance.sys.tables WHERE name IN ('fPreorder','fPreorder History');
GO
WITH raw AS (
SELECT 'current' source,* FROM Finance.dbo.fPreorder
UNION ALL SELECT 'history',* FROM Finance.dbo.[fPreorder History]
), s AS (
SELECT source,[Preorder Code] preorder_code,
CASE WHEN NULLIF(LTRIM(RTRIM([Item No])),N'') IS NOT NULL THEN N'I:'+LTRIM(RTRIM([Item No])) ELSE N'D:'+ISNULL(LTRIM(RTRIM([Item Description])),N'') END line_key,
[Customer No] customer_id,[Currency] currency_code,[Order Timestamp] order_timestamp,
MAX(NULLIF(LTRIM(RTRIM([Item No])),N'')) item_id,MAX(ISNULL(NULLIF(LTRIM(RTRIM([Item Description])),N''),N'')) description,
MAX(Season) season,MAX(Type) type,MAX([Brand Code]) brand_code,MAX([Category Code]) category_code,MAX([Country Code]) country_id,
SUM(CAST(Quantity AS decimal(38,20))) quantity,SUM(CAST(Value AS decimal(38,20))) value,
MAX([Start Timestamp]) start_timestamp,MAX([End Timestamp]) end_timestamp,MAX([ETA Timestamp]) eta_timestamp,COUNT_BIG(*) raw_rows
FROM raw GROUP BY source,[Preorder Code],CASE WHEN NULLIF(LTRIM(RTRIM([Item No])),N'') IS NOT NULL THEN N'I:'+LTRIM(RTRIM([Item No])) ELSE N'D:'+ISNULL(LTRIM(RTRIM([Item Description])),N'') END,[Customer No],[Currency],[Order Timestamp]
)
SELECT s.source,COUNT_BIG(*) business_keys,SUM(s.raw_rows) raw_rows,
SUM(CASE WHEN p.preorder_id IS NULL THEN 1 ELSE 0 END) missing_keys,
SUM(CASE WHEN s.source='history' AND p.is_current=1 THEN 1 ELSE 0 END) current_priority_overlap,
SUM(CASE WHEN p.preorder_id IS NOT NULL AND NOT(s.source='history' AND p.is_current=1) AND d.diff=1 THEN 1 ELSE 0 END) differing_rows,
MIN(p.last_seen_at) oldest_seen,MAX(p.last_seen_at) newest_seen
FROM s LEFT JOIN dbo.preorders p ON s.preorder_code=p.preorder_code AND s.line_key=p.line_key AND s.customer_id=p.customer_id AND s.currency_code=p.currency_code AND s.order_timestamp=p.order_timestamp
OUTER APPLY (SELECT 1 diff WHERE EXISTS(
SELECT s.item_id,s.description,s.season,s.type,s.brand_code,s.category_code,s.country_id,s.quantity,CAST(s.value AS decimal(28,8)),s.start_timestamp,s.end_timestamp,s.eta_timestamp
EXCEPT SELECT p.item_id,p.description,p.season,p.type,p.brand_code,p.category_code,p.country_id,p.quantity,CAST(p.value AS decimal(28,8)),p.start_timestamp,p.end_timestamp,p.eta_timestamp)) d
GROUP BY s.source;
GO
SELECT file_source,is_current,COUNT_BIG(*) rows,MIN(last_seen_at) oldest_seen,MAX(last_seen_at) newest_seen,SUM(CASE WHEN order_timestamp_missing=1 THEN 1 ELSE 0 END) missing_order_timestamp FROM dbo.preorders GROUP BY file_source,is_current;
GO
SELECT MIN(timestamp) first_log,MAX(timestamp) last_log,COUNT(*) log_count FROM dbo.db_log;
GO
SELECT TOP(20) timestamp,level,[table],rows,action,message FROM dbo.db_log WHERE level IN ('ERROR','FAILURE') ORDER BY timestamp DESC;

