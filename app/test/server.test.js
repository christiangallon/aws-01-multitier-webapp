'use strict';

/**
 * Smoke tests using only Node's built-in test runner and fetch.
 *
 *   npm test                              # no database needed
 *   TEST_DB=1 DB_HOST=... npm test        # also runs CRUD tests against MySQL
 */
const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');

if (!process.env.TEST_DB) {
  // Point at a closed port so DB calls fail fast and deterministically.
  process.env.DB_HOST = '127.0.0.1';
  process.env.DB_PORT = '1';
}

const { start } = require('../src/server');
const db = require('../src/db');

let server;
let baseUrl;

before(async () => {
  server = start(0);
  await new Promise((resolve) => server.once('listening', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
  await db.close();
});

describe('without database dependency', () => {
  test('GET /health returns 200 with JSON status', async () => {
    const res = await fetch(`${baseUrl}/health`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.status, 'ok');
    assert.ok(['up', 'down'].includes(body.db));
    assert.ok(res.headers.get('x-request-id'));
  });

  test('GET /api/items/:id rejects non-UUID ids', async () => {
    const res = await fetch(`${baseUrl}/api/items/not-a-uuid`);
    assert.equal(res.status, 400);
  });

  test('POST /api/items validates the body', async () => {
    const res = await fetch(`${baseUrl}/api/items`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ description: 'missing name' }),
    });
    assert.equal(res.status, 400);
    const body = await res.json();
    assert.match(body.error, /name/);
  });

  test('malformed JSON returns 400', async () => {
    const res = await fetch(`${baseUrl}/api/items`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{bad json',
    });
    assert.equal(res.status, 400);
  });

  test('unknown routes return 404 JSON', async () => {
    const res = await fetch(`${baseUrl}/does-not-exist`);
    assert.equal(res.status, 404);
  });

  test('static UI is served at /', async () => {
    const res = await fetch(`${baseUrl}/`);
    assert.equal(res.status, 200);
    assert.match(await res.text(), /AWS Multi-Tier Web App/);
  });
});

if (!process.env.TEST_DB) {
  test('GET /ready returns 503 when the database is unreachable', async () => {
    const res = await fetch(`${baseUrl}/ready`);
    assert.equal(res.status, 503);
  });
}

describe('CRUD against MySQL', { skip: !process.env.TEST_DB }, () => {
  before(async () => {
    const { migrate } = require('../scripts/migrate');
    await migrate();
  });

  test('create, read, update, list and delete an item', async () => {
    const json = { 'Content-Type': 'application/json' };

    let res = await fetch(`${baseUrl}/api/items`, {
      method: 'POST',
      headers: json,
      body: JSON.stringify({ name: 'test item', description: 'created by test' }),
    });
    assert.equal(res.status, 201);
    const { data: created } = await res.json();
    assert.equal(created.name, 'test item');

    res = await fetch(`${baseUrl}/api/items/${created.id}`);
    assert.equal(res.status, 200);

    res = await fetch(`${baseUrl}/api/items/${created.id}`, {
      method: 'PUT',
      headers: json,
      body: JSON.stringify({ name: 'renamed' }),
    });
    assert.equal(res.status, 200);
    assert.equal((await res.json()).data.name, 'renamed');

    res = await fetch(`${baseUrl}/api/items?limit=10`);
    assert.equal(res.status, 200);
    const list = await res.json();
    assert.ok(list.data.some((i) => i.id === created.id));

    res = await fetch(`${baseUrl}/api/items/${created.id}`, { method: 'DELETE' });
    assert.equal(res.status, 204);

    res = await fetch(`${baseUrl}/api/items/${created.id}`);
    assert.equal(res.status, 404);
  });

  test('GET /ready returns 200 when the database is reachable', async () => {
    const res = await fetch(`${baseUrl}/ready`);
    assert.equal(res.status, 200);
  });
});
