param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$pluginRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$targets = @(
  (Join-Path $CodexHome "plugins\cache\computer-use-for-windows-local\computer-use-for-windows\local"),
  (Join-Path $CodexHome "plugins\cache\openai-curated\computer-use-for-windows\local")
)

function Copy-PluginTree {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  $excludedDirs = @(".screenshots", ".scratch", "node_modules")
  $sourceRoot = [System.IO.Path]::GetFullPath($Source)
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null

  Get-ChildItem -LiteralPath $Source -Recurse -Force | ForEach-Object {
    $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart("\", "/")
    if ([string]::IsNullOrWhiteSpace($relative)) {
      return
    }
    $parts = $relative -split "[\\/]+"
    if ($parts | Where-Object { $_ -in $excludedDirs }) {
      return
    }

    $target = Join-Path $Destination $relative
    if ($_.PSIsContainer) {
      New-Item -ItemType Directory -Force -Path $target | Out-Null
    } else {
      New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($target)) | Out-Null
      Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
  }
}

foreach ($target in $targets) {
  Copy-PluginTree -Source $pluginRoot -Destination $target
}

[pscustomobject]@{
  ok = $true
  cacheTargets = $targets
} | ConvertTo-Json -Depth 4
