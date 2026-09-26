// Checks the signaling server end to end. Start it first with
// `npx wrangler dev --port 8787`, then run `node test.mjs`.
import assert from 'node:assert/strict';

const url = process.env.SIGNAL_URL ?? 'ws://127.0.0.1:8787';

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

const peersIs = (ids) => (m) =>
  m.type === 'peers' && m.peers.map((p) => p.id).sort().join() === ids.sort().join();

const a = await join({ id: 'a', name: 'Laptop', platform: 'linux', lan: 'http://192.168.1.24:53319' });
const b = await join({ id: 'b', name: 'Phone', lan: 'https://evil.example' });

const seen = await a.next(peersIs(['a', 'b']));
const byId = Object.fromEntries(seen.peers.map((p) => [p.id, p]));
assert.equal(byId.a.lan, 'http://192.168.1.24:53319');
assert.equal(byId.b.lan, undefined, 'links outside the LAN are dropped');
assert.equal(byId.b.platform, 'browser');

a.ws.send(JSON.stringify({ type: 'signal', to: 'b', data: { hi: 1 } }));
assert.deepEqual(await b.next((m) => m.type === 'signal'), { type: 'signal', from: 'a', data: { hi: 1 } });

// Someone else can't take a's id.
const imposter = new WebSocket(url);
const closed = new Promise((resolve) => (imposter.onclose = (e) => resolve(e.code)));
imposter.onopen = () => imposter.send(JSON.stringify({ type: 'hello', peer: { id: 'a', name: 'x' } }));
assert.equal(await closed, 1008);

b.ws.close();
await a.next(peersIs(['a']));
a.ws.close();
console.log('signaling ok');
