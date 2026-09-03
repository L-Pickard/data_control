USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE IF EXISTS [dbo].[record_link]

CREATE TABLE [dbo].[record_link] (
     [entity] NVARCHAR(20) NOT NULL
    ,[system] NVARCHAR(10) NOT NULL
    ,[link_id] INTEGER NOT NULL
    ,[record_id] VARBINARY(448) NOT NULL
    ,[url] NVARCHAR(2048) NULL
    ,[description] NVARCHAR(250) NULL
    ,[type] INTEGER NOT NULL
	,[created] DATETIME2(0) NOT NULL
	,[modified] DATETIME2(0) NOT NULL
	,CONSTRAINT [PK_record_link] PRIMARY KEY CLUSTERED (
		 [entity]
		,[system]
		,[link_id]
	)
	,CONSTRAINT [FK_record_link_entities] FOREIGN KEY ([entity])
		REFERENCES [dbo].[entities] ([entity])
	,CONSTRAINT [CK_record_link_system] CHECK (LEN([system]) > 0)
	,CONSTRAINT [CK_record_link_link_id] CHECK ([link_id] > 0)
	,CONSTRAINT [CK_record_link_modified]
		CHECK ([modified] >= [created])
	);

GO

-- Supports resolving all links attached to a source record.
CREATE NONCLUSTERED INDEX [IX_record_link_record_id]
	ON [dbo].[record_link] (
		 [entity]
		,[system]
		,[record_id]
	)
	INCLUDE (
		 [link_id]
		,[url]
		,[description]
		,[type]
		,[created]
		,[modified]
	);

GO

-- Supports incremental extracts and recently changed-link reporting.
CREATE NONCLUSTERED INDEX [IX_record_link_modified]
	ON [dbo].[record_link] (
		 [system]
		,[modified]
	)
	INCLUDE (
		 [entity]
		,[link_id]
		,[record_id]
		,[type]
	);

GO
