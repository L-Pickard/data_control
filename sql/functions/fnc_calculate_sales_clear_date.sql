USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

CREATE
	OR

ALTER FUNCTION [dbo].[fnc_calculate_sales_clear_date] ()
RETURNS DATE
AS
BEGIN
	DECLARE @current_datetime DATETIME = GETDATE();

	DECLARE @current_date DATE = CAST(@current_datetime AS DATE);

	DECLARE @current_time TIME(7) = CAST(@current_datetime AS TIME(7));

	DECLARE @financial_year_start DATE = DATEFROMPARTS(YEAR(@current_date), 4, 30);

	DECLARE @return_date DATE;

	IF @current_time > '06:00:00'
	BEGIN
		SET @return_date = DATEADD(DAY, - 7, @current_date);
	
	END
	
	ELSE IF DATEDIFF(DAY, CONVERT(DATE, '19000101', 112), @current_date) % 7 = 0
	BEGIN
		-- 1900-01-01 was Monday; independent of LANGUAGE and DATEFIRST.
		SET @return_date = DATEADD(YEAR, CASE 
					WHEN @current_date >= @financial_year_start
						THEN - 2
					ELSE - 3
					END, @financial_year_start);
	
	END
	
	ELSE
	BEGIN
		SET @return_date = DATEADD(MONTH, - 1, DATEFROMPARTS(YEAR(@current_date), MONTH(@current_date), 1));
	
	END;

	RETURN @return_date;

END;

GO
