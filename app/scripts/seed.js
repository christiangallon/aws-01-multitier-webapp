#!/usr/bin/env node
'use strict';

/**
 * Seeds sample rows into `items` (only when the table is empty, unless
 * --force is passed). Runs the migration first so it works on a fresh DB.
 *
 *   npm run seed
 *   npm run seed -- --force
 */
require('dotenv').config();

const { v4: uuidv4 } = require('uuid');
const db = require('../src/db');
const { migrate } = require('./migrate');

const SAMPLE_ITEMS = [
  { name: 'Application Load Balancer', description: 'Distributes HTTP traffic across the web tier in two AZs.' },
  { name: 'Web tier (nginx)', description: 'Serves static assets from S3 and proxies /api to the app tier.' },
  { name: 'App tier (Node.js)', description: 'Express API running in private subnets behind an internal ALB.' },
  { name: 'Amazon RDS for MySQL', description: 'Managed MySQL 8.0 database in private subnets.' },
  { name: 'Amazon S3', description: 'Stores application bundles, static assets and access logs.' },
  { name: 'Amazon CloudWatch', description: 'Collects metrics and logs, and raises alarms via SNS.' },
];

async function seed({ force = false } = {}) {
  await migrate();

  const [{ total }] = await db.query('SELECT COUNT(*) AS total FROM items');
  if (Number(total) > 0 && !force) {
    console.log(JSON.stringify({ type: 'seed', level: 'info', message: 'Table not empty; skipping (use --force)', total }));
    return 0;
  }

  for (const item of SAMPLE_ITEMS) {
    await db.query('INSERT INTO items (id, name, description) VALUES (?, ?, ?)', [uuidv4(), item.name, item.description]);
  }
  console.log(JSON.stringify({ type: 'seed', level: 'info', message: 'Seeded items', inserted: SAMPLE_ITEMS.length }));
  return SAMPLE_ITEMS.length;
}

if (require.main === module) {
  seed({ force: process.argv.includes('--force') })
    .then(async () => {
      await db.close();
      process.exit(0);
    })
    .catch(async (err) => {
      console.error(JSON.stringify({ type: 'seed', level: 'error', message: 'Seeding failed', error: err.message }));
      await db.close().catch(() => {});
      process.exit(1);
    });
}

module.exports = { seed, SAMPLE_ITEMS };
