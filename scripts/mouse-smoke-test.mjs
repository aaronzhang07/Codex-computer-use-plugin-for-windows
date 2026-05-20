import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const scratchDir = resolve(".scratch");
const scratchFile = resolve(scratchDir, "mouse-smoke.txt");
const script = resolve("scripts/windows-computer-use.ps1");

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
        reject(new Error(JSON.stringify({ command, args, code, stdout, stderr }, null, 2)));
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
    // Cleanup is best effort.
  }
}

async function getVisibleWindow(processId) {
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    const windows = await runBackend("list_windows");
    const match = windows.windows.find((window) => (
      (window.processId === processId || /mouse-smoke/i.test(window.title || "")) &&
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
  const originalCursor = await runBackend("get_cursor");
  const visibleWindow = await getVisibleWindow(processId);
  const focus = await runBackend("focus_window", { handle: visibleWindow.handle });
  const focusedWindow = focus.activeWindow?.rect?.width > 100 ? focus.activeWindow : focus.window;
  const window = focusedWindow?.rect?.width > 100 && focusedWindow?.rect?.height > 100
    ? focusedWindow
    : visibleWindow;
  const rect = window.rect;
  const clickX = Math.round(rect.left + rect.width / 2);
  const clickY = Math.round(rect.top + Math.max(120, rect.height / 3));
  const dragFromX = Math.round(rect.left + rect.width * 0.35);
  const dragToX = Math.round(rect.left + rect.width * 0.65);
  const dragY = Math.round(rect.top + rect.height * 0.55);
  async function focusTargetWindow() {
    const result = await runBackend("focus_window", { handle: window.handle });
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 150));
    return result;
  }

  const expectedWindowTitle = "mouse-smoke";
  const targetWindowHandle = window.handle;
  await focusTargetWindow();
  const click = await runBackend("mouse_click", { x: clickX, y: clickY, button: "left", count: 1, expectedWindowTitle, targetWindowHandle });
  await focusTargetWindow();
  const scroll = await runBackend("mouse_scroll", { x: clickX, y: clickY, clicks: -1, expectedWindowTitle, targetWindowHandle });
  await focusTargetWindow();
  const drag = await runBackend("mouse_drag", {
    fromX: dragFromX,
    fromY: dragY,
    toX: dragToX,
    toY: dragY,
    durationMs: 120,
    expectedWindowTitle,
    targetWindowHandle
  });

  await closeProcess(processId);
  await runBackend("mouse_move", originalCursor.cursor);

  const summary = {
    processId,
    windowTitle: window.title,
    rect,
    focusOk: focus.ok === true,
    click: { x: clickX, y: clickY, ok: click.ok === true, cursor: click.cursor },
    scroll: { ok: scroll.ok === true, delta: scroll.delta },
    drag: { ok: drag.ok === true, from: drag.from, to: drag.to },
    mouseToolsOk: (
      focus.ok === true &&
      click.ok === true &&
      click.cursor?.x === clickX &&
      click.cursor?.y === clickY &&
      scroll.ok === true &&
      scroll.delta === -120 &&
      drag.ok === true &&
      drag.to?.x === dragToX &&
      drag.to?.y === dragY
    ),
    restoredCursor: true
  };

  if (!summary.mouseToolsOk) {
    console.error(JSON.stringify(summary, null, 2));
    process.exit(1);
  }

  console.log(JSON.stringify(summary, null, 2));
} catch (error) {
  await closeProcess(processId);
  throw error;
}
