import { sha256 } from './util.js';

export function authenticateToken(db, token) {
  if (!token || typeof token !== 'string') return null;
  const row = db
    .prepare(
      `SELECT u.*, s.token_hash
         FROM sessions s
         JOIN users u ON u.id = s.user_id
        WHERE s.token_hash = ?`,
    )
    .get(sha256(token));
  return row ?? null;
}

export function bearerToken(req) {
  const header = req.get('authorization') || '';
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (match) return match[1].trim();
  if (typeof req.query.token === 'string') return req.query.token;
  return null;
}

export function requireAuth(db) {
  return (req, _res, next) => {
    const user = authenticateToken(db, bearerToken(req));
    if (!user) {
      const err = new Error('مطلوب تسجيل الدخول');
      err.status = 401;
      err.code = 'unauthorized';
      return next(err);
    }
    req.user = user;
    next();
  };
}
