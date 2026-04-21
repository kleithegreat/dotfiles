import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { BackendMux } from './index.mjs';

function createJsonResponse(payload, headers = {}) {
  return new Response(JSON.stringify(payload), {
    status: 200,
    headers: {
      'content-type': 'application/json',
      ...headers,
    },
  });
}

function withMockedFetch(t, handler) {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = handler;
  t.after(() => {
    globalThis.fetch = originalFetch;
  });
}

function createMux(t) {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'openchamber-backend-mux-test-'));
  const mux = new BackendMux({ host: '127.0.0.1', port: 0, dataDir });
  mux.backends.set('opencode', { origin: 'http://opencode.test' });
  mux.backends.set('claude-code', { origin: 'http://claude.test' });
  t.after(() => {
    fs.rmSync(dataDir, { recursive: true, force: true });
  });
  return mux;
}

test('mergeProviders preserves plain-string OpenCode providers', async (t) => {
  const mux = createMux(t);
  withMockedFetch(t, async (url) => {
    if (url === 'http://opencode.test/provider') {
      return createJsonResponse({
        all: ['openai', 'anthropic'],
        default: { openai: 'gpt-5' },
        connected: ['openai'],
      });
    }
    if (url === 'http://claude.test/provider') {
      return createJsonResponse({
        all: [{ id: 'claude-code', name: 'Claude Code' }],
        default: { 'claude-code': 'sonnet' },
        connected: ['claude-code'],
      });
    }
    throw new Error(`Unexpected fetch: ${url}`);
  });

  const merged = await mux.mergeProviders();

  assert.deepEqual(merged.all, [
    'openai',
    'anthropic',
    { id: 'claude-code', name: 'Claude Code' },
  ]);
  assert.deepEqual(merged.connected, ['openai', 'claude-code']);
  assert.deepEqual(merged.default, {
    openai: 'gpt-5',
    'claude-code': 'sonnet',
  });
});

test('listExperimentalSessions merges, filters, and paginates sessions across backends', async (t) => {
  const mux = createMux(t);
  withMockedFetch(t, async (url) => {
    if (url === 'http://opencode.test/session') {
      return createJsonResponse([
        { id: 'open-active', title: 'Open active', directory: '/repo', time: { updated: 30 } },
        { id: 'open-archived', title: 'Open archived', directory: '/repo', time: { updated: 10, archived: 5 } },
      ]);
    }
    if (url === 'http://claude.test/session') {
      return createJsonResponse([
        { id: 'claude-active', title: 'Claude active', directory: '/repo', time: { updated: 40 } },
        { id: 'claude-older', title: 'Claude older', directory: '/repo', time: { updated: 20 } },
      ]);
    }
    throw new Error(`Unexpected fetch: ${url}`);
  });

  const activePage = await mux.listExperimentalSessions(new URL('http://mux.test/experimental/session?limit=2'));
  const archivedPage = await mux.listExperimentalSessions(new URL('http://mux.test/experimental/session?archived=true'));

  assert.deepEqual(activePage.sessions.map((session) => session.id), ['claude-active', 'open-active']);
  assert.equal(activePage.nextCursor, 2);
  assert.deepEqual(archivedPage.sessions.map((session) => session.id), ['open-archived']);
  assert.equal(archivedPage.nextCursor, null);
});
