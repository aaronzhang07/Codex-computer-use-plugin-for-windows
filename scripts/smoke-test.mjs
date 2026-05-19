import { spawn } from "node:child_process";

const child = spawn(process.execPath, ["./scripts/mcp-server.js"], {
  cwd: new URL("..", import.meta.url),
  env: {
    ...process.env,
    WINDOWS_COMPUTER_USE_CONFIRM_INPUT: "true",
    WINDOWS_COMPUTER_USE_ALLOW_WINDOW: "__WINDOW_THAT_SHOULD_NOT_EXIST__",
    WINDOWS_COMPUTER_USE_SCREENSHOT_DIR: "./.screenshots"
  },
  stdio: ["pipe", "pipe", "pipe"]
});

const responses = [];
let stdout = "";
let stderr = "";

child.stdout.setEncoding("utf8");
child.stderr.setEncoding("utf8");
child.stdout.on("data", (chunk) => {
  stdout += chunk;
  let index = stdout.indexOf("\n");
  while (index >= 0) {
    const line = stdout.slice(0, index).trim();
    stdout = stdout.slice(index + 1);
    if (line) {
      responses.push(JSON.parse(line));
    }
    index = stdout.indexOf("\n");
  }
});
child.stderr.on("data", (chunk) => {
  stderr += chunk;
});

function send(message) {
  child.stdin.write(`${JSON.stringify(message)}\n`);
}

function waitFor(id, timeoutMs = 10000) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    const timer = setInterval(() => {
      const response = responses.find((item) => item.id === id);
      if (response) {
        clearInterval(timer);
        resolve(response);
      } else if (Date.now() - start > timeoutMs) {
        clearInterval(timer);
        reject(new Error(`Timed out waiting for id ${id}. stderr=${stderr}`));
      }
    }, 25);
  });
}

send({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2024-11-05" } });
send({ jsonrpc: "2.0", method: "notifications/initialized" });
send({ jsonrpc: "2.0", id: 2, method: "tools/list" });
send({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "get_cursor", arguments: {} } });
send({ jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "mouse_move", arguments: { x: 1, y: 1 } } });
send({ jsonrpc: "2.0", id: 5, method: "tools/call", params: { name: "screenshot", arguments: { includeImage: true } } });
send({ jsonrpc: "2.0", id: 6, method: "tools/call", params: { name: "key_press", arguments: { keys: "Escape", confirm: true } } });

const initialize = await waitFor(1);
const list = await waitFor(2);
const cursor = await waitFor(3);
const denied = await waitFor(4);
const screenshot = await waitFor(5);
const policyDenied = await waitFor(6);

child.stdin.end();
child.kill();

const summary = {
  initializeOk: Boolean(initialize.result?.serverInfo?.name),
  toolCount: list.result?.tools?.length || 0,
  cursorOk: cursor.result?.content?.[0]?.text?.includes("\"ok\": true") || false,
  confirmationGateOk: denied.error?.message?.includes("requires confirm: true") || false,
  screenshotImageOk: screenshot.result?.content?.some((item) => item.type === "image" && item.mimeType === "image/png" && item.data?.length > 100) || false,
  windowPolicyGateOk: policyDenied.error?.message?.includes("WINDOWS_COMPUTER_USE_ALLOW_WINDOW") || false
};

if (!summary.initializeOk || summary.toolCount < 17 || !summary.cursorOk || !summary.confirmationGateOk || !summary.screenshotImageOk || !summary.windowPolicyGateOk) {
  console.error(JSON.stringify({ summary, initialize, list, cursor, denied, screenshot, policyDenied }, null, 2));
  process.exit(1);
}

console.log(JSON.stringify(summary, null, 2));
