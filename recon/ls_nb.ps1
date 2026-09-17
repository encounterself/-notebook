param([string]$tok, [string]$host_ = 'https://dbc-deaed492-e72a.cloud.databricks.com')
$ErrorActionPreference = 'SilentlyContinue'
$hdr = @{ Authorization = "Bearer $tok" }
$found = New-Object System.Collections.Generic.List[string]

function Walk([string]$path, [int]$depth) {
  if ($depth -gt 5) { return }
  $r = Invoke-RestMethod -Uri "$host_/api/2.0/workspace/list" -Method Get -Headers $hdr -Body @{ path = $path }
  foreach ($o in $r.objects) {
    if ($o.object_type -eq 'NOTEBOOK') {
      $found.Add($o.path)
    } elseif ($o.object_type -eq 'DIRECTORY') {
      if ($o.path -notlike '*/.db_internal*' -and $o.path -notlike '*/.assistant*') {
        Walk $o.path ($depth + 1)
      }
    }
  }
}

foreach ($root in @('/Users', '/Shared', '/Repos')) { Walk $root 0 }
$found | Sort-Object -Unique | ForEach-Object { Write-Output $_ }
