USE [data_control]

GO

DROP TABLE

IF EXISTS [dbo].[increment_dates]
	CREATE TABLE [dbo].[increment_dates] (
		 [entity] NVARCHAR(10)
		,[sales] DATE NOT NULL
		,[gl_entry] DATE NOT NULL CONSTRAINT pk_increment_dates PRIMARY KEY CLUSTERED ([entity])
		);

INSERT INTO [dbo].[increment_dates] (
	 [entity]
	,[sales]
	,[gl_entry]
	)

VALUES
     ('Example Ltd', '2025-04-30', '2025-04-30')
    ,('Example BV', '2025-04-30', '2025-04-30')
    ,('Example LLC', '2025-04-30', '2025-04-30')