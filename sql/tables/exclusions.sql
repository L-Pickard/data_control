USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

DROP TABLE IF EXISTS [dbo].[exclusions];

CREATE TABLE [dbo].[exclusions] (
		 [entity] NVARCHAR(20) NOT NULL
		,[type] NVARCHAR(20) NOT NULL
		,[table_name] NVARCHAR(20) NOT NULL
		,[id] NVARCHAR(20) NOT NULL
		,CONSTRAINT [PK_exclusions] PRIMARY KEY CLUSTERED (
			 [entity]
			,[type]
			,[table_name]
			,[id]
			)
		,CONSTRAINT [FK_exclusions_entities] FOREIGN KEY ([entity])
			REFERENCES [dbo].[entities] ([entity])
		);

GO

INSERT INTO [dbo].[exclusions](
     [entity]
    ,[type]
    ,[table_name]
    ,[id]
)

VALUES
     ('Shiner Ltd', 'exclusion', 'customers', 'CU110025') -- Shiner BV - NPD Samples EUR
    ,('Shiner Ltd', 'exclusion', 'customers', 'CU110036') -- Shiner LLC (Management Recharge)
    ,('Shiner Ltd', 'exclusion', 'customers', 'CU110040') -- Shiner BV (Management Recharge)
    ,('Shiner Ltd', 'exclusion', 'customers', 'CU110083') -- Shiner BV - NPD Samples USD
    ,('Shiner Ltd', 'exclusion', 'customers', 'CU109989') -- Sales Sets Distributed - EU BV
    ,('Shiner Ltd', 'exclusion', 'customers', 'CU109330') -- Seeding Marketing PR162

    ,('Shiner B.V', 'exclusion', 'customers', 'CU110025') -- Shiner BV - NPD Samples EUR
    ,('Shiner B.V', 'exclusion', 'customers', 'CU109506') -- NPD Samples EU
    ,('Shiner B.V', 'exclusion', 'customers', 'CU109989') -- Sales Sets Distributed - EU BV
    ,('Shiner B.V', 'exclusion', 'customers', 'CU109330') -- Seeding Marketing PR162

    ,('Shiner LLC', 'exclusion', 'customers', 'UC000650') -- Management Recharge Shiner Ltd
    ,('Shiner LLC', 'exclusion', 'customers', 'UC000653') -- Management recharge Shiner EU BV
    ,('Shiner LLC', 'exclusion', 'customers', 'UC000340') -- Shiner Marketing
    ,('Shiner LLC', 'exclusion', 'customers', 'CU109989') -- Sales Sets Distributed - EU BV
    ,('Shiner LLC', 'exclusion', 'customers', 'CU109330') -- Seeding Marketing PR162
   
   -- Intercompany

   ,('Shiner Ltd', 'intercompany', 'customers', 'CU103500') -- Shiner Limited
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU109221') -- Shiner EU B.V.Replen
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU109441') -- Shiner EU BV BTB
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU109444') -- Shiner EU BV Replen DONT USE
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU109525') -- Shiner EU Riga B2B
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU110077') -- Shiner LLC
   ,('Shiner Ltd', 'intercompany', 'customers', 'CU110744') -- Shiner EU B.V. Redwood Replen

   ,('Shiner B.V', 'intercompany', 'customers', 'CU103500') -- Shiner Limited
   ,('Shiner B.V', 'intercompany', 'customers', 'CU109221') -- Shiner EU B.V.Replen
   ,('Shiner B.V', 'intercompany', 'customers', 'CU109441') -- Shiner EU BV BTB
   ,('Shiner B.V', 'intercompany', 'customers', 'CU109444') -- Shiner EU BV Replen DONT USE
   ,('Shiner B.V', 'intercompany', 'customers', 'CU109525') -- Shiner EU Riga B2B
   ,('Shiner B.V', 'intercompany', 'customers', 'CU110077') -- Shiner LLC

   ,('Shiner LLC', 'intercompany', 'customers', 'UC000458'); -- Shiner Ltd

-- The legacy purchase rules apply to every entity. Materialise one row for
-- each entity instead of storing '*' so the foreign key remains enforceable.

INSERT INTO [dbo].[exclusions] (
     [entity]
    ,[type]
    ,[table_name]
    ,[id]
)
SELECT
     en.[entity]
    ,rules.[type]
    ,N'vendors'
    ,rules.[id]
FROM [dbo].[entities] AS en
CROSS JOIN (
    VALUES
         (N'exclusion', N'UV000199') -- Management Recharge Shiner Ltd
        ,(N'exclusion', N'UV000200') -- Management Recharge Shiner EU BV
        ,(N'exclusion', N'VE100194') -- Shiner Properties Limited
        ,(N'exclusion', N'VE100890') -- Shiner LLC (Management Recharge)
        ,(N'intercompany', N'UV000081') -- Shiner Ltd
        ,(N'intercompany', N'UV000195') -- Shiner EU BV
        ,(N'intercompany', N'VE100520') -- Shiner Ltd - Replen
        ,(N'intercompany', N'VE100927') -- Shiner Ltd
        ,(N'intercompany', N'VE100934') -- Shiner LLC
        ,(N'intercompany', N'VE100952') -- Shiner EU B.V.
) AS rules ([type], [id]);

GO
