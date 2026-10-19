USE [data_control];

GO

DROP TABLE IF EXISTS [dbo].[pst_reports]

BEGIN
	CREATE TABLE [dbo].[pst_reports](
         [pst_id] INTEGER NOT NULL
        ,[pst_description] NVARCHAR(100) NOT NULL
        ,[last_updated] DATETIME
        ,CONSTRAINT [PK_pst_reports] PRIMARY KEY CLUSTERED ([pst_id])
		);

END;

GO