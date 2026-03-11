#!/usr/bin/env node
/**
 * Dev server: serves EmulatorJS_showdown/ static files and proxies
 * Showdown login requests to avoid CORS issues.
 *
 * Usage: node serve.mjs [port]
 */

import { createServer } from 'node:http';
import { readFile, appendFile, writeFile } from 'node:fs/promises';
import { join, extname } from 'node:path';
import { request as httpsRequest } from 'node:https';

const LOG_FILE = join(import.meta.dirname, 'browser.log');

const PORT = parseInt(process.argv[2] || '8080', 10);
const STATIC_DIR = join(import.meta.dirname, 'EmulatorJS_showdown');
const LOGIN_SERVER = 'https://play.pokemonshowdown.com/~~showdown/action.php';

const MIME = {
  '.html': 'text/html',
  '.js':   'application/javascript',
  '.css':  'text/css',
  '.gbc':  'application/octet-stream',
  '.png':  'image/png',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
};

function proxyLogin(req, res) {
  let body = '';
  req.on('data', c => body += c);
  req.on('end', () => {
    const url = new URL(LOGIN_SERVER);
    const proxyReq = httpsRequest({
      hostname: url.hostname,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      },
    }, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, { 'Content-Type': proxyRes.headers['content-type'] || 'text/plain' });
      proxyRes.pipe(res);
    });
    proxyReq.on('error', (e) => {
      res.writeHead(502);
      res.end('Proxy error: ' + e.message);
    });
    proxyReq.write(body);
    proxyReq.end();
  });
}

async function serveStatic(req, res) {
  const urlPath = req.url.split('?')[0];
  const filePath = join(STATIC_DIR, urlPath === '/' ? '/showdown.html' : urlPath);

  // Prevent directory traversal
  if (!filePath.startsWith(STATIC_DIR)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  try {
    const data = await readFile(filePath);
    const ext = extname(filePath);
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
}

async function serveConfig(req, res) {
  try {
    const data = await readFile(join(import.meta.dirname, 'config.json'));
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(data);
  } catch {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end('{}');
  }
}

function handleLog(req, res) {
  let body = '';
  req.on('data', c => body += c);
  req.on('end', async () => {
    try {
      const lines = JSON.parse(body);
      const text = lines.map(l => `[${new Date().toISOString()}] ${l}`).join('\n') + '\n';
      await appendFile(LOG_FILE, text);
    } catch {}
    res.writeHead(200);
    res.end('ok');
  });
}

async function clearLog(req, res) {
  await writeFile(LOG_FILE, '');
  res.writeHead(200);
  res.end('ok');
}

createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/api/login') {
    proxyLogin(req, res);
  } else if (req.method === 'POST' && req.url === '/api/log') {
    handleLog(req, res);
  } else if (req.url === '/api/clear-log') {
    clearLog(req, res);
  } else if (req.url === '/api/config') {
    serveConfig(req, res);
  } else {
    serveStatic(req, res);
  }
}).listen(PORT, () => {
  console.log(`ShowdownEmu dev server: http://localhost:${PORT}`);
});
