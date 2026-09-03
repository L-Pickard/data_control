USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

CREATE
	OR

ALTER VIEW [planning].[external_sales]
AS
/*
    Canonical external demand lines for demand planning.

    Example Ltd and Example BV are treated as one UK/EU fulfilment pool.
    Intercompany and reporting-excluded lines are omitted. Adjusted margin is
    used so margin transferred through the Ltd/B.V intercompany flow remains
    attached to the final external sale.
*/
SELECT s.[posting_date]
	,DATEADD(DAY, - (DATEDIFF(DAY, CONVERT(DATE, '19000101', 112), s.[posting_date]) % 7), s.[posting_date]) AS [week_start]
	,CAST(CASE 
			WHEN s.[entity] IN (N'Example Ltd', N'Example BV')
				THEN N'UK_EU'
			WHEN s.[entity] = N'Example LLC'
				THEN N'US'
			END AS NVARCHAR(10)) AS [planning_entity]
	,s.[entity] AS [source_entity]
	,s.[location_code]
	,s.[customer_id]
	,s.[document_no]
	,s.[order_no]
	,s.[doc_type]
	,s.[salesperson_id]
	,s.[country_id]
	,s.[sales_type]
	,s.[item_id]
	,COALESCE(NULLIF(LTRIM(RTRIM(i.[brand_id])), N''), N'UNKNOWN_BRAND') AS [brand_id]
	,COALESCE(NULLIF(LTRIM(RTRIM(i.[category_code])), N''), N'UNKNOWN_CATEGORY') AS [category_code]
	,COALESCE(NULLIF(LTRIM(RTRIM(i.[group_code])), N''), N'UNKNOWN_GROUP') AS [group_code]
	,s.[quantity] AS [net_units]
	,CASE 
		WHEN s.[quantity] > 0
			THEN s.[quantity]
		ELSE 0
		END AS [gross_units]
	,CASE 
		WHEN s.[quantity] < 0
			THEN - s.[quantity]
		ELSE 0
		END AS [return_units]
	,s.[gbp_sales]
	,s.[gbp_adjusted_margin]

FROM [dbo].[sales] AS s

LEFT JOIN [dbo].[items] AS i
	ON i.[item_id] = s.[item_id]

WHERE s.[intercompany] = 0
	AND s.[exclusion] = 0
	AND s.[entity] IN (N'Example Ltd', N'Example BV', N'Example LLC');

GO