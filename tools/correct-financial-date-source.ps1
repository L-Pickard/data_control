param([string]$Path = (Join-Path $PSScriptRoot '../documents/dates_import.csv'))
$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
$rows = Import-Csv -LiteralPath $Path
foreach ($row in $rows) {
    $date = [datetime]::ParseExact($row.date, 'yyyy-MM-dd', $culture)
    $labelDate = if ($date.Year -ge 2026 -and $date.Month -eq 4 -and $date.Day -eq 30) { $date.AddDays(1) } else { $date }
    $startYear = $labelDate.Year - [int]($labelDate.Month -lt 5)
    $yearStart = if ($startYear -ge 2026) { [datetime]::new($startYear, 4, 30) } else { [datetime]::new($startYear, 5, 1) }
    $yearEnd = if ($startYear -ge 2025) { [datetime]::new($startYear + 1, 4, 29) } else { [datetime]::new($startYear + 1, 4, 30) }
    $monthNo = ($labelDate.Month + 7) % 12 + 1
    $quarterNo = [int][math]::Floor(($monthNo - 1) / 3) + 1
    $monthStart = [datetime]::new($labelDate.Year, $labelDate.Month, 1)
    $monthEnd = $monthStart.AddMonths(1).AddDays(-1)
    if ($labelDate.Month -eq 5 -and $startYear -ge 2026) { $monthStart = $monthStart.AddDays(-1) }
    if ($labelDate.Month -eq 4 -and $labelDate.Year -ge 2026) { $monthEnd = $monthEnd.AddDays(-1) }
    $quarterStart = [datetime]::new($startYear, 5, 1).AddMonths(($quarterNo - 1) * 3)
    $quarterEnd = $quarterStart.AddMonths(3).AddDays(-1)
    if ($quarterNo -eq 1) { $quarterStart = $yearStart }
    if ($quarterNo -eq 4) { $quarterEnd = $yearEnd }
    $yearLabel = $yearStart.ToString('yy', $culture) + '-' + $yearEnd.ToString('yy', $culture)
    $row.financial_year_short = $startYear + 1
    $row.financial_year_long = $yearLabel
    $row.financial_year_full = 'FY ' + $yearLabel
    $row.financial_year_start = $yearStart.ToString('yyyy-MM-dd')
    $row.financial_year_end = $yearEnd.ToString('yyyy-MM-dd')
    $row.financial_year_day_count = ($yearEnd - $yearStart).Days + 1
    $row.'day_of_financial Year' = ($date - $yearStart).Days + 1
    $row.days_remaining_in_financial_Year = ($yearEnd - $date).Days
    $row.financial_week_no = [int][math]::Floor(($date - $yearStart).Days / 7) + 1
    $row.financial_quarter = $quarterNo
    $row.financial_quarter_full = "Q$quarterNo"
    $row.financial_quarter_start = $quarterStart.ToString('yyyy-MM-dd')
    $row.financial_quarter_end = $quarterEnd.ToString('yyyy-MM-dd')
    $row.day_of_financial_quarter = ($date - $quarterStart).Days + 1
    $row.'financial_quarter_&_year' = "Q$quarterNo $yearLabel"
    $row.financial_month_no = $monthNo
    $row.financial_month_start = $monthStart.ToString('yyyy-MM-dd')
    $row.financial_month_end = $monthEnd.ToString('yyyy-MM-dd')
    $row.day_of_financial_month = ($date - $monthStart).Days + 1
    $row.month_name = $labelDate.ToString('MMMM', $culture)
    $row.month_name_abbreviation = $labelDate.ToString('MMM', $culture)
    $row.'month_abbreviation_&_year' = $labelDate.ToString('MMM-yy', $culture)
    $row.'month_name_&_financial_year' = $labelDate.ToString('MMM', $culture) + ' ' + $yearLabel
    $row.'financial_month_&_year' = (($startYear + 1) % 100) * 100 + $monthNo
}
$rows | Export-Csv -LiteralPath $Path -NoTypeInformation -UseQuotes AsNeeded -Encoding utf8
Write-Output "Corrected $($rows.Count) source dates."
