USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER FUNCTION [dbo].[fnc_calculate_item_royalty] (
	 @item_id NVARCHAR(20)
	,@customer_id NVARCHAR(20)
	,@entity NVARCHAR(20)
	,@sales_value DECIMAL(38, 20)
	)
RETURNS DECIMAL(38, 20)
AS
BEGIN
	DECLARE @item_royalty DECIMAL(38, 20)
	DECLARE @item_sub_type NVARCHAR(30)

	SET @item_sub_type = SUBSTRING(@item_id, 5, 3)

	IF @item_sub_type = 'DLR'
	BEGIN
		RETURN 0.0
	
	END

	IF @customer_id IN (
			  'CUSTOMER_001' -- Prizes - Scoot lt 50
			, 'CUSTOMER_001' -- Team - D Street
			, 'CUSTOMER_001' -- Prizes - Rookie lt 50
			, 'CUSTOMER_001' -- Prizes - Heelys gt 50
			, 'CUSTOMER_001' -- Tony Hawk Incorporated
			, 'CUSTOMER_001' -- Photo Studio Account
			, 'CUSTOMER_001' -- Team - Sk8 One NO NOT USE
			, 'CUSTOMER_001' -- Prizes - NHS - 50
			, 'CUSTOMER_001' -- Seeding Marketing
			, 'CUSTOMER_001' -- Prizes Marketing
			, 'CUSTOMER_001' -- Prizes - Sports goods - cost gt 50
			, 'CUSTOMER_001' -- Samples - Distributed
			, 'CUSTOMER_001' -- Sales Team Samples - sales samples sets
			, 'CUSTOMER_001' -- Marketing Promotional Items DO NOT USE
			, 'CUSTOMER_001' -- Team - Heelys
			, 'CUSTOMER_001' -- Team - Scoot
			, 'CUSTOMER_001' -- Team - Core (Marketing)
			, 'CUSTOMER_001' -- Team - Action Sports (Marketing)
			, 'CUSTOMER_001' -- Eagle B.V
			, 'CUSTOMER_001' -- FSX Media Ltd - Daily Orders
			, 'CUSTOMER_001' -- Samples - Own Brand
			, 'CUSTOMER_001' -- Team - Protection
			, 'CUSTOMER_001' -- Team - core USA
			, 'CUSTOMER_001' -- Staff Clothing Allowance
			, 'CUSTOMER_001' -- NPD Samples
			, 'CUSTOMER_001' -- Samples - NHS Apparel
			)
	BEGIN
		RETURN 0.0
	
	END

	IF @entity = 'Example LLC'
	BEGIN
		RETURN @sales_value * ISNULL((
					SELECT [deduction_value]
					
					FROM [dbo].[deductions]
					
					WHERE [deduction_id] = LEFT(@item_id, 3)
						AND [deduction_type] = 'Brand Royalty'
						AND [deduction_sub_type] = ''
						AND [deduction_entity] = 'Example LLC'
					), 0)
	
	END

	SET @item_royalty = ISNULL((
				SELECT [royalty]
				
				FROM [dbo].[items]
				
				WHERE [item_id] = @item_id
				), 0.0)

	IF @item_royalty > 0.0
	BEGIN
		RETURN @sales_value * (@item_royalty / 100)
	
	END

	RETURN @sales_value * ISNULL((
				SELECT TOP 1 [deduction_value]
				
				FROM [dbo].[deductions]
				
				WHERE [deduction_id] = LEFT(@item_id, 3)
					AND [deduction_type] = 'Brand Royalty'
					AND [deduction_sub_type] IN (@item_sub_type, '')
					AND [deduction_entity] = @entity
				
				ORDER BY CASE
						WHEN [deduction_sub_type] = @item_sub_type
							THEN 0
						ELSE 1
						END
				), 0)

END
