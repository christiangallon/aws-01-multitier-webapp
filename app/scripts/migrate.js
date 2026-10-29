#!/usr/bin/env node
'use strict';

/**
 * Idempotent schema migration: creates the `items` table if it does not exist.
 * Runs automatically before every app start on EC2 (see app_userdata.sh), so it
 * retries while RDS is still becoming reachable.
 *
 *   npm run migrate
 */
require('dotenv').config();

const db = require('../src/db');

const MAX_ATTEMPTS = Number.parseInt(process.env.MIGRATE_MAX_ATTEMPTS || '10', 10);
const RETRY_DELAY_MS = Number.parseInt(process.env.MIGRATE_RETRY_DELAY_MS || '5000', 10);

const MIGRATIONS = [
  {
    name: '001_create_items',
    sql: `
      CREATE TABLE IF NOT EXISTS items (
        id          CHAR(36)     NOT NULL,
        name        VARCHAR(255) NOT NULL,
        description TEXT         NULL,
        created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_items_created_at (created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `,
  },
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitForDatabase() {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    try {
      await db.ping(5000);
      return;
    } catch (err) {
      console.log(
        JSON.stringify({ type: 'migrate', level: 'warn', message: 'Database not reachable yet', attempt, error: err.message })
      );
      if (attempt === MAX_ATTEMPTS) throw err;
      await sleep(RETRY_DELAY_MS);
    }
  }
}

async function migrate() {
  await waitForDatabase();
  for (const migration of MIGRATIONS) {
    await db.getPool().query(migration.sql);
    console.log(JSON.stringify({ type: 'migrate', level: 'info', message: 'Applied migration', name: migration.name }));
  }
}

if (require.main === module) {
  migrate()
    .then(async () => {
      await db.close();
      process.exit(0);
    })
    .catch(async (err) => {
      console.error(JSON.stringify({ type: 'migrate', level: 'error', message: 'Migration failed', error: err.message }));
      await db.close().catch(() => {});
      process.exit(1);
    });
}

module.exports = { migrate, MIGRATIONS };
