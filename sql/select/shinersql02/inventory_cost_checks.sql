-- Read-only inventory source query, scoped to selected entities and locations.
-- Parameters: as-of date, then XML scope (SQL02 supports XML, not OPENJSON).
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @scope XML = CAST(? AS XML);
DECLARE @ltd_enabled BIT = @scope.exist('/scope/entity[@name="Shiner Ltd"]');
DECLARE @ltd_all BIT = @scope.exist('/scope/entity[@name="Shiner Ltd" and @all="1"]');
DECLARE @bv_enabled BIT = @scope.exist('/scope/entity[@name="Shiner B.V"]');
DECLARE @bv_all BIT = @scope.exist('/scope/entity[@name="Shiner B.V" and @all="1"]');
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);

SELECT N'Shiner Ltd' AS [entity]
	,(
		SELECT COUNT(*)

		FROM [Shiner$Value Entry] AS ve

		WHERE ve.[Cost Amount (Actual)] <> ve.[Cost Posted to G_L]
			AND ve.[Posting Date] < @day_after
            AND (@ltd_enabled=1 AND (@ltd_all=1 OR ve.[Location Code] IN (SELECT lc.n.value('@code','nvarchar(10)') FROM @scope.nodes('/scope/entity[@name="Shiner Ltd"]/location') AS lc(n))))
		) AS [unposted_entries]
WHERE @scope.exist('/scope/entity[@name="Shiner Ltd"]') = 1
UNION ALL


SELECT N'Shiner B.V' AS [entity]
	,(
		SELECT COUNT(*)

		FROM [Shiner BV$Value Entry] AS ve

		WHERE ve.[Cost Amount (Actual)] <> ve.[Cost Posted to G_L]
			AND ve.[Posting Date] < @day_after
            AND (@bv_enabled=1 AND (@bv_all=1 OR ve.[Location Code] IN (SELECT lc.n.value('@code','nvarchar(10)') FROM @scope.nodes('/scope/entity[@name="Shiner B.V"]/location') AS lc(n))))
		) AS [unposted_entries]
WHERE @scope.exist('/scope/entity[@name="Shiner B.V"]') = 1
OPTION (RECOMPILE, MAXDOP 1);
