// Wisp signaling server (Cloudflare Worker).
//
// Devices behind the same public IP, which usually means the same home
// network, share a room. Everyone in a room sees who else is there, and
// browsers pass WebRTC setup messages to each other through it. Files
// never go through here: they go straight between the devices.

export default {
  async fetch(request, env) {
    if (request.headers.get('Upgrade') !== 'websocket') {
      return new Response('Wisp signaling server\n');
    }
    const room = env.ROOMS.get(env.ROOMS.idFromName(roomFor(request)));
    return room.fetch(request);
  },
};

/** The room for a request: its IPv4 address, or its IPv6 /64 network. */
function roomFor(request) {
  const ip = request.headers.get('CF-Connecting-IP') ?? 'local';
  // ponytail: devices mixing IPv4 and IPv6 land in different rooms; add
  // room codes if that turns out to be common.
  return ip.includes(':') ? ip.split(':').slice(0, 4).join(':') : ip;
}

export class Room {
  constructor(ctx) {
    this.ctx = ctx;
    // Keep-alive pings are answered without waking the room up.
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  async fetch() {
    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, raw) {
    if (typeof raw !== 'string' || raw.length > 64 * 1024) return;
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    if (msg.type === 'hello') {
      const peer = cleanPeer(msg.peer);
      if (!peer) return;
      const taken = this.ctx.getWebSockets()
        .some((other) => other !== ws && other.deserializeAttachment()?.id === peer.id);
      if (taken) return ws.close(1008, 'That id is in use');
      ws.serializeAttachment(peer);
      this.broadcast();
    } else if (msg.type === 'signal') {
      const from = ws.deserializeAttachment();
      if (!from || typeof msg.to !== 'string') return;
      const text = JSON.stringify({ type: 'signal', from: from.id, data: msg.data });
      for (const other of this.ctx.getWebSockets()) {
        if (other.deserializeAttachment()?.id === msg.to) other.send(text);
      }
    }
  }

  webSocketClose(ws) {
    this.broadcast(ws);
  }

  webSocketError(ws) {
    this.broadcast(ws);
  }

  /** Tells everyone who's here, except [gone], which just left. */
  broadcast(gone) {
    const sockets = this.ctx.getWebSockets().filter((ws) => ws !== gone);
    const peers = sockets.map((ws) => ws.deserializeAttachment()).filter(Boolean);
    const text = JSON.stringify({ type: 'peers', peers });
    for (const ws of sockets) {
      try {
        ws.send(text);
      } catch {
        // Already closing.
      }
    }
  }
}

const text = (value, max) =>
  typeof value === 'string' && value.length > 0 && value.length <= max ? value : undefined;

/** Keeps only what the others need, in sizes they can show. */
export function cleanPeer(peer) {
  if (typeof peer !== 'object' || peer === null) return null;
  const id = text(peer.id, 64);
  const name = text(peer.name, 64);
  if (!id || !name) return null;
  // An installed device's own web app, which must be on a local network:
  // this is where browsers get sent, so no links to the internet.
  const lan = text(peer.lan, 64);
  const local = /^http:\/\/(10(\.\d{1,3}){3}|192\.168(\.\d{1,3}){2}|172\.(1[6-9]|2\d|3[01])(\.\d{1,3}){2}):\d{1,5}$/;
  return {
    id,
    name,
    platform: text(peer.platform, 16) ?? 'browser',
    detail: text(peer.detail, 40),
    lan: lan && local.test(lan) ? lan : undefined,
  };
}
