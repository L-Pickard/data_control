USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER FUNCTION [dbo].[fnc_calculate_customer_rebate] (
	 @item_id NVARCHAR(20)
	,@customer_id NVARCHAR(20)
	,@entity NVARCHAR(20)
	,@sales_value DECIMAL(38, 20)
	)
RETURNS DECIMAL(38, 20)
AS
BEGIN
	DECLARE @brand_id NVARCHAR(30)

	SET @brand_id = LEFT(@item_id, 3)

	IF @entity = 'Example LLC'
	BEGIN
		RETURN 0.0
	
	END

	RETURN @sales_value * ISNULL((
				SELECT TOP 1 [deduction_value]
				
				FROM [dbo].[deductions]
				
				WHERE [deduction_id] = @customer_id
					AND [deduction_type] = 'Customer Rebate'
					AND [deduction_sub_type] IN (@brand_id, '')
					AND [deduction_entity] = @entity
				
				ORDER BY CASE
						WHEN [deduction_sub_type] = @brand_id
							THEN 0
						ELSE 1
						END
				), 0)

END
