import { WebSocketServer } from 'ws';
import { authenticateToken } from './auth.js';
import { now } from './util.js';

export class Hub {
  constructor(db) {
    this.db = db;
    /** @type {Map<string, Set<import('ws').WebSocket>>} */
    this.sockets = new Map();
  }

  isOnline(userId) {
    return (this.sockets.get(userId)?.size ?? 0) > 0;
  }

  add(userId, socket) {
    let set = this.sockets.get(userId);
    const first = !set || set.size === 0;
    if (!set) {
      set = new Set();
      this.sockets.set(userId, set);
    }
    set.add(socket);
    if (first) this.announcePresence(userId, true);
  }

  remove(userId, socket) {
    const set = this.sockets.get(userId);
    if (!set) return;
    set.delete(socket);
    if (set.size === 0) {
      this.sockets.delete(userId);
      this.db.prepare('UPDATE users SET last_seen = ? WHERE id = ?').run(now(), userId);
      this.announcePresence(userId, false);
    }
  }

  send(userId, payload) {
    const set = this.sockets.get(userId);
    if (!set) return;
    const data = JSON.stringify(payload);
    for (const socket of set) {
      if (socket.readyState === 1) socket.send(data);
    }
  }

  chatMemberIds(chatId) {
    return this.db
      .prepare('SELECT user_id FROM chat_members WHERE chat_id = ?')
      .all(chatId)
      .map((r) => r.user_id);
  }

  broadcastToChat(chatId, payload, exceptUserId = null) {
    for (const memberId of this.chatMemberIds(chatId)) {
      if (memberId === exceptUserId) continue;
      this.send(memberId, payload);
    }
  }

  contactIds(userId) {
    return this.db
      .prepare(
        `SELECT DISTINCT other.user_id AS id
           FROM chat_members mine
           JOIN chat_members other ON other.chat_id = mine.chat_id
          WHERE mine.user_id = ? AND other.user_id <> ?`,
      )
      .all(userId, userId)
      .map((r) => r.id);
  }

  announcePresence(userId, online) {
    const payload = { type: 'presence', userId, online, lastSeen: online ? 0 : now() };
    for (const contactId of this.contactIds(userId)) this.send(contactId, payload);
  }
}

export function attachWebSocket(server, db, hub) {
  const wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname !== '/ws') {
      socket.destroy();
      return;
    }
    const user = authenticateToken(db, url.searchParams.get('token'));
    if (!user) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      ws.userId = user.id;
      wss.emit('connection', ws, req, user);
    });
  });

  wss.on('connection', (ws, _req, user) => {
    hub.add(user.id, ws);
    ws.send(JSON.stringify({ type: 'ready', userId: user.id, online: hub.contactIds(user.id).filter((id) => hub.isOnline(id)) }));

    ws.on('message', (raw) => {
      let msg;
      try {
        msg = JSON.parse(String(raw));
      } catch {
        return;
      }
      if (!msg || typeof msg.type !== 'string') return;

      if (msg.type === 'ping') {
        ws.send(JSON.stringify({ type: 'pong', t: now() }));
        return;
      }

      if (msg.type === 'typing' && typeof msg.chatId === 'string') {
        const member = db
          .prepare('SELECT 1 FROM chat_members WHERE chat_id = ? AND user_id = ?')
          .get(msg.chatId, user.id);
        if (!member) return;
        hub.broadcastToChat(msg.chatId, { type: 'typing', chatId: msg.chatId, userId: user.id }, user.id);
      }
    });

    ws.on('close', () => hub.remove(user.id, ws));
    ws.on('error', () => hub.remove(user.id, ws));
  });

  return wss;
}
