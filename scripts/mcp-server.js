#!/usr/bin/env node
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const psScript = resolve(__dirname, "windows-computer-use.ps1");
const confirmInput = /^true$/i.test(process.env.WINDOWS_COMPUTER_USE_CONFIRM_INPUT || "false");
const screenshotDir = process.env.WINDOWS_COMPUTER_USE_SCREENSHOT_DIR || "./.screenshots";
const allowWindowPattern = process.env.WINDOWS_COMPUTER_USE_ALLOW_WINDOW || "";
const blockWindowPattern = process.env.WINDOWS_COMPUTER_USE_BLOCK_WINDOW || "";

const tools = [
  {
    name: "doctor",
    description: "Run a local environment self-check for screen access, screenshot capture, window metadata, cursor read access, and runtime file usage.",
    inputSchema: { type: "object", properties: {} }
  },
  {
    name: "screenshot",
    description: "Capture the primary Windows screen as a PNG and return file path plus screen metadata.",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Optional output PNG path. Defaults to a timestamped file." },
        allScreens: { type: "boolean", description: "Capture the full virtual desktop instead of only the primary screen." },
        includeImage: { type: "boolean", description: "Return the PNG as MCP image content in addition to JSON metadata." }
      }
    }
  },
  {
    name: "list_windows",
    description: "List visible top-level Windows desktop windows with handles, titles, process ids, and rectangles.",
    inputSchema: { type: "object", properties: {} }
  },
  {
    name: "list_screens",
    description: "List all attached display screens and the virtual desktop bounds.",
    inputSchema: { type: "object", properties: {} }
  },
  {
    name: "get_active_window",
    description: "Return the current foreground window title, process id, handle, and rectangle.",
    inputSchema: { type: "object", properties: {} }
  },
  {
    name: "focus_window",
    description: "Bring a visible window to the foreground by handle, process id, or title substring.",
    inputSchema: {
      type: "object",
      properties: {
        handle: { type: "integer" },
        processId: { type: "integer" },
        title: { type: "string" },
        confirm: { type: "boolean" }
      }
    }
  },
  {
    name: "open_url",
    description: "Open a URL with the Windows default browser.",
    inputSchema: {
      type: "object",
      required: ["url"],
      properties: {
        url: { type: "string" },
        confirm: { type: "boolean" }
      }
    }
  },
  {
    name: "get_cursor",
    description: "Return the current cursor position in absolute screen pixels.",
    inputSchema: { type: "object", properties: {} }
  },
  {
    name: "mouse_move",
    description: "Move the cursor to an absolute screen coordinate.",
    inputSchema: {
      type: "object",
      required: ["x", "y"],
      properties: {
        x: { type: "integer" },
        y: { type: "integer" },
        expectedWindowTitle: { type: "string" },
        confirm: { type: "boolean" }
      }
    }
  },
  {
    name: "mouse_click",
    description: "Click at an absolute coordinate, or at the current cursor position if x/y are omitted.",
    inputSchema: {
      type: "object",
      properties: {
        x: { type: "integer" },
        y: { type: "integer" },
        button: { type: "string", enum: ["left", "right", "middle"], default: "left" },
        count: { type: "integer", minimum: 1, maximum: 3, default: 1 },
        expectedWindowTitle: { type: "string" },
        confirm: { type: "boolean" }
      }
    }
  },
  {
    name: "mouse_drag",
    description: "Drag from one absolute screen coordinate to another.",
    inputSchema: {
      type: "object",
      required: ["fromX", "fromY", "toX", "toY"],
      properties: {
        fromX: { type: "integer" },
        fromY: { type: "integer" },
        toX: { type: "integer" },
        toY: { type: "integer" },
        durationMs: { type: "integer", minimum: 50, maximum: 5000, default: 400 },
        expectedWindowTitle: { type: "string" },
        confirm: { type: "boolean" }
      }
    }
  },
  {
    name: "mouse_scroll",
    description: "Scroll the mouse wheel at an optional absolute coordinate.",
    inputSchema: {
      type: "object",
      properties: {
        x: { type: "integer" },
        y: { type: "integer" },
        delta: { type: "integer", description: "Wheel delta. Positive scrolls up, negative scrolls down. One notch is 120." },
        clicks: { type: "integer", description: "Alternative to delta. Positive scrolls up, negative scrolls down." },
        expectedWindowTitle: { type: "string" },
        confirm: { type: "boolean" }
      }
    }
  },
  {
    name: "type_text",
    description: "Type text into the focused Windows application.",
    inputSchema: {
      type: "object",
      required: ["text"],
      properties: {
        text: { type: "string" },
        targetWindowHandle: { type: "integer", description: "Optional top-level window handle used for UI Automation text fallback." },
        expectedWindowTitle: { type: "string" },
        confirm: { type: "boolean" }
      }
    }
  },
  {
    name: "key_press",
    description: "Send a key or key chord, for example Enter, Escape, Ctrl+L, Alt+Tab, or Ctrl+Shift+Esc.",
    inputSchema: {
      type: "object",
      required: ["keys"],
      properties: {
        keys: { type: "string" },
        expectedWindowTitle: { type: "string" },
        confirm: { type: "boolean" }
      }
    }
  },
  {
    name: "clipboard_set",
    description: "Set Unicode text on the Windows clipboard.",
    inputSchema: {
      type: "object",
      required: ["text"],
      properties: {
        text: { type: "string" },
        confirm: { type: "boolean" }
      }
    }
  },
  {
    name: "clipboard_clear",
    description: "Clear the Windows clipboard.",
    inputSchema: {
      type: "object",
      properties: {
        confirm: { type: "boolean" }
      }
    }
  },
  {
    name: "clipboard_get",
    description: "Read Unicode text from the Windows clipboard.",
    inputSchema: { type: "object", properties: {} }
  }
];

const write = (message) => {
  process.stdout.write(`${JSON.stringify(message)}\n`);
};

const ok = (id, result) => write({ jsonrpc: "2.0", id, result });
const fail = (id, code, message, data) => write({ jsonrpc: "2.0", id, error: { code, message, data } });

const inputTools = new Set(["focus_window", "open_url", "mouse_move", "mouse_click", "mouse_drag", "mouse_scroll", "type_text", "key_press", "clipboard_set", "clipboard_clear"]);
const windowScopedInputTools = new Set(["mouse_move", "mouse_click", "mouse_drag", "mouse_scroll", "type_text", "key_press"]);

function assertInputAllowed(name, args) {
  if (confirmInput && inputTools.has(name) && args?.confirm !== true) {
    throw new Error(`Tool ${name} requires confirm: true because WINDOWS_COMPUTER_USE_CONFIRM_INPUT=true`);
  }
}

function matchesPattern(pattern, window) {
  if (!pattern) {
    return false;
  }
  const regex = new RegExp(pattern, "i");
  return regex.test(window?.title || "") || regex.test(window?.processName || "");
}

function runPowerShell(action, args = {}) {
  return new Promise((resolvePromise, reject) => {
    const encodedArgs = Buffer.from(JSON.stringify(args), "utf16le").toString("base64");
    const child = spawn("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      psScript,
      "-Action",
      action,
      "-ArgsBase64",
      encodedArgs,
      "-DefaultScreenshotDir",
      screenshotDir
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
        reject(new Error(`Invalid PowerShell JSON output: ${stdout || error.message}`));
      }
    });
  });
}

async function callTool(name, args) {
  assertInputAllowed(name, args);
  if (!tools.some((tool) => tool.name === name)) {
    throw new Error(`Unknown tool: ${name}`);
  }
  if (windowScopedInputTools.has(name) && (allowWindowPattern || blockWindowPattern || args?.expectedWindowTitle)) {
    const active = await runPowerShell("get_active_window", {});
    const window = active?.window || {};
    if (blockWindowPattern && matchesPattern(blockWindowPattern, window)) {
      throw new Error(`Active window blocked by WINDOWS_COMPUTER_USE_BLOCK_WINDOW: ${window.title || window.processName || "unknown"}`);
    }
    if (allowWindowPattern && !matchesPattern(allowWindowPattern, window)) {
      throw new Error(`Active window does not match WINDOWS_COMPUTER_USE_ALLOW_WINDOW: ${window.title || window.processName || "unknown"}`);
    }
    if (args?.expectedWindowTitle && !new RegExp(args.expectedWindowTitle, "i").test(window.title || "")) {
      throw new Error(`Active window does not match expectedWindowTitle: ${window.title || "unknown"}`);
    }
  }
  const result = await runPowerShell(name, args || {});
  if (name === "screenshot" && args?.includeImage === true && result?.path) {
    const data = await readFile(result.path, { encoding: "base64" });
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(result, null, 2)
        },
        {
          type: "image",
          data,
          mimeType: "image/png"
        }
      ]
    };
  }
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(result, null, 2)
      }
    ]
  };
}

async function handle(message) {
  const { id, method, params } = message;
  try {
    if (method === "initialize") {
      ok(id, {
        protocolVersion: params?.protocolVersion || "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "computer-use-for-windows", version: "0.1.0" }
      });
      return;
    }
    if (method === "notifications/initialized") {
      return;
    }
    if (method === "tools/list") {
      ok(id, { tools });
      return;
    }
    if (method === "tools/call") {
      ok(id, await callTool(params?.name, params?.arguments));
      return;
    }
    fail(id, -32601, `Method not found: ${method}`);
  } catch (error) {
    fail(id, -32000, error.message);
  }
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let index = buffer.indexOf("\n");
  while (index >= 0) {
    const line = buffer.slice(0, index).trim();
    buffer = buffer.slice(index + 1);
    if (line) {
      try {
        void handle(JSON.parse(line));
      } catch (error) {
        fail(null, -32700, error.message);
      }
    }
    index = buffer.indexOf("\n");
  }
});
