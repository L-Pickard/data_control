USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE
	OR

ALTER FUNCTION [dbo].[fnc_convert_currency] (
	 @from_currency NVARCHAR(10)
	,@to_currency NVARCHAR(10)
	,@posting_date DATE
	,@sales_value DECIMAL(38, 20)
	)
RETURNS DECIMAL(38, 20)
AS
BEGIN
	DECLARE @exchange_rate_amount DECIMAL(38, 20)

	IF @from_currency = @to_currency
	BEGIN
		RETURN @sales_value
	
	END

	-- Stored as: relational/system currency -> currency_code.
	SELECT TOP 1 @exchange_rate_amount = [exchange_rate_amount]
	
	FROM [dbo].[exchange_rates]
	
	WHERE [relational_currency_code] = @from_currency
		AND [currency_code] = @to_currency
		AND [starting_date] <= @posting_date
	
	ORDER BY [starting_date] DESC

	IF @exchange_rate_amount IS NOT NULL
	BEGIN
		RETURN @sales_value * @exchange_rate_amount
	
	END

	SET @exchange_rate_amount = NULL

	-- Reverse conversion: currency_code -> relational/system currency.
	SELECT TOP 1 @exchange_rate_amount = [exchange_rate_amount]
	
	FROM [dbo].[exchange_rates]
	
	WHERE [currency_code] = @from_currency
		AND [relational_currency_code] = @to_currency
		AND [starting_date] <= @posting_date
	
	ORDER BY [starting_date] DESC

	IF @exchange_rate_amount IS NOT NULL
		AND @exchange_rate_amount <> 0
	BEGIN
		RETURN @sales_value / @exchange_rate_amount
	
	END

	RETURN @sales_value

END

