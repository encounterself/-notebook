# Databricks SQL runner (ASCII-safe, no underscore params).
param(
  [Parameter(Mandatory=$true)][string]$SqlFile,
  [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'
$dbrHost = 'https://dbc-deaed492-e72a.cloud.databricks.com'
$wh = 'e9b22cc5b0d2d957'
$tok = (databricks auth token -p simo_cdc | ConvertFrom-Json).access_token
$hdr = @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json; charset=utf-8' }

function EscJson([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $s.ToCharArray()) {
    $c = [int]$ch
    if ($ch -eq '"') { [void]$sb.Append('\"') }
    elseif ($ch -eq '\') { [void]$sb.Append('\\') }
    elseif ($c -eq 10) { [void]$sb.Append('\n') }
    elseif ($c -eq 13) { [void]$sb.Append('\r') }
    elseif ($c -eq 9) { [void]$sb.Append('\t') }
    elseif ($c -lt 32) { [void]$sb.Append('\u' + ('{0:x4}' -f $c)) }
    else { [void]$sb.Append($ch) }
  }
  return $sb.ToString()
}

$sql = [System.IO.File]::ReadAllText($SqlFile, [System.Text.Encoding]::UTF8)
$json = '{"warehouse_id":"' + $wh + '","statement":"' + (EscJson $sql) + '","wait_timeout":"50s","disposition":"INLINE","format":"JSON_ARRAY"}'

$raw = (Invoke-WebRequest -Method Post -Uri "$dbrHost/api/2.0/sql/statements" -Headers $hdr -Body ([System.Text.Encoding]::UTF8.GetBytes($json))).Content
$resp = $raw | ConvertFrom-Json
$sid = [string]$resp.statement_id

$deadline = (Get-Date).AddMinutes(45)
while ($resp.status.state -in @('PENDING','RUNNING')) {
  if ((Get-Date) -gt $deadline) { throw "timeout on statement $sid" }
  Start-Sleep -Seconds 4
  $resp = (Invoke-WebRequest -Method Get -Uri "$dbrHost/api/2.0/sql/statements/$sid" -Headers $hdr).Content | ConvertFrom-Json
}

if ($resp.status.state -ne 'SUCCEEDED') {
  Write-Host "STATE: $($resp.status.state)"
  Write-Host "ERROR: $($resp.status.error.message)"
  exit 1
}

$rowsUri = "$dbrHost/api/2.0/sql/statements/$sid" + '?include_rows=true'
$resp = (Invoke-WebRequest -Method Get -Uri $rowsUri -Headers $hdr).Content | ConvertFrom-Json

$cols = @($resp.manifest.schema.columns | ForEach-Object { $_.name })
$rows = @($resp.result.data_array)
Write-Host "STATE: SUCCEEDED  ROWS: $($rows.Count)  COLS: $($cols.Count)  TOTAL: $($resp.manifest.total_row_count)"

$out = New-Object System.Collections.Generic.List[string]
$out.Add(($cols -join "`t"))
foreach ($r in $rows) {
  $cells = @($r | ForEach-Object { if ($null -eq $_) { '' } else { "$_" } })
  $out.Add(($cells -join "`t"))
}

if ($OutFile -ne '') {
  [System.IO.File]::WriteAllLines($OutFile, $out, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "WROTE: $OutFile"
} else {
  $out | ForEach-Object { Write-Host $_ }
}
if ($resp.manifest.truncated) { Write-Host "WARNING: truncated result" }
