// Checks the signaling server end to end. Start it first with
// `npx wrangler dev --port 8787`, then run `node test.mjs`.
import assert from 'node:assert/strict';

const url = process.env.SIGNAL_URL ?? 'ws://127.0.0.1:8787';

// Browsers ask for relay servers first.
const ice = await (await fetch(url.replace(/^ws/, 'http') + '/ice')).json();
assert.ok(ice.iceServers.length > 0, 'ice servers');

function join(peer) {
  const ws = new WebSocket(url);
  const inbox = [];
  const waiters = [];
  ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    const i = waiters.findIndex((w) => w.test(msg));
    if (i >= 0) waiters.splice(i, 1)[0].resolve(msg);
    else inbox.push(msg);
  };
  const next = (test) => {
    const i = inbox.findIndex(test);
    if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
    return new Promise((resolve, reject) => {
      waiters.push({ test, resolve });
      setTimeout(() => reject(new Error('timed out')), 5000);
    });
  };
  return new Promise((resolve) => {
    ws.onopen = () => {
      ws.send(JSON.stringify({ type: 'hello', peer }));
      resolve({ ws, next });
    };
  });
}

// Unique ids: on a live server, the room may have real devices in it too.
const run = Math.random().toString(36).slice(2, 8);
const A = `test-a-${run}`;
const B = `test-b-${run}`;
const ours = (m) => m.peers.map((p) => p.id).filter((id) => id.endsWith(run)).sort().join();
const peersIs = (ids) => (m) => m.type === 'peers' && ours(m) === ids.sort().join();

const a = await join({ id: A, name: 'Laptop', platform: 'linux', lan: 'http://192.168.1.24:53319' });
const b = await join({ id: B, name: 'Phone', lan: 'https://evil.example' });

const seen = await a.next(peersIs([A, B]));
const byId = Object.fromEntries(seen.peers.map((p) => [p.id, p]));
assert.equal(byId[A].lan, 'http://192.168.1.24:53319');
assert.equal(byId[B].lan, undefined, 'links outside the LAN are dropped');
assert.equal(byId[B].platform, 'browser');

a.ws.send(JSON.stringify({ type: 'signal', to: B, data: { hi: 1 } }));
assert.deepEqual(await b.next((m) => m.type === 'signal'), { type: 'signal', from: A, data: { hi: 1 } });

// Someone else can't take a's id.
const imposter = new WebSocket(url);
const closed = new Promise((resolve) => (imposter.onclose = (e) => resolve(e.code)));
imposter.onopen = () => imposter.send(JSON.stringify({ type: 'hello', peer: { id: A, name: 'x' } }));
assert.equal(await closed, 1008);

b.ws.close();
await a.next(peersIs([A]));
a.ws.close();
console.log('signaling ok');
