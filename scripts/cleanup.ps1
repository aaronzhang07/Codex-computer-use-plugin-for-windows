param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [int]$ScreenshotMaxAgeHours = 24,
  [int]$ScreenshotKeepLatest = 50,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Remove-IfAllowed {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$AllowedRoot
  )

  $resolvedPath = [System.IO.Path]::GetFullPath($Path)
  $resolvedRoot = [System.IO.Path]::GetFullPath($AllowedRoot)
  if (-not $resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove path outside allowed root: $resolvedPath"
  }

  if ($DryRun) {
    [pscustomobject]@{ action = "would_remove"; path = $resolvedPath }
  } else {
    Remove-Item -LiteralPath $resolvedPath -Force
    [pscustomobject]@{ action = "removed"; path = $resolvedPath }
  }
}

function Get-TotalLength {
  param(
    [object[]]$Files
  )

  if ($Files.Count -eq 0) {
    return [int64]0
  }

  return [int64](($Files | Measure-Object -Property Length -Sum).Sum)
}

$pluginRoot = [System.IO.Path]::GetFullPath($Root)
$screenshotDir = Join-Path $pluginRoot ".screenshots"
$scratchDir = Join-Path $pluginRoot ".scratch"
$removed = New-Object System.Collections.Generic.List[object]
$removedBytes = [int64]0
$screenshotStats = [ordered]@{
  directory = $screenshotDir
  scannedCount = 0
  keptCount = 0
  removedCount = 0
  scannedBytes = [int64]0
  keptBytes = [int64]0
  removedBytes = [int64]0
}
$scratchStats = [ordered]@{
  directory = $scratchDir
  scannedCount = 0
  removedCount = 0
  scannedBytes = [int64]0
  removedBytes = [int64]0
}

if (Test-Path -LiteralPath $screenshotDir) {
  $cutoff = (Get-Date).AddHours(-1 * $ScreenshotMaxAgeHours)
  $screenshots = @(Get-ChildItem -LiteralPath $screenshotDir -File -Filter "*.png" |
    Sort-Object LastWriteTime -Descending)
  $screenshotStats.scannedCount = $screenshots.Count
  $screenshotStats.scannedBytes = Get-TotalLength $screenshots

  $screenshotsToRemove = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $screenshots.Count; $i++) {
    if ($i -ge $ScreenshotKeepLatest -or $screenshots[$i].LastWriteTime -lt $cutoff) {
      $screenshotsToRemove.Add($screenshots[$i]) | Out-Null
    }
  }

  foreach ($file in $screenshotsToRemove) {
    $removedBytes += [int64]$file.Length
    $screenshotStats.removedBytes += [int64]$file.Length
    $removed.Add((Remove-IfAllowed -Path $file.FullName -AllowedRoot $screenshotDir)) | Out-Null
  }
  $screenshotStats.removedCount = $screenshotsToRemove.Count
  $screenshotStats.keptCount = $screenshots.Count - $screenshotsToRemove.Count
  $screenshotStats.keptBytes = $screenshotStats.scannedBytes - $screenshotStats.removedBytes
}

if (Test-Path -LiteralPath $scratchDir) {
  $scratchFiles = @(Get-ChildItem -LiteralPath $scratchDir -File |
    Where-Object { $_.Name -notin @(".gitkeep") })
  $scratchStats.scannedCount = $scratchFiles.Count
  $scratchStats.scannedBytes = Get-TotalLength $scratchFiles
  foreach ($file in $scratchFiles) {
    $removedBytes += [int64]$file.Length
    $scratchStats.removedBytes += [int64]$file.Length
    $removed.Add((Remove-IfAllowed -Path $file.FullName -AllowedRoot $scratchDir)) | Out-Null
  }
  $scratchStats.removedCount = $scratchFiles.Count
}

[pscustomobject]@{
  ok = $true
  dryRun = [bool]$DryRun
  root = $pluginRoot
  removedCount = $removed.Count
  removedBytes = $removedBytes
  screenshots = [pscustomobject]$screenshotStats
  scratch = [pscustomobject]$scratchStats
  removed = $removed
} | ConvertTo-Json -Depth 5
