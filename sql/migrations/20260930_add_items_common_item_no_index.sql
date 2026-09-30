-- Index: dbo.items by common item number (style), for the Shiner Reports Item Sales styles table.
-- Styles are looked up by common_item_no (descriptions, and images through dbo.item_image_catalogue); without an
-- index each lookup scanned all of dbo.items (~180,000 rows, 40-170 ms each, 100 per table).
-- item_id (the clustered key) is carried automatically, so item_image_catalogue joins on to item_images by index.
-- Online, with a short lock timeout; safe to re-run (does nothing once the index exists).
USE [data_control];
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 5000;

IF NOT EXISTS (
		SELECT 1
		FROM sys.indexes
		WHERE [object_id] = OBJECT_ID(N'dbo.items')
			AND [name] = N'IX_items_common_item_no'
		)
	CREATE NONCLUSTERED INDEX [IX_items_common_item_no] ON [dbo].[items] ([common_item_no]) INCLUDE (
		[description]
		,[brand_id]
		)
		WITH (
				ONLINE = ON
				,MAXDOP = 2
				);

SELECT i.[name] AS index_name
	,i.[type_desc]
	,SUM(ps.[used_page_count]) * 8 / 1024.0 AS used_mb

FROM sys.indexes AS i

INNER JOIN sys.dm_db_partition_stats AS ps
	ON ps.[object_id] = i.[object_id]
		AND ps.[index_id] = i.[index_id]

WHERE i.[object_id] = OBJECT_ID(N'dbo.items')
	AND i.[name] = N'IX_items_common_item_no'

GROUP BY i.[name]
	,i.[type_desc];
