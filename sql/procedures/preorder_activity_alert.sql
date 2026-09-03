USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE
	OR

ALTER PROCEDURE [dbo].[preorder_activity_alert]
AS
BEGIN
	SET NOCOUNT ON;

	DROP TABLE

	IF EXISTS #new_preorder_totals
		CREATE TABLE #new_preorder_totals (
			[deadline] DATETIME2(3)
			,[eta] DATETIME2(3)
			,[timestamp] DATETIME2(3)
			,[preorder_code] NVARCHAR(50)
			,[customer_id] NVARCHAR(20)
			,[customer_name] NVARCHAR(100)
			,[salesperson_id] NVARCHAR(20)
			,[email] NVARCHAR(100)
			,[entries] INTEGER
			,[quantity] DECIMAL(38, 20)
			,[currency_code] NVARCHAR(10)
			,[value] DECIMAL(38, 20)
			,PRIMARY KEY CLUSTERED (
				[preorder_code]
				,[customer_id]
				,[currency_code]
				)
			)

	INSERT INTO #new_preorder_totals
	
	SELECT MIN(pr.[end_timestamp]) AS [deadline]
		,MAX(pr.[eta_timestamp]) AS [eta]
		,MAX(pr.[order_timestamp]) AS [timestamp]
		,pr.[preorder_code]
		,pr.[customer_id]
		,cu.[customer_name]
		,cu.[salesperson_id]
		,sp.[email]
		,COUNT(DISTINCT pr.[order_timestamp]) AS [entries]
		,SUM(pr.[quantity]) AS [quantity]
		,pr.[currency_code]
		,ROUND(SUM(pr.[Value]), 2) AS [Value]
	
	FROM [dbo].[preorders] AS pr
	
	INNER JOIN [dbo].[customers] AS cu
		ON pr.[customer_id] = cu.[customer_id]
	
	INNER JOIN [dbo].[sales_people] AS sp
		ON cu.[salesperson_id] = sp.[salesperson_id]
	
	GROUP BY pr.[preorder_code]
		,pr.[customer_id]
		,cu.[customer_name]
		,cu.[salesperson_id]
		,sp.[email]
		,pr.[currency_code]

	-- Below is the code to create another temp table for the data we need to send out as emails.
	DROP TABLE

	IF EXISTS #send_email_totals
		CREATE TABLE #send_email_totals (
			 [deadline] DATETIME2(3)
			,[eta] DATETIME2(3)
			,[timestamp] DATETIME2(3)
			,[preorder_code] NVARCHAR(50)
			,[customer_id] NVARCHAR(20)
			,[customer_name] NVARCHAR(100)
			,[salesperson_id] NVARCHAR(20)
			,[email] NVARCHAR(100)
			,[category] NVARCHAR(20)
			,[entries] INTEGER
			,[quantity] DECIMAL(38, 20)
			,[currency_code] NVARCHAR(10)
			,[value] DECIMAL(38, 20)
			,PRIMARY KEY CLUSTERED (
				 [preorder_code]
				,[customer_id]
				,[currency_code]
				)
			)

	INSERT INTO #send_email_totals

	SELECT 	 nt.[deadline]
			,nt.[eta]
			,nt.[timestamp]
			,nt.[preorder_code]
			,nt.[customer_id]
			,nt.[customer_name]
			,nt.[salesperson_id]
			,nt.[email]
			,'New Order' AS [Category]
			,nt.[entries]
			,nt.[quantity]
			,nt.[currency_code]
			,nt.[value]

	FROM #new_preorder_totals AS nt

END

