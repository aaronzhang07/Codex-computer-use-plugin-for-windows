import { spawn } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { resolve } from "node:path";

const script = resolve("scripts/windows-computer-use.ps1");

function encodeArgs(args) {
  return Buffer.from(JSON.stringify(args), "utf16le").toString("base64");
}

function runBackend(action, args = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn("powershell.exe", [
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
    ], {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(stderr || stdout || `PowerShell exited with ${code}`));
        return;
      }
      try {
        resolvePromise(JSON.parse(stdout));
      } catch (error) {
        reject(new Error(`Invalid JSON from ${action}: ${stdout || error.message}`));
      }
    });
  });
}

const originalClipboard = await runBackend("clipboard_get");
const marker = `computer-use-for-windows smoke ${Date.now()} 中文符号()[]{}+-`;

try {
  const cursor = await runBackend("get_cursor");
  const screenshot = await runBackend("screenshot");
  const screens = await runBackend("list_screens");
  const allScreens = await runBackend("screenshot", { allScreens: true });
  const windows = await runBackend("list_windows");
  const activeWindow = await runBackend("get_active_window");
  const setClipboard = await runBackend("clipboard_set", { text: marker });
  const readClipboard = await runBackend("clipboard_get");

  const screenshotPath = screenshot.path;
  const summary = {
    cursorOk: cursor.ok === true && Number.isInteger(cursor.cursor?.x) && Number.isInteger(cursor.cursor?.y),
    screenshotOk: screenshot.ok === true && existsSync(screenshotPath) && statSync(screenshotPath).size > 0,
    listScreensOk: screens.ok === true && Array.isArray(screens.screens) && screens.screens.length > 0,
    allScreensScreenshotOk: allScreens.ok === true && existsSync(allScreens.path) && statSync(allScreens.path).size > 0,
    listWindowsOk: windows.ok === true && Array.isArray(windows.windows) && windows.windows.length > 0,
    activeWindowOk: activeWindow.ok === true && typeof activeWindow.window?.title === "string",
    clipboardSetOk: setClipboard.ok === true && setClipboard.length === marker.length,
    clipboardRoundTripOk: readClipboard.ok === true && readClipboard.text === marker,
    expectedClipboardLength: marker.length,
    actualClipboardLength: readClipboard.text?.length ?? null,
    actualClipboardPreview: readClipboard.text?.slice(0, 80) ?? null,
    restoredClipboard: false
  };

  if (originalClipboard.text) {
    await runBackend("clipboard_set", { text: originalClipboard.text });
    summary.restoredClipboard = true;
  } else {
    await runBackend("clipboard_clear");
    summary.restoredClipboard = true;
  }

  if (!summary.cursorOk || !summary.screenshotOk || !summary.listScreensOk || !summary.allScreensScreenshotOk || !summary.listWindowsOk || !summary.activeWindowOk || !summary.clipboardSetOk || !summary.clipboardRoundTripOk || !summary.restoredClipboard) {
    console.error(JSON.stringify(summary, null, 2));
    process.exit(1);
  }

  console.log(JSON.stringify(summary, null, 2));
} catch (error) {
  if (originalClipboard.text) {
    await runBackend("clipboard_set", { text: originalClipboard.text });
  } else {
    await runBackend("clipboard_clear");
  }
  throw error;
}
