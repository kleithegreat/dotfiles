#!/usr/bin/env node

import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import readline from 'node:readline';

const BRIDGE_VERSION = '0.1.0';
const SERVER_VERSION = `${BRIDGE_VERSION}+claude-code`;
const DEFAULT_HOST = '127.0.0.1';
const DEFAULT_PORT = 4096;
const DEFAULT_DATA_DIR = path.join(os.homedir(), '.local', 'share', 'openchamber-claude-bridge');
const DEFAULT_PERMISSION_MODE = process.env.OPENCHAMBER_CLAUDE_PERMISSION_MODE || 'default';
const DEFAULT_MODEL_ID = process.env.OPENCHAMBER_CLAUDE_DEFAULT_MODEL || 'sonnet';
const PROVIDER_ID = 'claude-code';
const PROVIDER_NAME = 'Claude Code';
const CLAUDE_BIN = process.env.CLAUDE_CODE_BIN || 'claude';
const TEXT_FIELD = 'text';

const DEFAULT_TOOL_IDS = [
  'Task',
  'AskUserQuestion',
  'Bash',
  'Edit',
  'Glob',
  'Grep',
  'Read',
  'TodoWrite',
  'WebFetch',
  'WebSearch',
  'Write',
];

const MODEL_SPECS = {
  fable: {
    id: 'fable',
    cliModel: 'fable',
    name: 'Claude Fable 5 (Claude Code)',
    limit: {
      context: 1000000,
      output: 128000,
    },
    releaseDate: '2026-06-09',
  },
  opus: {
    id: 'opus',
    cliModel: 'opus',
    name: 'Claude Opus (Claude Code)',
  },
  sonnet: {
    id: 'sonnet',
    cliModel: 'sonnet',
    name: 'Claude Sonnet (Claude Code)',
  },
  haiku: {
    id: 'haiku',
    cliModel: 'haiku',
    name: 'Claude Haiku (Claude Code)',
  },
};

const PERMISSION_RULES_ALLOW_ALL = [
  { permission: '*', pattern: '*', action: 'allow' },
];

const AGENTS = [
  {
    name: 'build',
    description: 'Default Claude Code agent bridge.',
    mode: 'primary',
    native: true,
    permission: PERMISSION_RULES_ALLOW_ALL,
    options: {},
  },
  {
    name: 'plan',
    description: 'Plan-only Claude Code bridge agent.',
    mode: 'primary',
    native: true,
    permission: PERMISSION_RULES_ALLOW_ALL,
    options: {},
  },
  {
    name: 'general',
    description: 'General-purpose Claude Code subagent bridge.',
    mode: 'subagent',
    native: true,
    permission: PERMISSION_RULES_ALLOW_ALL,
    options: {},
  },
  {
    name: 'explore',
    description: 'Codebase exploration Claude Code subagent bridge.',
    mode: 'subagent',
    native: true,
    permission: PERMISSION_RULES_ALLOW_ALL,
    options: {},
  },
];

const CONFIG_TEMPLATE = {
  $schema: 'https://opencode.ai/config.json',
  model: `${PROVIDER_ID}/${DEFAULT_MODEL_ID}`,
  small_model: `${PROVIDER_ID}/haiku`,
  share: 'disabled',
  provider: {
    [PROVIDER_ID]: {
      name: PROVIDER_NAME,
      options: {},
    },
  },
};

function printHelp() {
  console.log(`openchamber-claude-bridge ${BRIDGE_VERSION}

Usage:
  openchamber-claude-bridge serve [--host HOST] [--port PORT] [--data-dir PATH]

Environment:
  OPENCHAMBER_CLAUDE_PERMISSION_MODE   Claude permission mode (default: ${DEFAULT_PERMISSION_MODE})
  OPENCHAMBER_CLAUDE_DEFAULT_MODEL     Default model id (default: ${DEFAULT_MODEL_ID})
  OPENCHAMBER_CLAUDE_BRIDGE_DATA_DIR   Persistent state directory
  CLAUDE_CODE_BIN                      Claude Code executable path
`);
}

function parseArgs(argv) {
  const args = [...argv];
  let command = 'serve';
  if (args[0] && !args[0].startsWith('-')) {
    command = args.shift();
  }

  const options = {
    host: DEFAULT_HOST,
    port: DEFAULT_PORT,
    dataDir: process.env.OPENCHAMBER_CLAUDE_BRIDGE_DATA_DIR || DEFAULT_DATA_DIR,
  };

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === '--help' || arg === '-h') {
      options.help = true;
      continue;
    }
    if (arg === '--host') {
      options.host = args[i + 1] || options.host;
      i += 1;
      continue;
    }
    if (arg === '--port') {
      options.port = Number.parseInt(args[i + 1] || `${DEFAULT_PORT}`, 10) || DEFAULT_PORT;
      i += 1;
      continue;
    }
    if (arg === '--data-dir') {
      options.dataDir = args[i + 1] || options.dataDir;
      i += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  return { command, options };
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function normalizeDirectory(input) {
  if (typeof input !== 'string') {
    return process.cwd();
  }
  const trimmed = input.trim();
  if (!trimmed) {
    return process.cwd();
  }
  return path.resolve(trimmed);
}

function projectIdForDirectory(directory) {
  return crypto.createHash('sha1').update(directory).digest('hex');
}

function slugForSession(id) {
  return `claude-${id.slice(0, 8)}`;
}

function modelSpecFor(modelID) {
  return MODEL_SPECS[modelID] || MODEL_SPECS[DEFAULT_MODEL_ID] || MODEL_SPECS.sonnet;
}

function modelList() {
  return Object.values(MODEL_SPECS).map((spec) => ({
    id: spec.id,
    providerID: PROVIDER_ID,
    api: {
      id: 'claude-code-cli',
      url: 'cli://claude',
      npm: '',
    },
    name: spec.name,
    family: 'claude',
    capabilities: {
      temperature: false,
      reasoning: false,
      // The bridge does not pass attachment bytes to the claude CLI yet, so
      // do not advertise attachment/image/pdf input support.
      attachment: false,
      toolcall: true,
      input: {
        text: true,
        audio: false,
        image: false,
        video: false,
        pdf: false,
      },
      output: {
        text: true,
        audio: false,
        image: false,
        video: false,
        pdf: false,
      },
      interleaved: false,
    },
    cost: {
      input: 0,
      output: 0,
      cache: {
        read: 0,
        write: 0,
      },
    },
    limit: spec.limit || {
      context: 1000000,
      output: 64000,
    },
    status: 'active',
    options: {
      cliModel: spec.cliModel,
    },
    headers: {},
    release_date: spec.releaseDate || '2026-04-18',
  }));
}

function providerRecord() {
  return {
    id: PROVIDER_ID,
    name: PROVIDER_NAME,
    source: 'custom',
    env: [],
    options: {},
    models: Object.fromEntries(modelList().map((model) => [model.id, model])),
  };
}

function configForBridge() {
  return {
    ...CONFIG_TEMPLATE,
    model: `${PROVIDER_ID}/${DEFAULT_MODEL_ID}`,
    small_model: `${PROVIDER_ID}/haiku`,
  };
}

function routeAgentName(agent) {
  if (agent === 'plan') return 'Plan';
  if (agent === 'explore') return 'Explore';
  if (agent === 'general') return 'general-purpose';
  return null;
}

function buildPromptFromParts(parts) {
  const sections = [];
  for (const part of parts || []) {
    if (!part || typeof part !== 'object') continue;
    if (part.type === 'text' && typeof part.text === 'string' && part.text.trim()) {
      sections.push(part.text.trim());
      continue;
    }
    if (part.type === 'agent' && typeof part.name === 'string' && part.name.trim()) {
      sections.push(`@${part.name.trim()}`);
      continue;
    }
    if (part.type === 'file') {
      const sourcePath = typeof part.source?.path === 'string' && part.source.path.trim().length > 0
        ? part.source.path.trim()
        : null;
      const label = sourcePath || part.filename || 'attached-file';
      sections.push(`[Attached file: ${label}]`);
    }
  }
  return sections.join('\n\n').trim() || 'Continue.';
}

function defaultSessionTitle(body, existingTitle) {
  if (typeof existingTitle === 'string' && existingTitle.trim()) {
    return existingTitle;
  }
  const text = buildPromptFromParts(body?.parts || []);
  return text.length <= 80 ? text : `${text.slice(0, 77)}...`;
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      if (chunks.length === 0) {
        resolve(undefined);
        return;
      }
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch (error) {
        reject(error);
      }
    });
    req.on('error', reject);
  });
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
  });
  res.end(body);
}

function sendNoContent(res) {
  res.writeHead(204);
  res.end();
}

function sendNotFound(res, message = 'Not found') {
  sendJson(res, 404, { name: 'NotFoundError', data: { message } });
}

function sendBadRequest(res, message) {
  sendJson(res, 400, { success: false, data: null, errors: [{ message }] });
}

function safeJsonParse(value, fallback) {
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

class BridgeState {
  constructor(dataDir) {
    this.dataDir = dataDir;
    this.stateFile = path.join(dataDir, 'state.json');
    this.sessions = new Map();
    // Event IDs only need per-process monotonicity; they are not persisted.
    this.nextEventId = Date.now();
    this.toolIds = [...DEFAULT_TOOL_IDS];
    this.saveTimer = null;
    this.load();
  }

  load() {
    ensureDir(this.dataDir);
    if (!fs.existsSync(this.stateFile)) {
      return;
    }
    const parsed = safeJsonParse(fs.readFileSync(this.stateFile, 'utf8'), null);
    if (!parsed || typeof parsed !== 'object') {
      return;
    }
    if (Array.isArray(parsed.toolIds) && parsed.toolIds.every((value) => typeof value === 'string')) {
      this.toolIds = parsed.toolIds;
    }
    for (const session of Array.isArray(parsed.sessions) ? parsed.sessions : []) {
      if (!session || typeof session !== 'object' || typeof session.info?.id !== 'string') {
        continue;
      }
      this.sessions.set(session.info.id, {
        info: session.info,
        messages: Array.isArray(session.messages) ? session.messages : [],
        status: session.status && typeof session.status === 'object' ? session.status : { type: 'idle' },
        turns: Number.isInteger(session.turns) ? session.turns : 0,
        // Legacy entries predate the flag; any session with recorded turns
        // was created with --session-id and must keep resuming.
        claudeSessionStarted: session.claudeSessionStarted === true
          || (Number.isInteger(session.turns) && session.turns > 0),
      });
    }
  }

  save() {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
      this.saveTimer = null;
    }
    ensureDir(this.dataDir);
    const payload = {
      toolIds: this.toolIds,
      sessions: Array.from(this.sessions.values()).map((session) => ({
        info: session.info,
        messages: session.messages,
        status: session.status,
        turns: session.turns,
        claudeSessionStarted: session.claudeSessionStarted,
      })),
    };
    const tempPath = `${this.stateFile}.tmp`;
    fs.writeFileSync(tempPath, JSON.stringify(payload, null, 2));
    fs.renameSync(tempPath, this.stateFile);
  }

  // Coalesces high-frequency writes (e.g. streaming deltas) into one save;
  // any direct save() flushes the pending timer.
  saveSoon() {
    if (this.saveTimer) {
      return;
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      this.save();
    }, 250);
    this.saveTimer.unref();
  }

  createSession({ directory, title, parentID, permission }) {
    const now = Date.now();
    const id = crypto.randomUUID();
    const info = {
      id,
      slug: slugForSession(id),
      projectID: projectIdForDirectory(directory),
      directory,
      ...(parentID ? { parentID } : {}),
      title: title && title.trim() ? title.trim() : 'New Claude Code session',
      version: SERVER_VERSION,
      time: {
        created: now,
        updated: now,
      },
      ...(permission ? { permission } : {}),
    };
    const session = {
      info,
      messages: [],
      status: { type: 'idle' },
      turns: 0,
      claudeSessionStarted: false,
    };
    this.sessions.set(id, session);
    this.save();
    return session;
  }

  getSession(sessionID) {
    return this.sessions.get(sessionID) || null;
  }

  deleteSession(sessionID) {
    const deleted = this.sessions.delete(sessionID);
    if (deleted) {
      this.save();
    }
    return deleted;
  }

  updateSession(sessionID, updater) {
    const session = this.getSession(sessionID);
    if (!session) {
      return null;
    }
    updater(session);
    session.info.time.updated = Date.now();
    this.save();
    return session;
  }

  listSessions({ directory, roots, start, search, limit }) {
    let sessions = Array.from(this.sessions.values());
    if (directory) {
      sessions = sessions.filter((session) => session.info.directory === directory);
    }
    if (roots) {
      sessions = sessions.filter((session) => !session.info.parentID);
    }
    if (Number.isFinite(start)) {
      sessions = sessions.filter((session) => session.info.time.updated >= start);
    }
    if (typeof search === 'string' && search.trim()) {
      const needle = search.trim().toLowerCase();
      sessions = sessions.filter((session) => session.info.title.toLowerCase().includes(needle));
    }
    sessions.sort((left, right) => right.info.time.updated - left.info.time.updated);
    if (Number.isFinite(limit) && limit > 0) {
      sessions = sessions.slice(0, limit);
    }
    return sessions.map((session) => session.info);
  }

  appendMessage(sessionID, message) {
    const session = this.getSession(sessionID);
    if (!session) {
      throw new Error(`Session not found: ${sessionID}`);
    }
    session.messages.push(message);
    session.info.time.updated = Date.now();
    this.saveSoon();
    return message;
  }

  replaceMessage(sessionID, messageID, updater) {
    const session = this.getSession(sessionID);
    if (!session) {
      return null;
    }
    const message = session.messages.find((entry) => entry.info.id === messageID) || null;
    if (!message) {
      return null;
    }
    updater(message);
    session.info.time.updated = Date.now();
    this.saveSoon();
    return message;
  }

  getMessage(sessionID, messageID) {
    const session = this.getSession(sessionID);
    if (!session) return null;
    return session.messages.find((entry) => entry.info.id === messageID) || null;
  }

  listMessages(sessionID, { limit, before } = {}) {
    const session = this.getSession(sessionID);
    if (!session) return null;
    let messages = [...session.messages];
    if (typeof before === 'string' && before) {
      const index = messages.findIndex((entry) => entry.info.id === before);
      if (index >= 0) {
        messages = messages.slice(0, index);
      }
    }
    if (Number.isFinite(limit) && limit > 0) {
      messages = messages.slice(-limit);
    }
    return messages;
  }

  setStatus(sessionID, status) {
    const session = this.getSession(sessionID);
    if (!session) return null;
    session.status = status;
    this.save();
    return status;
  }

  statusMap(directory) {
    const entries = {};
    for (const session of this.sessions.values()) {
      if (directory && session.info.directory !== directory) continue;
      entries[session.info.id] = session.status;
    }
    return entries;
  }

  projectForDirectory(directory) {
    return {
      id: projectIdForDirectory(directory),
      worktree: directory,
      ...(fs.existsSync(path.join(directory, '.git')) ? { vcs: 'git' } : {}),
      name: path.basename(directory) || directory,
      time: {
        created: 0,
        updated: Date.now(),
      },
      sandboxes: [],
    };
  }
}

class EventHub {
  constructor(state) {
    this.state = state;
    this.subscribers = new Set();
  }

  subscribe(req, res, directoryFilter = null) {
    res.writeHead(200, {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
    });
    res.write(': connected\n\n');
    const subscriber = { res, directoryFilter };
    this.subscribers.add(subscriber);
    const heartbeat = setInterval(() => {
      try {
        res.write(': heartbeat\n\n');
      } catch {
        clearInterval(heartbeat);
      }
    }, 10000);
    req.on('close', () => {
      clearInterval(heartbeat);
      this.subscribers.delete(subscriber);
    });
    this.publish(directoryFilter || 'global', {
      type: 'server.connected',
      properties: {},
    });
  }

  publish(directory, payload) {
    const eventId = `${this.state.nextEventId}`;
    this.state.nextEventId += 1;
    const wrapper = JSON.stringify({ directory, payload });
    for (const subscriber of this.subscribers) {
      if (subscriber.directoryFilter && subscriber.directoryFilter !== directory) {
        continue;
      }
      try {
        subscriber.res.write(`id: ${eventId}\n`);
        subscriber.res.write(`data: ${wrapper}\n\n`);
      } catch {
        this.subscribers.delete(subscriber);
      }
    }
  }
}

function createTextPart({ sessionID, messageID, text = '', synthetic = false }) {
  return {
    id: crypto.randomUUID(),
    sessionID,
    messageID,
    type: 'text',
    text,
    ...(synthetic ? { synthetic: true } : {}),
  };
}

function createFilePart({ sessionID, messageID, input }) {
  return {
    id: input.id || crypto.randomUUID(),
    sessionID,
    messageID,
    type: 'file',
    mime: input.mime,
    ...(input.filename ? { filename: input.filename } : {}),
    url: input.url,
    ...(input.source ? { source: input.source } : {}),
  };
}

function createAgentPart({ sessionID, messageID, input }) {
  return {
    id: input.id || crypto.randomUUID(),
    sessionID,
    messageID,
    type: 'agent',
    name: input.name,
    ...(input.source ? { source: input.source } : {}),
  };
}

function createUserMessage({ sessionID, agent, providerID, modelID, variant, format }) {
  return {
    id: crypto.randomUUID(),
    sessionID,
    role: 'user',
    time: {
      created: Date.now(),
    },
    ...(format ? { format } : {}),
    agent: agent || 'build',
    model: {
      providerID,
      modelID,
      ...(variant ? { variant } : {}),
    },
  };
}

function createAssistantMessage({ sessionID, parentID, providerID, modelID, agent, variant, directory, mode }) {
  return {
    id: crypto.randomUUID(),
    sessionID,
    role: 'assistant',
    time: {
      created: Date.now(),
    },
    parentID,
    modelID,
    providerID,
    mode: mode || 'default',
    agent: agent || 'build',
    path: {
      cwd: directory,
      root: directory,
    },
    cost: 0,
    tokens: {
      input: 0,
      output: 0,
      reasoning: 0,
      cache: {
        read: 0,
        write: 0,
      },
    },
    ...(variant ? { variant } : {}),
  };
}

function normalizeIncomingParts(sessionID, messageID, parts) {
  const normalized = [];
  for (const part of parts || []) {
    if (!part || typeof part !== 'object' || typeof part.type !== 'string') {
      continue;
    }
    if (part.type === 'text' && typeof part.text === 'string') {
      normalized.push(createTextPart({ sessionID, messageID, text: part.text, synthetic: part.synthetic === true }));
      continue;
    }
    if (part.type === 'file' && typeof part.mime === 'string' && typeof part.url === 'string') {
      normalized.push(createFilePart({ sessionID, messageID, input: part }));
      continue;
    }
    if (part.type === 'agent' && typeof part.name === 'string') {
      normalized.push(createAgentPart({ sessionID, messageID, input: part }));
    }
  }
  return normalized;
}

function updateAssistantUsage(messageInfo, usage, totalCostUsd, stopReason) {
  if (!usage || typeof usage !== 'object') {
    if (typeof stopReason === 'string' && stopReason) {
      messageInfo.finish = stopReason;
    }
    return;
  }

  messageInfo.tokens = {
    total: typeof usage.input_tokens === 'number' && typeof usage.output_tokens === 'number'
      ? usage.input_tokens + usage.output_tokens
      : undefined,
    input: typeof usage.input_tokens === 'number' ? usage.input_tokens : 0,
    output: typeof usage.output_tokens === 'number' ? usage.output_tokens : 0,
    reasoning: 0,
    cache: {
      read: typeof usage.cache_read_input_tokens === 'number' ? usage.cache_read_input_tokens : 0,
      write: typeof usage.cache_creation_input_tokens === 'number' ? usage.cache_creation_input_tokens : 0,
    },
  };
  if (typeof totalCostUsd === 'number') {
    messageInfo.cost = totalCostUsd;
  }
  if (typeof stopReason === 'string' && stopReason) {
    messageInfo.finish = stopReason;
  }
}

class ClaudeRunner {
  constructor({ state, events }) {
    this.state = state;
    this.events = events;
    this.activeRuns = new Map();
  }

  isBusy(sessionID) {
    return this.activeRuns.has(sessionID);
  }

  abort(sessionID) {
    const active = this.activeRuns.get(sessionID);
    if (!active) {
      return false;
    }
    try {
      active.aborted = true;
      active.child.kill('SIGTERM');
      setTimeout(() => {
        try {
          active.child.kill('SIGKILL');
        } catch {
        }
      }, 500);
    } catch {
    }
    return true;
  }

  start(session, body) {
    const requestedModel = body?.model && typeof body.model === 'object' ? body.model : {};
    const providerID = typeof requestedModel.providerID === 'string' ? requestedModel.providerID : PROVIDER_ID;
    const modelID = typeof requestedModel.modelID === 'string' ? requestedModel.modelID : DEFAULT_MODEL_ID;
    if (providerID !== PROVIDER_ID) {
      throw new Error(`Unsupported provider: ${providerID}`);
    }

    const userMessageInfo = createUserMessage({
      sessionID: session.info.id,
      agent: body?.agent,
      providerID,
      modelID,
      variant: body?.variant,
      format: body?.format,
    });
    const userParts = normalizeIncomingParts(session.info.id, userMessageInfo.id, body?.parts || []);
    const userMessage = { info: userMessageInfo, parts: userParts };
    this.state.appendMessage(session.info.id, userMessage);
    this.events.publish(session.info.directory, {
      type: 'message.updated',
      properties: {
        sessionID: session.info.id,
        info: userMessage.info,
      },
    });
    for (const part of userParts) {
      this.events.publish(session.info.directory, {
        type: 'message.part.updated',
        properties: {
          sessionID: session.info.id,
          part,
          time: Date.now(),
        },
      });
    }

    const existingTitle = session.info.title === 'New Claude Code session' ? '' : session.info.title;
    const title = defaultSessionTitle(body, existingTitle);
    this.state.updateSession(session.info.id, (mutableSession) => {
      mutableSession.info.title = title;
      mutableSession.turns += 1;
    });
    this.events.publish(session.info.directory, {
      type: 'session.updated',
      properties: {
        sessionID: session.info.id,
        info: this.state.getSession(session.info.id).info,
      },
    });

    this.state.setStatus(session.info.id, { type: 'busy' });
    this.events.publish(session.info.directory, {
      type: 'session.status',
      properties: {
        sessionID: session.info.id,
        status: { type: 'busy' },
      },
    });

    const promptText = buildPromptFromParts(body?.parts || []);
    const modelSpec = modelSpecFor(modelID);
    const args = [
      '-p',
      '--verbose',
      '--output-format',
      'stream-json',
      '--include-partial-messages',
      '--permission-mode',
      DEFAULT_PERMISSION_MODE,
      '--model',
      modelSpec.cliModel,
    ];

    const routedAgent = routeAgentName(body?.agent);
    if (routedAgent) {
      args.push('--agent', routedAgent);
    }

    if (body?.format?.type === 'json_schema' && body?.format?.schema) {
      args.push('--json-schema', JSON.stringify(body.format.schema));
    }

    if (!session.claudeSessionStarted) {
      args.push('--session-id', session.info.id);
    } else {
      args.push('--resume', session.info.id);
    }
    args.push(promptText);

    const child = spawn(CLAUDE_BIN, args, {
      cwd: session.info.directory,
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    const run = {
      child,
      sessionID: session.info.id,
      userMessageID: userMessage.info.id,
      modelID,
      agent: body?.agent || 'build',
      variant: body?.variant,
      currentAssistant: null,
      textPartByIndex: new Map(),
      toolPartByIndex: new Map(),
      toolPartByCallId: new Map(),
      stderr: '',
      aborted: false,
      finished: false,
    };
    this.activeRuns.set(session.info.id, run);

    const rl = readline.createInterface({ input: child.stdout });
    rl.on('line', (line) => {
      if (!line.trim()) {
        return;
      }
      let parsed;
      try {
        parsed = JSON.parse(line);
      } catch {
        return;
      }
      this.processClaudeEvent(run, parsed);
    });

    child.stderr.on('data', (chunk) => {
      run.stderr += chunk.toString();
    });

    child.on('close', (code) => {
      rl.close();
      this.finishRun(run, code);
    });

    child.on('error', (error) => {
      run.stderr += `${error.message}\n`;
      this.finishRun(run, 1);
    });
  }

  ensureAssistantMessage(run, messageID) {
    const session = this.state.getSession(run.sessionID);
    if (!session) {
      return null;
    }
    if (run.currentAssistant && run.currentAssistant.info.id === messageID) {
      return run.currentAssistant;
    }
    const assistant = {
      info: createAssistantMessage({
        sessionID: run.sessionID,
        parentID: run.userMessageID,
        providerID: PROVIDER_ID,
        modelID: modelSpecFor(run.modelID).id,
        agent: run.agent,
        variant: run.variant,
        directory: session.info.directory,
        mode: DEFAULT_PERMISSION_MODE,
      }),
      parts: [],
    };
    assistant.info.id = messageID;
    this.state.appendMessage(run.sessionID, assistant);
    run.currentAssistant = assistant;
    run.textPartByIndex = new Map();
    run.toolPartByIndex = new Map();
    this.events.publish(session.info.directory, {
      type: 'message.updated',
      properties: {
        sessionID: run.sessionID,
        info: assistant.info,
      },
    });
    return assistant;
  }

  processClaudeEvent(run, parsed) {
    const session = this.state.getSession(run.sessionID);
    if (!session) {
      return;
    }

    if (parsed.type === 'system' && parsed.subtype === 'init') {
      // Claude Code has persisted the session at this point; later prompts
      // must use --resume instead of --session-id.
      if (!session.claudeSessionStarted) {
        this.state.updateSession(run.sessionID, (mutableSession) => {
          mutableSession.claudeSessionStarted = true;
        });
      }
      if (Array.isArray(parsed.tools) && parsed.tools.every((value) => typeof value === 'string')) {
        this.state.toolIds = parsed.tools;
        this.state.save();
      }
      return;
    }

    if (parsed.type === 'stream_event' && parsed.event && typeof parsed.event === 'object') {
      const event = parsed.event;
      if (event.type === 'message_start' && event.message?.id) {
        const assistant = this.ensureAssistantMessage(run, event.message.id);
        if (assistant) {
          assistant.info.time.created = Date.now();
          this.state.replaceMessage(run.sessionID, assistant.info.id, (message) => {
            message.info = assistant.info;
          });
        }
        return;
      }

      if (event.type === 'content_block_start' && run.currentAssistant) {
        if (event.content_block?.type === 'text') {
          const part = createTextPart({
            sessionID: run.sessionID,
            messageID: run.currentAssistant.info.id,
          });
          run.currentAssistant.parts.push(part);
          run.textPartByIndex.set(event.index, part.id);
          this.state.replaceMessage(run.sessionID, run.currentAssistant.info.id, (message) => {
            message.parts = run.currentAssistant.parts;
          });
          this.events.publish(session.info.directory, {
            type: 'message.part.updated',
            properties: {
              sessionID: run.sessionID,
              part,
              time: Date.now(),
            },
          });
          return;
        }

        if (event.content_block?.type === 'tool_use') {
          const callID = event.content_block.id || crypto.randomUUID();
          const part = {
            id: crypto.randomUUID(),
            sessionID: run.sessionID,
            messageID: run.currentAssistant.info.id,
            type: 'tool',
            callID,
            tool: event.content_block.name || 'tool',
            state: {
              status: 'pending',
              input: {},
              raw: '',
            },
          };
          run.currentAssistant.parts.push(part);
          run.toolPartByIndex.set(event.index, part.id);
          run.toolPartByCallId.set(callID, part.id);
          this.state.replaceMessage(run.sessionID, run.currentAssistant.info.id, (message) => {
            message.parts = run.currentAssistant.parts;
          });
          this.events.publish(session.info.directory, {
            type: 'message.part.updated',
            properties: {
              sessionID: run.sessionID,
              part,
              time: Date.now(),
            },
          });
        }
        return;
      }

      if (event.type === 'content_block_delta' && run.currentAssistant) {
        if (event.delta?.type === 'text_delta') {
          const partID = run.textPartByIndex.get(event.index);
          if (!partID) return;
          const updated = this.state.replaceMessage(run.sessionID, run.currentAssistant.info.id, (message) => {
            const part = message.parts.find((entry) => entry.id === partID);
            if (part && part.type === 'text') {
              part.text += event.delta.text || '';
            }
          });
          const part = updated?.parts.find((entry) => entry.id === partID);
          if (part) {
            this.events.publish(session.info.directory, {
              type: 'message.part.delta',
              properties: {
                sessionID: run.sessionID,
                messageID: run.currentAssistant.info.id,
                partID,
                field: TEXT_FIELD,
                delta: event.delta.text || '',
              },
            });
          }
          return;
        }

        if (event.delta?.type === 'input_json_delta') {
          const partID = run.toolPartByIndex.get(event.index);
          if (!partID) return;
          this.state.replaceMessage(run.sessionID, run.currentAssistant.info.id, (message) => {
            const part = message.parts.find((entry) => entry.id === partID);
            if (part && part.type === 'tool' && part.state.status === 'pending') {
              part.state.raw += event.delta.partial_json || '';
            }
          });
          return;
        }
      }

      if (event.type === 'content_block_stop' && run.currentAssistant) {
        const partID = run.toolPartByIndex.get(event.index);
        if (!partID) return;
        const updated = this.state.replaceMessage(run.sessionID, run.currentAssistant.info.id, (message) => {
          const part = message.parts.find((entry) => entry.id === partID);
          if (part && part.type === 'tool' && part.state.status === 'pending') {
            part.state.input = safeJsonParse(part.state.raw || '{}', {});
          }
        });
        const part = updated?.parts.find((entry) => entry.id === partID);
        if (part) {
          this.events.publish(session.info.directory, {
            type: 'message.part.updated',
            properties: {
              sessionID: run.sessionID,
              part,
              time: Date.now(),
            },
          });
        }
        return;
      }

      if (event.type === 'message_delta' && run.currentAssistant) {
        const updated = this.state.replaceMessage(run.sessionID, run.currentAssistant.info.id, (message) => {
          updateAssistantUsage(message.info, event.usage, undefined, event.delta?.stop_reason || undefined);
        });
        if (updated) {
          this.events.publish(session.info.directory, {
            type: 'message.updated',
            properties: {
              sessionID: run.sessionID,
              info: updated.info,
            },
          });
        }
        return;
      }

      if (event.type === 'message_stop' && run.currentAssistant) {
        const updated = this.state.replaceMessage(run.sessionID, run.currentAssistant.info.id, (message) => {
          message.info.time.completed = Date.now();
        });
        if (updated) {
          this.events.publish(session.info.directory, {
            type: 'message.updated',
            properties: {
              sessionID: run.sessionID,
              info: updated.info,
            },
          });
        }
      }
      return;
    }

    if (parsed.type === 'assistant' && parsed.message?.id) {
      const assistant = this.ensureAssistantMessage(run, parsed.message.id);
      if (!assistant) {
        return;
      }
      const updated = this.state.replaceMessage(run.sessionID, assistant.info.id, (message) => {
        updateAssistantUsage(message.info, parsed.message.usage, undefined, parsed.message.stop_reason || undefined);
        if (Array.isArray(parsed.message.content)) {
          for (const content of parsed.message.content) {
            if (content.type === 'text') {
              const existingTextPart = message.parts.find((entry) => entry.type === 'text');
              if (!existingTextPart) {
                message.parts.push(createTextPart({
                  sessionID: run.sessionID,
                  messageID: message.info.id,
                  text: content.text || '',
                }));
              }
            }
            if (content.type === 'tool_use') {
              const partID = run.toolPartByCallId.get(content.id);
              const input = content.input && typeof content.input === 'object' ? content.input : {};
              if (partID) {
                const part = message.parts.find((entry) => entry.id === partID);
                if (part && part.type === 'tool' && part.state.status === 'pending') {
                  part.state.input = input;
                  part.state.raw = JSON.stringify(input);
                }
              }
            }
          }
        }
      });
      if (updated) {
        this.events.publish(session.info.directory, {
          type: 'message.updated',
          properties: {
            sessionID: run.sessionID,
            info: updated.info,
          },
        });
        for (const part of updated.parts) {
          this.events.publish(session.info.directory, {
            type: 'message.part.updated',
            properties: {
              sessionID: run.sessionID,
              part,
              time: Date.now(),
            },
          });
        }
      }
      return;
    }

    if (parsed.type === 'user') {
      const resultEntry = Array.isArray(parsed.message?.content)
        ? parsed.message.content.find((entry) => entry && typeof entry === 'object' && (entry.type === 'tool_result' || entry.tool_use_id))
        : null;
      const partID = resultEntry?.tool_use_id ? run.toolPartByCallId.get(resultEntry.tool_use_id) : null;
      if (!partID || !run.currentAssistant) {
        return;
      }
      let output;
      if (parsed.tool_use_result?.stdout != null) {
        output = [
          parsed.tool_use_result.stdout || '',
          parsed.tool_use_result.stderr || '',
        ].filter(Boolean).join(parsed.tool_use_result.stderr ? '\n\n' : '');
      } else if (typeof resultEntry.content === 'string') {
        output = resultEntry.content;
      } else if (Array.isArray(resultEntry.content)) {
        output = resultEntry.content
          .filter((entry) => entry && typeof entry === 'object' && typeof entry.text === 'string')
          .map((entry) => entry.text)
          .join('\n');
      } else {
        output = typeof parsed.tool_use_result === 'string'
          ? parsed.tool_use_result
          : JSON.stringify(parsed.tool_use_result ?? '');
      }
      const updated = this.state.replaceMessage(run.sessionID, run.currentAssistant.info.id, (message) => {
        const part = message.parts.find((entry) => entry.id === partID);
        if (part && part.type === 'tool') {
          // The OpenChamber UI only renders error text from the `error` field
          // of a ToolStateError-shaped state.
          part.state = resultEntry.is_error === true
            ? {
              status: 'error',
              input: part.state.input || {},
              error: output,
              time: {
                start: Date.now(),
                end: Date.now(),
              },
            }
            : {
              status: 'completed',
              input: part.state.input || {},
              output,
              title: part.tool,
              metadata: {},
              time: {
                start: Date.now(),
                end: Date.now(),
              },
            };
        }
      });
      const part = updated?.parts.find((entry) => entry.id === partID);
      if (part) {
        this.events.publish(session.info.directory, {
          type: 'message.part.updated',
          properties: {
            sessionID: run.sessionID,
            part,
            time: Date.now(),
          },
        });
      }
      return;
    }

    if (parsed.type === 'result' && run.currentAssistant) {
      const updated = this.state.replaceMessage(run.sessionID, run.currentAssistant.info.id, (message) => {
        updateAssistantUsage(message.info, parsed.usage, parsed.total_cost_usd, parsed.stop_reason || undefined);
        message.info.time.completed = Date.now();
      });
      if (updated) {
        this.events.publish(session.info.directory, {
          type: 'message.updated',
          properties: {
            sessionID: run.sessionID,
            info: updated.info,
          },
        });
      }
    }
  }

  finishRun(run, code) {
    // 'close' follows 'error' on spawn failure; only finish once.
    if (run.finished) {
      return;
    }
    run.finished = true;
    const session = this.state.getSession(run.sessionID);
    this.activeRuns.delete(run.sessionID);
    if (!session) {
      return;
    }

    const failed = code !== 0 || run.aborted;
    if (failed && run.stderr.includes('No conversation found with session ID')) {
      // Claude lost the session; fall back to --session-id on the next prompt.
      this.state.updateSession(run.sessionID, (mutableSession) => {
        mutableSession.claudeSessionStarted = false;
      });
    }
    if (failed) {
      this.events.publish(session.info.directory, {
        type: 'session.error',
        properties: {
          sessionID: run.sessionID,
          error: {
            name: run.aborted ? 'MessageAbortedError' : 'UnknownError',
            data: {
              message: run.aborted ? 'Claude Code run aborted' : (run.stderr.trim() || `Claude Code exited with code ${code}`),
            },
          },
        },
      });
    }

    this.state.setStatus(run.sessionID, { type: 'idle' });
    this.events.publish(session.info.directory, {
      type: 'session.status',
      properties: {
        sessionID: run.sessionID,
        status: { type: 'idle' },
      },
    });
    this.events.publish(session.info.directory, {
      type: 'session.idle',
      properties: {
        sessionID: run.sessionID,
      },
    });
    this.events.publish(session.info.directory, {
      type: 'session.updated',
      properties: {
        sessionID: run.sessionID,
        info: this.state.getSession(run.sessionID).info,
      },
    });
  }
}

function tryDetectBranch(directory) {
  try {
    const headPath = path.join(directory, '.git', 'HEAD');
    const head = fs.readFileSync(headPath, 'utf8').trim();
    const refMatch = /^ref: refs\/heads\/(.+)$/.exec(head);
    return refMatch ? refMatch[1] : head;
  } catch {
    return undefined;
  }
}

function createServer({ host, port, dataDir }) {
  const state = new BridgeState(dataDir);
  const events = new EventHub(state);
  const runner = new ClaudeRunner({ state, events });

  // Flush any debounced state write before exiting.
  const flushAndExit = () => {
    try {
      state.save();
    } catch (error) {
      console.error('[openchamber-claude-bridge] failed to flush state:', error);
    }
    process.exit(0);
  };
  process.on('SIGINT', flushAndExit);
  process.on('SIGTERM', flushAndExit);

  const server = http.createServer(async (req, res) => {
    const requestUrl = new URL(req.url || '/', `http://${req.headers.host || `${host}:${port}`}`);
    const pathname = requestUrl.pathname;
    const directory = normalizeDirectory(requestUrl.searchParams.get('directory') || undefined);

    try {
      if (req.method === 'GET' && (pathname === '/global/health' || pathname === '/health')) {
        return sendJson(res, 200, { healthy: true, version: SERVER_VERSION });
      }

      if (req.method === 'GET' && pathname === '/global/config') {
        return sendJson(res, 200, configForBridge());
      }

      if (req.method === 'POST' && pathname === '/global/dispose') {
        return sendJson(res, 200, true);
      }

      if (req.method === 'GET' && (pathname === '/global/event' || pathname === '/event')) {
        return events.subscribe(req, res, pathname === '/event' ? directory : null);
      }

      if (req.method === 'GET' && pathname === '/provider') {
        return sendJson(res, 200, {
          all: [providerRecord()],
          default: { [PROVIDER_ID]: DEFAULT_MODEL_ID },
          connected: [PROVIDER_ID],
        });
      }

      if (req.method === 'GET' && pathname === '/provider/auth') {
        return sendJson(res, 200, {});
      }

      if (req.method === 'GET' && pathname === '/config/providers') {
        return sendJson(res, 200, {
          providers: [providerRecord()],
          default: { [PROVIDER_ID]: DEFAULT_MODEL_ID },
        });
      }

      if (req.method === 'GET' && pathname === '/config') {
        return sendJson(res, 200, configForBridge());
      }

      if (req.method === 'GET' && pathname === '/model') {
        return sendJson(res, 200, modelList());
      }

      if (req.method === 'GET' && pathname === '/agent') {
        return sendJson(res, 200, AGENTS);
      }

      if (req.method === 'GET' && pathname === '/command') {
        return sendJson(res, 200, []);
      }

      if (req.method === 'GET' && pathname === '/skill') {
        return sendJson(res, 200, []);
      }

      if (req.method === 'GET' && pathname === '/formatter') {
        return sendJson(res, 200, []);
      }

      if (req.method === 'GET' && pathname === '/lsp') {
        return sendJson(res, 200, []);
      }

      if (req.method === 'GET' && pathname === '/mcp') {
        return sendJson(res, 200, {});
      }

      if (req.method === 'GET' && pathname === '/project/current') {
        return sendJson(res, 200, state.projectForDirectory(directory));
      }

      if (req.method === 'GET' && pathname === '/project') {
        return sendJson(res, 200, [state.projectForDirectory(directory)]);
      }

      if (req.method === 'GET' && pathname === '/path') {
        return sendJson(res, 200, {
          home: os.homedir(),
          state: dataDir,
          config: path.join(os.homedir(), '.config', 'openchamber-claude-bridge'),
          worktree: directory,
          directory,
        });
      }

      if (req.method === 'GET' && pathname === '/vcs') {
        return sendJson(res, 200, {
          branch: tryDetectBranch(directory),
        });
      }

      if (req.method === 'GET' && pathname === '/experimental/tool/ids') {
        return sendJson(res, 200, state.toolIds);
      }

      if (req.method === 'GET' && pathname === '/experimental/tool') {
        return sendJson(res, 200, []);
      }

      if (req.method === 'GET' && pathname === '/permission') {
        return sendJson(res, 200, []);
      }

      if (req.method === 'GET' && pathname === '/question') {
        return sendJson(res, 200, []);
      }

      if (req.method === 'GET' && pathname === '/session') {
        const roots = requestUrl.searchParams.get('roots') === 'true';
        const start = requestUrl.searchParams.has('start')
          ? Number.parseInt(requestUrl.searchParams.get('start') || '', 10)
          : undefined;
        const limit = requestUrl.searchParams.has('limit')
          ? Number.parseInt(requestUrl.searchParams.get('limit') || '', 10)
          : undefined;
        return sendJson(res, 200, state.listSessions({
          directory: requestUrl.searchParams.has('directory') ? directory : null,
          roots,
          start,
          search: requestUrl.searchParams.get('search') || undefined,
          limit,
        }));
      }

      if (req.method === 'POST' && pathname === '/session') {
        const body = await readJsonBody(req).catch(() => null);
        if (body === null) {
          return sendBadRequest(res, 'Invalid JSON body');
        }
        const session = state.createSession({
          directory,
          title: typeof body?.title === 'string' ? body.title : undefined,
          parentID: typeof body?.parentID === 'string' ? body.parentID : undefined,
          permission: body?.permission,
        });
        events.publish(session.info.directory, {
          type: 'session.created',
          properties: {
            sessionID: session.info.id,
            info: session.info,
          },
        });
        return sendJson(res, 200, session.info);
      }

      if (req.method === 'GET' && pathname === '/session/status') {
        return sendJson(res, 200, state.statusMap(requestUrl.searchParams.has('directory') ? directory : null));
      }

      const sessionMatch = /^\/session\/([^/]+)$/.exec(pathname);
      if (sessionMatch) {
        const session = state.getSession(sessionMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${sessionMatch[1]}`);
        }
        if (req.method === 'GET') {
          return sendJson(res, 200, session.info);
        }
        if (req.method === 'DELETE') {
          state.deleteSession(session.info.id);
          events.publish(session.info.directory, {
            type: 'session.deleted',
            properties: {
              sessionID: session.info.id,
              info: session.info,
            },
          });
          return sendJson(res, 200, true);
        }
        if (req.method === 'PATCH' || req.method === 'POST') {
          const body = await readJsonBody(req).catch(() => null);
          if (body === null) {
            return sendBadRequest(res, 'Invalid JSON body');
          }
          const updated = state.updateSession(session.info.id, (mutableSession) => {
            if (typeof body?.title === 'string') {
              mutableSession.info.title = body.title;
            }
            if (body?.permission) {
              mutableSession.info.permission = body.permission;
            }
            if (body?.time && 'archived' in body.time) {
              if (body.time.archived) {
                mutableSession.info.time.archived = body.time.archived;
              } else {
                delete mutableSession.info.time.archived;
              }
            }
          });
          events.publish(session.info.directory, {
            type: 'session.updated',
            properties: {
              sessionID: updated.info.id,
              info: updated.info,
            },
          });
          return sendJson(res, 200, updated.info);
        }
      }

      const childrenMatch = /^\/session\/([^/]+)\/children$/.exec(pathname);
      if (req.method === 'GET' && childrenMatch) {
        const session = state.getSession(childrenMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${childrenMatch[1]}`);
        }
        const children = Array.from(state.sessions.values())
          .filter((candidate) => candidate.info.parentID === session.info.id)
          .map((candidate) => candidate.info);
        return sendJson(res, 200, children);
      }

      const todoMatch = /^\/session\/([^/]+)\/todo$/.exec(pathname);
      if (req.method === 'GET' && todoMatch) {
        const session = state.getSession(todoMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${todoMatch[1]}`);
        }
        return sendJson(res, 200, []);
      }

      const initMatch = /^\/session\/([^/]+)\/init$/.exec(pathname);
      if (req.method === 'POST' && initMatch) {
        const session = state.getSession(initMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${initMatch[1]}`);
        }
        return sendJson(res, 200, true);
      }

      const abortMatch = /^\/session\/([^/]+)\/abort$/.exec(pathname);
      if (req.method === 'POST' && abortMatch) {
        const session = state.getSession(abortMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${abortMatch[1]}`);
        }
        return sendJson(res, 200, runner.abort(session.info.id));
      }

      const shareMatch = /^\/session\/([^/]+)\/share$/.exec(pathname);
      if (shareMatch) {
        const session = state.getSession(shareMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${shareMatch[1]}`);
        }
        return sendJson(res, 200, session.info);
      }

      const revertMatch = /^\/session\/([^/]+)\/(revert|unrevert)$/.exec(pathname);
      if (revertMatch) {
        const session = state.getSession(revertMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${revertMatch[1]}`);
        }
        return sendJson(res, 200, session.info);
      }

      const diffMatch = /^\/session\/([^/]+)\/diff$/.exec(pathname);
      if (req.method === 'GET' && diffMatch) {
        const session = state.getSession(diffMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${diffMatch[1]}`);
        }
        return sendJson(res, 200, []);
      }

      const summarizeMatch = /^\/session\/([^/]+)\/summarize$/.exec(pathname);
      if (req.method === 'POST' && summarizeMatch) {
        const session = state.getSession(summarizeMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${summarizeMatch[1]}`);
        }
        return sendJson(res, 200, true);
      }

      const messagesMatch = /^\/session\/([^/]+)\/message$/.exec(pathname);
      if (messagesMatch) {
        const session = state.getSession(messagesMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${messagesMatch[1]}`);
        }
        if (req.method === 'GET') {
          const limit = requestUrl.searchParams.has('limit')
            ? Number.parseInt(requestUrl.searchParams.get('limit') || '', 10)
            : undefined;
          return sendJson(res, 200, state.listMessages(session.info.id, {
            limit,
            before: requestUrl.searchParams.get('before') || undefined,
          }));
        }
        if (req.method === 'POST') {
          return sendBadRequest(res, 'Synchronous bridge prompt is not implemented. Use prompt_async instead.');
        }
      }

      const messageMatch = /^\/session\/([^/]+)\/message\/([^/]+)$/.exec(pathname);
      if (messageMatch) {
        const session = state.getSession(messageMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${messageMatch[1]}`);
        }
        if (req.method === 'GET') {
          const message = state.getMessage(session.info.id, messageMatch[2]);
          if (!message) {
            return sendNotFound(res, `Message not found: ${messageMatch[2]}`);
          }
          return sendJson(res, 200, message);
        }
        if (req.method === 'DELETE') {
          const deleted = state.updateSession(session.info.id, (mutableSession) => {
            mutableSession.messages = mutableSession.messages.filter((entry) => entry.info.id !== messageMatch[2]);
          });
          if (!deleted) {
            return sendNotFound(res, `Message not found: ${messageMatch[2]}`);
          }
          events.publish(session.info.directory, {
            type: 'message.removed',
            properties: {
              sessionID: session.info.id,
              messageID: messageMatch[2],
            },
          });
          return sendJson(res, 200, true);
        }
      }

      const partMatch = /^\/session\/([^/]+)\/message\/([^/]+)\/part\/([^/]+)$/.exec(pathname);
      if (partMatch) {
        const session = state.getSession(partMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${partMatch[1]}`);
        }
        const message = state.getMessage(session.info.id, partMatch[2]);
        if (!message) {
          return sendNotFound(res, `Message not found: ${partMatch[2]}`);
        }
        if (req.method === 'DELETE') {
          state.replaceMessage(session.info.id, message.info.id, (mutableMessage) => {
            mutableMessage.parts = mutableMessage.parts.filter((entry) => entry.id !== partMatch[3]);
          });
          events.publish(session.info.directory, {
            type: 'message.part.removed',
            properties: {
              sessionID: session.info.id,
              messageID: message.info.id,
              partID: partMatch[3],
            },
          });
          return sendJson(res, 200, true);
        }
        if (req.method === 'PATCH' || req.method === 'POST') {
          const body = await readJsonBody(req).catch(() => null);
          if (body === null || typeof body !== 'object') {
            return sendBadRequest(res, 'Invalid JSON body');
          }
          let updatedPart = null;
          state.replaceMessage(session.info.id, message.info.id, (mutableMessage) => {
            const index = mutableMessage.parts.findIndex((entry) => entry.id === partMatch[3]);
            if (index >= 0) {
              mutableMessage.parts[index] = body;
              updatedPart = mutableMessage.parts[index];
            }
          });
          if (!updatedPart) {
            return sendNotFound(res, `Part not found: ${partMatch[3]}`);
          }
          events.publish(session.info.directory, {
            type: 'message.part.updated',
            properties: {
              sessionID: session.info.id,
              part: updatedPart,
              time: Date.now(),
            },
          });
          return sendJson(res, 200, updatedPart);
        }
      }

      const promptAsyncMatch = /^\/session\/([^/]+)\/prompt_async$/.exec(pathname);
      if (req.method === 'POST' && promptAsyncMatch) {
        const session = state.getSession(promptAsyncMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${promptAsyncMatch[1]}`);
        }
        const body = await readJsonBody(req).catch(() => null);
        if (body === null || typeof body !== 'object' || !Array.isArray(body.parts) || body.parts.length === 0) {
          return sendBadRequest(res, 'Prompt body must include at least one part');
        }
        // Checked after the await so the guard is atomic with the synchronous
        // start(); concurrent prompts cannot both pass it.
        if (runner.isBusy(session.info.id)) {
          return sendBadRequest(res, 'Session is already busy');
        }
        runner.start(session, body);
        return sendNoContent(res);
      }

      const commandMatch = /^\/session\/([^/]+)\/command$/.exec(pathname);
      if (req.method === 'POST' && commandMatch) {
        const session = state.getSession(commandMatch[1]);
        if (!session) {
          return sendNotFound(res, `Session not found: ${commandMatch[1]}`);
        }
        return sendBadRequest(res, 'The Claude bridge does not implement OpenCode command routing yet. Use prompt_async instead.');
      }

      const permissionReplyMatch = /^\/permission\/([^/]+)\/reply$/.exec(pathname);
      if (req.method === 'POST' && permissionReplyMatch) {
        return sendJson(res, 200, false);
      }

      const questionReplyMatch = /^\/question\/([^/]+)\/reply$/.exec(pathname);
      if (req.method === 'POST' && questionReplyMatch) {
        return sendJson(res, 200, false);
      }

      const questionRejectMatch = /^\/question\/([^/]+)\/reject$/.exec(pathname);
      if (req.method === 'POST' && questionRejectMatch) {
        return sendJson(res, 200, false);
      }

      if (req.method === 'POST' && pathname === '/instance/dispose') {
        return sendJson(res, 200, true);
      }

      return sendNotFound(res);
    } catch (error) {
      console.error('[openchamber-claude-bridge] request failed:', error);
      return sendJson(res, 500, {
        name: 'UnknownError',
        data: {
          message: error instanceof Error ? error.message : String(error),
        },
      });
    }
  });

  return server;
}

function main() {
  let parsed;
  try {
    parsed = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    printHelp();
    process.exit(1);
  }

  if (parsed.options.help || parsed.command !== 'serve') {
    printHelp();
    process.exit(parsed.options.help ? 0 : 1);
  }

  const server = createServer(parsed.options);
  server.listen(parsed.options.port, parsed.options.host, () => {
    console.log(`openchamber-claude-bridge listening on http://${parsed.options.host}:${parsed.options.port}`);
  });
}

main();
