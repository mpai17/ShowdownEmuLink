#!/usr/bin/env node
/**
 * Headless test runner for the Showdown Bridge.
 * Starts a local HTTP server, launches Puppeteer, captures console output,
 * waits for __TEST_DONE__ sentinel, then exits.
 *
 * Usage: node run-test.mjs [--runs N]
 */

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import puppeteer from 'puppeteer';

const EMULATOR_DIR = path.join(import.meta.dirname, 'EmulatorJS_showdown');
const PORT = 8377;
const PAGE_TIMEOUT = 600_000; // 10 min max per run

// ---------- simple static file server ----------

const MIME = {
  '.html': 'text/html',
  '.js':   'application/javascript',
  '.gbc':  'application/octet-stream',
  '.css':  'text/css',
  '.wasm': 'application/wasm',
  '.json': 'application/json',
  '.png':  'image/png',
};

function serve(req, res) {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  let filePath = path.join(EMULATOR_DIR, decodeURIComponent(url.pathname));
  if (!filePath.startsWith(EMULATOR_DIR)) { res.writeHead(403); res.end(); return; }
  if (filePath.endsWith('/')) filePath += 'index.html';
  const ext = path.extname(filePath);
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  });
}

// ---------- run a single test ----------

async function runOnce(browser, runNum) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`  RUN ${runNum}`);
  console.log('='.repeat(60));

  const page = await browser.newPage();
  const logs = [];

  page.on('console', msg => {
    const text = msg.text();
    logs.push(text);
    // Stream ShowdownBridge and Test lines to stdout
    if (text.startsWith('[ShowdownBridge]') || text.startsWith('[Test]') ||
        text.startsWith('Turn ') || text.startsWith('====') || text.startsWith('TOTAL'))
      console.log(text);
  });
  page.on('pageerror', err => console.error('[PAGE ERROR]', err.message));

  const done = new Promise((resolve) => {
    const timeout = setTimeout(() => {
      console.error('[Runner] Page timeout — forcing close');
      resolve(false);
    }, PAGE_TIMEOUT);

    page.on('console', msg => {
      if (msg.text().includes('__TEST_DONE__')) {
        clearTimeout(timeout);
        resolve(true);
      }
    });
  });

  await page.goto(`http://localhost:${PORT}/test.html?test`, { waitUntil: 'domcontentloaded' });
  const completed = await done;

  await page.close();
  return { completed, logs };
}

// ---------- main ----------

const args = process.argv.slice(2);
const runsIdx = args.indexOf('--runs');
const NUM_RUNS = runsIdx !== -1 ? parseInt(args[runsIdx + 1], 10) : 1;

const server = http.createServer(serve);
server.listen(PORT, async () => {
  console.log(`[Runner] Serving ${EMULATOR_DIR} on http://localhost:${PORT}`);

  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--autoplay-policy=no-user-gesture-required'],
  });

  const results = [];
  for (let i = 1; i <= NUM_RUNS; i++) {
    const r = await runOnce(browser, i);
    results.push(r);
  }

  await browser.close();
  server.close();

  // Summary across runs
  console.log(`\n${'='.repeat(60)}`);
  console.log(`  ALL RUNS COMPLETE (${NUM_RUNS})`);
  console.log('='.repeat(60));
  for (let i = 0; i < results.length; i++) {
    const totalLine = results[i].logs.find(l => l.startsWith('TOTAL:'));
    console.log(`  Run ${i + 1}: ${results[i].completed ? 'FINISHED' : 'TIMED OUT'} ${totalLine ?? ''}`);
  }

  process.exit(results.every(r => r.completed) ? 0 : 1);
});
