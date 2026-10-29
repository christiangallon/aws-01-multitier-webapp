'use strict';

/**
 * Structured (JSON-lines) logging.
 *
 * - requestId(): assigns/propagates an X-Request-Id header (uuid v4).
 * - accessLog:   morgan middleware emitting one JSON object per request:
 *     {"type":"access","level":"info","method":"GET","path":"/api/items","status":200,...}
 * - log.info / log.warn / log.error: application logs in the same format.
 *
 * The CloudWatch agent ships stdout (/var/log/app/app.log) to the
 * /aws/ec2/app-tier log group, where metric filters such as
 * `{ $.type = "access" && $.status >= 500 }` turn these lines into metrics.
 */
const morgan = require('morgan');
const { v4: uuidv4 } = require('uuid');

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,128}$/;

function write(level, message, fields = {}) {
  const entry = {
    time: new Date().toISOString(),
    type: 'app',
    level,
    message,
    ...fields,
  };
  const line = JSON.stringify(entry);
  if (level === 'error') {
    process.stderr.write(`${line}\n`);
  } else {
    process.stdout.write(`${line}\n`);
  }
}

const log = {
  info: (message, fields) => write('info', message, fields),
  warn: (message, fields) => write('warn', message, fields),
  error: (message, fields) => write('error', message, fields),
};

function requestId() {
  return (req, res, next) => {
    const incoming = req.get('X-Request-Id');
    req.id = incoming && REQUEST_ID_PATTERN.test(incoming) ? incoming : uuidv4();
    res.setHeader('X-Request-Id', req.id);
    next();
  };
}

function jsonFormat(tokens, req, res) {
  const status = Number(tokens.status(req, res)) || 0;
  let level = 'info';
  if (status >= 500) level = 'error';
  else if (status >= 400) level = 'warn';

  return JSON.stringify({
    time: new Date().toISOString(),
    type: 'access',
    level,
    requestId: req.id,
    method: tokens.method(req, res),
    path: tokens.url(req, res),
    status,
    durationMs: Number(tokens['response-time'](req, res)) || 0,
    contentLength: Number(tokens.res(req, res, 'content-length')) || 0,
    remoteAddr: req.get('X-Forwarded-For') || tokens['remote-addr'](req, res),
    userAgent: tokens['user-agent'](req, res),
  });
}

// Skip ALB health checks to keep logs (and CloudWatch ingestion cost) small.
const accessLog = morgan(jsonFormat, {
  skip: (req, res) => req.path === '/health' && res.statusCode < 400,
});

module.exports = { log, requestId, accessLog };
