-- Read-only inventory source query, scoped to selected entities and locations.
-- Parameters: as-of date, then XML scope (SQL02 supports XML, not OPENJSON).
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @scope XML = CAST(? AS XML);
DECLARE @llc_enabled BIT = @scope.exist('/scope/entity[@name="Shiner LLC"]');
DECLARE @llc_all BIT = @scope.exist('/scope/entity[@name="Shiner LLC" and @all="1"]');
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);

SELECT N'Shiner LLC' AS [entity]
	,(
		SELECT COUNT(*)

		FROM [Shiner USA Master Setup$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] AS ve

		WHERE ve.[Cost Amount (Actual)] <> ve.[Cost Posted to G_L]
			AND ve.[Posting Date] < @day_after
            AND (@llc_enabled=1 AND (@llc_all=1 OR ve.[Location Code] IN (SELECT lc.n.value('@code','nvarchar(10)') FROM @scope.nodes('/scope/entity[@name="Shiner LLC"]/location') AS lc(n))))
		) AS [unposted_entries]
WHERE @scope.exist('/scope/entity[@name="Shiner LLC"]') = 1
OPTION (RECOMPILE, MAXDOP 1);
