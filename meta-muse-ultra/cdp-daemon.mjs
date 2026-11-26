#!/usr/bin/env node
// cdp-daemon.mjs — Muse Ultra Browser raw-CDP daemon (harness replacement, 2026-11-26).
//
// Why: the previous harness (ego-browser v2.2.1 generation, both the stock
// launcher and the ego-linux fork) delivered the first Fetch.requestPaused
// event to scripts ~15s after navigation (measured 2026-11-26: 15,029ms on
// the fork, ~15,000ms on the stock launcher vs 79-88ms over raw CDP).
// This daemon speaks CDP directly over the browser WebSocket and pushes
// events to scripts immediately. Zero npm dependencies (Node >= 22 globals).
//
// It exposes the same script surface run.sh generates code against:
//   taskSpace(name) / claimTaskSpace(id) -> { id, name, newPage(), pages(), finish({keep}) }
//   page: cdp(), events(), evaluate(), goto(), snapshot(), screenshot(), close()
// Scripts run IN THIS PROCESS (AsyncFunction), so they see this daemon's
// environment — identical semantics to the old harness (agent-vault relies
// on the daemon-start environment, e.g. AGENT_VAULT_VALUE).
//
// Protocol (Unix socket, newline-delimited JSON):
//   -> {type:"run", script:"..."}  <- {type:"out"|"err", text} ... {type:"done", code}
//   -> {type:"status"}             <- {type:"status-result", ...} {type:"done", code:0}
//   -> {type:"stop"}               <- {type:"done", code:0} then daemon exits
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdirSync, writeFileSync, rmSync, openSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import util from 'node:util';

const STATE_DIR = join(homedir(), '.local', 'share', 'muse-ultra-browser');
const SOCK = join(STATE_DIR, 'cdp-daemon.sock');
const PIDFILE = join(STATE_DIR, 'cdp-daemon.pid');
const HERE = new URL('.', import.meta.url).pathname;
const WRAPPER = join(HERE, 'chrome-wrapper.sh');
const PROFILE = process.env.MUSE_ULTRA_PROFILE || join(HERE, 'profile');
const HEADLESS = process.env.MUSE_ULTRA_HEADLESS !== '0';
const EPHEMERAL = process.env.MUSE_ULTRA_EPHEMERAL === '1';
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

mkdirSync(STATE_DIR, { recursive: true });
writeFileSync(PIDFILE, String(process.pid));

// ---------------------------------------------------------------- Chrome/CDP
let chromeProc = null;
let chromePort = 0;
let ws = null;
let readyPromise = null;
let nextId = 1;
const pending = new Map();          // id -> {res, rej}
const sessions = new Map();         // sessionId -> {targetId, events: [], loadWaiters: []}

const DEBUG = process.env.UB_CDP_DEBUG === '1';
const dbg = (...a) => { if (DEBUG) try { writeFileSync(join(STATE_DIR, 'cdp-debug.log'), a.join(' ') + '\n', { flag: 'a' }); } catch {} };
function cdpSend(method, params = {}, sessionId) {
  return new Promise((res, rej) => {
    const id = nextId++;
    pending.set(id, { res, rej });
    dbg(Date.now(), 'SEND', id, method, sessionId || '-');
    ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
  });
}

function onWsMessage(ev) {
  let m;
  try { m = JSON.parse(ev.data); } catch { return; }
  if (m.id && pending.has(m.id)) {
    const { res, rej } = pending.get(m.id);
    pending.delete(m.id);
    dbg(Date.now(), 'RECV', m.id, m.error ? 'ERR ' + (m.error.message || '') : 'ok');
    if (m.error) rej(new Error(m.error.message || JSON.stringify(m.error)));
    else res(m.result);
    return;
  }
  dbg(Date.now(), 'EVT', m.method || '?', m.sessionId || '-');
  if (m.method && m.sessionId && sessions.has(m.sessionId)) {
    const s = sessions.get(m.sessionId);
    // Armed Fetch policy: answer requestPaused IMMEDIATELY here in the event
    // handler. If scripts answer via events()+cdp() instead, the pump's next
    // Runtime.evaluate deadlocks against the paused document (evaluate is
    // queued until the navigation commits; the commit waits for the Fetch
    // answer) — measured 2026-11-26. The old harness masked this by
    // delivering events ~15s late, after evaluates had already returned.
    if (m.method === 'Fetch.requestPaused' && s.fetchPolicy) {
      const p = m.params || {};
      let decision;
      try {
        decision = s.fetchPolicy.policy({
          url: (p.request && p.request.url) || '',
          method: (p.request && p.request.method) || '',
          resourceType: p.resourceType || '',
          requestId: p.requestId,
        });
      } catch { decision = s.fetchPolicy.fallback; }
      if (decision === 'continue') {
        cdpSend('Fetch.continueRequest', { requestId: p.requestId }, m.sessionId).catch(() => {});
      } else {
        cdpSend('Fetch.failRequest', { requestId: p.requestId, errorReason: 'BlockedByClient' }, m.sessionId).catch(() => {});
      }
    }
    s.events.push({ method: m.method, params: m.params });
    if (s.events.length > 10000) s.events.splice(0, s.events.length - 10000);
    if (m.method === 'Page.loadEventFired' || m.method === 'Page.frameStoppedLoading') {
      const w = s.loadWaiters.splice(0);
      for (const fn of w) fn(m.method);
    }
  }
}

async function launchChrome() {
  // Fixed-ish port (never 0: Chrome reports navigator.webdriver=true on an
  // OS-assigned debugging port — same reasoning as ego-linux's launcher).
  for (const p of [19222, 19223, 19224, 19225, 19226]) {
    try {
      const r = await fetch(`http://127.0.0.1:${p}/json/version`);
      if (r.ok) throw new Error('busy');
    } catch (e) { if (e.message !== 'busy') { chromePort = p; break; } }
  }
  if (!chromePort) chromePort = 19222;
  const args = [
    `--remote-debugging-port=${chromePort}`, '--remote-debugging-address=127.0.0.1',
    `--user-data-dir=${PROFILE}`,
    '--no-first-run', '--no-default-browser-check', '--disable-dev-shm-usage',
    '--no-sandbox', '--disable-setuid-sandbox', '--mute-audio',
    '--disable-blink-features=AutomationControlled',
    ...(HEADLESS ? ['--headless=new', '--hide-scrollbars', '--window-size=1280,800'] : []),
    'about:blank',
  ];
  const logFd = openSync(join(STATE_DIR, 'cdp-chrome.log'), 'a');
  chromeProc = spawn(WRAPPER, args, { stdio: ['ignore', logFd, logFd], env: process.env });
  chromeProc.on('exit', () => { chromeProc = null; ws = null; readyPromise = null; sessions.clear(); spaces.clear(); });
  // Wait for the DevTools endpoint, then connect the browser-level socket.
  let ver = null;
  for (let i = 0; i < 80 && !ver; i++) {
    try { const r = await fetch(`http://127.0.0.1:${chromePort}/json/version`); if (r.ok) ver = await r.json(); } catch {}
    if (!ver) await new Promise(r => setTimeout(r, 250));
  }
  if (!ver) throw new Error('chrome devtools endpoint never came up (see cdp-chrome.log)');
  ws = new WebSocket(ver.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  ws.onmessage = onWsMessage;
}

function ensureChrome() {
  if (!readyPromise) {
    readyPromise = launchChrome().catch(e => { readyPromise = null; throw e; });
  }
  return readyPromise;
}

// ---------------------------------------------------------------- Page shim
class UBPage {
  constructor(space, targetId, sessionId, label) {
    this.space = space; this.targetId = targetId; this.sessionId = sessionId; this.label = label;
  }
  async cdp(method, params = {}) { return cdpSend(method, params, this.sessionId); }
  // armFetch(policy, fallback): policy({url, method, resourceType, requestId})
  // runs daemon-side per Fetch.requestPaused and must return 'continue' or
  // 'fail'. Because scripts execute in this process, the policy may be a
  // closure over script variables (counters, timestamps).
  armFetch(policy, fallback = 'fail') {
    const s = sessions.get(this.sessionId);
    if (s) s.fetchPolicy = { policy, fallback };
  }
  disarmFetch() {
    const s = sessions.get(this.sessionId);
    if (s) s.fetchPolicy = null;
  }
  async events() {
    const s = sessions.get(this.sessionId);
    if (!s) return [];
    const out = s.events; s.events = [];
    return out;
  }
  async evaluate(fnOrExpr, arg) {
    let expression;
    if (typeof fnOrExpr === 'function') {
      expression = `(${fnOrExpr.toString()})(${arg === undefined ? '' : JSON.stringify(arg)})`;
    } else { expression = String(fnOrExpr); }
    const r = await this.cdp('Runtime.evaluate', {
      expression, awaitPromise: true, returnByValue: true,
    });
    if (r.exceptionDetails) {
      const msg = (r.exceptionDetails.exception && (r.exceptionDetails.exception.description || r.exceptionDetails.exception.value)) || r.exceptionDetails.text || 'page evaluation failed';
      throw new Error(String(msg).slice(0, 500));
    }
    return r.result ? r.result.value : undefined;
  }
  async goto(url) {
    const s = sessions.get(this.sessionId);
    const loaded = new Promise(res => {
      const t = setTimeout(() => res('timeout'), 15000);
      s.loadWaiters.push(() => { clearTimeout(t); res('loaded'); });
    });
    await this.cdp('Page.navigate', { url });
    const how = await loaded;
    if (how === 'timeout') throw new Error('goto: load timeout (15s) for ' + url);
  }
  async snapshot() {
    const { nodes } = await this.cdp('Accessibility.getFullAXTree', {});
    const byId = new Map(nodes.map(n => [n.nodeId, n]));
    const lines = [];
    try {
      const href = await this.evaluate(() => location.href);
      const title = await this.evaluate(() => document.title);
      lines.push('title: ' + title, 'url: ' + href);
    } catch {}
    const esc = s => String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n');
    const walk = (node, depth) => {
      if (!node) return;
      const role = (node.role && node.role.value) || 'generic';
      // InlineTextBox nodes are per-character layout fragments of a parent
      // StaticText — emitting them bloats the snapshot ~10x and leaks
      // space-separated characters into snaptrim's text mode. Drop them.
      if (role === 'InlineTextBox') return;
      const name = node.name ? node.name.value : '';
      if (!node.ignored || depth === 0) {
        let line = '  '.repeat(depth) + role;
        if (name) line += ' "' + esc(name) + '"';
        if (node.backendDOMNodeId) line += ' [ref=' + node.backendDOMNodeId + ']';
        lines.push(line);
        depth++;
      }
      for (const cid of node.childIds || []) walk(byId.get(cid), depth);
    };
    for (const n of nodes) if (!n.parentId) walk(n, 0);
    return lines.join('\n');
  }
  async screenshot() {
    const r = await this.cdp('Page.captureScreenshot', { format: 'png' });
    return r.data;
  }
  async close() {
    try { await cdpSend('Target.closeTarget', { targetId: this.targetId }); } catch {}
    sessions.delete(this.sessionId);
    this.space.pages.delete(this.label);
  }
}

// ---------------------------------------------------------------- Task spaces
let spaceSeq = 0;
const spaces = new Map(); // name -> space
class UBSpace {
  constructor(name) {
    this.id = ++spaceSeq; this.name = name; this.pages = new Map();
    this.contextId = null; this.finished = false; this.pageSeq = 0;
  }
  async newPage(label) {
    await ensureChrome();
    if (EPHEMERAL && !this.contextId) {
      const r = await cdpSend('Target.createBrowserContext', {});
      this.contextId = r.browserContextId;
    }
    const { targetId } = await cdpSend('Target.createTarget', {
      url: 'about:blank', ...(this.contextId ? { browserContextId: this.contextId } : {}),
    });
    const { sessionId } = await cdpSend('Target.attachToTarget', { targetId, flatten: true });
    sessions.set(sessionId, { targetId, events: [], loadWaiters: [] });
    const page = new UBPage(this, targetId, sessionId, label || ('p' + (++this.pageSeq)));
    this.pages.set(page.label, page);
    try { await page.cdp('Page.enable', {}); } catch {}
    return page;
  }
  async page(label) {
    if (label && this.pages.has(label)) return this.pages.get(label);
    return this.newPage(label);
  }
  async pages() { return [...this.pages.values()]; }
  async finish({ keep = [] } = {}) {
    const keepSet = new Set(keep.map(k => (k && k.label) || k));
    for (const p of [...this.pages.values()]) {
      if (!keepSet.has(p.label) && !keepSet.has(p)) await p.close();
    }
    if (this.pages.size === 0) {
      this.finished = true;
      spaces.delete(this.name);
      if (this.contextId) { try { await cdpSend('Target.disposeBrowserContext', { browserContextId: this.contextId }); } catch {} this.contextId = null; }
    }
  }
}
async function taskSpace(name) {
  const key = String(name);
  if (spaces.has(key) && !spaces.get(key).finished) return spaces.get(key);
  const s = new UBSpace(key);
  spaces.set(key, s);
  return s;
}
async function claimTaskSpace(idOrName) {
  const key = String(idOrName);
  for (const s of spaces.values()) if (String(s.id) === key || s.name === key) return s;
  return taskSpace(key);
}

// ---------------------------------------------------------------- Script runner
function formatArg(a) {
  if (typeof a === 'string') return a;
  if (a instanceof Error) return a.stack || a.message;
  try { return util.inspect(a, { depth: 4, maxArrayLength: 50 }); } catch { return String(a); }
}

async function runScript(code, emit) {
  const con = {
    log: (...a) => emit('out', a.map(formatArg).join(' ') + '\n'),
    info: (...a) => emit('out', a.map(formatArg).join(' ') + '\n'),
    warn: (...a) => emit('err', a.map(formatArg).join(' ') + '\n'),
    error: (...a) => emit('err', a.map(formatArg).join(' ') + '\n'),
  };
  const fn = new AsyncFunction('taskSpace', 'claimTaskSpace', 'console', code);
  await fn(taskSpace, claimTaskSpace, con);
}

// ---------------------------------------------------------------- Socket server
try { rmSync(SOCK, { force: true }); } catch {}
const server = createServer(sock => {
  let buf = '';
  let handled = false;
  sock.on('data', async chunk => {
    buf += chunk;
    const nl = buf.indexOf('\n');
    if (nl < 0 || handled) return;
    handled = true;
    let msg;
    try { msg = JSON.parse(buf.slice(0, nl)); } catch { sock.end(); return; }
    // A run message carries the script in a follow-up frame if it is large:
    // the client sends {type:"run", scriptLen} then raw bytes. Simpler path:
    // script is inline in the JSON (JSON-escaped) — handled here directly.
    const emit = (type, text) => { try { sock.write(JSON.stringify({ type, text }) + '\n'); } catch {} };
    const done = code => { try { sock.write(JSON.stringify({ type: 'done', code }) + '\n'); sock.end(); } catch {} };
    try {
      if (msg.type === 'run') {
        await runScript(msg.script || '', emit);
        done(0);
      } else if (msg.type === 'status') {
        emit('out', JSON.stringify({
          daemon: 'up', pid: process.pid, chrome: chromeProc ? 'up' : 'down',
          port: chromePort, profile: PROFILE,
          spaces: [...spaces.values()].map(s => ({ id: s.id, name: s.name, pages: s.pages.size })),
        }) + '\n');
        done(0);
      } else if (msg.type === 'stop') {
        done(0);
        shutdown();
      } else { done(1); }
    } catch (e) {
      emit('err', 'cdp-daemon: ' + String(e && e.stack || e).slice(0, 2000) + '\n');
      done(1);
    }
  });
  sock.on('error', () => {});
});

function shutdown() {
  try { if (chromeProc) chromeProc.kill('SIGKILL'); } catch {}
  try { rmSync(SOCK, { force: true }); rmSync(PIDFILE, { force: true }); } catch {}
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1500).unref();
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

server.listen(SOCK, () => {
  // Chrome launches lazily on the first page request; warm-up calls trigger
  // it through taskSpace/newPage. Nothing to do here.
});
