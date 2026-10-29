'use strict';

/**
 * MySQL connection pool (mysql2/promise).
 *
 * Configuration comes from environment variables:
 *   DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME
 * On EC2, DB_USER / DB_PASSWORD are injected by /opt/app/bin/start.sh, which
 * reads them from AWS Secrets Manager just before the process starts.
 *
 * The pool is created lazily so the HTTP server (and /health) can start even
 * when the database is temporarily unreachable.
 */
const mysql = require('mysql2/promise');

let pool = null;

function getConfig() {
  return {
    host: process.env.DB_HOST || '127.0.0.1',
    port: Number.parseInt(process.env.DB_PORT || '3306', 10),
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'appdb',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0,
    connectTimeout: 5000,
    enableKeepAlive: true,
    keepAliveInitialDelay: 10000,
    charset: 'utf8mb4',
    timezone: 'Z',
    dateStrings: false,
  };
}

function getPool() {
  if (!pool) {
    pool = mysql.createPool(getConfig());
  }
  return pool;
}

/** Run a parameterised query and return rows. */
async function query(sql, params = []) {
  const [rows] = await getPool().execute(sql, params);
  return rows;
}

/** Lightweight connectivity check used by /health and /ready. */
async function ping(timeoutMs = 2000) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`DB ping timed out after ${timeoutMs}ms`)), timeoutMs);
  });
  try {
    await Promise.race([getPool().query('SELECT 1'), timeout]);
    return true;
  } finally {
    clearTimeout(timer);
  }
}

async function close() {
  if (pool) {
    const p = pool;
    pool = null;
    await p.end();
  }
}

module.exports = { getPool, query, ping, close, getConfig };
