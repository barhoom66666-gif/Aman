import fs from 'node:fs';
import path from 'node:path';
import express from 'express';
import {
  HttpError,
  colorFor,
  hashPassword,
  newId,
  newToken,
  normalizePhone,
  now,
  phoneQueryDigits,
  publicUser,
  sha256,
  validEnvelope,
  verifyPassword,
} from './util.js';
import { requireAuth } from './auth.js';

const USERNAME_RE = /^[a-z0-9_]{3,20}$/;

function text(value, { min = 1, max = 500, field = 'قيمة' } = {}) {
  if (typeof value !== 'string') throw new HttpError(400, 'bad_request', `${field} غير صالح`);
  const trimmed = value.trim();
  if (trimmed.length < min || trimmed.length > max) {
    throw new HttpError(400, 'bad_request', `${field} يجب أن يكون بين ${min} و${max} حرفًا`);
  }
  return trimmed;
}

function identityKeyOf(value) {
  if (typeof value !== 'string') throw new HttpError(400, 'bad_request', 'مفتاح الهوية مفقود');
  const raw = Buffer.from(value, 'base64');
  if (raw.length !== 32) throw new HttpError(400, 'bad_request', 'مفتاح الهوية يجب أن يكون 32 بايت');
  return value;
}

function messageOut(row) {
  return {
    id: row.id,
    chatId: row.chat_id,
    senderId: row.sender_id,
    clientId: row.client_id,
    kind: row.kind,
    epoch: row.epoch,
    envelope: JSON.parse(row.envelope),
    createdAt: row.created_at,
  };
}

export function createRouter({ db, hub, mediaDir, maxMediaBytes }) {
  fs.mkdirSync(mediaDir, { recursive: true });
  const router = express.Router();
  const auth = requireAuth(db);

  // ---------- helpers ----------

  function memberRow(chatId, userId) {
    return db
      .prepare(
        `SELECT m.*, c.type, c.title, c.epoch, c.created_at AS chat_created_at, c.created_by, c.avatar_color
           FROM chat_members m
           JOIN chats c ON c.id = m.chat_id
          WHERE m.chat_id = ? AND m.user_id = ?`,
      )
      .get(chatId, userId);
  }

  function assertMember(chatId, userId) {
    const row = memberRow(chatId, userId);
    if (!row) throw new HttpError(404, 'not_found', 'المحادثة غير موجودة');
    return row;
  }

  function userByName(username) {
    return db.prepare('SELECT * FROM users WHERE username = ?').get(username);
  }

  function userByIdentifier(identifier) {
    if (!identifier) return null;
    const username = String(identifier).toLowerCase();
    const digits = normalizePhone(identifier);
    const exact = db
      .prepare('SELECT * FROM users WHERE username = ? OR (phone IS NOT NULL AND phone = ?)')
      .get(username, digits);
    if (exact) return exact;

    // تسامح مع من أدخل رقمه المحلي بدل الدولي (أو العكس): آخر 9 أرقام.
    if (digits.length >= 8 && /^[+\d\s()-]+$/.test(String(identifier).trim())) {
      const rows = db
        .prepare('SELECT * FROM users WHERE phone IS NOT NULL AND phone LIKE ? LIMIT 2')
        .all(`%${digits.slice(-9)}`);
      if (rows.length === 1) return rows[0];
    }
    return null;
  }

  function freshUsername() {
    for (let i = 0; i < 12; i += 1) {
      const candidate = `u${newId('').slice(0, 12)}`;
      if (!userByName(candidate)) return candidate;
    }
    throw new HttpError(500, 'internal', 'تعذّر إنشاء اسم مستخدم');
  }

  function chatSummary(chatId, userId) {
    const chat = db.prepare('SELECT * FROM chats WHERE id = ?').get(chatId);
    if (!chat) return null;
    const members = db
      .prepare(
        `SELECT u.*, m.role, m.joined_at, m.last_read_at
           FROM chat_members m JOIN users u ON u.id = m.user_id
          WHERE m.chat_id = ?
          ORDER BY m.joined_at ASC`,
      )
      .all(chatId);
    const me = members.find((m) => m.id === userId);
    if (!me) return null;
    const last = db
      .prepare('SELECT * FROM messages WHERE chat_id = ? ORDER BY created_at DESC LIMIT 1')
      .get(chatId);
    const unread = db
      .prepare('SELECT COUNT(*) AS c FROM messages WHERE chat_id = ? AND created_at > ? AND sender_id <> ?')
      .get(chatId, me.last_read_at, userId).c;
    const peer = chat.type === 'direct' ? members.find((m) => m.id !== userId) : null;

    return {
      id: chat.id,
      type: chat.type,
      title: chat.type === 'direct' ? peer?.display_name ?? 'محادثة' : chat.title,
      avatarColor: chat.type === 'direct' ? peer?.avatar_color ?? '#0EA5A4' : chat.avatar_color,
      epoch: chat.epoch,
      createdBy: chat.created_by,
      createdAt: chat.created_at,
      members: members.map((m) => ({
        ...publicUser(m),
        role: m.role,
        lastReadAt: m.last_read_at,
        online: hub.isOnline(m.id),
      })),
      peer: peer ? publicUser(peer) : null,
      lastReadAt: me.last_read_at,
      unreadCount: unread,
      lastMessage: last ? messageOut(last) : null,
      updatedAt: last ? last.created_at : chat.created_at,
    };
  }

  function broadcastChat(chatId, userId) {
    for (const memberId of hub.chatMemberIds(chatId)) {
      const summary = chatSummary(chatId, memberId);
      if (summary) hub.send(memberId, { type: 'chat', chat: summary, forUser: memberId });
    }
    void userId;
  }

  function sessionFor(userId, device) {
    const token = newToken();
    db.prepare('INSERT INTO sessions (token_hash, user_id, device, created_at) VALUES (?,?,?,?)').run(
      sha256(token),
      userId,
      device ?? 'device',
      now(),
    );
    return token;
  }

  // ---------- auth ----------

  router.post('/auth/register', (req, res) => {
    const phone = normalizePhone(req.body?.phone);
    if (phone.length < 7 || phone.length > 15) {
      throw new HttpError(
        400,
        'bad_phone',
        'أدخل رقم الهاتف مع رمز الدولة (7 إلى 15 رقمًا)، مثال: +971501234567',
      );
    }
    const password = text(req.body?.password, { min: 6, max: 128, field: 'كلمة المرور' });
    const displayName = text(req.body?.displayName, { max: 40, field: 'الاسم' });
    const identityKey = identityKeyOf(req.body?.identityKey);

    let username = null;
    if (req.body?.username != null && String(req.body.username).trim() !== '') {
      username = text(req.body.username, { max: 20, field: 'اسم المستخدم' }).toLowerCase();
      if (!USERNAME_RE.test(username)) {
        throw new HttpError(400, 'bad_username', 'اسم المستخدم يجب أن يكون 3-20 حرفًا لاتينيًا أو أرقامًا أو _');
      }
      if (userByName(username)) throw new HttpError(409, 'username_taken', 'اسم المستخدم محجوز');
    } else {
      username = freshUsername();
    }

    if (db.prepare('SELECT 1 FROM users WHERE phone = ?').get(phone)) {
      throw new HttpError(409, 'phone_taken', 'رقم الهاتف مسجّل بالفعل');
    }

    const user = {
      id: newId('u'),
      username,
      display_name: displayName,
      phone,
      password_hash: hashPassword(password),
      identity_key: identityKey,
      avatar_color: colorFor(username),
      created_at: now(),
      last_seen: now(),
    };
    db.prepare(
      `INSERT INTO users (id, username, display_name, phone, password_hash, identity_key, avatar_color, created_at, last_seen)
       VALUES (@id, @username, @display_name, @phone, @password_hash, @identity_key, @avatar_color, @created_at, @last_seen)`,
    ).run(user);

    const token = sessionFor(user.id, req.body?.device);
    res.status(201).json({ token, user: publicUser(user) });
  });

  router.post('/auth/login', (req, res) => {
    const identifier = text(req.body?.identifier ?? req.body?.username, {
      max: 40,
      field: 'رقم الهاتف أو اسم المستخدم',
    }).toLowerCase();
    const password = text(req.body?.password, { min: 1, max: 128, field: 'كلمة المرور' });
    const user = userByIdentifier(identifier);
    if (!user || !verifyPassword(password, user.password_hash)) {
      throw new HttpError(401, 'bad_credentials', 'رقم الهاتف أو كلمة المرور غير صحيحة');
    }
    db.prepare('UPDATE users SET last_seen = ? WHERE id = ?').run(now(), user.id);
    const token = sessionFor(user.id, req.body?.device);
    res.json({ token, user: publicUser(user) });
  });

  router.post('/auth/logout', auth, (req, res) => {
    const header = req.get('authorization') || '';
    const raw = header.replace(/^Bearer\s+/i, '').trim();
    if (raw) db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(sha256(raw));
    res.json({ ok: true });
  });

  // ---------- me / users ----------

  router.get('/me', auth, (req, res) => {
    res.json({ user: publicUser(req.user) });
  });

  router.patch('/me', auth, (req, res) => {
    const body = req.body ?? {};
    let displayName = req.user.display_name;
    if (body.displayName !== undefined) {
      displayName = text(body.displayName, { max: 40, field: 'الاسم' });
    }
    let phone = req.user.phone ?? null;
    if (body.phone !== undefined) {
      const next = normalizePhone(body.phone);
      if (next === '') {
        phone = null;
      } else if (next.length < 7 || next.length > 15) {
        throw new HttpError(400, 'bad_phone', 'أدخل رقم الهاتف مع رمز الدولة (7 إلى 15 رقمًا)، مثال: +971501234567');
      } else {
        const taken = db.prepare('SELECT 1 FROM users WHERE phone = ? AND id <> ?').get(next, req.user.id);
        if (taken) throw new HttpError(409, 'phone_taken', 'رقم الهاتف مسجّل لحساب آخر');
        phone = next;
      }
    }
    db.prepare('UPDATE users SET display_name = ?, phone = ? WHERE id = ?').run(displayName, phone, req.user.id);
    res.json({ user: publicUser({ ...req.user, display_name: displayName, phone }) });
  });

  // مفتاح الهوية لكل جهاز؛ عند الدخول من جهاز جديد يُحدَّث المفتاح العام
  // (نموذج جهاز واحد لكل حساب في هذه النسخة).
  router.post('/me/identity', auth, (req, res) => {
    const identityKey = identityKeyOf(req.body?.identityKey);
    db.prepare('UPDATE users SET identity_key = ? WHERE id = ?').run(identityKey, req.user.id);
    res.json({ ok: true, identityKey });
  });

  router.get('/users', auth, (req, res) => {
    const q = text(req.query.q ?? '', { min: 0, max: 40, field: 'البحث' });
    if (!q) return res.json({ users: [] });
    const safe = q.replace(/[%_]/g, '');
    const like = `%${safe}%`;
    const digits = phoneQueryDigits(q);
    const alt = digits.replace(/^0+/, '') || digits;
    const rows =
      digits.length >= 3
        ? db
            .prepare(
              `SELECT * FROM users
                WHERE id <> ?
                  AND (username LIKE ? OR display_name LIKE ? OR (phone IS NOT NULL AND (phone LIKE ? OR phone LIKE ?)))
                ORDER BY CASE WHEN phone = ? OR phone = ? THEN 0 ELSE 1 END, username ASC
                LIMIT 20`,
            )
            .all(req.user.id, like, like, `%${digits}%`, `%${alt}%`, digits, alt)
        : db
            .prepare(
              `SELECT * FROM users
                WHERE id <> ? AND (username LIKE ? OR display_name LIKE ?)
                ORDER BY username ASC LIMIT 20`,
            )
            .all(req.user.id, like, like);
    res.json({ users: rows.map((u) => ({ ...publicUser(u), online: hub.isOnline(u.id) })) });
  });

  router.get('/users/:username/key', auth, (req, res) => {
    const user = userByName(String(req.params.username).toLowerCase());
    if (!user) throw new HttpError(404, 'not_found', 'المستخدم غير موجود');
    const prekey = db
      .prepare('SELECT * FROM prekeys WHERE user_id = ? AND used = 0 ORDER BY created_at ASC LIMIT 1')
      .get(user.id);
    if (prekey) db.prepare('UPDATE prekeys SET used = 1 WHERE id = ?').run(prekey.id);
    res.json({
      user: publicUser(user),
      identityKey: user.identity_key,
      prekey: prekey?.key ?? null,
    });
  });

  router.post('/prekeys', auth, (req, res) => {
    const list = Array.isArray(req.body?.prekeys) ? req.body.prekeys.slice(0, 200) : [];
    const insert = db.prepare('INSERT OR IGNORE INTO prekeys (id, user_id, key, used, created_at) VALUES (?,?,?,0,?)');
    const tx = db.transaction(() => {
      for (const item of list) {
        if (typeof item?.id !== 'string' || typeof item?.key !== 'string') continue;
        insert.run(item.id.slice(0, 64), req.user.id, item.key.slice(0, 128), now());
      }
    });
    tx();
    const remaining = db.prepare('SELECT COUNT(*) AS c FROM prekeys WHERE user_id = ? AND used = 0').get(req.user.id).c;
    res.json({ ok: true, remaining });
  });

  // ---------- chats ----------

  router.get('/chats', auth, (req, res) => {
    const ids = db
      .prepare('SELECT chat_id FROM chat_members WHERE user_id = ?')
      .all(req.user.id)
      .map((r) => r.chat_id);
    const chats = ids.map((id) => chatSummary(id, req.user.id)).filter(Boolean);
    chats.sort((a, b) => b.updatedAt - a.updatedAt);
    res.json({ chats });
  });

  router.get('/chats/:id', auth, (req, res) => {
    assertMember(req.params.id, req.user.id);
    const summary = chatSummary(req.params.id, req.user.id);
    res.json({ chat: summary });
  });

  router.post('/chats/direct', auth, (req, res) => {
    const username = text(req.body?.username, { max: 20, field: 'اسم المستخدم' }).toLowerCase();
    const peer = userByName(username);
    if (!peer) throw new HttpError(404, 'not_found', 'المستخدم غير موجود');
    if (peer.id === req.user.id) throw new HttpError(400, 'bad_request', 'لا يمكنك محادثة نفسك');

    const existing = db
      .prepare(
        `SELECT c.id FROM chats c
          JOIN chat_members a ON a.chat_id = c.id AND a.user_id = ?
          JOIN chat_members b ON b.chat_id = c.id AND b.user_id = ?
         WHERE c.type = 'direct'
           AND (SELECT COUNT(*) FROM chat_members m WHERE m.chat_id = c.id) = 2
         LIMIT 1`,
      )
      .get(req.user.id, peer.id);

    if (existing) {
      return res.json({ chat: chatSummary(existing.id, req.user.id), created: false });
    }

    const chatId = newId('c');
    const tx = db.transaction(() => {
      db.prepare(
        'INSERT INTO chats (id, type, title, created_by, created_at, epoch, avatar_color) VALUES (?,?,?,?,?,1,?)',
      ).run(chatId, 'direct', null, req.user.id, now(), colorFor(chatId));
      const addMember = db.prepare(
        'INSERT INTO chat_members (chat_id, user_id, role, joined_at, last_read_at) VALUES (?,?,?,?,0)',
      );
      addMember.run(chatId, req.user.id, 'member', now());
      addMember.run(chatId, peer.id, 'member', now());
    });
    tx();
    broadcastChat(chatId, req.user.id);
    res.status(201).json({ chat: chatSummary(chatId, req.user.id), created: true });
  });

  router.post('/chats/group', auth, (req, res) => {
    const title = text(req.body?.title, { max: 60, field: 'اسم المجموعة' });
    const names = Array.isArray(req.body?.members) ? req.body.members : [];
    const members = [];
    for (const name of names.slice(0, 50)) {
      const user = userByName(String(name).toLowerCase());
      if (user && user.id !== req.user.id && !members.some((m) => m.id === user.id)) members.push(user);
    }
    if (members.length === 0) throw new HttpError(400, 'bad_request', 'أضف عضوًا واحدًا على الأقل');

    const chatId = newId('c');
    const tx = db.transaction(() => {
      db.prepare(
        'INSERT INTO chats (id, type, title, created_by, created_at, epoch, avatar_color) VALUES (?,?,?,?,?,1,?)',
      ).run(chatId, 'group', title, req.user.id, now(), colorFor(chatId));
      const addMember = db.prepare(
        'INSERT INTO chat_members (chat_id, user_id, role, joined_at, last_read_at) VALUES (?,?,?,?,0)',
      );
      addMember.run(chatId, req.user.id, 'admin', now());
      for (const m of members) addMember.run(chatId, m.id, 'member', now());
    });
    tx();
    broadcastChat(chatId, req.user.id);
    res.status(201).json({ chat: chatSummary(chatId, req.user.id) });
  });

  router.post('/chats/:id/members', auth, (req, res) => {
    const me = assertMember(req.params.id, req.user.id);
    if (me.type !== 'group') throw new HttpError(400, 'bad_request', 'ليست مجموعة');
    const names = Array.isArray(req.body?.usernames) ? req.body.usernames : [];
    const added = [];
    const tx = db.transaction(() => {
      const insert = db.prepare(
        'INSERT OR IGNORE INTO chat_members (chat_id, user_id, role, joined_at, last_read_at) VALUES (?,?,?,?,0)',
      );
      for (const name of names.slice(0, 50)) {
        const user = userByName(String(name).toLowerCase());
        if (!user) continue;
        const result = insert.run(me.chat_id, user.id, 'member', now());
        if (result.changes > 0) added.push(user);
      }
      if (added.length > 0) {
        db.prepare('UPDATE chats SET epoch = epoch + 1 WHERE id = ?').run(me.chat_id);
      }
    });
    tx();
    const chat = chatSummary(me.chat_id, req.user.id);
    if (added.length > 0) {
      hub.broadcastToChat(me.chat_id, { type: 'chat_update', chatId: me.chat_id, epoch: chat.epoch, reason: 'members' });
      broadcastChat(me.chat_id, req.user.id);
    }
    res.json({ chat, added: added.map(publicUser) });
  });

  router.delete('/chats/:id/members/:userId', auth, (req, res) => {
    const me = assertMember(req.params.id, req.user.id);
    if (me.type !== 'group') throw new HttpError(400, 'bad_request', 'ليست مجموعة');
    if (me.created_by !== req.user.id) throw new HttpError(403, 'forbidden', 'المشرف فقط يمكنه الإزالة');
    if (req.params.userId === req.user.id) throw new HttpError(400, 'bad_request', 'استخدم مغادرة المجموعة');
    db.prepare('DELETE FROM chat_members WHERE chat_id = ? AND user_id = ?').run(me.chat_id, req.params.userId);
    db.prepare('UPDATE chats SET epoch = epoch + 1 WHERE id = ?').run(me.chat_id);
    hub.send(req.params.userId, { type: 'removed', chatId: me.chat_id });
    hub.broadcastToChat(me.chat_id, { type: 'chat_update', chatId: me.chat_id, epoch: me.epoch + 1, reason: 'members' });
    broadcastChat(me.chat_id, req.user.id);
    res.json({ ok: true });
  });

  router.post('/chats/:id/leave', auth, (req, res) => {
    const me = assertMember(req.params.id, req.user.id);
    db.prepare('DELETE FROM chat_members WHERE chat_id = ? AND user_id = ?').run(me.chat_id, req.user.id);
    if (me.type === 'group') {
      db.prepare('UPDATE chats SET epoch = epoch + 1 WHERE id = ?').run(me.chat_id);
      hub.broadcastToChat(me.chat_id, { type: 'chat_update', chatId: me.chat_id, epoch: me.epoch + 1, reason: 'members' });
      broadcastChat(me.chat_id, req.user.id);
    }
    res.json({ ok: true });
  });

  // ---------- messages ----------

  router.get('/chats/:id/messages', auth, (req, res) => {
    assertMember(req.params.id, req.user.id);
    const limit = Math.min(Math.max(Number(req.query.limit) || 40, 1), 100);
    const before = Number(req.query.before) || Number.MAX_SAFE_INTEGER;
    const rows = db
      .prepare(
        `SELECT * FROM messages
          WHERE chat_id = ? AND created_at < ?
          ORDER BY created_at DESC LIMIT ?`,
      )
      .all(req.params.id, before, limit + 1);
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    res.json({ messages: page.map(messageOut).reverse(), hasMore });
  });

  router.post('/chats/:id/messages', auth, (req, res) => {
    const me = assertMember(req.params.id, req.user.id);
    const kind = String(req.body?.kind ?? 'text');
    if (!['text', 'media'].includes(kind)) throw new HttpError(400, 'bad_request', 'نوع رسالة غير مدعوم');
    const envelope = req.body?.envelope;
    if (!validEnvelope(envelope)) throw new HttpError(400, 'bad_envelope', 'مغلف التشفير غير صالح');
    const clientId = typeof req.body?.clientId === 'string' ? req.body.clientId.slice(0, 64) : null;

    let epoch = null;
    if (me.type === 'group') {
      epoch = Number(req.body?.epoch ?? me.epoch);
      if (!Number.isInteger(epoch) || epoch < 1) throw new HttpError(400, 'bad_request', 'رقم الجيل غير صالح');
      if (epoch !== me.epoch) {
        throw new HttpError(409, 'epoch_mismatch', 'تغيّرت أعضاء المجموعة، أعد المحاولة');
      }
    }

    if (clientId) {
      const existing = db
        .prepare('SELECT * FROM messages WHERE chat_id = ? AND sender_id = ? AND client_id = ?')
        .get(me.chat_id, req.user.id, clientId);
      if (existing) return res.json({ message: messageOut(existing), duplicate: true });
    }

    const row = {
      id: newId('m'),
      chat_id: me.chat_id,
      sender_id: req.user.id,
      client_id: clientId,
      kind,
      epoch,
      envelope: JSON.stringify(envelope),
      created_at: now(),
    };
    db.prepare(
      `INSERT INTO messages (id, chat_id, sender_id, client_id, kind, epoch, envelope, created_at)
       VALUES (@id, @chat_id, @sender_id, @client_id, @kind, @epoch, @envelope, @created_at)`,
    ).run(row);

    const message = messageOut(row);
    hub.broadcastToChat(me.chat_id, { type: 'message', chatId: me.chat_id, message }, req.user.id);
    res.status(201).json({ message });
  });

  router.post('/chats/:id/read', auth, (req, res) => {
    assertMember(req.params.id, req.user.id);
    const at = now();
    db.prepare('UPDATE chat_members SET last_read_at = ? WHERE chat_id = ? AND user_id = ?').run(
      at,
      req.params.id,
      req.user.id,
    );
    hub.broadcastToChat(req.params.id, { type: 'read', chatId: req.params.id, userId: req.user.id, at }, req.user.id);
    res.json({ ok: true, at });
  });

  // ---------- group key envelopes ----------

  router.post('/chats/:id/keys', auth, (req, res) => {
    const me = assertMember(req.params.id, req.user.id);
    if (me.type !== 'group') throw new HttpError(400, 'bad_request', 'ليست مجموعة');
    const epoch = Number(req.body?.epoch);
    if (!Number.isInteger(epoch) || epoch < 1) throw new HttpError(400, 'bad_request', 'رقم الجيل غير صالح');
    const envelopes = req.body?.envelopes;
    if (!envelopes || typeof envelopes !== 'object') throw new HttpError(400, 'bad_request', 'المغلفات مفقودة');

    const members = db
      .prepare('SELECT u.username, u.id FROM chat_members m JOIN users u ON u.id = m.user_id WHERE m.chat_id = ?')
      .all(me.chat_id);
    const byName = new Map(members.map((m) => [m.username, m.id]));

    const upsert = db.prepare(
      `INSERT INTO group_keys (chat_id, epoch, recipient_id, sender_id, envelope, created_at)
       VALUES (?,?,?,?,?,?)
       ON CONFLICT (chat_id, epoch, recipient_id)
       DO UPDATE SET sender_id = excluded.sender_id, envelope = excluded.envelope, created_at = excluded.created_at`,
    );
    let count = 0;
    const tx = db.transaction(() => {
      for (const [username, envelope] of Object.entries(envelopes)) {
        const recipientId = byName.get(username);
        if (!recipientId) continue;
        if (!validEnvelope(envelope)) throw new HttpError(400, 'bad_envelope', 'مغلف مفتاح غير صالح');
        upsert.run(me.chat_id, epoch, recipientId, req.user.id, JSON.stringify(envelope), now());
        count += 1;
      }
    });
    tx();
    hub.broadcastToChat(me.chat_id, { type: 'keys', chatId: me.chat_id, epoch });
    res.json({ ok: true, count });
  });

  router.get('/chats/:id/keys/:epoch', auth, (req, res) => {
    assertMember(req.params.id, req.user.id);
    const epoch = Number(req.params.epoch);
    const row = db
      .prepare('SELECT * FROM group_keys WHERE chat_id = ? AND epoch = ? AND recipient_id = ?')
      .get(req.params.id, epoch, req.user.id);
    if (!row) throw new HttpError(404, 'no_key', 'لا يوجد مفتاح لهذا الجيل بعد');
    res.json({ epoch, senderId: row.sender_id, envelope: JSON.parse(row.envelope) });
  });

  // ---------- media (client-side encrypted blobs) ----------

  router.post('/media', auth, express.raw({ type: () => true, limit: maxMediaBytes }), (req, res) => {
    const chatId = String(req.query.chatId ?? '');
    if (!chatId) throw new HttpError(400, 'bad_request', 'معرّف المحادثة مفقود');
    assertMember(chatId, req.user.id);
    const body = req.body;
    if (!Buffer.isBuffer(body) || body.length === 0) throw new HttpError(400, 'bad_request', 'الملف فارغ');
    const id = newId('f');
    fs.writeFileSync(path.join(mediaDir, id), body);
    db.prepare('INSERT INTO media (id, owner_id, chat_id, size, created_at) VALUES (?,?,?,?,?)').run(
      id,
      req.user.id,
      chatId,
      body.length,
      now(),
    );
    res.status(201).json({ id, size: body.length });
  });

  router.get('/media/:id', auth, (req, res) => {
    const row = db.prepare('SELECT * FROM media WHERE id = ?').get(req.params.id);
    if (!row) throw new HttpError(404, 'not_found', 'الملف غير موجود');
    assertMember(row.chat_id, req.user.id);
    res.setHeader('content-type', 'application/octet-stream');
    res.setHeader('content-length', String(row.size));
    fs.createReadStream(path.join(mediaDir, req.params.id)).pipe(res);
  });

  return router;
}
