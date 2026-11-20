import crypto from 'node:crypto';

const COLORS = ['#0EA5A4', '#6366F1', '#F59E0B', '#EC4899', '#10B981', '#8B5CF6', '#EF4444', '#0EA5E9'];

export function newId(prefix = '') {
  return prefix + crypto.randomUUID().replaceAll('-', '');
}

export function now() {
  return Date.now();
}

export function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

export function newToken() {
  return crypto.randomBytes(32).toString('base64url');
}

export function colorFor(seed) {
  let h = 0;
  for (const ch of String(seed)) h = (h * 31 + ch.codePointAt(0)) % 1_000_003;
  return COLORS[h % COLORS.length];
}

const EASTERN_ARABIC = '٠١٢٣٤٥٦٧٨٩';
const PERSIAN = '۰۱۲۳۴۵۶۷۸۹';

/** يحوّل رقم الهاتف إلى أرقام إنجليزية فقط، ويدعم الأرقام العربية والفارسية و+ والمسافات و00. */
export function normalizePhone(value) {
  let out = '';
  for (const ch of String(value ?? '')) {
    const arabic = EASTERN_ARABIC.indexOf(ch);
    if (arabic >= 0) {
      out += String(arabic);
      continue;
    }
    const persian = PERSIAN.indexOf(ch);
    if (persian >= 0) {
      out += String(persian);
      continue;
    }
    if (ch >= '0' && ch <= '9') out += ch;
  }
  if (out.startsWith('00')) out = out.slice(2);
  return out;
}

/** أرقام البحث: تسمح للمستخدم بكتابة المسافات أو + أو 00 أو أرقام عربية. */
export function phoneQueryDigits(value) {
  return normalizePhone(value);
}

/** scrypt password hashing: "<saltHex>:<hashHex>" */
export function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(password, salt, 32, { N: 16384, r: 8, p: 1 });
  return `${salt.toString('hex')}:${hash.toString('hex')}`;
}

export function verifyPassword(password, stored) {
  try {
    const [saltHex, hashHex] = String(stored).split(':');
    if (!saltHex || !hashHex) return false;
    const salt = Buffer.from(saltHex, 'hex');
    const expected = Buffer.from(hashHex, 'hex');
    const actual = crypto.scryptSync(password, salt, expected.length, { N: 16384, r: 8, p: 1 });
    return crypto.timingSafeEqual(expected, actual);
  } catch {
    return false;
  }
}

export class HttpError extends Error {
  constructor(status, code, message) {
    super(message || code);
    this.status = status;
    this.code = code;
  }
}

export function publicUser(row) {
  if (!row) return null;
  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name,
    phone: row.phone ?? null,
    avatarColor: row.avatar_color,
    identityKey: row.identity_key ?? undefined,
    lastSeen: row.last_seen ?? 0,
  };
}

export function isPlainObject(v) {
  return !!v && typeof v === 'object' && !Array.isArray(v);
}

/** Basic structural validation of an opaque encrypted envelope. */
export function validEnvelope(env) {
  const b64 = /^[A-Za-z0-9+/_-]{16,512}={0,2}$/;
  if (!isPlainObject(env)) return false;
  const flat = JSON.stringify(env);
  if (flat.length > 96 * 1024) return false;
  if (env.v !== 1) return false;
  if (typeof env.ct !== 'string' || !b64.test(env.ct)) return false;
  if (typeof env.nonce !== 'string' || !b64.test(env.nonce)) return false;
  if (env.alg === 'x25519-aesgcm') {
    return typeof env.epk === 'string' && b64.test(env.epk) && typeof env.salt === 'string' && b64.test(env.salt);
  }
  if (env.alg === 'senderkey-aesgcm') return true;
  return false;
}
