USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER FUNCTION [dbo].[fnc_is_customer_intercompany] (
	 @entity NVARCHAR(20)
	,@customer_id NVARCHAR(20)
	)
RETURNS BIT
AS
/*===============================================================================================================================================
Returns 1 when the entity/customer combination is configured as an intercompany
customer in dbo.exclusions; otherwise returns 0.
===============================================================================================================================================*/
BEGIN
	DECLARE @is_intercompany BIT = 0;

	IF EXISTS (
			SELECT 1
			FROM [dbo].[exclusions]
			WHERE [entity] = @entity
				AND [type] = 'intercompany'
				AND [table_name] = 'customers'
				AND [id] = @customer_id
			)
	BEGIN
		SET @is_intercompany = 1;
	END;

	RETURN @is_intercompany;
END;

GO
