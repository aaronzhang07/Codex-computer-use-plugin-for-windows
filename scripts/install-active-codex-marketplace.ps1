param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$pluginRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$activeMarketplaceRoot = Join-Path $CodexHome ".tmp\plugins"
$targetPluginRoot = Join-Path $activeMarketplaceRoot "plugins\computer-use-for-windows"
$marketplaceFile = Join-Path $activeMarketplaceRoot ".agents\plugins\marketplace.json"
$configFile = Join-Path $CodexHome "config.toml"

function Write-Utf8NoBom {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Value
  )
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Copy-PluginTree {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  $excludedDirs = @(".screenshots", ".scratch", "node_modules")
  $sourceRoot = [System.IO.Path]::GetFullPath($Source)

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

if (-not (Test-Path -LiteralPath $marketplaceFile)) {
  throw "Active marketplace file not found: $marketplaceFile"
}

New-Item -ItemType Directory -Force -Path $targetPluginRoot | Out-Null
Copy-PluginTree -Source $pluginRoot -Destination $targetPluginRoot

$marketplace = Get-Content -LiteralPath $marketplaceFile -Raw | ConvertFrom-Json
$existing = @($marketplace.plugins | Where-Object { $_.name -eq "computer-use-for-windows" })
if ($existing.Count -eq 0) {
  $entry = [pscustomobject]@{
    name = "computer-use-for-windows"
    source = [pscustomobject]@{
      source = "local"
      path = "./plugins/computer-use-for-windows"
    }
    policy = [pscustomobject]@{
      installation = "AVAILABLE"
      authentication = "ON_INSTALL"
    }
    category = "Productivity"
  }
  $marketplace.plugins += $entry
  Write-Utf8NoBom -Path $marketplaceFile -Value ($marketplace | ConvertTo-Json -Depth 10)
} else {
  Write-Utf8NoBom -Path $marketplaceFile -Value ($marketplace | ConvertTo-Json -Depth 10)
}

if (-not (Test-Path -LiteralPath $configFile)) {
  New-Item -ItemType File -Force -Path $configFile | Out-Null
}
$config = Get-Content -LiteralPath $configFile -Raw
if ($config -notmatch '\[plugins\."computer-use-for-windows@openai-curated"\]') {
  Add-Content -LiteralPath $configFile -Encoding UTF8 -Value @"

[plugins."computer-use-for-windows@openai-curated"]
enabled = true
"@
}

$config = Get-Content -LiteralPath $configFile -Raw
if ($config -match '\[plugins\."computer-use-for-windows@computer-use-for-windows-local"\]') {
  $config = [regex]::Replace(
    $config,
    '(\[plugins\."computer-use-for-windows@computer-use-for-windows-local"\]\s*)enabled\s*=\s*true',
    '${1}enabled = false'
  )
  [System.IO.File]::WriteAllText($configFile, $config, (New-Object System.Text.UTF8Encoding($false)))
}

[pscustomobject]@{
  ok = $true
  activeMarketplaceRoot = $activeMarketplaceRoot
  pluginRoot = $targetPluginRoot
  marketplaceFile = $marketplaceFile
  configFile = $configFile
  pluginId = "computer-use-for-windows@openai-curated"
  fallbackPluginId = "computer-use-for-windows@computer-use-for-windows-local"
  fallbackEnabled = $false
} | ConvertTo-Json -Depth 4
