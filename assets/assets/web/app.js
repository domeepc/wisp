// The Wisp browser page. Served by the Wisp app itself, so every request
// goes to the same origin: the device you opened. No libraries, no CDN.
//
// Rule for this file: text that comes from anywhere else (file names,
// device names, shared text) only ever goes into the page with
// textContent — never innerHTML — so it can't run as code.
'use strict';

const API = '/api/wisp/v1';
const STORE_KEY = 'wisp-browser';
const POLL_EVERY = 2000;

const $ = (id) => document.getElementById(id);

const state = {
  id: null,
  token: null,
  name: '',
  detail: '',
  host: null,
  connected: null,
  itemsKey: null,
  items: [],
  sending: false,
};

// ---------------------------------------------------------------- helpers

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

const ICONS = {
  download: ['M12 3v12', 'm7 10 5 5 5-5', 'M5 21h14'],
  text: ['M4 7h16', 'M4 12h16', 'M4 17h10'],
};

function icon(name) {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  for (const [key, value] of Object.entries({
    viewBox: '0 0 24 24', width: '20', height: '20', fill: 'none',
    stroke: 'currentColor', 'stroke-width': '2', 'stroke-linecap': 'round',
    'stroke-linejoin': 'round', 'aria-hidden': 'true',
  })) {
    svg.setAttribute(key, value);
  }
  for (const d of ICONS[name]) {
    const path = document.createElementNS(ns, 'path');
    path.setAttribute('d', d);
    svg.appendChild(path);
  }
  return svg;
}

/** 480 KB, 3.2 MB, 184 MB — same as the app. */
function formatBytes(bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let size = bytes;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  const number = unit > 0 && size < 10 ? size.toFixed(1) : String(Math.round(size));
  return `${number} ${units[unit]}`;
}

// crypto.randomUUID needs https; getRandomValues works on plain http too.
function randomHex(bytes) {
  const data = new Uint8Array(bytes);
  crypto.getRandomValues(data);
  return Array.from(data, (b) => b.toString(16).padStart(2, '0')).join('');
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

let toastTimer;
function toast(message) {
  const box = $('toast');
  box.textContent = message;
  box.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { box.hidden = true; }, 4000);
}

// navigator.clipboard only exists on https (or localhost), so fall back to
// the old select-and-copy trick on plain http.
async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (_) { /* fall through */ }
  }
  const area = document.createElement('textarea');
  area.value = text;
  area.setAttribute('readonly', '');
  area.style.position = 'fixed';
  area.style.opacity = '0';
  document.body.appendChild(area);
  area.select();
  let ok = false;
  try { ok = document.execCommand('copy'); } catch (_) { ok = false; }
  area.remove();
  return ok;
}

function badge(name) {
  const dot = name.lastIndexOf('.');
  const ext = dot > 0 ? name.slice(dot + 1).toLowerCase() : '';
  const color = {
    pdf: 'red', mp4: 'blue', mov: 'blue', zip: 'blue', fig: 'purple',
  }[ext] || '';
  return el('div', `badge ${color}`, (ext || 'file').slice(0, 4).toUpperCase());
}

// --------------------------------------------------------------- identity

/** Which browser this is, shown next to the name ("Chrome"). */
function browserName() {
  const ua = navigator.userAgent;
  // Order matters: Edge and Opera also say Chrome; Chrome also says Safari.
  if (/Edg\//.test(ua)) return 'Edge';
  if (/OPR\//.test(ua)) return 'Opera';
  if (/SamsungBrowser/.test(ua)) return 'Samsung Internet';
  if (/Firefox\/|FxiOS/.test(ua)) return 'Firefox';
  if (/Chrome\/|CriOS/.test(ua)) return 'Chrome';
  if (/Safari\//.test(ua)) return 'Safari';
  return 'Browser';
}

function loadStored() {
  try {
    return JSON.parse(localStorage.getItem(STORE_KEY)) || {};
  } catch (_) {
    return {};
  }
}

function store() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify({
      id: state.id, token: state.token, name: state.name,
    }));
  } catch (_) { /* private mode: we'll just get a new id next time */ }
}

function authQuery() {
  return `id=${encodeURIComponent(state.id)}&token=${encodeURIComponent(state.token)}`;
}

function hostName() {
  return state.host?.name || 'the other device';
}

// ------------------------------------------------------------- connection

async function hello() {
  const res = await fetch(`${API}/browser/hello`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      // No name yet: the app picks a random one ("Swift Otter").
      id: state.id, token: state.token, name: state.name || null, detail: state.detail,
    }),
  });
  if (!res.ok) throw new Error(`hello failed (${res.status})`);
  const body = await res.json();
  state.id = body.id;
  state.token = body.token;
  state.name = body.name;
  store();
  renderMe();
  setHost(body.host);
}

async function fetchInbox() {
  return fetch(`${API}/browser/inbox?${authQuery()}`, { cache: 'no-store' });
}

// Checking the inbox is also how the app knows this tab is still open.
async function poll() {
  try {
    if (!state.token) await hello();
    let res = await fetchInbox();
    if (res.status === 403) {
      // The app restarted and forgot us: say hello again.
      state.token = null;
      await hello();
      res = await fetchInbox();
    }
    if (!res.ok) throw new Error(`inbox failed (${res.status})`);
    const body = await res.json();
    setHost(body.host);
    setConnected(true);
    renderInbox(body.items);
  } catch (_) {
    setConnected(false);
  } finally {
    setTimeout(poll, POLL_EVERY);
  }
}

function setHost(host) {
  state.host = host;
  const name = hostName();
  $('send-title').textContent = `Send to ${host?.name || 'the other device'}`;
  for (const node of document.querySelectorAll('.host-name')) node.textContent = name;
  document.title = host?.name ? `Wisp · ${host.name}` : 'Wisp';

  const note = $('hidden-note');
  note.hidden = !host || host.receiving !== false;
  note.textContent = `${name} is hidden right now, so it won't accept files.`;
  if (state.connected) setConnected(true, true);
}

function setConnected(ok, force = false) {
  if (state.connected === ok && !force) return;
  state.connected = ok;
  const pill = $('status');
  pill.className = `pill ${ok ? 'ok' : 'bad'}`;
  $('status-text').textContent = ok
    ? `Connected to ${hostName()}`
    : `Can't reach ${state.host?.name || 'Wisp'} — is it still open?`;
}

function renderMe() {
  $('me-name').textContent = state.name ? `${state.name} · ${state.detail}` : '…';
}

// ------------------------------------------------------------------ inbox

function downloadUrl(item) {
  return `${API}/browser/download?${authQuery()}&item=${encodeURIComponent(item.item)}`;
}

function renderInbox(items) {
  const key = JSON.stringify(items.map((i) => i.item));
  if (key === state.itemsKey) return; // don't redraw (and lose focus) needlessly
  state.itemsKey = key;
  state.items = items;

  const list = $('inbox');
  list.replaceChildren(
    ...items.slice().reverse().map((item) => (item.kind === 'text' ? textRow(item) : fileRow(item))),
  );
  list.hidden = items.length === 0;
  $('inbox-empty').hidden = items.length > 0;

  const files = items.filter((i) => i.kind === 'file');
  const all = $('download-all');
  all.hidden = files.length < 2;
  all.textContent = `Download all (${files.length})`;
}

function fileRow(item) {
  const row = el('div', 'item');
  const info = el('div', 'info');
  info.append(el('div', 'name', item.name), el('div', 'meta', formatBytes(item.size)));

  const link = el('a', 'icon-btn');
  link.href = downloadUrl(item);
  link.setAttribute('download', '');
  link.title = 'Download';
  link.setAttribute('aria-label', `Download ${item.name}`);
  link.append(icon('download'));

  row.append(badge(item.name), info, link);
  return row;
}

function textRow(item) {
  const row = el('div', 'item');
  const box = el('div', 'badge');
  box.append(icon('text'));

  const lines = item.text.split('\n');
  const first = lines.find((l) => l.trim()) || '';
  const preview = first.length > 60 ? `${first.slice(0, 60)}…` : first;
  const info = el('div', 'info');
  info.append(
    el('div', 'name', 'Text snippet'),
    el('div', 'meta', `${preview} · ${lines.length} ${lines.length === 1 ? 'line' : 'lines'}`),
  );

  const button = el('button', 'btn btn-small', 'Copy');
  button.type = 'button';
  button.addEventListener('click', async () => {
    const ok = await copyText(item.text);
    button.textContent = ok ? 'Copied' : 'Couldn’t copy';
    setTimeout(() => { button.textContent = 'Copy'; }, 1500);
  });

  row.append(box, info, button);
  return row;
}

// Browsers ask once before allowing several downloads from one page.
async function downloadAll() {
  for (const item of state.items.filter((i) => i.kind === 'file')) {
    const link = el('a');
    link.href = downloadUrl(item);
    link.setAttribute('download', '');
    document.body.append(link);
    link.click();
    link.remove();
    await sleep(700);
  }
}

// ---------------------------------------------------------------- sending

class OutgoingCard {
  constructor(files, code) {
    this.onCancel = null;
    const root = $('outgoing');
    root.replaceChildren();
    root.hidden = false;
    delete root.dataset.state;

    const titles = el('div', 'out-titles');
    this.title = el('div', 'out-title', `Waiting for ${hostName()} to accept`);
    this.code = el('div', 'out-code muted');
    this.code.append('Security code ', el('b', 'mono', code));
    titles.append(this.title, this.code);

    this.button = el('button', 'btn btn-small btn-danger', 'Cancel');
    this.button.type = 'button';
    this.button.addEventListener('click', () => this.onCancel?.());

    const head = el('div', 'out-head');
    head.append(titles, this.button);
    root.append(head);

    this.rows = files.map((file) => {
      const row = el('div', 'out-row');
      const top = el('div', 'out-top');
      const status = el('span', 'meta', 'Waiting');
      top.append(el('span', 'name', file.name), status);
      const bar = el('div', 'bar');
      const fill = el('span');
      bar.append(fill);
      row.append(top, bar);
      root.append(row);
      return { status, fill, size: file.size };
    });
  }

  setTitle(text) {
    this.title.textContent = text;
  }

  setProgress(index, loaded, done = false) {
    const row = this.rows[index];
    const percent = row.size ? Math.min(100, Math.round((loaded * 100) / row.size)) : 100;
    row.fill.style.width = `${done ? 100 : percent}%`;
    row.status.textContent = done ? 'Sent' : `${percent}%`;
    row.status.classList.toggle('ok', done);
  }

  finish(kind, text) {
    const root = $('outgoing');
    root.dataset.state = kind;
    this.title.textContent = text;
    this.code.hidden = true;
    this.button.textContent = 'Close';
    this.button.className = 'btn btn-small';
    this.onCancel = () => { root.hidden = true; };
  }
}

function uploadOne(url, blob, onProgress, onStart) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    onStart(xhr);
    xhr.open('POST', url);
    xhr.upload.addEventListener('progress', (e) => onProgress(e.loaded));
    xhr.addEventListener('load', () => {
      if (xhr.status === 200) resolve();
      else if (xhr.status === 410) reject(new Error(`Cancelled on ${hostName()}`));
      else reject(new Error(`Upload failed (${xhr.status})`));
    });
    xhr.addEventListener('error', () => reject(new Error(`Lost connection to ${hostName()}`)));
    xhr.addEventListener('abort', () => reject(new Error('Cancelled')));
    xhr.send(blob);
  });
}

/** Offers [files] ({name, size, blob}) to the app, then uploads them. */
async function send(files) {
  if (!files.length) return;
  if (state.sending) {
    toast('Wait for the current transfer to finish first.');
    return;
  }
  if (!state.token || !state.connected) {
    toast(`Can't reach ${hostName()} right now.`);
    return;
  }
  state.sending = true;

  const sessionId = randomHex(16);
  const code = randomHex(2).toUpperCase();
  const card = new OutgoingCard(files, code);
  let cancelled = false;
  let xhr = null;
  card.onCancel = () => {
    cancelled = true;
    if (xhr) xhr.abort();
    fetch(`${API}/cancel?sessionId=${sessionId}`, { method: 'POST' }).catch(() => {});
    card.finish('cancelled', 'Cancelled');
    state.sending = false;
  };

  try {
    // Waits (up to two minutes) until someone taps Accept or Decline.
    const res = await fetch(`${API}/prepare-upload`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sessionId,
        code,
        info: {
          id: state.id, name: state.name, platform: 'browser', detail: state.detail, port: 0,
        },
        files: files.map((f, i) => ({ id: String(i), name: f.name, size: f.size })),
      }),
    });
    if (cancelled) return;
    if (res.status === 403) {
      card.finish('failed', `${hostName()} declined the files`);
      return;
    }
    if (res.status === 409) {
      card.finish('failed', `${hostName()} is busy — try again in a moment`);
      return;
    }
    if (!res.ok) throw new Error(`Unexpected reply (${res.status})`);
    const { tokens } = await res.json();

    card.setTitle(`Sending to ${hostName()}…`);
    for (let i = 0; i < files.length; i++) {
      if (cancelled) return;
      const url = `${API}/upload?sessionId=${sessionId}&fileId=${i}`
        + `&token=${encodeURIComponent(tokens[String(i)])}`;
      await uploadOne(
        url,
        files[i].blob,
        (loaded) => card.setProgress(i, loaded),
        (request) => { xhr = request; },
      );
      card.setProgress(i, files[i].size, true);
    }
    card.finish('done', `Sent to ${hostName()}`);
  } catch (err) {
    if (!cancelled) card.finish('failed', err.message || 'Something went wrong');
  } finally {
    if (!cancelled) state.sending = false;
  }
}

function asUploads(fileList) {
  return Array.from(fileList, (f) => ({ name: f.name, size: f.size, blob: f }));
}

function sendText(text) {
  const blob = new Blob([text], { type: 'text/plain' });
  send([{ name: 'Text.txt', size: blob.size, blob }]);
}

function askForText() {
  const dialog = $('text-dialog');
  if (typeof dialog.showModal !== 'function') {
    const text = window.prompt('Text to send');
    if (text && text.trim()) sendText(text);
    return;
  }
  $('text-input').value = '';
  dialog.showModal();
  $('text-input').focus();
}

// ------------------------------------------------------------------ setup

function wireUp() {
  $('choose').addEventListener('click', () => $('file-input').click());
  $('file-input').addEventListener('change', (e) => {
    const files = asUploads(e.target.files);
    e.target.value = '';
    send(files);
  });

  $('send-text').addEventListener('click', askForText);
  $('text-cancel').addEventListener('click', () => $('text-dialog').close());
  $('text-send').addEventListener('click', () => {
    const text = $('text-input').value;
    $('text-dialog').close();
    if (text.trim()) sendText(text);
  });

  $('download-all').addEventListener('click', downloadAll);

  $('rename').addEventListener('click', () => {
    const name = window.prompt('Your name on the other device', state.name);
    if (!name || !name.trim()) return;
    state.name = name.trim().slice(0, 40);
    store();
    renderMe();
    hello().catch(() => {});
  });

  const drop = $('drop');
  drop.addEventListener('dragover', (e) => {
    e.preventDefault();
    drop.classList.add('dragging');
  });
  drop.addEventListener('dragleave', (e) => {
    if (!drop.contains(e.relatedTarget)) drop.classList.remove('dragging');
  });
  drop.addEventListener('drop', (e) => {
    e.preventDefault();
    drop.classList.remove('dragging');
    const files = [];
    let folders = 0;
    for (const item of Array.from(e.dataTransfer.items || [])) {
      if (item.kind !== 'file') continue;
      if (item.webkitGetAsEntry?.()?.isDirectory) {
        folders++;
        continue;
      }
      const file = item.getAsFile();
      if (file) files.push(file);
    }
    if (!e.dataTransfer.items) files.push(...e.dataTransfer.files);
    if (folders) toast('Folders can’t be sent from a browser yet — zip them first.');
    send(asUploads(files));
  });
  // Dropping a file anywhere else would make the browser open it instead.
  window.addEventListener('dragover', (e) => e.preventDefault());
  window.addEventListener('drop', (e) => e.preventDefault());

  // Tell the app right away when the tab closes.
  window.addEventListener('pagehide', () => {
    if (state.token) navigator.sendBeacon(`${API}/browser/bye?${authQuery()}`);
  });
}

function init() {
  const stored = loadStored();
  state.id = stored.id || null;
  state.token = stored.token || null;
  state.name = stored.name || '';
  state.detail = browserName();
  renderMe();
  wireUp();
  poll();
}

init();
