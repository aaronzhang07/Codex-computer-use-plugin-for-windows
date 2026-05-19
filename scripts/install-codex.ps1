param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$pluginRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$marketplaceName = "computer-use-for-windows-local"
$marketplaceRoot = Join-Path $CodexHome "local-marketplaces\computer-use-for-windows"
$targetPluginRoot = Join-Path $marketplaceRoot "plugins\computer-use-for-windows"
$marketplaceFile = Join-Path $marketplaceRoot ".agents\plugins\marketplace.json"
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

New-Item -ItemType Directory -Force -Path $targetPluginRoot | Out-Null
New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($marketplaceFile)) | Out-Null

Copy-PluginTree -Source $pluginRoot -Destination $targetPluginRoot

$marketplace = [ordered]@{
  name = $marketplaceName
  interface = [ordered]@{
    displayName = "computer_use_for_windows Local"
  }
  plugins = @(
    [ordered]@{
      name = "computer-use-for-windows"
      source = [ordered]@{
        source = "local"
        path = "./plugins/computer-use-for-windows"
      }
      policy = [ordered]@{
        installation = "AVAILABLE"
        authentication = "ON_INSTALL"
      }
      category = "Productivity"
    }
  )
}
Write-Utf8NoBom -Path $marketplaceFile -Value ($marketplace | ConvertTo-Json -Depth 8)

if (-not (Test-Path -LiteralPath $configFile)) {
  New-Item -ItemType File -Force -Path $configFile | Out-Null
}

$config = Get-Content -LiteralPath $configFile -Raw
$sourceForToml = "\\?\$marketplaceRoot"

if ($config -notmatch "\[marketplaces\.computer-use-for-windows-local\]") {
  $utcNow = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  Add-Content -LiteralPath $configFile -Encoding UTF8 -Value @"

[marketplaces.computer-use-for-windows-local]
last_updated = "$utcNow"
source_type = "local"
source = '$sourceForToml'
"@
} else {
  $config = Get-Content -LiteralPath $configFile -Raw
}

if ($config -notmatch '\[plugins\."computer-use-for-windows@computer-use-for-windows-local"\]') {
  Add-Content -LiteralPath $configFile -Encoding UTF8 -Value @"

[plugins."computer-use-for-windows@computer-use-for-windows-local"]
enabled = true
"@
}

[pscustomobject]@{
  ok = $true
  pluginRoot = $targetPluginRoot
  marketplaceRoot = $marketplaceRoot
  marketplaceFile = $marketplaceFile
  configFile = $configFile
  pluginMention = "@computer_use_for_windows"
  pluginId = "computer-use-for-windows@computer-use-for-windows-local"
} | ConvertTo-Json -Depth 4
