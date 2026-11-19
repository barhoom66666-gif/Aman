import http from 'node:http';
import path from 'node:path';
import express from 'express';
import { openDatabase } from './db.js';
import { createRouter } from './routes.js';
import { Hub, attachWebSocket } from './ws.js';

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';
const DATA_DIR = process.env.DATA_DIR || path.resolve(process.cwd(), 'data');
const DB_FILE = process.env.DB_FILE || path.join(DATA_DIR, 'najwa.db');
const MEDIA_DIR = process.env.MEDIA_DIR || path.join(DATA_DIR, 'media');
const MAX_MEDIA_BYTES = Number(process.env.MAX_MEDIA_BYTES || 25 * 1024 * 1024);

const db = openDatabase(DB_FILE);
const hub = new Hub(db);

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', true);

// CORS مفتوح لتسهيل التجربة من المتصفح أثناء التطوير
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// حدّ بسيط لمحاولات الدخول/التسجيل
const attempts = new Map();
const WINDOW_MS = 60_000;
const MAX_ATTEMPTS = 30;
app.use('/api/auth', (req, res, next) => {
  const key = req.ip + ':' + req.path;
  const t = Date.now();
  const entry = attempts.get(key);
  if (!entry || t - entry.start > WINDOW_MS) {
    attempts.set(key, { start: t, count: 1 });
  } else if (++entry.count > MAX_ATTEMPTS) {
    return res.status(429).json({ error: 'too_many_requests', message: 'محاولات كثيرة، انتظر دقيقة' });
  }
  next();
});

app.use(express.json({ limit: '512kb' }));
app.get('/health', (_req, res) => res.json({ ok: true, service: 'najwa', time: Date.now() }));
app.use('/api', createRouter({ db, hub, mediaDir: MEDIA_DIR, maxMediaBytes: MAX_MEDIA_BYTES }));

app.use((req, res) => {
  res.status(404).json({ error: 'not_found', message: 'المسار غير موجود' });
});

app.use((err, _req, res, _next) => {
  const status = err.status || (err.type === 'entity.too.large' ? 413 : 500);
  const code = err.code || (status === 413 ? 'too_large' : 'server_error');
  if (status >= 500) console.error('[najwa]', err);
  res.status(status).json({ error: code, message: err.message || 'خطأ غير متوقع' });
});

const server = http.createServer(app);
attachWebSocket(server, db, hub);

server.listen(PORT, HOST, () => {
  console.log(`[najwa] يعمل على http://${HOST}:${PORT}  (بيانات: ${DATA_DIR})`);
});

function shutdown() {
  console.log('[najwa] إيقاف...');
  server.close(() => {
    db.close();
    process.exit(0);
  });
  setTimeout(() => process.exit(0), 3000).unref();
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
