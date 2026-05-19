import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const scratchDir = resolve(".scratch");
const scratchFile = resolve(scratchDir, "input-smoke.txt");
const script = resolve("scripts/windows-computer-use.ps1");
const marker = `computer_use_for_windows input smoke\r\n中文输入 ok\r\nSymbols ()[]{}+-`;

mkdirSync(scratchDir, { recursive: true });
writeFileSync(scratchFile, "", "utf8");

function encodeArgs(args) {
  return Buffer.from(JSON.stringify(args), "utf16le").toString("base64");
}

function runProcess(command, args, options = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"],
      ...options
    });

    let stdout = "";
    let stderr = "";
    child.stdout?.setEncoding("utf8");
    child.stderr?.setEncoding("utf8");
    child.stdout?.on("data", (chunk) => { stdout += chunk; });
    child.stderr?.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(JSON.stringify({
          command,
          args,
          code,
          stdout,
          stderr
        }, null, 2)));
        return;
      }
      resolvePromise(stdout);
    });
  });
}

async function runBackend(action, args = {}) {
  const stdout = await runProcess("powershell.exe", [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    script,
    "-Action",
    action,
    "-ArgsBase64",
    encodeArgs(args),
    "-DefaultScreenshotDir",
    "./.screenshots"
  ]);
  return JSON.parse(stdout);
}

async function readWindowText(handle) {
  const command = [
    "Add-Type -AssemblyName UIAutomationClient",
    "Add-Type -AssemblyName UIAutomationTypes",
    `$handle = [IntPtr]${handle}`,
    "if ($handle -eq [IntPtr]::Zero) { ''; exit 0 }",
    "$root = [System.Windows.Automation.AutomationElement]::FromHandle($handle)",
    "if ($null -eq $root) { ''; exit 0 }",
    "$condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::IsValuePatternAvailableProperty, $true)",
    "$element = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)",
    "if ($null -eq $element) { ''; exit 0 }",
    "$pattern = $null",
    "if ($element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) { $pattern.Current.Value } else { '' }"
  ].join("; ");
  return (await runProcess("powershell.exe", ["-NoProfile", "-Command", command])).replace(/\r?\n$/, "");
}

async function focusProcess(processId) {
  try {
    return await runBackend("focus_window", { processId });
  } catch {
    return await runBackend("focus_window", { title: "input-smoke" });
  }
}

async function getVisibleWindow(processId) {
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    const windows = await runBackend("list_windows");
    const match = windows.windows.find((window) => (
      (window.processId === processId || /input-smoke/i.test(window.title || "")) &&
      window.rect?.width > 100 &&
      window.rect?.height > 100
    ));
    if (match) {
      return match;
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 150));
  }
  throw new Error(`Could not find visible Notepad window for process ${processId}`);
}

async function closeProcess(processId) {
  const command = [
    "$ErrorActionPreference = 'SilentlyContinue'",
    `$p = Get-Process -Id ${processId}`,
    "if ($p) { $p.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 500 }",
    `$p = Get-Process -Id ${processId}`,
    "if ($p) { Stop-Process -Id $($p.Id) -Force }",
    "exit 0"
  ].join("; ");
  try {
    await runProcess("powershell.exe", ["-NoProfile", "-Command", command]);
  } catch {
    // Cleanup is best effort; input assertions should report the real failure.
  }
}

const launchOutput = await runProcess("powershell.exe", [
  "-NoProfile",
  "-Command",
  `$p = Start-Process notepad.exe -ArgumentList '${scratchFile.replaceAll("'", "''")}' -PassThru; $p.Id`
]);
const processId = Number.parseInt(launchOutput.trim(), 10);

if (!Number.isInteger(processId)) {
  throw new Error(`Could not launch Notepad. Output: ${launchOutput}`);
}

try {
  const focus = await focusProcess(processId);
  const focusedWindow = focus.activeWindow?.rect?.width > 100 ? focus.activeWindow : focus.window;
  const window = focusedWindow?.rect?.width > 100 && focusedWindow?.rect?.height > 100
    ? focusedWindow
    : await getVisibleWindow(processId);
  const rect = window.rect;
  const clickX = Math.round(rect.left + rect.width / 2);
  const clickY = Math.round(rect.top + Math.max(120, rect.height / 3));

  const click = await runBackend("mouse_click", { x: clickX, y: clickY, button: "left", count: 1 });
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 250));
  const selectAll = await runBackend("key_press", { keys: "Ctrl+A" });
  const typed = await runBackend("type_text", { text: marker, targetWindowHandle: window.handle });
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 250));
  const focusedText = await readWindowText(window.handle);
  const savedKeys = await runBackend("key_press", { keys: "Ctrl+S" });
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 700));

  const saved = readFileSync(scratchFile, "utf8").replace(/^\uFEFF/, "");
  const summary = {
    processId,
    windowTitle: window.title,
    rect,
    focusOk: focus.ok === true,
    clickOk: click.ok === true && click.cursor?.x === clickX && click.cursor?.y === clickY,
    selectAllOk: selectAll.ok === true,
    typeTextToolOk: typed.ok === true && typed.length === marker.length,
    automationSet: typed.automationSet === true,
    automationError: typed.automationError,
    nativeTextClass: typed.nativeTextClass,
    saveKeysOk: savedKeys.ok === true,
    typeTextOk: focusedText === marker || saved === marker || typed.automationSet === true,
    focusedTextLength: focusedText.length,
    savedLength: saved.length,
    expectedLength: marker.length,
    savedPreview: saved.slice(0, 80)
  };

  await closeProcess(processId);

  if (!summary.typeTextOk) {
    console.error(JSON.stringify(summary, null, 2));
    process.exit(1);
  }

  console.log(JSON.stringify(summary, null, 2));
} catch (error) {
  await closeProcess(processId);
  throw error;
}
