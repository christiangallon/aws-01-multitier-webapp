'use strict';

/**
 * CRUD routes for the `items` table.
 *
 *   GET    /api/items        list items (newest first, ?limit=&offset=)
 *   POST   /api/items        create   { name, description? }
 *   GET    /api/items/:id    fetch one
 *   PUT    /api/items/:id    update   { name?, description? }
 *   DELETE /api/items/:id    delete
 */
const express = require('express');
const { v4: uuidv4, validate: uuidValidate } = require('uuid');
const db = require('../db');

const router = express.Router();

const NAME_MAX = 255;
const DESCRIPTION_MAX = 10000;

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// Express 4 does not catch rejected promises; forward them to the error handler.
const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function validateId(req, res, next) {
  if (!uuidValidate(req.params.id)) {
    return next(new HttpError(400, 'id must be a valid UUID'));
  }
  return next();
}

function parseItemBody(body, { partial = false } = {}) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new HttpError(400, 'Request body must be a JSON object');
  }

  const result = {};

  if (body.name !== undefined || !partial) {
    if (typeof body.name !== 'string' || body.name.trim() === '') {
      throw new HttpError(400, 'name is required and must be a non-empty string');
    }
    if (body.name.length > NAME_MAX) {
      throw new HttpError(400, `name must be at most ${NAME_MAX} characters`);
    }
    result.name = body.name.trim();
  }

  if (body.description !== undefined && body.description !== null) {
    if (typeof body.description !== 'string') {
      throw new HttpError(400, 'description must be a string');
    }
    if (body.description.length > DESCRIPTION_MAX) {
      throw new HttpError(400, `description must be at most ${DESCRIPTION_MAX} characters`);
    }
    result.description = body.description;
  } else if (body.description === null) {
    result.description = null;
  }

  if (partial && Object.keys(result).length === 0) {
    throw new HttpError(400, 'Provide at least one of: name, description');
  }

  return result;
}

function clampInt(value, fallback, min, max) {
  const n = Number.parseInt(value, 10);
  if (Number.isNaN(n)) return fallback;
  return Math.min(Math.max(n, min), max);
}

async function findItem(id) {
  const rows = await db.query(
    'SELECT id, name, description, created_at, updated_at FROM items WHERE id = ?',
    [id]
  );
  return rows[0] || null;
}

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const limit = clampInt(req.query.limit, 100, 1, 500);
    const offset = clampInt(req.query.offset, 0, 0, Number.MAX_SAFE_INTEGER);
    // LIMIT/OFFSET are validated integers; inline them because prepared
    // statements in MySQL 8.0.22+ reject string-typed LIMIT parameters.
    const rows = await db.query(
      `SELECT id, name, description, created_at, updated_at
         FROM items
        ORDER BY created_at DESC, id
        LIMIT ${limit} OFFSET ${offset}`
    );
    res.json({ data: rows, count: rows.length, limit, offset });
  })
);

router.post(
  '/',
  asyncHandler(async (req, res) => {
    const item = parseItemBody(req.body);
    const id = uuidv4();
    await db.query('INSERT INTO items (id, name, description) VALUES (?, ?, ?)', [
      id,
      item.name,
      item.description ?? null,
    ]);
    const created = await findItem(id);
    res.status(201).location(`/api/items/${id}`).json({ data: created });
  })
);

router.get(
  '/:id',
  validateId,
  asyncHandler(async (req, res) => {
    const item = await findItem(req.params.id);
    if (!item) throw new HttpError(404, 'Item not found');
    res.json({ data: item });
  })
);

router.put(
  '/:id',
  validateId,
  asyncHandler(async (req, res) => {
    const changes = parseItemBody(req.body, { partial: true });
    const fields = Object.keys(changes);
    const assignments = fields.map((f) => `${f} = ?`).join(', ');
    const result = await db.query(`UPDATE items SET ${assignments} WHERE id = ?`, [
      ...fields.map((f) => changes[f]),
      req.params.id,
    ]);
    if (result.affectedRows === 0) throw new HttpError(404, 'Item not found');
    res.json({ data: await findItem(req.params.id) });
  })
);

router.delete(
  '/:id',
  validateId,
  asyncHandler(async (req, res) => {
    const result = await db.query('DELETE FROM items WHERE id = ?', [req.params.id]);
    if (result.affectedRows === 0) throw new HttpError(404, 'Item not found');
    res.status(204).end();
  })
);

module.exports = router;
module.exports.HttpError = HttpError;
module.exports.parseItemBody = parseItemBody;
