import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { BridgeState, createServer } from './index.mjs';

async function startBridge(t) {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'openchamber-claude-bridge-'));
  const server = createServer({ host: '127.0.0.1', port: 0, dataDir });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(dataDir, { recursive: true, force: true });
  });

  const address = server.address();
  assert(address && typeof address === 'object');
  return { dataDir, origin: `http://127.0.0.1:${address.port}` };
}

async function createSession(origin, metadata) {
  const response = await fetch(`${origin}/session?directory=${encodeURIComponent('/repo')}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ title: 'Review', metadata }),
  });
  assert.equal(response.status, 200);
  return response.json();
}

const reviewMetadata = {
  openchamber: {
    review: true,
    originalSessionID: 'original-session',
  },
};

test('session creation returns the supplied metadata', async (t) => {
  const { origin } = await startBridge(t);
  const created = await createSession(origin, reviewMetadata);

  assert.deepEqual(created.metadata, reviewMetadata);
});

test('session PATCH replaces metadata and returns the updated session', async (t) => {
  const { origin } = await startBridge(t);
  const created = await createSession(origin, reviewMetadata);
  const patchedMetadata = {
    openchamber: {
      review: true,
      originalSessionID: 'original-session',
      reviewSessionID: created.id,
    },
  };
  const patchResponse = await fetch(`${origin}/session/${created.id}?directory=${encodeURIComponent('/repo')}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ metadata: patchedMetadata }),
  });
  assert.equal(patchResponse.status, 200);
  const patched = await patchResponse.json();
  assert.equal(patched.id, created.id);
  assert.deepEqual(patched.metadata, patchedMetadata);
});

test('patched session metadata survives state reload', async (t) => {
  const { dataDir, origin } = await startBridge(t);
  const created = await createSession(origin, reviewMetadata);
  const patchedMetadata = {
    openchamber: {
      review: true,
      originalSessionID: 'original-session',
      reviewSessionID: created.id,
    },
  };
  const patchResponse = await fetch(`${origin}/session/${created.id}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ metadata: patchedMetadata }),
  });
  assert.equal(patchResponse.status, 200);

  const reloaded = new BridgeState(dataDir).getSession(created.id);
  assert.deepEqual(reloaded?.info.metadata, patchedMetadata);
});
