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

INSERT INTO [dbo].[exclusions] ([entity], [type], [table_name], [id])
VALUES
     ('Example Ltd', 'exclusion', 'customers', 'CUSTOMER_001');

-- Apply a neutral vendor rule to each entity.
INSERT INTO [dbo].[exclusions] ([entity], [type], [table_name], [id])
SELECT en.[entity], N'exclusion', N'vendors', N'VENDOR_001'
FROM [dbo].[entities] AS en;