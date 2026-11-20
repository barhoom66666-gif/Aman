import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const PORT = 18000 + Math.floor(Math.random() * 1000);
const BASE = `http://127.0.0.1:${PORT}`;
const DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'aman-test-'));
let child;

// ---------- crypto helpers (same scheme as the Flutter client) ----------
const PKCS8_PREFIX = Buffer.from('302e020100300506032b656e04220420', 'hex');
const SPKI_PREFIX = Buffer.from('302a300506032b656e032100', 'hex');

function newKeyPair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('x25519');
  const pubRaw = publicKey.export({ type: 'spki', format: 'der' }).subarray(-32);
  const privRaw = privateKey.export({ type: 'pkcs8', format: 'der' }).subarray(-32);
  return { publicKey, privateKey, pubRaw, privRaw };
}

function importPublic(raw) {
  return crypto.createPublicKey({
    key: Buffer.concat([SPKI_PREFIX, raw]),
    format: 'der',
    type: 'spki',
  });
}

function importPrivate(raw) {
  return crypto.createPrivateKey({
    key: Buffer.concat([PKCS8_PREFIX, raw]),
    format: 'der',
    type: 'pkcs8',
  });
}

function deriveKey(shared, salt, info) {
  return Buffer.from(crypto.hkdfSync('sha256', shared, salt, Buffer.from(info), 32));
}

function seal({ chatId, senderId, recipientId, recipientPubRaw, plaintext, kind = 'pairwise' }) {
  const eph = newKeyPair();
  const shared = crypto.diffieHellman({
    privateKey: eph.privateKey,
    publicKey: importPublic(recipientPubRaw),
  });
  const salt = crypto.randomBytes(16);
  const nonce = crypto.randomBytes(12);
  const info = kind === 'pairwise' ? 'aman/v1/pairwise' : 'aman/v1/groupkey';
  const aad = `aman/v1|${chatId}|${senderId}|${recipientId}`;
  const key = deriveKey(shared, salt, info);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from(aad));
  const body = Buffer.isBuffer(plaintext) ? plaintext : Buffer.from(plaintext, 'utf8');
  const ct = Buffer.concat([cipher.update(body), cipher.final(), cipher.getAuthTag()]);
  return {
    v: 1,
    alg: 'x25519-aesgcm',
    epk: eph.pubRaw.toString('base64'),
    salt: salt.toString('base64'),
    nonce: nonce.toString('base64'),
    ct: ct.toString('base64'),
  };
}

function open({ chatId, senderId, recipientId, myPrivRaw, envelope, kind = 'pairwise' }) {
  const shared = crypto.diffieHellman({
    privateKey: importPrivate(myPrivRaw),
    publicKey: importPublic(Buffer.from(envelope.epk, 'base64')),
  });
  const info = kind === 'pairwise' ? 'aman/v1/pairwise' : 'aman/v1/groupkey';
  const key = deriveKey(shared, Buffer.from(envelope.salt, 'base64'), info);
  const aad = `aman/v1|${chatId}|${senderId}|${recipientId}`;
  const raw = Buffer.from(envelope.ct, 'base64');
  const tag = raw.subarray(-16);
  const ct = raw.subarray(0, -16);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.nonce, 'base64'));
  decipher.setAAD(Buffer.from(aad));
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ct), decipher.final()]);
}

let groupKeySeq = 0;
function sealGroupMessage({ chatId, epoch, senderId, groupKey, plaintext }) {
  const nonce = crypto.randomBytes(12);
  groupKeySeq += 1;
  const aad = `aman/v1/group|${chatId}|${epoch}|${senderId}`;
  const cipher = crypto.createCipheriv('aes-256-gcm', groupKey, nonce);
  cipher.setAAD(Buffer.from(aad));
  const ct = Buffer.concat([cipher.update(Buffer.from(plaintext)), cipher.final(), cipher.getAuthTag()]);
  return { v: 1, alg: 'senderkey-aesgcm', nonce: nonce.toString('base64'), ct: ct.toString('base64') };
}

function openGroupMessage({ chatId, epoch, senderId, groupKey, envelope }) {
  const raw = Buffer.from(envelope.ct, 'base64');
  const tag = raw.subarray(-16);
  const ct = raw.subarray(0, -16);
  const decipher = crypto.createDecipheriv('aes-256-gcm', groupKey, Buffer.from(envelope.nonce, 'base64'));
  decipher.setAAD(Buffer.from(`aman/v1/group|${chatId}|${epoch}|${senderId}`));
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ct), decipher.final()]);
}

// ---------- http helpers ----------
async function api(pathname, { method = 'GET', token, body, raw, contentType } = {}) {
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
  let payload;
  if (raw !== undefined) {
    payload = raw;
    headers['content-type'] = contentType || 'application/octet-stream';
  } else if (body !== undefined) {
    payload = JSON.stringify(body);
    headers['content-type'] = 'application/json';
  }
  const res = await fetch(BASE + pathname, { method, headers, body: payload });
  const type = res.headers.get('content-type') || '';
  const data = type.includes('application/json') ? await res.json() : Buffer.from(await res.arrayBuffer());
  if (!res.ok) throw new Error(`${method} ${pathname} -> ${res.status} ${JSON.stringify(data)}`);
  return data;
}

function phoneFor(username) {
  const hex = crypto.createHash('sha256').update(username).digest('hex').slice(0, 12);
  return '9' + BigInt(`0x${hex}`).toString().padStart(12, '0').slice(-12);
}

async function register(username, displayName, phone = phoneFor(username)) {
  const keys = newKeyPair();
  const data = await api('/api/auth/register', {
    method: 'POST',
    body: {
      username,
      phone,
      password: 'secret-pass-123',
      displayName,
      identityKey: keys.pubRaw.toString('base64'),
      device: 'test',
    },
  });
  return { ...keys, token: data.token, user: data.user };
}

function connectWs(token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${BASE.replace('http', 'ws')}/ws?token=${encodeURIComponent(token)}`);
    const queue = [];
    ws.addEventListener('message', (event) => {
      queue.push(JSON.parse(event.data));
    });
    ws.addEventListener('open', () => resolve({ ws, queue }));
    ws.addEventListener('error', reject);
  });
}

async function waitFor(queue, predicate, timeout = 3000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const found = queue.find(predicate);
    if (found) return found;
    await new Promise((r) => setTimeout(r, 25));
  }
  throw new Error('waitFor timeout');
}

before(async () => {
  child = spawn(process.execPath, ['src/index.js'], {
    cwd: path.resolve(import.meta.dirname, '..'),
    env: { ...process.env, PORT: String(PORT), DATA_DIR, MAX_MEDIA_BYTES: '5242880' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stderr.on('data', (d) => process.stderr.write(d));
  const start = Date.now();
  while (Date.now() - start < 15000) {
    try {
      const res = await fetch(BASE + '/health');
      if (res.ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error('server did not start');
});

after(() => {
  child?.kill('SIGKILL');
  fs.rmSync(DATA_DIR, { recursive: true, force: true });
});

test('تسجيل، محادثة فردية مشفرة، إشعار فوري', async () => {
  const ali = await register('ali_test', 'علي');
  const sara = await register('sara_test', 'سارة');

  const login = await api('/api/auth/login', {
    method: 'POST',
    body: { identifier: ali.user.phone, password: 'secret-pass-123' },
  });
  assert.ok(login.token);

  const loginByName = await api('/api/auth/login', {
    method: 'POST',
    body: { username: 'ali_test', password: 'secret-pass-123' },
  });
  assert.ok(loginByName.token);

  const found = await api('/api/users?q=sara', { token: ali.token });
  assert.equal(found.users.length, 1);
  assert.equal(found.users[0].username, 'sara_test');

  const foundByPhone = await api(`/api/users?q=${sara.user.phone}`, { token: ali.token });
  assert.equal(foundByPhone.users[0].username, 'sara_test');

  const arabicPhone = sara.user.phone.replace(/[0-9]/g, (d) => '٠١٢٣٤٥٦٧٨٩'[Number(d)]);
  const foundByArabicPhone = await api(`/api/users?q=${encodeURIComponent(arabicPhone)}`, {
    token: ali.token,
  });
  assert.equal(foundByArabicPhone.users[0].username, 'sara_test');

  const localLogin = await api('/api/auth/login', {
    method: 'POST',
    body: { identifier: sara.user.phone.slice(-9), password: 'secret-pass-123' },
  });
  assert.ok(localLogin.token);

  const directory = await api('/api/users', { token: ali.token });
  assert.ok(directory.users.some((u) => u.username === 'sara_test'));

  const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=';
  const withAvatar = await api('/api/me/avatar', {
    method: 'POST',
    token: sara.token,
    body: { image: png, mime: 'image/png' },
  });
  assert.match(withAvatar.user.avatarUrl, /^\/api\/avatars\/avatar-/);
  const fetchedAvatar = await api(withAvatar.user.avatarUrl.split('?')[0]);
  assert.ok(Buffer.isBuffer(fetchedAvatar));
  assert.ok(fetchedAvatar.length > 20);

  const { chat } = await api('/api/chats/direct', {
    method: 'POST',
    token: ali.token,
    body: { username: 'sara_test' },
  });
  assert.equal(chat.type, 'direct');
  assert.equal(chat.title, 'سارة');

  const saraWs = await connectWs(sara.token);
  await waitFor(saraWs.queue, (m) => m.type === 'ready');

  const plaintext = 'مرحبا سارة، هذه رسالة مشفرة من الطرف إلى الطرف 🔐';
  const envelope = seal({
    chatId: chat.id,
    senderId: ali.user.id,
    recipientId: sara.user.id,
    recipientPubRaw: sara.pubRaw,
    plaintext,
  });

  const { message } = await api(`/api/chats/${chat.id}/messages`, {
    method: 'POST',
    token: ali.token,
    body: { clientId: 'c-1', kind: 'text', envelope },
  });
  assert.equal(message.kind, 'text');

  const pushed = await waitFor(saraWs.queue, (m) => m.type === 'message' && m.message.id === message.id);
  assert.equal(pushed.message.senderId, ali.user.id);

  const page = await api(`/api/chats/${chat.id}/messages`, { token: sara.token });
  assert.equal(page.messages.length, 1);
  const decrypted = open({
    chatId: chat.id,
    senderId: ali.user.id,
    recipientId: sara.user.id,
    myPrivRaw: sara.privRaw,
    envelope: page.messages[0].envelope,
  }).toString('utf8');
  assert.equal(decrypted, plaintext);

  const chats = await api('/api/chats', { token: sara.token });
  assert.equal(chats.chats[0].unreadCount, 1);

  await api(`/api/chats/${chat.id}/read`, { method: 'POST', token: sara.token });
  const afterRead = await api('/api/chats', { token: sara.token });
  assert.equal(afterRead.chats[0].unreadCount, 0);

  saraWs.ws.close();
});

test('إرسال وسائط مشفّرة واسترجاعها', async () => {
  const ali = await register('ali_media', 'علي');
  const sara = await register('sara_media', 'سارة');
  const { chat } = await api('/api/chats/direct', {
    method: 'POST',
    token: ali.token,
    body: { username: 'sara_media' },
  });

  const fileKey = crypto.randomBytes(32);
  const nonce = crypto.randomBytes(12);
  const plain = crypto.randomBytes(4096);
  const cipher = crypto.createCipheriv('aes-256-gcm', fileKey, nonce);
  const blob = Buffer.concat([cipher.update(plain), cipher.final(), cipher.getAuthTag()]);

  const uploaded = await api(`/api/media?chatId=${chat.id}`, {
    method: 'POST',
    token: ali.token,
    raw: blob,
  });
  assert.equal(uploaded.size, blob.length);

  const downloaded = await fetch(`${BASE}/api/media/${uploaded.id}`, {
    headers: { authorization: `Bearer ${sara.token}` },
  });
  const body = Buffer.from(await downloaded.arrayBuffer());
  assert.deepEqual(body, blob);

  const tag = body.subarray(-16);
  const ct = body.subarray(0, -16);
  const decipher = crypto.createDecipheriv('aes-256-gcm', fileKey, nonce);
  decipher.setAuthTag(tag);
  const out = Buffer.concat([decipher.update(ct), decipher.final()]);
  assert.deepEqual(out, plain);

  // غير الأعضاء لا يستطيعون التحميل
  const outsider = await register('outsider_media', 'غريب');
  const denied = await fetch(`${BASE}/api/media/${uploaded.id}`, {
    headers: { authorization: `Bearer ${outsider.token}` },
  });
  assert.equal(denied.status, 404);
});

test('مجموعة: توزيع مفتاح المجموعة ورسالة جماعية', async () => {
  const ali = await register('ali_grp', 'علي');
  const sara = await register('sara_grp', 'سارة');
  const omar = await register('omar_grp', 'عمر');

  const lone = await api('/api/chats/group', {
    method: 'POST',
    token: ali.token,
    body: { title: 'مجموعة فارغة', members: [] },
  });
  assert.equal(lone.chat.members.length, 1);
  assert.equal(lone.chat.members[0].username, 'ali_grp');
  const loneAdded = await api(`/api/chats/${lone.chat.id}/members`, {
    method: 'POST',
    token: ali.token,
    body: { usernames: ['sara_grp'] },
  });
  assert.equal(loneAdded.chat.members.length, 2);
  assert.equal(loneAdded.chat.epoch, 2);

  const { chat } = await api('/api/chats/group', {
    method: 'POST',
    token: ali.token,
    body: { title: 'أصدقاء', members: ['sara_grp', 'omar_grp'] },
  });
  assert.equal(chat.type, 'group');
  assert.equal(chat.members.length, 3);
  assert.equal(chat.epoch, 1);

  const groupKey = crypto.randomBytes(32);
  const envelopes = {};
  for (const member of [ali, sara, omar]) {
    envelopes[member.user.username] = seal({
      chatId: chat.id,
      senderId: ali.user.id,
      recipientId: member.user.id,
      recipientPubRaw: member.pubRaw,
      plaintext: groupKey,
      kind: 'groupkey',
    });
  }
  const posted = await api(`/api/chats/${chat.id}/keys`, {
    method: 'POST',
    token: ali.token,
    body: { epoch: 1, envelopes },
  });
  assert.equal(posted.count, 3);

  const mine = await api(`/api/chats/${chat.id}/keys/1`, { token: sara.token });
  const saraKey = open({
    chatId: chat.id,
    senderId: ali.user.id,
    recipientId: sara.user.id,
    myPrivRaw: sara.privRaw,
    envelope: mine.envelope,
    kind: 'groupkey',
  });
  assert.deepEqual(saraKey, groupKey);

  const envelope = sealGroupMessage({
    chatId: chat.id,
    epoch: 1,
    senderId: ali.user.id,
    groupKey,
    plaintext: 'مرحبا بالجميع',
  });
  const { message } = await api(`/api/chats/${chat.id}/messages`, {
    method: 'POST',
    token: ali.token,
    body: { clientId: 'g-1', kind: 'text', epoch: 1, envelope },
  });
  assert.equal(message.epoch, 1);

  const page = await api(`/api/chats/${chat.id}/messages`, { token: omar.token });
  const plain = openGroupMessage({
    chatId: chat.id,
    epoch: 1,
    senderId: ali.user.id,
    groupKey: saraKey,
    envelope: page.messages[0].envelope,
  });
  assert.equal(plain.toString('utf8'), 'مرحبا بالجميع');

  // إضافة عضو ترفع الجيل وتمنع الرسائل بالجيل القديم
  await register('layla_grp', 'ليلى');
  await api(`/api/chats/${chat.id}/members`, {
    method: 'POST',
    token: ali.token,
    body: { usernames: ['layla_grp'] },
  });
  const updated = await api(`/api/chats/${chat.id}`, { token: ali.token });
  assert.equal(updated.chat.epoch, 2);

  const stale = await fetch(`${BASE}/api/chats/${chat.id}/messages`, {
    method: 'POST',
    headers: { authorization: `Bearer ${ali.token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ clientId: 'g-2', kind: 'text', epoch: 1, envelope }),
  });
  assert.equal(stale.status, 409);
});

test('منع التكرار (idempotency) ورفض المغلفات غير الصالحة', async () => {
  const ali = await register('ali_idem', 'علي');
  const sara = await register('sara_idem', 'سارة');
  const { chat } = await api('/api/chats/direct', {
    method: 'POST',
    token: ali.token,
    body: { username: 'sara_idem' },
  });
  const envelope = seal({
    chatId: chat.id,
    senderId: ali.user.id,
    recipientId: sara.user.id,
    recipientPubRaw: sara.pubRaw,
    plaintext: 'مرة واحدة',
  });

  const first = await api(`/api/chats/${chat.id}/messages`, {
    method: 'POST',
    token: ali.token,
    body: { clientId: 'same', kind: 'text', envelope },
  });
  const second = await api(`/api/chats/${chat.id}/messages`, {
    method: 'POST',
    token: ali.token,
    body: { clientId: 'same', kind: 'text', envelope },
  });
  assert.equal(first.message.id, second.message.id);

  const bad = await fetch(`${BASE}/api/chats/${chat.id}/messages`, {
    method: 'POST',
    headers: { authorization: `Bearer ${ali.token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ kind: 'text', envelope: { v: 1, alg: 'x25519-aesgcm', ct: 'x' } }),
  });
  assert.equal(bad.status, 400);
});
