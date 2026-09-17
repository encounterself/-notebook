param([string]$Html, [string]$Out)
$h = Get-Content -LiteralPath $Html -Raw -Encoding UTF8
$m = [regex]::Match($h, "var __DATABRICKS_NOTEBOOK_MODEL = '([^']+)'")
if (-not $m.Success) { Write-Host "NOT FOUND"; exit 1 }
$b64 = $m.Groups[1].Value
$json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
if ($json.StartsWith('%')) { $json = [System.Uri]::UnescapeDataString($json) }
$obj = $json | ConvertFrom-Json

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("NOTEBOOK: $($obj.name)   language=$($obj.language)   origId=$($obj.origId)")
[void]$sb.AppendLine("COMMANDS: $($obj.commands.Count)")
[void]$sb.AppendLine(("=" * 100))
$i = 0
foreach ($c in $obj.commands) {
  $i++
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("########## COMMAND $i ##########")
  if ($c.guid) { [void]$sb.AppendLine("guid: $($c.guid)") }
  [void]$sb.AppendLine($c.command)
}
[System.IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "WROTE $Out  ($((Get-Item $Out).Length) bytes, $($obj.commands.Count) commands)"
