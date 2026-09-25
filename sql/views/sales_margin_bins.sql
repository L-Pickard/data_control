USE [data_control];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW [dbo].[sales_margin_bins]
AS
-- One row per stored sales line; the entity-currency bin is persisted and is its sort key.
-- Keep the supplied report's external-sales and customer/brand exclusions.
-- Date range is supplied by the caller, rather than fixed in this reusable view.
SELECT s.[date_key]
    ,s.[date_key_ny]
    ,s.[posting_date]
    ,s.[document_date]
    ,s.[location_code]
    ,s.[customer_id]
    ,s.[document_no]
    ,s.[order_no]
    ,s.[doc_type]
    ,s.[salesperson_id]
    ,s.[country_id]
    ,s.[entity]
    ,s.[is_adjusted]
    ,s.[exclusion]
    ,s.[intercompany]
    ,s.[sales_type]
    ,s.[brand_id]
    ,s.[item_id]
    ,s.[quantity]
    ,s.[margin_bin]
    ,CONVERT(VARCHAR(32), CASE
        WHEN s.[margin_bin] = 127 THEN 'Undefined margin'
        WHEN s.[margin_bin] = -10 THEN '<= -100%'
        WHEN s.[margin_bin] = 11 THEN '> 100%'
        ELSE CONCAT('> ', (s.[margin_bin] - 1) * 10, '% & <= ', s.[margin_bin] * 10, '%')
    END) AS [margin_bin_label]
    ,s.[gbp_sales]
    ,s.[gbp_cost]
    ,s.[gbp_royalty]
    ,s.[gbp_rebate]
    ,s.[gbp_margin]
    ,s.[gbp_adjusted_margin]
    ,s.[eur_sales]
    ,s.[eur_cost]
    ,s.[eur_royalty]
    ,s.[eur_rebate]
    ,s.[eur_margin]
    ,s.[eur_adjusted_margin]
    ,s.[usd_sales]
    ,s.[usd_cost]
    ,s.[usd_royalty]
    ,s.[usd_rebate]
    ,s.[usd_margin]
    ,s.[usd_adjusted_margin]
FROM [dbo].[sales] AS s

GO
