#!/usr/bin/env node

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

const MUX_VERSION = '0.1.0';
const DEFAULT_HOST = '127.0.0.1';
const DEFAULT_PORT = 4096;
const DEFAULT_DATA_DIR = path.join(os.homedir(), '.local', 'share', 'openchamber-backend-mux');
const DEFAULT_OPENCODE_BIN = process.env.OPENCHAMBER_BACKEND_MUX_OPENCODE_BINARY || process.env.OPENCODE_BINARY || 'opencode';
const DEFAULT_CLAUDE_BRIDGE_BIN = process.env.OPENCHAMBER_CLAUDE_BRIDGE_BINARY || 'openchamber-claude-bridge';
const BACKEND_OPENCODE = 'opencode';
const BACKEND_CLAUDE = 'claude-code';
const SESSION_BINDINGS_FILE = 'session-bindings.json';

function printHelp() {
  console.log(`openchamber-backend-mux ${MUX_VERSION}

Usage:
  openchamber-backend-mux serve [--host HOST] [--port PORT] [--data-dir PATH]

Environment:
  OPENCHAMBER_BACKEND_MUX_OPENCODE_BINARY   OpenCode executable path
  OPENCHAMBER_CLAUDE_BRIDGE_BINARY          Claude bridge executable path
  OPENCHAMBER_BACKEND_MUX_DATA_DIR          Persistent state directory
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
    dataDir: process.env.OPENCHAMBER_BACKEND_MUX_DATA_DIR || DEFAULT_DATA_DIR,
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

function sendJson(res, statusCode, payload, extraHeaders = {}) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    ...extraHeaders,
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

function hasRequestBody(method) {
  return method !== 'GET' && method !== 'HEAD';
}

function normalizeSessionSortTime(session) {
  if (typeof session?.time?.updated === 'number') return session.time.updated;
  if (typeof session?.info?.time?.updated === 'number') return session.info.time.updated;
  if (typeof session?.time_updated === 'number') return session.time_updated;
  return 0;
}

function mergeByKey(items, getKey) {
  const map = new Map();
  for (const item of items) {
    const key = getKey(item);
    if (!key || map.has(key)) continue;
    map.set(key, item);
  }
  return Array.from(map.values());
}

function providerEntryKey(entry) {
  if (typeof entry === 'string') {
    const trimmed = entry.trim();
    return trimmed.length > 0 ? trimmed : '';
  }
  if (!entry || typeof entry !== 'object') {
    return '';
  }
  for (const candidate of [entry.id, entry.providerID, entry.slug, entry.name]) {
    if (typeof candidate === 'string') {
      const trimmed = candidate.trim();
      if (trimmed.length > 0) {
        return trimmed;
      }
    }
  }
  return '';
}

function isArchivedSession(session) {
  const archivedAt = session?.time?.archived
    ?? session?.info?.time?.archived
    ?? session?.time_archived;
  return typeof archivedAt === 'number' && archivedAt > 0;
}

function parsePositiveInteger(value) {
  const parsed = Number.parseInt(value || '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function buildSessionQuery(requestUrl, { includeLimit = false } = {}) {
  const params = new URLSearchParams();
  for (const key of ['directory', 'roots', 'start', 'search']) {
    const value = requestUrl.searchParams.get(key);
    if (value !== null) {
      params.set(key, value);
    }
  }
  if (includeLimit) {
    const value = requestUrl.searchParams.get('limit');
    if (value !== null) {
      params.set('limit', value);
    }
  }
  const query = params.toString();
  return query ? `?${query}` : '';
}

async function allocatePort(host) {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on('error', reject);
    server.listen(0, host, () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : 0;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(port);
      });
    });
  });
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      accept: 'application/json',
      ...(options.headers || {}),
    },
  });
  const data = await response.json().catch(() => null);
  return { response, data };
}

// Like fetchJson, but a dead backend degrades to empty data instead of
// rejecting the whole merged request.
async function fetchJsonSafe(url, options = {}) {
  try {
    return await fetchJson(url, options);
  } catch (error) {
    console.warn(`[openchamber-backend-mux] backend request failed (${url}):`, error?.message || error);
    return { response: null, data: null };
  }
}

async function waitForPort(host, port, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      await new Promise((resolve, reject) => {
        const socket = net.connect({ host, port });
        socket.once('connect', () => {
          socket.destroy();
          resolve(true);
        });
        socket.once('error', (error) => {
          socket.destroy();
          reject(error);
        });
        socket.setTimeout(500, () => {
          socket.destroy();
          reject(new Error('timeout'));
        });
      });
      return true;
    } catch {
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  return false;
}

function copyResponseHeaders(source, res) {
  for (const [key, value] of source.headers.entries()) {
    if (key.toLowerCase() === 'content-length') {
      continue;
    }
    res.setHeader(key, value);
  }
}

function buildForwardHeaders(req, extra = {}, options = {}) {
  const headers = { ...req.headers, ...extra };
  delete headers.host;
  if (options.stripContentLength) {
    delete headers['content-length'];
  }
  return headers;
}

class BindingStore {
  constructor(dataDir) {
    this.filePath = path.join(dataDir, SESSION_BINDINGS_FILE);
    this.sessionBindings = new Map();
    this.load();
  }

  load() {
    try {
      if (!fs.existsSync(this.filePath)) return;
      const parsed = JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
      const bindings = Array.isArray(parsed?.sessionBindings) ? parsed.sessionBindings : [];
      for (const entry of bindings) {
        if (!entry || typeof entry.id !== 'string' || typeof entry.backend !== 'string') continue;
        this.sessionBindings.set(entry.id, entry.backend);
      }
    } catch (error) {
      console.warn('[openchamber-backend-mux] failed to load bindings:', error?.message || error);
    }
  }

  save() {
    const payload = {
      sessionBindings: Array.from(this.sessionBindings.entries()).map(([id, backend]) => ({ id, backend })),
    };
    const tempPath = `${this.filePath}.tmp`;
    ensureDir(path.dirname(this.filePath));
    fs.writeFileSync(tempPath, JSON.stringify(payload, null, 2));
    fs.renameSync(tempPath, this.filePath);
  }

  setSession(id, backend) {
    this.sessionBindings.set(id, backend);
    this.save();
  }

  deleteSession(id) {
    if (this.sessionBindings.delete(id)) {
      this.save();
    }
  }

  getSessionBackend(id) {
    return this.sessionBindings.get(id) || null;
  }

  replaceAll(nextBindings) {
    this.sessionBindings = nextBindings;
    this.save();
  }
}

class BackendMux {
  constructor(options) {
    this.host = options.host;
    this.port = options.port;
    this.dataDir = options.dataDir;
    this.bindingStore = new BindingStore(options.dataDir);
    this.backends = new Map();
    this.server = null;
    this.closing = false;
  }

  async start() {
    try {
      ensureDir(this.dataDir);
      const opencodePort = await allocatePort(this.host);
      const claudePort = await allocatePort(this.host);

      this.backends.set(BACKEND_OPENCODE, await this.startBackend({
        kind: BACKEND_OPENCODE,
        binary: DEFAULT_OPENCODE_BIN,
        args: ['serve', '--hostname', this.host, '--port', String(opencodePort)],
        port: opencodePort,
      }));
      this.backends.set(BACKEND_CLAUDE, await this.startBackend({
        kind: BACKEND_CLAUDE,
        binary: DEFAULT_CLAUDE_BRIDGE_BIN,
        args: ['serve', '--host', this.host, '--port', String(claudePort)],
        port: claudePort,
      }));

      await this.rebuildSessionBindings();

      this.server = http.createServer((req, res) => {
        void this.handleRequest(req, res).catch((error) => {
          console.error('[openchamber-backend-mux] request failed:', error);
          if (!res.headersSent) {
            sendJson(res, 500, { error: error instanceof Error ? error.message : String(error) });
          } else {
            res.end();
          }
        });
      });

      await new Promise((resolve, reject) => {
        this.server.on('error', reject);
        this.server.listen(this.port, this.host, resolve);
      });
    } catch (error) {
      await this.close();
      throw error;
    }

    const shutdown = async () => {
      await this.close();
      process.exit(0);
    };
    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);

    console.log(`openchamber-backend-mux listening on http://${this.host}:${this.port}`);
  }

  async close() {
    this.closing = true;
    // Kill the children first: server.close() waits for in-flight requests,
    // and a held SSE connection would otherwise block shutdown forever.
    for (const backend of this.backends.values()) {
      backend.child.kill('SIGTERM');
    }
    if (this.server) {
      this.server.closeAllConnections?.();
      await new Promise((resolve) => this.server.close(() => resolve()));
      this.server = null;
    }
  }

  async startBackend(spec) {
    const child = spawn(spec.binary, spec.args, {
      cwd: process.cwd(),
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });

    let output = '';
    child.stdout?.on('data', (chunk) => {
      output += chunk.toString();
    });
    child.stderr?.on('data', (chunk) => {
      output += chunk.toString();
    });

    const origin = `http://${this.host}:${spec.port}`;
    const healthy = await Promise.race([
      waitForPort(this.host, spec.port, 30000),
      new Promise((_, reject) => {
        child.once('exit', (code) => {
          reject(new Error(`${spec.kind} backend exited with code ${code}. Output: ${output}`));
        });
        child.once('error', reject);
      }),
    ]);

    if (!healthy) {
      child.kill('SIGTERM');
      throw new Error(`Timed out waiting for ${spec.kind} backend. Output: ${output}`);
    }

    // After startup, a dead child means the mux can no longer honestly report
    // healthy; exit so the OpenChamber lifecycle restarts the whole pair.
    child.on('exit', (code, signal) => {
      if (this.closing) {
        return;
      }
      console.error(`[openchamber-backend-mux] ${spec.kind} backend exited (code=${code} signal=${signal}); shutting down mux for lifecycle restart`);
      for (const other of this.backends.values()) {
        if (other.child !== child) {
          other.child.kill('SIGTERM');
        }
      }
      process.exit(1);
    });

    return { ...spec, child, origin };
  }

  getBackend(kind) {
    const backend = this.backends.get(kind);
    if (!backend) {
      throw new Error(`Unknown backend: ${kind}`);
    }
    return backend;
  }

  async listSessionsFor(kind, query = '') {
    const backend = this.getBackend(kind);
    const { data } = await fetchJsonSafe(new URL(`/session${query}`, backend.origin).toString());
    const sessions = Array.isArray(data) ? data : [];
    let changed = false;
    for (const session of sessions) {
      if (typeof session?.id === 'string' && this.bindingStore.sessionBindings.get(session.id) !== kind) {
        this.bindingStore.sessionBindings.set(session.id, kind);
        changed = true;
      }
    }
    if (changed) {
      this.bindingStore.save();
    }
    return sessions;
  }

  async rebuildSessionBindings() {
    const nextBindings = new Map();
    for (const kind of [BACKEND_OPENCODE, BACKEND_CLAUDE]) {
      const backend = this.getBackend(kind);
      const { data } = await fetchJson(`${backend.origin}/session`);
      const sessions = Array.isArray(data) ? data : [];
      for (const session of sessions) {
        if (typeof session?.id === 'string') {
          nextBindings.set(session.id, kind);
        }
      }
    }
    this.bindingStore.replaceAll(nextBindings);
  }

  chooseBackendFromModel(body) {
    const providerId = typeof body?.model?.providerID === 'string'
      ? body.model.providerID
      : typeof body?.providerID === 'string'
        ? body.providerID
        : typeof body?.backend === 'string'
          ? body.backend
          : '';
    return providerId === BACKEND_CLAUDE ? BACKEND_CLAUDE : BACKEND_OPENCODE;
  }

  async resolveSessionBackend(sessionId, fallbackBody) {
    const cached = this.bindingStore.getSessionBackend(sessionId);
    if (cached) return cached;

    for (const kind of [BACKEND_OPENCODE, BACKEND_CLAUDE]) {
      const backend = this.getBackend(kind);
      try {
        const { response } = await fetchJson(`${backend.origin}/session/${encodeURIComponent(sessionId)}`);
        if (response.ok) {
          this.bindingStore.setSession(sessionId, kind);
          return kind;
        }
      } catch {
      }
    }

    return fallbackBody ? this.chooseBackendFromModel(fallbackBody) : null;
  }

  async mergeProviders() {
    const [openCodeResult, claudeResult] = await Promise.all([
      fetchJsonSafe(`${this.getBackend(BACKEND_OPENCODE).origin}/provider`),
      fetchJsonSafe(`${this.getBackend(BACKEND_CLAUDE).origin}/provider`),
    ]);
    const all = mergeByKey(
      [
        ...(Array.isArray(openCodeResult.data?.all) ? openCodeResult.data.all : []),
        ...(Array.isArray(claudeResult.data?.all) ? claudeResult.data.all : []),
      ],
      providerEntryKey,
    );
    return {
      all,
      default: {
        ...(openCodeResult.data?.default || {}),
        ...(claudeResult.data?.default || {}),
      },
      connected: mergeByKey(
        [
          ...(Array.isArray(openCodeResult.data?.connected) ? openCodeResult.data.connected : []),
          ...(Array.isArray(claudeResult.data?.connected) ? claudeResult.data.connected : []),
        ],
        (id) => id,
      ),
    };
  }

  async mergeConfigProviders() {
    const [openCodeResult, claudeResult] = await Promise.all([
      fetchJsonSafe(`${this.getBackend(BACKEND_OPENCODE).origin}/config/providers`),
      fetchJsonSafe(`${this.getBackend(BACKEND_CLAUDE).origin}/config/providers`),
    ]);
    return {
      providers: mergeByKey(
        [
          ...(Array.isArray(openCodeResult.data?.providers) ? openCodeResult.data.providers : []),
          ...(Array.isArray(claudeResult.data?.providers) ? claudeResult.data.providers : []),
        ],
        providerEntryKey,
      ),
      default: {
        ...(openCodeResult.data?.default || {}),
        ...(claudeResult.data?.default || {}),
      },
    };
  }

  async listExperimentalSessions(requestUrl) {
    const archived = requestUrl.searchParams.get('archived') === 'true';
    const cursor = parsePositiveInteger(requestUrl.searchParams.get('cursor')) || 0;
    const limit = parsePositiveInteger(requestUrl.searchParams.get('limit'));
    const query = buildSessionQuery(requestUrl);
    const sessions = await this.listMergedSessions(query);
    const filtered = sessions.filter((session) => isArchivedSession(session) === archived);

    if (!limit) {
      return { sessions: filtered, nextCursor: null };
    }

    const page = filtered.slice(cursor, cursor + limit);
    const nextCursor = cursor + limit < filtered.length ? cursor + limit : null;
    return { sessions: page, nextCursor };
  }

  async listMergedSessions(query = '') {
    const [openCodeSessions, claudeSessions] = await Promise.all([
      this.listSessionsFor(BACKEND_OPENCODE, query),
      this.listSessionsFor(BACKEND_CLAUDE, query),
    ]);
    const sessions = mergeByKey([...openCodeSessions, ...claudeSessions], (session) => session?.id);
    sessions.sort((left, right) => normalizeSessionSortTime(right) - normalizeSessionSortTime(left));
    return sessions;
  }

  async mergeModels() {
    const [openCodeResult, claudeResult] = await Promise.all([
      fetchJsonSafe(`${this.getBackend(BACKEND_OPENCODE).origin}/model`),
      fetchJsonSafe(`${this.getBackend(BACKEND_CLAUDE).origin}/model`),
    ]);
    return mergeByKey(
      [
        ...(Array.isArray(openCodeResult.data) ? openCodeResult.data : []),
        ...(Array.isArray(claudeResult.data) ? claudeResult.data : []),
      ],
      (model) => `${model?.providerID || ''}/${model?.id || ''}`,
    );
  }

  async mergeAgents() {
    const [openCodeResult, claudeResult] = await Promise.all([
      fetchJsonSafe(`${this.getBackend(BACKEND_OPENCODE).origin}/agent`),
      fetchJsonSafe(`${this.getBackend(BACKEND_CLAUDE).origin}/agent`),
    ]);
    return mergeByKey(
      [
        ...(Array.isArray(openCodeResult.data) ? openCodeResult.data : []),
        ...(Array.isArray(claudeResult.data) ? claudeResult.data : []),
      ],
      (agent) => agent?.name,
    );
  }

  async mergeStatuses(pathname, requestUrl) {
    const merged = {};
    for (const kind of [BACKEND_OPENCODE, BACKEND_CLAUDE]) {
      const backend = this.getBackend(kind);
      const { data } = await fetchJsonSafe(new URL(`${pathname}${requestUrl.search}`, backend.origin).toString());
      if (data && typeof data === 'object') {
        Object.assign(merged, data);
      }
    }
    return merged;
  }

  async mergeSimpleLists(pathname) {
    const [openCodeResult, claudeResult] = await Promise.all([
      fetchJsonSafe(`${this.getBackend(BACKEND_OPENCODE).origin}${pathname}`),
      fetchJsonSafe(`${this.getBackend(BACKEND_CLAUDE).origin}${pathname}`),
    ]);
    return mergeByKey(
      [
        ...(Array.isArray(openCodeResult.data) ? openCodeResult.data : []),
        ...(Array.isArray(claudeResult.data) ? claudeResult.data : []),
      ],
      (entry) => (typeof entry === 'string' ? entry : entry?.id || entry?.name),
    );
  }

  async proxyJson(req, res, backendKind, pathname, requestUrl, bodyBuffer, onJson) {
    const backend = this.getBackend(backendKind);
    const response = await fetch(new URL(`${pathname}${requestUrl.search}`, backend.origin).toString(), {
      method: req.method,
      headers: buildForwardHeaders(req, {}, { stripContentLength: true }),
      body: hasRequestBody(req.method) ? bodyBuffer : undefined,
    });
    const text = await response.text();
    let payload = null;
    try {
      payload = text ? JSON.parse(text) : null;
    } catch {
    }
    if (onJson) {
      await onJson(payload, response);
    }
    res.statusCode = response.status;
    copyResponseHeaders(response, res);
    res.end(text);
  }

  async proxyRequest(req, res, backendKind, pathname, requestUrl) {
    const backend = this.getBackend(backendKind);
    const response = await fetch(new URL(`${pathname}${requestUrl.search}`, backend.origin).toString(), {
      method: req.method,
      headers: buildForwardHeaders(req),
      body: hasRequestBody(req.method) ? req : undefined,
      duplex: hasRequestBody(req.method) ? 'half' : undefined,
    });

    res.statusCode = response.status;
    copyResponseHeaders(response, res);
    if (!response.body) {
      res.end();
      return;
    }
    for await (const chunk of response.body) {
      res.write(chunk);
    }
    res.end();
  }

  async proxyBufferedRequest(req, res, backendKind, pathname, requestUrl, bodyBuffer) {
    const backend = this.getBackend(backendKind);
    const response = await fetch(new URL(`${pathname}${requestUrl.search}`, backend.origin).toString(), {
      method: req.method,
      headers: buildForwardHeaders(req, {}, { stripContentLength: true }),
      body: bodyBuffer,
    });

    res.statusCode = response.status;
    copyResponseHeaders(response, res);
    if (!response.body) {
      const text = await response.text().catch(() => '');
      res.end(text);
      return;
    }
    for await (const chunk of response.body) {
      res.write(chunk);
    }
    res.end();
  }

  async handleMergedSse(req, res, pathname, requestUrl) {
    const abortController = new AbortController();
    req.on('close', () => abortController.abort());

    res.writeHead(200, {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
    });
    res.write(': connected\n\n');

    const forwardStream = async (backendKind) => {
      const backend = this.getBackend(backendKind);
      const response = await fetch(new URL(`${pathname}${requestUrl.search}`, backend.origin).toString(), {
        headers: buildForwardHeaders(req, { accept: 'text/event-stream', 'cache-control': 'no-cache' }),
        signal: abortController.signal,
      });
      if (!response.ok || !response.body) {
        throw new Error(`${backendKind} SSE unavailable (${response.status})`);
      }

      const decoder = new TextDecoder();
      let buffer = '';
      for await (const chunk of response.body) {
        if (abortController.signal.aborted) break;
        buffer += decoder.decode(chunk, { stream: true }).replace(/\r\n/g, '\n');
        let separatorIndex = buffer.indexOf('\n\n');
        while (separatorIndex !== -1) {
          const block = buffer.slice(0, separatorIndex);
          buffer = buffer.slice(separatorIndex + 2);
          if (block.trim().length > 0) {
            res.write(`${block}\n\n`);
          }
          separatorIndex = buffer.indexOf('\n\n');
        }
      }
      if (buffer.trim().length > 0 && !abortController.signal.aborted) {
        res.write(`${buffer.trim()}\n\n`);
      }
    };

    // allSettled keeps the merged stream alive while at least one backend
    // stream is healthy; res only ends once both settle or the client aborts.
    const results = await Promise.allSettled([
      forwardStream(BACKEND_OPENCODE),
      forwardStream(BACKEND_CLAUDE),
    ]);
    if (!abortController.signal.aborted) {
      for (const result of results) {
        if (result.status === 'rejected') {
          console.warn('[openchamber-backend-mux] SSE merge failed:', result.reason?.message || result.reason);
        }
      }
    }
    res.end();
  }

  async handleSessionCreate(req, res, requestUrl) {
    const body = await readJsonBody(req).catch(() => null);
    if (body === null) {
      sendJson(res, 400, { error: 'Invalid JSON body' });
      return;
    }
    const backendKind = this.chooseBackendFromModel(body);
    const backend = this.getBackend(backendKind);
    const payload = {
      parentID: body?.parentID,
      title: body?.title,
      permission: body?.permission,
      workspaceID: body?.workspaceID,
      model: body?.model,
      variant: body?.variant,
      agent: body?.agent,
    };
    const { response, data } = await fetchJson(new URL(`/session${requestUrl.search}`, backend.origin).toString(), {
      method: 'POST',
      headers: buildForwardHeaders(req, { 'content-type': 'application/json' }, { stripContentLength: true }),
      body: JSON.stringify(payload),
    });
    if (response.ok && typeof data?.id === 'string') {
      this.bindingStore.setSession(data.id, backendKind);
    }
    sendJson(res, response.status, data);
  }

  async handleSessionList(res, requestUrl) {
    const sessions = await this.listMergedSessions(buildSessionQuery(requestUrl, { includeLimit: true }));
    // Each backend already applied the limit; re-apply it to the merged list
    // so the response never exceeds the requested count.
    const limit = parsePositiveInteger(requestUrl.searchParams.get('limit'));
    sendJson(res, 200, limit ? sessions.slice(0, limit) : sessions);
  }

  async handleExperimentalSessionList(res, requestUrl) {
    const { sessions, nextCursor } = await this.listExperimentalSessions(requestUrl);
    sendJson(res, 200, sessions, nextCursor !== null ? { 'x-next-cursor': String(nextCursor) } : {});
  }

  async handleRequest(req, res) {
    const requestUrl = new URL(typeof req.url === 'string' ? req.url : '/', 'http://127.0.0.1');
    const pathname = requestUrl.pathname;

    if (req.method === 'GET' && (pathname === '/health' || pathname === '/global/health')) {
      sendJson(res, 200, {
        healthy: true,
        version: `${MUX_VERSION}+mixed`,
        backends: {
          opencode: this.getBackend(BACKEND_OPENCODE).origin,
          claude: this.getBackend(BACKEND_CLAUDE).origin,
        },
      });
      return;
    }

    if (req.method === 'GET' && pathname === '/provider') {
      sendJson(res, 200, await this.mergeProviders());
      return;
    }

    if (req.method === 'GET' && pathname === '/config/providers') {
      sendJson(res, 200, await this.mergeConfigProviders());
      return;
    }

    if (req.method === 'GET' && pathname === '/model') {
      sendJson(res, 200, await this.mergeModels());
      return;
    }

    if (req.method === 'GET' && pathname === '/agent') {
      sendJson(res, 200, await this.mergeAgents());
      return;
    }

    if (req.method === 'GET' && pathname === '/experimental/tool/ids') {
      sendJson(res, 200, await this.mergeSimpleLists('/experimental/tool/ids'));
      return;
    }

    if (req.method === 'GET' && pathname === '/experimental/session') {
      await this.handleExperimentalSessionList(res, requestUrl);
      return;
    }

    if (req.method === 'GET' && pathname === '/permission') {
      sendJson(res, 200, await this.mergeSimpleLists('/permission'));
      return;
    }

    if (req.method === 'GET' && pathname === '/question') {
      sendJson(res, 200, await this.mergeSimpleLists('/question'));
      return;
    }

    if (req.method === 'POST' && pathname === '/session') {
      await this.handleSessionCreate(req, res, requestUrl);
      return;
    }

    if (req.method === 'GET' && pathname === '/session') {
      await this.handleSessionList(res, requestUrl);
      return;
    }

    if (req.method === 'GET' && pathname === '/session/status') {
      sendJson(res, 200, await this.mergeStatuses(pathname, requestUrl));
      return;
    }

    if (req.method === 'GET' && (pathname === '/global/event' || pathname === '/event')) {
      await this.handleMergedSse(req, res, pathname, requestUrl);
      return;
    }

    const forkMatch = /^\/session\/([^/]+)\/fork$/.exec(pathname);
    if (forkMatch) {
      const backendKind = await this.resolveSessionBackend(forkMatch[1]);
      if (!backendKind) {
        sendJson(res, 404, { error: `Session not found: ${forkMatch[1]}` });
        return;
      }
      const bodyBuffer = hasRequestBody(req.method) ? await new Response(req).arrayBuffer() : null;
      await this.proxyJson(req, res, backendKind, pathname, requestUrl, bodyBuffer, async (payload, response) => {
        if (response.ok && typeof payload?.id === 'string') {
          this.bindingStore.setSession(payload.id, backendKind);
        }
      });
      return;
    }

    const sessionMatch = /^\/session\/([^/]+)(?:\/.*)?$/.exec(pathname);
    if (sessionMatch) {
      const bodyBuffer = hasRequestBody(req.method) ? Buffer.from(await new Response(req).arrayBuffer()) : null;
      let fallbackBody;
      if (bodyBuffer && bodyBuffer.length > 0) {
        try {
          fallbackBody = JSON.parse(bodyBuffer.toString('utf8'));
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON body' });
          return;
        }
      }
      const backendKind = await this.resolveSessionBackend(sessionMatch[1], fallbackBody);
      if (!backendKind) {
        sendJson(res, 404, { error: `Session not found: ${sessionMatch[1]}` });
        return;
      }
      if (req.method === 'DELETE' && pathname === `/session/${sessionMatch[1]}`) {
        await this.proxyJson(req, res, backendKind, pathname, requestUrl, bodyBuffer, async (_payload, response) => {
          if (response.ok) {
            this.bindingStore.deleteSession(sessionMatch[1]);
          }
        });
        return;
      }
      if (bodyBuffer) {
        await this.proxyBufferedRequest(req, res, backendKind, pathname, requestUrl, bodyBuffer);
        return;
      }
      await this.proxyRequest(req, res, backendKind, pathname, requestUrl);
      return;
    }

    const permissionReplyMatch = /^\/permission\/([^/]+)\/reply$/.exec(pathname);
    if (permissionReplyMatch) {
      const bodyBuffer = hasRequestBody(req.method) ? await new Response(req).arrayBuffer() : null;
      for (const backendKind of [BACKEND_OPENCODE, BACKEND_CLAUDE]) {
        const backend = this.getBackend(backendKind);
        const response = await fetch(new URL(`${pathname}${requestUrl.search}`, backend.origin).toString(), {
          method: req.method,
          headers: buildForwardHeaders(req, {}, { stripContentLength: true }),
          body: bodyBuffer,
        });
        const text = await response.text();
        if (response.ok && text !== 'false') {
          res.statusCode = response.status;
          copyResponseHeaders(response, res);
          res.end(text);
          return;
        }
      }
      sendJson(res, 404, { error: `Permission request not found: ${permissionReplyMatch[1]}` });
      return;
    }

    const questionReplyMatch = /^\/question\/([^/]+)\/(reply|reject)$/.exec(pathname);
    if (questionReplyMatch) {
      const bodyBuffer = hasRequestBody(req.method) ? await new Response(req).arrayBuffer() : null;
      for (const backendKind of [BACKEND_OPENCODE, BACKEND_CLAUDE]) {
        const backend = this.getBackend(backendKind);
        const response = await fetch(new URL(`${pathname}${requestUrl.search}`, backend.origin).toString(), {
          method: req.method,
          headers: buildForwardHeaders(req, {}, { stripContentLength: true }),
          body: bodyBuffer,
        });
        const text = await response.text();
        if (response.ok && text !== 'false') {
          res.statusCode = response.status;
          copyResponseHeaders(response, res);
          res.end(text);
          return;
        }
      }
      sendJson(res, 404, { error: `Question request not found: ${questionReplyMatch[1]}` });
      return;
    }

    await this.proxyRequest(req, res, BACKEND_OPENCODE, pathname, requestUrl);
  }
}

async function main() {
  const parsed = parseArgs(process.argv.slice(2));
  if (parsed.options.help || parsed.command === 'help') {
    printHelp();
    return;
  }
  if (parsed.command !== 'serve') {
    throw new Error(`Unsupported command: ${parsed.command}`);
  }
  const mux = new BackendMux(parsed.options);
  await mux.start();
}

const isDirectExecution = typeof process.argv[1] === 'string'
  && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;

if (isDirectExecution) {
  main().catch((error) => {
    console.error('[openchamber-backend-mux] fatal:', error);
    process.exit(1);
  });
}

export {
  BackendMux,
  buildSessionQuery,
  isArchivedSession,
  parsePositiveInteger,
  providerEntryKey,
};
