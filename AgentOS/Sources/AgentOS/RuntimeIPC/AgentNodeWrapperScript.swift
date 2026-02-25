import Foundation

enum AgentNodeWrapperScript {
    private static let fileName = "agentos-node-wrapper.js"

    static func ensureInstalled() throws -> String {
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        let payload = Data(scriptContent.utf8)

        let existing = try? Data(contentsOf: fileURL)
        if existing != payload {
            try payload.write(to: fileURL, options: .atomic)
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fileURL.path
        )
        return fileURL.path
    }

    private static let scriptContent = #"""
#!/usr/bin/env node
const { spawn } = require('node:child_process');
const net = require('node:net');

function parseArgs(argv) {
  const delimiter = argv.indexOf('--');
  const optionPart = delimiter >= 0 ? argv.slice(0, delimiter) : argv;
  const targetPart = delimiter >= 0 ? argv.slice(delimiter + 1) : [];

  let ipcPath = process.env.AGENTOS_IPC_PATH || '';
  let tool = '';
  for (let i = 0; i < optionPart.length; i += 1) {
    const token = optionPart[i];
    if (token === '--ipc-path' && i + 1 < optionPart.length) {
      ipcPath = optionPart[i + 1];
      i += 1;
      continue;
    }
    if (token === '--tool' && i + 1 < optionPart.length) {
      tool = optionPart[i + 1];
      i += 1;
    }
  }

  return {
    ipcPath,
    tool,
    targetExecutable: targetPart[0] || '',
    targetArgs: targetPart.slice(1),
  };
}

function stripANSI(value) {
  return value
    .replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, '')
    .replace(/\u001b\][^\u0007]*\u0007/g, '')
    .replace(/\u001b\][^\u001b]*\u001b\\/g, '');
}

function looksLikePromptTail(line) {
  if (!line) return false;
  const prompt = line.trim();
  if (!prompt) return false;
  if (prompt.startsWith('? ') || prompt.startsWith('? for shortcuts')) return true;
  const first = prompt[0];
  if (!['›', '❯', '➜', '>', '$', '%', '#'].includes(first)) return false;
  if (first === '>' && /^> (\- |\* |#|##|```)/.test(prompt)) return false;
  return prompt.length <= 240;
}

const approvalPatterns = [
  /approval required/i,
  /requires approval/i,
  /awaiting approval/i,
  /allow this command/i,
  /approve this action/i,
  /permission required/i,
  /grant permission/i,
  /是否允许/,
  /需要授权/,
  /等待授权/,
  /请批准/,
  /批准执行/,
];

const inputPatterns = [
  /waiting for input/i,
  /awaiting user input/i,
  /awaiting input/i,
  /press enter to continue/i,
  /input required/i,
  /enter your choice/i,
  /请输入/,
  /等待输入/,
  /等待用户输入/,
  /请选择/,
  /输入后回车/,
];

const toolPatterns = [
  /exec/i,
  /command/i,
  /tool/i,
  /mcp/i,
  /patch/i,
  /bash/i,
  /git /i,
  /npm /i,
  /pnpm /i,
  /swift /i,
];

const options = parseArgs(process.argv.slice(2));
if (!options.targetExecutable) {
  console.error('[AgentOS Wrapper] missing target executable');
  process.exit(2);
}

let socket = null;
let socketReady = false;
let socketClosed = false;
const pendingEvents = [];
let lastStreamingSentAt = 0;

function pushEvent(payload) {
  if (socketClosed) return;
  if (!options.ipcPath) return;
  if (!socketReady || !socket) {
    pendingEvents.push(payload);
    if (pendingEvents.length > 64) {
      pendingEvents.shift();
    }
    return;
  }
  socket.write(`${JSON.stringify(payload)}\n`);
}

function emit(status, extra = {}) {
  pushEvent({
    status,
    timestamp: new Date().toISOString(),
    tool: options.tool || undefined,
    ...extra,
  });
}

function flushPendingEvents() {
  if (!socketReady || !socket || pendingEvents.length === 0) return;
  while (pendingEvents.length > 0) {
    const payload = pendingEvents.shift();
    socket.write(`${JSON.stringify(payload)}\n`);
  }
}

if (options.ipcPath) {
  socket = net.createConnection(options.ipcPath);
  socket.on('connect', () => {
    socketReady = true;
    flushPendingEvents();
    emit('thinking', { message: 'wrapper_connected' });
  });
  socket.on('error', () => {
    socketReady = false;
  });
  socket.on('close', () => {
    socketClosed = true;
    socketReady = false;
  });
}

const child = spawn('/usr/bin/script', [
  '-q',
  '/dev/null',
  options.targetExecutable,
  ...options.targetArgs,
], {
  env: process.env,
  cwd: process.cwd(),
  // Keep stdin attached to the controlling TTY so interactive CLIs stay in
  // full-screen/interactive mode, while still letting wrapper parse output.
  stdio: ['inherit', 'pipe', 'pipe'],
});

emit('thinking', { message: 'wrapper_spawn' });

function emitFromLine(rawLine) {
  const cleaned = stripANSI(rawLine).trim();
  if (!cleaned) return;

  if (approvalPatterns.some((pattern) => pattern.test(cleaned))) {
    emit('approving', { message: cleaned, approvalPrompt: cleaned });
    return;
  }

  if (inputPatterns.some((pattern) => pattern.test(cleaned)) || looksLikePromptTail(cleaned)) {
    emit('awaiting_user', { message: cleaned });
    return;
  }

  if (toolPatterns.some((pattern) => pattern.test(cleaned))) {
    emit('calling_tool', { message: cleaned });
    return;
  }

  const now = Date.now();
  if (now - lastStreamingSentAt >= 180) {
    lastStreamingSentAt = now;
    emit('streaming', { message: cleaned.slice(0, 220) });
  }
}

function emitFromChunk(chunk) {
  const text = chunk.toString('utf8');
  if (!text) return;
  text.split(/\r?\n/).forEach((line) => emitFromLine(line));
}

child.stdout.on('data', (chunk) => {
  process.stdout.write(chunk);
  emitFromChunk(chunk);
});

child.stderr.on('data', (chunk) => {
  process.stderr.write(chunk);
  emitFromChunk(chunk);
});

child.on('error', (error) => {
  emit('awaiting_user', { message: `wrapper_child_error:${error.message}` });
  if (socket && !socket.destroyed) socket.end();
  process.exit(1);
});

child.on('exit', (code, signal) => {
  emit('awaiting_user', {
    message: 'wrapper_child_exit',
    exitCode: code === null ? undefined : code,
    signal: signal || undefined,
  });

  if (socket && !socket.destroyed) {
    socket.end();
  }
  process.exit(code === null ? 0 : code);
});
"""#
}
