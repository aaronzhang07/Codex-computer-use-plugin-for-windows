import { spawn } from "node:child_process";

const child = spawn(process.execPath, ["./scripts/mcp-server.js"], {
  cwd: new URL("..", import.meta.url),
  env: {
    ...process.env,
    WINDOWS_COMPUTER_USE_CONFIRM_INPUT: "true",
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

function waitFor(id, timeoutMs = 15000) {
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
send({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "doctor", arguments: {} } });

const initialize = await waitFor(1);
const doctor = await waitFor(2);

child.stdin.end();
child.kill();

const text = doctor.result?.content?.[0]?.text || "";
const report = JSON.parse(text);
const summary = {
  initializeOk: Boolean(initialize.result?.serverInfo?.name),
  doctorOk: report.ok === true,
  status: report.status,
  screensChecked: report.checks?.screens?.ok === true,
  cursorChecked: report.checks?.cursor?.ok === true,
  screenshotChecked: typeof report.checks?.screenshot?.ok === "boolean",
  runtimeFilesChecked: Number.isInteger(report.runtimeFiles?.screenshots?.fileCount),
  cleanupRecommendationChecked: typeof report.cleanupRecommended === "boolean"
};

if (!summary.initializeOk || !summary.doctorOk || !summary.screensChecked || !summary.cursorChecked || !summary.screenshotChecked || !summary.runtimeFilesChecked || !summary.cleanupRecommendationChecked) {
  console.error(JSON.stringify({ summary, initialize, doctor }, null, 2));
  process.exit(1);
}

console.log(JSON.stringify(summary, null, 2));
