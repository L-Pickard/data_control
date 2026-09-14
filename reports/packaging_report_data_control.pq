let

	brands = try Excel.CurrentWorkbook(){[Name="SQL_BRAND"]}[Content]{0}[Column1] otherwise null,
    countries = try Excel.CurrentWorkbook(){[Name="SQL_COUNTRY"]}[Content]{0}[Column1] otherwise null,
    entities = try Excel.CurrentWorkbook(){[Name="SQL_ENTITY"]}[Content]{0}[Column1] otherwise null,
    start_date = try Excel.CurrentWorkbook(){[Name="SQL_START"]}[Content]{0}[Column1] otherwise null,
    end_date = try Excel.CurrentWorkbook(){[Name="SQL_END"]}[Content]{0}[Column1] otherwise null,


    Source = Sql.Database("shinersql18", "data_control", [Query="

DROP TABLE

IF EXISTS #weights_sales
	CREATE TABLE #weights_sales (
		[Category] NVARCHAR(30) NOT NULL
		,[Carton/Item] NVARCHAR(10) NOT NULL
		,[Article Type] NVARCHAR(30) NOT NULL
		,[Brand Type] NVARCHAR(20) NOT NULL
		,[Sales Type] NVARCHAR(3) NOT NULL
		,[Rigid] NVARCHAR(15) NOT NULL
		,[Grading] NVARCHAR(10) NOT NULL
		,[Component Type] NVARCHAR(30) NULL
		,[Material] NVARCHAR(30) NULL
		,[Avg Carton Qty] DECIMAL(38, 20) NOT NULL
		,[Item No] NVARCHAR(30) NOT NULL
		,[Weight KG] DECIMAL(38, 20) NOT NULL
		);

WITH [sales]
AS (
	SELECT fs.[Item No]
		,fs.[Sales Type]
		,SUM(fs.[Quantity]) AS [Quantity]
	
	FROM [Finance].[dbo].[fSales] AS fs
	
	WHERE fs.[Intercompany] = 0
		AND fs.[Exclusion] = 0
		AND fs.[Entity] IN (" & entities & ")
		AND fs.[Brand Code] IN (" & brands & ")
		AND fs.[Country Code] IN (" & countries & ")
		AND fs.[Posting Date] BETWEEN " & start_date & "
			AND " & end_date & "
	
	GROUP BY fs.[Item No]
		,fs.[Sales Type]
	)
	,[weights]
AS (
	SELECT CASE 
			WHEN CHARINDEX(' Per', itp.[Category]) > 0
				THEN LEFT(itp.[Category], CHARINDEX(' Per', itp.[Category]) - 1)
			ELSE itp.[Category]
			END AS [Category]
		,CASE 
			WHEN itp.[Category] LIKE '%Per Carton%'
				THEN 'Carton'
			ELSE 'Item'
			END AS [Carton/Item]
		,REPLACE(REPLACE(itp.[Article Type], 'Secondary ', ''), 'Primary ', '') AS [Article Type]
		,itp.[Brand Type]
		,st.[Sales Type]
		,ISNULL(itp.[Rigid], 'N/A') AS [Rigid]
		,itp.[Grading]
		,itp.[Component Type]
		,itp.[Material]
		,ISNULL(itp.[Avg Carton Qty], 1) AS [Avg Carton Qty]
		,itp.[Item No]
		,itp.[Weight KG]
	
	FROM (
        SELECT [item_id] AS [Item No],
               [category] AS [Category],
               [article_type] AS [Article Type],
               [brand_type] AS [Brand Type],
               [rigid] AS [Rigid],
               [grading] AS [Grading],
               [component_type] AS [Component Type],
               [material] AS [Material],
               [avg_carton_qty] AS [Avg Carton Qty],
               [weight_kg] AS [Weight KG]
        FROM [data_control].[dbo].[item_packaging]
    ) AS itp
	
	CROSS APPLY (
		VALUES ('B2B')
			,('D2C')
		) AS st([Sales Type])
	
	WHERE EXISTS (
			SELECT 1
			
			FROM [sales] AS sl
			
			WHERE sl.[Item No] = itp.[Item No]
			)
	)

INSERT INTO #weights_sales

SELECT we.[Category]
	,we.[Carton/Item]
	,we.[Article Type]
	,CASE 
		WHEN we.[Brand Type] IN ('Licensee', 'Distributer', 'Distributor')
			THEN 'Importer'
		ELSE we.[Brand Type]
		END AS [Brand Type]
	,we.[Sales Type]
	,we.[Rigid]
	,CASE 
		WHEN we.[Grading] IS NULL
			THEN 'Red'
		ELSE we.[Grading]
		END AS [Grading]
	,CASE 
		WHEN we.[Component Type] IS NULL
			THEN 'Not Assigned'
		ELSE we.[Component Type]
		END AS [Component Type]
	,CASE 
		WHEN we.[Material] IS NULL
			THEN 'Not Assigned'
		ELSE we.[Material]
		END AS [Material]
	,ISNULL(we.[Avg Carton Qty], 1) AS [Avg Carton Qty]
	,we.[Item No]
	,CASE 
		WHEN we.[Carton/Item] = 'Carton'
			THEN (CAST(sl.[Quantity] AS DECIMAL(38, 20)) / ISNULL(NULLIF(we.[Avg Carton Qty], 0), 1)) * we.[Weight KG]
		ELSE CAST(sl.[Quantity] AS DECIMAL(38, 20)) * we.[Weight KG]
		END AS [Weight KG]
		
FROM [weights] AS we

INNER JOIN [sales] AS sl
	ON we.[Item No] = sl.[Item No]
		AND we.[Sales Type] = sl.[Sales Type]

OPTION (RECOMPILE);

CREATE INDEX IX_weights_sales_report ON #weights_sales (
	[Category]
	,[Article Type]
	,[Brand Type]
	,[Sales Type]
	,[Rigid]
	,[Grading]
	,[Material]
	,[Component Type]
	) INCLUDE ([Weight KG]);

-- Insert primary packaging own brand paper/cardboard B2B.
SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'
	AND [Component Type] <> 'Manual'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'
	AND [Component Type] <> 'Manual'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'
	AND [Component Type] <> 'Manual'

-- Insert primary packaging own brand paper/cardboard D2C.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'
	AND [Component Type] <> 'Manual'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'
	AND [Component Type] <> 'Manual'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'
	AND [Component Type] <> 'Manual'

-- Insert primary packaging own brand steel B2B.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert primary packaging own brand steel D2C.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging own brand rigid plastic B2B.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'
	AND [Rigid] = 'Rigid'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'
	AND [Rigid] = 'Rigid'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'
	AND [Rigid] = 'Rigid'

-- Insert primary packaging own brand rigid plastic D2C.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'
	AND [Rigid] = 'Rigid'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'
	AND [Rigid] = 'Rigid'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'
	AND [Rigid] = 'Rigid'

-- Insert primary packaging own brand flexible plastic B2B.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Green'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Green'
			), 0) AS [Weight KG]


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Amber'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Amber'
			), 0) AS [Weight KG]


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Red'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Red'
			), 0) AS [Weight KG]

-- Insert primary packaging own brand flexible plastic D2C.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Green'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Green'
			), 0) AS [Weight KG]


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Amber'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Amber'
			), 0) AS [Weight KG]


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Red'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Own Brand'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Red'
			), 0) AS [Weight KG]

-- Insert primary packaging own brand cotton string B2B

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert primary packaging own brand cotton string D2C

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging own brand nylon string B2B

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert primary packaging own brand nylon string D2C

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging own brand polyester string B2B.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert primary packaging own brand polyester string D2C.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging own brand silica gel

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Silica Gel' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Silica Gel'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Silica Gel' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Silica Gel'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging own brand copper

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Copper' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Copper'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Copper' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Copper'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging own brand elastic band B2B

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert primary packaging own brand elastic band D2C

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert secondary packaging paper/card B2B.

UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert secondary packaging plastic own brand B2B

UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Own Brand' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Own Brand'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Below are the inserts for importer brands
-- Insert primary packaging importer brand paper/cardboard B2B.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'
	AND [Component Type] <> 'Manual'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'
	AND [Component Type] <> 'Manual'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'
	AND [Component Type] <> 'Manual'

-- Insert primary packaging importer brand paper/cardboard D2C.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'
	AND [Component Type] <> 'Manual'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'
	AND [Component Type] <> 'Manual'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'
	AND [Component Type] <> 'Manual'

-- Insert primary packaging importer steel B2B.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert primary packaging importer steel D2C.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Steel' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Steel'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging Importer rigid plastic B2B.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'
	AND [Rigid] = 'Rigid'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'
	AND [Rigid] = 'Rigid'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'
	AND [Rigid] = 'Rigid'

-- Insert primary packaging importer rigid plastic D2C.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'
	AND [Rigid] = 'Rigid'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'
	AND [Rigid] = 'Rigid'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Rigid' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'
	AND [Rigid] = 'Rigid'

-- Insert primary packaging importer flexible plastic B2B.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Green'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Green'
			), 0) AS [Weight KG]


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Amber'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Amber'
			), 0) AS [Weight KG]


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Red'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'B2B'
				AND [Grading] = 'Red'
			), 0) AS [Weight KG]

-- Insert primary packaging importer flexible plastic D2C.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Green'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Green'
			), 0) AS [Weight KG]


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Amber'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Amber'
			), 0) AS [Weight KG]


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Plastic'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Red'
				AND [Rigid] = 'Flexible'
			), 0) + ISNULL((
			SELECT SUM([Weight KG]) AS [Weight KG]
			
			FROM #weights_sales
			
			WHERE [Category] = 'Primary Packaging'
				AND [Article Type] = 'Fabric / Fibres'
				AND [Material] IN ('Nylon', 'Polyester')
				AND [Component Type] = 'String'
				AND [Brand Type] = 'Importer'
				AND [Sales Type] = 'D2C'
				AND [Grading] = 'Red'
			), 0) AS [Weight KG]

-- Insert primary packaging importer cotton string B2B

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert primary packaging importer cotton string D2C

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Cotton String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Cotton'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging importer nylon string B2B

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert primary packaging importer nylon string D2C

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Nylon String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Nylon'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging importer polyester string B2B.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert primary packaging importer polyester string D2C.

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Polyester String' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Polyester'
	AND [Component Type] = 'String'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging importer silica gel

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Silica Gel' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Silica Gel'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Silica Gel' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Silica Gel'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging importer copper

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Copper' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Copper'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Copper' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Material] = 'Copper'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert primary packaging importer elastic band B2B

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert primary packaging importer elastic band D2C

UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Primary Packaging' AS [Category]
	,'Rubber Elastic Band' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'D2C' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Primary Packaging'
	AND [Component Type] = 'Elastic Band'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'D2C'
	AND [Grading] = 'Red'

-- Insert secondary packaging importer paper/card B2B.

UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Paper/Cardboard' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'N/A' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Paper/Cardboard'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

-- Insert secondary packaging plastic importer B2B

UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Green' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Green'


UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Amber' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Amber'


UNION ALL

SELECT 'Secondary Packaging' AS [Category]
	,'Plastic' AS [Article Type]
	,'Importer' AS [Brand Type]
	,'B2B' AS [Sales Type]
	,'Flexible' AS [Rigid]
	,'Red' AS [Grading]
	,ISNULL(SUM([Weight KG]), 0) AS [Weight KG]

FROM #weights_sales

WHERE [Category] = 'Secondary Packaging'
	AND [Article Type] = 'Plastic'
	AND [Brand Type] = 'Importer'
	AND [Sales Type] = 'B2B'
	AND [Grading] = 'Red'

OPTION (RECOMPILE);

"])
in
    Source
