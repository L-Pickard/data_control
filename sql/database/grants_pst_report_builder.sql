USE data_control;
GO
GRANT SELECT ON portal.pst_reports TO shiner_reports;
GRANT SELECT ON dbo.exclusions TO shiner_reports;
GRANT EXECUTE ON portal.save_pst_report TO shiner_reports;
GO
