USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER FUNCTION [dbo].[fnc_is_customer_exclusion] (
	 @entity NVARCHAR(20)
	,@customer_id NVARCHAR(20)
	,@brand_id NVARCHAR(20)
	)
RETURNS BIT
AS
/*===============================================================================================================================================
Returns 1 when the entity/customer combination is configured as a customer
exclusion in dbo.exclusions for all brands (blank brand_id) or the supplied brand; otherwise returns 0.
===============================================================================================================================================*/
BEGIN
	DECLARE @is_exclusion BIT = 0;

	IF EXISTS (
			SELECT 1
			FROM [dbo].[exclusions]
			WHERE [entity] = @entity
				AND [type] = 'exclusion'
				AND [table_name] = 'customers'
				AND [id] = @customer_id
				AND ([brand_id] = N'' OR [brand_id] = @brand_id)
			)
	BEGIN
		SET @is_exclusion = 1;
	END;

	RETURN @is_exclusion;
END;

GO
