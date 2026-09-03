USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

CREATE OR ALTER VIEW [dbo].[item_image_catalogue]
AS
SELECT i.[item_id]
	,i.[common_item_no]
	,ii.[item_image_id]
	,ii.[image_key]
	,ii.[file_name]
	,ii.[image_type]
	,ii.[display_order]
	,ii.[is_primary]
	,il.[image_location_id]
	,il.[source_code]
	,il.[source_file_id]
	,il.[location_type]
	,il.[location_uri]
	,il.[file_size]
	,il.[width]
	,il.[height]
	,il.[last_modified]
FROM [dbo].[items] AS i
INNER JOIN [dbo].[item_images] AS ii
	ON ii.[item_id] = i.[item_id]
INNER JOIN [dbo].[item_image_locations] AS il
	ON il.[item_image_id] = ii.[item_image_id];

GO
