'use strict';

/**
 * Application tier entry point.
 *
 *   GET /health      liveness: always 200 while the process is up; reports DB status
 *   GET /ready       readiness: 200 only if the database answers, else 503
 *   /api/items       CRUD API backed by RDS MySQL
 *   /                static UI (served by nginx in AWS; by Express locally)
 */
require('dotenv').config();

const path = require('node:path');
const express = require('express');
const db = require('./db');
const itemsRouter = require('./routes/items');
const { log, requestId, accessLog } = require('./middleware/logger');

const PORT = Number.parseInt(process.env.PORT || '3000', 10);
const startedAt = new Date();

function createApp() {
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', true);

  app.use(requestId());
  app.use(accessLog);
  app.use(express.json({ limit: '100kb' }));

  app.get('/health', async (req, res) => {
    let dbStatus = 'up';
    try {
      await db.ping();
    } catch (err) {
      dbStatus = 'down';
    }
    res.status(200).json({
      status: 'ok',
      db: dbStatus,
      uptimeSeconds: Math.round(process.uptime()),
      startedAt: startedAt.toISOString(),
      version: process.env.APP_VERSION || 'local',
      environment: process.env.APP_ENV || process.env.NODE_ENV || 'development',
      hostname: require('node:os').hostname(),
    });
  });

  app.get('/ready', async (req, res) => {
    try {
      await db.ping();
      res.status(200).json({ status: 'ready' });
    } catch (err) {
      res.status(503).json({ status: 'not_ready', error: err.message });
    }
  });

  app.use('/api/items', itemsRouter);

  app.use(express.static(path.join(__dirname, '..', 'public'), { maxAge: '5m' }));

  // 404 for anything else
  app.use((req, res) => {
    res.status(404).json({ error: 'Not found', path: req.originalUrl });
  });

  // Central error handler
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err.type === 'entity.parse.failed') {
      return res.status(400).json({ error: 'Malformed JSON body' });
    }
    if (err.type === 'entity.too.large') {
      return res.status(413).json({ error: 'Request body too large' });
    }
    const status = Number.isInteger(err.status) && err.status >= 400 && err.status < 600 ? err.status : 500;
    if (status >= 500) {
      log.error('Unhandled request error', {
        requestId: req.id,
        method: req.method,
        path: req.originalUrl,
        error: err.message,
        code: err.code,
        stack: err.stack,
      });
      return res.status(status).json({ error: 'Internal server error', requestId: req.id });
    }
    return res.status(status).json({ error: err.message });
  });

  return app;
}

function start(port = PORT) {
  const app = createApp();
  const server = app.listen(port, () => {
    log.info('Server listening', { port: server.address().port, pid: process.pid });
  });

  // Keep-alive longer than the ALB idle timeout (60s) to avoid 502s.
  server.keepAliveTimeout = 65000;
  server.headersTimeout = 66000;

  let shuttingDown = false;
  const shutdown = (signal) => {
    if (shuttingDown) return;
    shuttingDown = true;
    log.info('Shutdown requested', { signal });

    const forceExit = setTimeout(() => {
      log.error('Forced shutdown after timeout');
      process.exit(1);
    }, 15000);
    forceExit.unref();

    server.close(async (err) => {
      if (err) log.error('Error closing HTTP server', { error: err.message });
      try {
        await db.close();
      } catch (closeErr) {
        log.error('Error closing DB pool', { error: closeErr.message });
      }
      log.info('Shutdown complete');
      process.exit(err ? 1 : 0);
    });
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  return server;
}

process.on('unhandledRejection', (reason) => {
  log.error('Unhandled promise rejection', { error: reason instanceof Error ? reason.message : String(reason) });
});

if (require.main === module) {
  start();
}

module.exports = { createApp, start };
