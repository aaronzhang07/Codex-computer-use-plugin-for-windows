param(
  [Parameter(Mandatory = $true)]
  [string]$Action,

  [string]$ArgsBase64 = "",

  [string]$DefaultScreenshotDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$PluginRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($DefaultScreenshotDir)) {
  $DefaultScreenshotDir = Join-Path $PluginRoot ".screenshots"
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.ComponentModel;

public static class NativeInput {
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT {
    public int X;
    public int Y;
  }

  [DllImport("user32.dll")]
  public static extern bool GetCursorPos(out POINT lpPoint);

  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool SetCursorPos(int X, int Y);

  [DllImport("user32.dll")]
  public static extern void mouse_event(uint dwFlags, uint dx, uint dy, int dwData, UIntPtr dwExtraInfo);

  [DllImport("user32.dll")]
  public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.ComponentModel;

public static class NativeKeyboard {
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT {
    public uint type;
    public InputUnion U;
  }

  [StructLayout(LayoutKind.Explicit)]
  public struct InputUnion {
    [FieldOffset(0)]
    public KEYBDINPUT ki;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public ushort wVk;
    public ushort wScan;
    public uint dwFlags;
    public uint time;
    public UIntPtr dwExtraInfo;
  }

  [DllImport("user32.dll", SetLastError = true)]
  public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

  public static void SendKey(ushort virtualKey, bool keyUp) {
    INPUT[] inputs = new INPUT[1];
    inputs[0].type = 1;
    inputs[0].U.ki.wVk = virtualKey;
    inputs[0].U.ki.wScan = 0;
    inputs[0].U.ki.dwFlags = keyUp ? 0x0002u : 0u;
    inputs[0].U.ki.time = 0;
    inputs[0].U.ki.dwExtraInfo = UIntPtr.Zero;
    uint sent = SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
    if (sent != 1) {
      throw new Win32Exception(Marshal.GetLastWin32Error());
    }
  }
}
"@

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class NativeWindow {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowTextLength(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class NativeTextWindow {
  public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc lpEnumFunc, IntPtr lParam);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam);
}
"@

$MouseFlags = @{
  leftDown = 0x0002
  leftUp = 0x0004
  rightDown = 0x0008
  rightUp = 0x0010
  middleDown = 0x0020
  middleUp = 0x0040
  wheel = 0x0800
}

$KeyFlags = @{
  keyUp = 0x0002
}

$VirtualKeys = @{
  ctrl = 0x11
  control = 0x11
  alt = 0x12
  shift = 0x10
  enter = 0x0D
  return = 0x0D
  escape = 0x1B
  esc = 0x1B
  tab = 0x09
  backspace = 0x08
  delete = 0x2E
  up = 0x26
  down = 0x28
  left = 0x25
  right = 0x27
  home = 0x24
  end = 0x23
  pageup = 0x21
  pagedown = 0x22
  space = 0x20
}

function Get-InputArgs {
  if ([string]::IsNullOrWhiteSpace($ArgsBase64)) {
    return [pscustomobject]@{}
  }
  $json = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgsBase64))
  if ([string]::IsNullOrWhiteSpace($json)) {
    return [pscustomobject]@{}
  }
  return $json | ConvertFrom-Json
}

function Write-Json($Value) {
  $Value | ConvertTo-Json -Depth 8 -Compress
}

function Get-ArgValue($InputObject, $Name, $Default = $null) {
  if ($null -eq $InputObject) {
    return $Default
  }
  $property = $InputObject.PSObject.Properties.Match($Name) | Select-Object -First 1
  if ($null -eq $property) {
    return $Default
  }
  if ($null -eq $property.Value) {
    return $Default
  }
  return $property.Value
}

function Get-CursorInfo {
  $point = New-Object NativeInput+POINT
  [void][NativeInput]::GetCursorPos([ref]$point)
  return [pscustomobject]@{
    x = $point.X
    y = $point.Y
  }
}

function Set-CursorPosition {
  param(
    [Parameter(Mandatory = $true)]
    [int]$X,
    [Parameter(Mandatory = $true)]
    [int]$Y
  )

  if (-not [NativeInput]::SetCursorPos($X, $Y)) {
    $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "SetCursorPos failed for ($X, $Y). Win32 error: $lastError"
  }
}

function Convert-KeyNameToVirtualKey {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Key
  )

  $normalized = $Key.Trim().ToLowerInvariant()
  if ($VirtualKeys.ContainsKey($normalized)) {
    return [byte]$VirtualKeys[$normalized]
  }
  if ($normalized.Length -eq 1) {
    $char = [char]$normalized.ToUpperInvariant()[0]
    if (($char -ge [char]"A" -and $char -le [char]"Z") -or ($char -ge [char]"0" -and $char -le [char]"9")) {
      return [byte][int][char]$char
    }
  }
  if ($normalized -match "^f([1-9]|1[0-2])$") {
    return [byte](0x6F + [int]$Matches[1])
  }
  throw "Unsupported key: $Key"
}

function Send-VirtualKey {
  param(
    [Parameter(Mandatory = $true)]
    [byte]$VirtualKey,
    [bool]$KeyUp = $false
  )

  try {
    [NativeKeyboard]::SendKey([uint16]$VirtualKey, $KeyUp)
  } catch {
    $flags = if ($KeyUp) { [uint32]$KeyFlags.keyUp } else { [uint32]0 }
    [NativeInput]::keybd_event($VirtualKey, 0, $flags, [UIntPtr]::Zero)
  }
}

function Send-KeyChordNative {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Keys
  )

  $parts = ([string]$Keys).Split("+") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  if ($parts.Count -eq 0) {
    throw "keys cannot be empty"
  }

  $modifiers = @()
  if ($parts.Count -gt 1) {
    foreach ($part in $parts[0..($parts.Count - 2)]) {
      $lower = $part.ToLowerInvariant()
      if ($lower -notin @("ctrl", "control", "alt", "shift")) {
        throw "Unsupported modifier: $part"
      }
      $modifiers += [pscustomobject]@{
        name = $lower
        vk = Convert-KeyNameToVirtualKey $lower
      }
    }
  }

  $main = Convert-KeyNameToVirtualKey $parts[-1]
  foreach ($modifier in $modifiers) {
    Send-VirtualKey -VirtualKey $modifier.vk
    Start-Sleep -Milliseconds 15
  }
  Send-VirtualKey -VirtualKey $main
  Start-Sleep -Milliseconds 35
  Send-VirtualKey -VirtualKey $main -KeyUp $true
  for ($i = $modifiers.Count - 1; $i -ge 0; $i--) {
    Start-Sleep -Milliseconds 15
    Send-VirtualKey -VirtualKey $modifiers[$i].vk -KeyUp $true
  }
  Start-Sleep -Milliseconds 80
}

function Set-WindowAutomationText {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Handle,
    [Parameter(Mandatory = $true)]
    [string]$Text
  )

  $windowHandle = New-Object System.IntPtr -ArgumentList ([int64]$Handle)
  if ($windowHandle -eq [IntPtr]::Zero) {
    return $false
  }
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($windowHandle)
  if ($null -eq $root) {
    return $false
  }

  $targets = $root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition
  )
  if ($null -eq $targets -or $targets.Count -eq 0) {
    return $false
  }

  $orderedTargets = @($targets | Sort-Object {
    $className = $_.Current.ClassName
    $controlType = $_.Current.ControlType.ProgrammaticName
    if ($className -match "RichEdit|Edit|Text" -or $controlType -match "Document|Edit|Text") { 0 } else { 1 }
  })

  foreach ($target in $orderedTargets) {
    try {
      $valuePattern = $null
      if ($target.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valuePattern)) {
        $valuePattern.SetValue($Text)
        return $true
      }
    } catch {
      continue
    }
  }
  return $false
}

function Set-FocusedAutomationText {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Text
  )

  $focusedElement = [System.Windows.Automation.AutomationElement]::FocusedElement
  if ($null -eq $focusedElement) {
    return $false
  }
  $valuePattern = $null
  if (-not $focusedElement.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valuePattern)) {
    return $false
  }
  $valuePattern.SetValue($Text)
  return $true
}

function Set-WindowTextNative {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Handle,
    [Parameter(Mandatory = $true)]
    [string]$Text
  )

  $windowHandle = New-Object System.IntPtr -ArgumentList ([int64]$Handle)
  if ($windowHandle -eq [IntPtr]::Zero) {
    return $false
  }

  $target = [IntPtr]::Zero
  $callback = [NativeTextWindow+EnumChildProc]{
    param([IntPtr]$child, [IntPtr]$lParam)
    $builder = New-Object System.Text.StringBuilder 256
    [void][NativeTextWindow]::GetClassName($child, $builder, $builder.Capacity)
    $className = $builder.ToString()
    if ($className -match "RichEdit|Edit") {
      $script:NativeTextTarget = $child
      $script:NativeTextTargetClass = $className
      return $false
    }
    return $true
  }
  $script:NativeTextTarget = [IntPtr]::Zero
  $script:NativeTextTargetClass = ""
  [void][NativeTextWindow]::EnumChildWindows($windowHandle, $callback, [IntPtr]::Zero)
  $target = $script:NativeTextTarget
  $targetClass = $script:NativeTextTargetClass
  Remove-Variable -Name NativeTextTarget -Scope Script -ErrorAction SilentlyContinue
  Remove-Variable -Name NativeTextTargetClass -Scope Script -ErrorAction SilentlyContinue

  if ($target -eq [IntPtr]::Zero) {
    return [pscustomobject]@{ ok = $false; className = "" }
  }
  [void][NativeTextWindow]::SendMessage($target, 0x000C, [IntPtr]::Zero, $Text)
  return [pscustomobject]@{ ok = $true; className = $targetClass }
}

function Get-WindowValuePatternCandidates {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Handle
  )

  $windowHandle = New-Object System.IntPtr -ArgumentList ([int64]$Handle)
  if ($windowHandle -eq [IntPtr]::Zero) {
    return @()
  }
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($windowHandle)
  if ($null -eq $root) {
    return @()
  }
  $targets = $root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition
  )
  $items = New-Object System.Collections.Generic.List[object]
  foreach ($target in $targets) {
    $valuePattern = $null
    if ($target.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valuePattern)) {
      $items.Add([pscustomobject]@{
        name = $target.Current.Name
        className = $target.Current.ClassName
        controlType = $target.Current.ControlType.ProgrammaticName
      }) | Out-Null
    }
  }
  return @($items)
}

function Set-ForegroundAutomationText {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Text
  )

  return Set-WindowAutomationText -Handle ([NativeWindow]::GetForegroundWindow().ToInt64()) -Text $Text
}

function Get-ScreenInfo {
  param([bool]$AllScreens = $false)
  $bounds = if ($AllScreens) {
    [System.Windows.Forms.SystemInformation]::VirtualScreen
  } else {
    [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  }
  return [pscustomobject]@{
    x = $bounds.X
    y = $bounds.Y
    width = $bounds.Width
    height = $bounds.Height
  }
}

function Invoke-ListScreens {
  $screens = [System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
    [pscustomobject]@{
      deviceName = $_.DeviceName
      primary = $_.Primary
      bounds = [pscustomobject]@{
        x = $_.Bounds.X
        y = $_.Bounds.Y
        width = $_.Bounds.Width
        height = $_.Bounds.Height
      }
      workingArea = [pscustomobject]@{
        x = $_.WorkingArea.X
        y = $_.WorkingArea.Y
        width = $_.WorkingArea.Width
        height = $_.WorkingArea.Height
      }
    }
  }
  return [pscustomobject]@{
    ok = $true
    virtualScreen = Get-ScreenInfo $true
    screens = @($screens)
  }
}

function Convert-Rect($Rect) {
  return [pscustomobject]@{
    left = $Rect.Left
    top = $Rect.Top
    right = $Rect.Right
    bottom = $Rect.Bottom
    width = $Rect.Right - $Rect.Left
    height = $Rect.Bottom - $Rect.Top
  }
}

function Get-WindowTitle([IntPtr]$Handle) {
  $length = [NativeWindow]::GetWindowTextLength($Handle)
  if ($length -le 0) {
    return ""
  }
  $builder = New-Object System.Text.StringBuilder ($length + 1)
  [void][NativeWindow]::GetWindowText($Handle, $builder, $builder.Capacity)
  return $builder.ToString()
}

function Get-WindowInfo([IntPtr]$Handle) {
  $rect = New-Object NativeWindow+RECT
  [void][NativeWindow]::GetWindowRect($Handle, [ref]$rect)
  $processId = [uint32]0
  [void][NativeWindow]::GetWindowThreadProcessId($Handle, [ref]$processId)
  $processName = ""
  try {
    $processName = (Get-Process -Id ([int]$processId) -ErrorAction Stop).ProcessName
  } catch {
    $processName = ""
  }
  return [pscustomobject]@{
    handle = $Handle.ToInt64()
    title = Get-WindowTitle $Handle
    processId = [int]$processId
    processName = $processName
    rect = Convert-Rect $rect
  }
}

function Invoke-ListWindows {
  $items = New-Object System.Collections.Generic.List[object]
  $callback = [NativeWindow+EnumWindowsProc]{
    param([IntPtr]$handle, [IntPtr]$lParam)
    if ([NativeWindow]::IsWindowVisible($handle)) {
      $title = Get-WindowTitle $handle
      if (-not [string]::IsNullOrWhiteSpace($title)) {
        $items.Add((Get-WindowInfo $handle))
      }
    }
    return $true
  }
  [void][NativeWindow]::EnumWindows($callback, [IntPtr]::Zero)
  return [pscustomobject]@{
    ok = $true
    windows = $items
  }
}

function Invoke-GetActiveWindow {
  $handle = [NativeWindow]::GetForegroundWindow()
  if ($handle -eq [IntPtr]::Zero) {
    return [pscustomobject]@{
      ok = $false
      window = $null
    }
  }
  return [pscustomobject]@{
    ok = $true
    window = Get-WindowInfo $handle
  }
}

function Assert-ExpectedWindow($InputObject) {
  $expectedWindowTitle = [string](Get-ArgValue $InputObject "expectedWindowTitle" "")
  $targetWindowHandle = Get-ArgValue $InputObject "targetWindowHandle"
  $expectedHandle = $null
  if ($null -ne $targetWindowHandle) {
    $expectedHandle = [int64]$targetWindowHandle
    $target = New-Object System.IntPtr -ArgumentList $expectedHandle
    if ($target -ne [IntPtr]::Zero) {
      [void][NativeWindow]::ShowWindow($target, 5)
      [void][NativeWindow]::SetForegroundWindow($target)
      Start-Sleep -Milliseconds 150
    }
  } elseif ([string]::IsNullOrWhiteSpace($expectedWindowTitle)) {
    return
  }

  $active = Invoke-GetActiveWindow
  if ($null -ne $expectedHandle -and $active.ok -eq $true -and [int64]$active.window.handle -eq $expectedHandle) {
    return
  }
  if ([string]::IsNullOrWhiteSpace($expectedWindowTitle)) {
    throw "Active window does not match targetWindowHandle '$expectedHandle'"
  }
  $title = if ($null -ne $active.window) { [string]($active.window.title) } else { "" }
  $displayTitle = if ([string]::IsNullOrWhiteSpace($title)) { "unknown" } else { $title }
  if ($active.ok -ne $true -or $title -notmatch $expectedWindowTitle) {
    throw "Active window does not match expectedWindowTitle '$expectedWindowTitle': $displayTitle"
  }
}

function Invoke-FocusWindow($InputObject) {
  $target = [IntPtr]::Zero
  $handle = Get-ArgValue $InputObject "handle"
  $processId = Get-ArgValue $InputObject "processId"
  $title = [string](Get-ArgValue $InputObject "title" "")

  if ($null -ne $handle) {
    $target = [IntPtr]([int64]$handle)
  } elseif ($null -ne $processId) {
    $process = Get-Process -Id ([int]$processId) -ErrorAction Stop
    $target = $process.MainWindowHandle
  } elseif (-not [string]::IsNullOrWhiteSpace($title)) {
    $windows = (Invoke-ListWindows).windows
    $match = $windows | Where-Object { $_.title -like "*$title*" } | Select-Object -First 1
    if ($null -ne $match) {
      $target = [IntPtr]([int64]$match.handle)
    }
  }

  if ($target -eq [IntPtr]::Zero) {
    throw "No focusable window matched the provided selector"
  }

  [void][NativeWindow]::ShowWindow($target, 5)
  [void][NativeWindow]::SetForegroundWindow($target)
  Start-Sleep -Milliseconds 120

  return [pscustomobject]@{
    ok = $true
    window = Get-WindowInfo $target
    activeWindow = (Invoke-GetActiveWindow).window
  }
}

function Invoke-OpenUrl($InputObject) {
  $url = [string](Get-ArgValue $InputObject "url" "")
  if ([string]::IsNullOrWhiteSpace($url)) {
    throw "url cannot be empty"
  }
  $uri = [Uri]$url
  if ($uri.Scheme -notin @("http", "https")) {
    throw "Only http and https URLs are supported"
  }
  Start-Process $uri.AbsoluteUri
  return [pscustomobject]@{
    ok = $true
    url = $uri.AbsoluteUri
  }
}

function Resolve-OutputPath($MaybePath) {
  if (-not [string]::IsNullOrWhiteSpace($MaybePath)) {
    $explicitPath = [System.IO.Path]::GetFullPath($MaybePath)
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($explicitPath)) | Out-Null
    return $explicitPath
  }
  $dir = [System.IO.Path]::GetFullPath($DefaultScreenshotDir)
  [System.IO.Directory]::CreateDirectory($dir) | Out-Null
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
  return [System.IO.Path]::Combine($dir, "screenshot-$stamp.png")
}

function Get-DirectoryStats($Path, $Filter = "*") {
  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $resolved)) {
    return [pscustomobject]@{
      path = $resolved
      exists = $false
      fileCount = 0
      bytes = [int64]0
    }
  }

  $files = @(Get-ChildItem -LiteralPath $resolved -File -Filter $Filter)
  $bytes = [int64]0
  foreach ($file in $files) {
    $bytes += [int64]$file.Length
  }
  return [pscustomobject]@{
    path = $resolved
    exists = $true
    fileCount = $files.Count
    bytes = $bytes
  }
}

function Invoke-Probe {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [scriptblock]$ScriptBlock
  )

  try {
    $value = & $ScriptBlock
    return [pscustomobject]@{
      ok = $true
      value = $value
      error = $null
    }
  } catch {
    return [pscustomobject]@{
      ok = $false
      value = $null
      error = $_.Exception.Message
    }
  }
}

function Invoke-Doctor {
  $scratchDir = Join-Path $PluginRoot ".scratch"
  [System.IO.Directory]::CreateDirectory($scratchDir) | Out-Null
  $doctorScreenshot = Join-Path $scratchDir "doctor-screenshot.png"

  $screens = Invoke-Probe "list_screens" { Invoke-ListScreens }
  $windows = Invoke-Probe "list_windows" { Invoke-ListWindows }
  $activeWindow = Invoke-Probe "get_active_window" { Invoke-GetActiveWindow }
  $cursor = Invoke-Probe "get_cursor" { Get-CursorInfo }
  $screenshot = Invoke-Probe "screenshot" {
    $result = Invoke-Screenshot ([pscustomobject]@{ path = $doctorScreenshot })
    if (Test-Path -LiteralPath $doctorScreenshot) {
      Remove-Item -LiteralPath $doctorScreenshot -Force
    }
    $result
  }
  if (Test-Path -LiteralPath $doctorScreenshot) {
    Remove-Item -LiteralPath $doctorScreenshot -Force
  }

  $runtimeFiles = [pscustomobject]@{
    screenshots = Get-DirectoryStats (Join-Path $PluginRoot ".screenshots") "*.png"
    scratch = Get-DirectoryStats $scratchDir
  }
  $interactiveDesktopOk = $screenshot.ok -and $cursor.ok
  $cleanupRecommended = (
    $runtimeFiles.screenshots.fileCount -gt 50 -or
    $runtimeFiles.screenshots.bytes -gt 52428800 -or
    $runtimeFiles.scratch.fileCount -gt 0
  )

  return [pscustomobject]@{
    ok = $true
    status = if ($interactiveDesktopOk) { "ready" } else { "limited" }
    checks = [pscustomobject]@{
      screens = $screens
      windows = $windows
      activeWindow = $activeWindow
      cursor = $cursor
      screenshot = $screenshot
    }
    runtimeFiles = $runtimeFiles
    cleanupRecommended = $cleanupRecommended
    notes = @(
      if (-not $screenshot.ok) { "Screenshot capture is unavailable from this process context." }
      if ($cleanupRecommended) { "Run npm.cmd run cleanup to remove old screenshots and scratch files." }
    )
  }
}

function Invoke-Screenshot($InputObject) {
  $screen = Get-ScreenInfo ([bool](Get-ArgValue $InputObject "allScreens" $false))
  $path = Resolve-OutputPath (Get-ArgValue $InputObject "path")
  $bitmap = New-Object System.Drawing.Bitmap($screen.width, $screen.height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    try {
      $graphics.CopyFromScreen($screen.x, $screen.y, 0, 0, $bitmap.Size)
    } catch {
      throw "Screenshot capture failed for bounds $($screen.width)x$($screen.height) at ($($screen.x), $($screen.y)). Windows error: $($_.Exception.Message). This usually means the process cannot access the interactive desktop."
    }
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
  return [pscustomobject]@{
    ok = $true
    path = $path
    screen = $screen
    cursor = Get-CursorInfo
  }
}

function Invoke-MouseMove($InputObject) {
  Assert-ExpectedWindow $InputObject
  Set-CursorPosition -X ([int](Get-ArgValue $InputObject "x")) -Y ([int](Get-ArgValue $InputObject "y"))
  return [pscustomobject]@{
    ok = $true
    cursor = Get-CursorInfo
  }
}

function Invoke-MouseClick($InputObject) {
  Assert-ExpectedWindow $InputObject
  $x = Get-ArgValue $InputObject "x"
  $y = Get-ArgValue $InputObject "y"
  if ($null -ne $x -and $null -ne $y) {
    Set-CursorPosition -X ([int]$x) -Y ([int]$y)
  }

  $button = [string](Get-ArgValue $InputObject "button" "left")
  $count = [Math]::Min([Math]::Max([int](Get-ArgValue $InputObject "count" 1), 1), 3)
  $down = $MouseFlags["$button`Down"]
  $up = $MouseFlags["$button`Up"]
  if ($null -eq $down -or $null -eq $up) {
    throw "Unsupported mouse button: $button"
  }

  for ($i = 0; $i -lt $count; $i++) {
    [NativeInput]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 35
    [NativeInput]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
  }

  return [pscustomobject]@{
    ok = $true
    cursor = Get-CursorInfo
    button = $button
    count = $count
  }
}

function Invoke-MouseDrag($InputObject) {
  Assert-ExpectedWindow $InputObject
  $fromX = [int](Get-ArgValue $InputObject "fromX")
  $fromY = [int](Get-ArgValue $InputObject "fromY")
  $toX = [int](Get-ArgValue $InputObject "toX")
  $toY = [int](Get-ArgValue $InputObject "toY")
  $durationMs = [Math]::Min([Math]::Max([int](Get-ArgValue $InputObject "durationMs" 400), 50), 5000)
  $steps = [Math]::Max([int]($durationMs / 16), 3)

  Set-CursorPosition -X $fromX -Y $fromY
  Start-Sleep -Milliseconds 40
  [NativeInput]::mouse_event($MouseFlags.leftDown, 0, 0, 0, [UIntPtr]::Zero)
  for ($i = 1; $i -le $steps; $i++) {
    $t = $i / $steps
    $x = [int][Math]::Round($fromX + (($toX - $fromX) * $t))
    $y = [int][Math]::Round($fromY + (($toY - $fromY) * $t))
    Set-CursorPosition -X $x -Y $y
    Start-Sleep -Milliseconds ([Math]::Max([int]($durationMs / $steps), 1))
  }
  [NativeInput]::mouse_event($MouseFlags.leftUp, 0, 0, 0, [UIntPtr]::Zero)

  return [pscustomobject]@{
    ok = $true
    cursor = Get-CursorInfo
    from = [pscustomobject]@{ x = $fromX; y = $fromY }
    to = [pscustomobject]@{ x = $toX; y = $toY }
    durationMs = $durationMs
  }
}

function Invoke-MouseScroll($InputObject) {
  Assert-ExpectedWindow $InputObject
  $x = Get-ArgValue $InputObject "x"
  $y = Get-ArgValue $InputObject "y"
  if ($null -ne $x -and $null -ne $y) {
    Set-CursorPosition -X ([int]$x) -Y ([int]$y)
  }

  $delta = Get-ArgValue $InputObject "delta"
  if ($null -eq $delta) {
    $delta = 120 * [int](Get-ArgValue $InputObject "clicks" -3)
  }
  [NativeInput]::mouse_event($MouseFlags.wheel, 0, 0, [int]$delta, [UIntPtr]::Zero)

  return [pscustomobject]@{
    ok = $true
    cursor = Get-CursorInfo
    delta = [int]$delta
  }
}

function Invoke-TypeText($InputObject) {
  Assert-ExpectedWindow $InputObject
  $text = [string](Get-ArgValue $InputObject "text" "")
  $targetWindowHandle = Get-ArgValue $InputObject "targetWindowHandle"
  $automationSet = $false
  $automationError = $null
  $nativeTextClass = ""

  try {
    if ($null -ne $targetWindowHandle) {
      $nativeText = Set-WindowTextNative -Handle ([int64]$targetWindowHandle) -Text $text
      $automationSet = $nativeText.ok
      $nativeTextClass = $nativeText.className
    }
    if (-not $automationSet) {
      $automationSet = Set-FocusedAutomationText $text
    }
    if (-not $automationSet -and $null -ne $targetWindowHandle) {
      $automationSet = Set-WindowAutomationText -Handle ([int64]$targetWindowHandle) -Text $text
    } elseif (-not $automationSet) {
      $automationSet = Set-ForegroundAutomationText $text
    }
  } catch {
    $automationError = "$($_.Exception.GetType().FullName): $($_.Exception.Message)"
    # Some controls reject UI Automation writes; in that case the native paste remains the attempted input path.
  }
  if (-not $automationSet) {
    $hadText = [System.Windows.Forms.Clipboard]::ContainsText()
    $previousText = if ($hadText) { [System.Windows.Forms.Clipboard]::GetText() } else { "" }
    [System.Windows.Forms.Clipboard]::SetText($text)
    try {
      Send-KeyChordNative "Ctrl+V"
    } catch {
      throw "Native paste failed. Windows error: $($_.Exception.Message). This usually means the process cannot send input to the active desktop or target window."
    }
    Start-Sleep -Milliseconds 80
    if ($hadText) {
      [System.Windows.Forms.Clipboard]::SetText($previousText)
    }
  }
  return [pscustomobject]@{
    ok = $true
    length = $text.Length
    automationSet = $automationSet
    automationError = $automationError
    nativeTextClass = $nativeTextClass
  }
}

function Convert-KeyChord($Keys) {
  $parts = ([string]$Keys).Split("+") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  if ($parts.Count -eq 0) {
    throw "keys cannot be empty"
  }

  $prefix = ""
  $main = $parts[-1]
  if ($parts.Count -gt 1) {
    foreach ($part in $parts[0..($parts.Count - 2)]) {
      switch -Regex ($part.ToLowerInvariant()) {
        "^ctrl|control$" { $prefix += "^"; break }
        "^alt$" { $prefix += "%"; break }
        "^shift$" { $prefix += "+"; break }
        default { throw "Unsupported modifier: $part" }
      }
    }
  }

  $special = @{
    enter = "{ENTER}"
    return = "{ENTER}"
    escape = "{ESC}"
    esc = "{ESC}"
    tab = "{TAB}"
    backspace = "{BACKSPACE}"
    delete = "{DELETE}"
    up = "{UP}"
    down = "{DOWN}"
    left = "{LEFT}"
    right = "{RIGHT}"
    home = "{HOME}"
    end = "{END}"
    pageup = "{PGUP}"
    pagedown = "{PGDN}"
    space = " "
  }

  $key = $special[$main.ToLowerInvariant()]
  if (-not $key) {
    if ($main.Length -eq 1) {
      $key = $main.ToLowerInvariant()
    } else {
      $key = "{$($main.ToUpperInvariant())}"
    }
  }

  if ($prefix.Length -gt 0 -and $key.Length -eq 1) {
    return "$prefix$key"
  }
  if ($prefix.Length -gt 0) {
    return "$prefix($key)"
  }
  return $key
}

function Invoke-KeyPress($InputObject) {
  Assert-ExpectedWindow $InputObject
  $requestedKeys = [string](Get-ArgValue $InputObject "keys" "")
  try {
    Send-KeyChordNative $requestedKeys
  } catch {
    throw "Native key press failed for '$requestedKeys'. Windows error: $($_.Exception.Message). This usually means the process cannot send input to the active desktop or target window."
  }
  return [pscustomobject]@{
    ok = $true
    keys = $requestedKeys
  }
}

function Invoke-ClipboardSet($InputObject) {
  $text = [string](Get-ArgValue $InputObject "text" "")
  [System.Windows.Forms.Clipboard]::SetText($text)
  return [pscustomobject]@{
    ok = $true
    length = $text.Length
  }
}

function Invoke-ClipboardClear {
  [System.Windows.Forms.Clipboard]::Clear()
  return [pscustomobject]@{
    ok = $true
  }
}

function Invoke-ClipboardGet {
  $text = if ([System.Windows.Forms.Clipboard]::ContainsText()) {
    [System.Windows.Forms.Clipboard]::GetText()
  } else {
    ""
  }
  return [pscustomobject]@{
    ok = $true
    text = $text
    length = $text.Length
  }
}

$inputArgs = Get-InputArgs

switch ($Action) {
  "doctor" { Write-Json (Invoke-Doctor) }
  "screenshot" { Write-Json (Invoke-Screenshot $inputArgs) }
  "list_screens" { Write-Json (Invoke-ListScreens) }
  "list_windows" { Write-Json (Invoke-ListWindows) }
  "get_active_window" { Write-Json (Invoke-GetActiveWindow) }
  "focus_window" { Write-Json (Invoke-FocusWindow $inputArgs) }
  "open_url" { Write-Json (Invoke-OpenUrl $inputArgs) }
  "get_cursor" { Write-Json ([pscustomobject]@{ ok = $true; cursor = Get-CursorInfo }) }
  "mouse_move" { Write-Json (Invoke-MouseMove $inputArgs) }
  "mouse_click" { Write-Json (Invoke-MouseClick $inputArgs) }
  "mouse_drag" { Write-Json (Invoke-MouseDrag $inputArgs) }
  "mouse_scroll" { Write-Json (Invoke-MouseScroll $inputArgs) }
  "type_text" { Write-Json (Invoke-TypeText $inputArgs) }
  "key_press" { Write-Json (Invoke-KeyPress $inputArgs) }
  "clipboard_set" { Write-Json (Invoke-ClipboardSet $inputArgs) }
  "clipboard_clear" { Write-Json (Invoke-ClipboardClear) }
  "clipboard_get" { Write-Json (Invoke-ClipboardGet) }
  default { throw "Unknown action: $Action" }
}
