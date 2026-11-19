import fs from 'node:fs';
import path from 'node:path';
import Database from 'better-sqlite3';

const SCHEMA = `
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE COLLATE NOCASE,
  display_name  TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  identity_key  TEXT NOT NULL,
  avatar_color  TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  last_seen     INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device     TEXT,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS prekeys (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key        TEXT NOT NULL,
  used       INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS chats (
  id           TEXT PRIMARY KEY,
  type         TEXT NOT NULL CHECK (type IN ('direct','group')),
  title        TEXT,
  created_by   TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  epoch        INTEGER NOT NULL DEFAULT 1,
  avatar_color TEXT
);

CREATE TABLE IF NOT EXISTS chat_members (
  chat_id      TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role         TEXT NOT NULL DEFAULT 'member',
  joined_at    INTEGER NOT NULL,
  last_read_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
  id         TEXT PRIMARY KEY,
  chat_id    TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  sender_id  TEXT NOT NULL,
  client_id  TEXT,
  kind       TEXT NOT NULL,
  epoch      INTEGER,
  envelope   TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS messages_chat_idx ON messages(chat_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS messages_client_idx ON messages(chat_id, sender_id, client_id);

CREATE TABLE IF NOT EXISTS group_keys (
  chat_id      TEXT NOT NULL,
  epoch        INTEGER NOT NULL,
  recipient_id TEXT NOT NULL,
  sender_id    TEXT NOT NULL,
  envelope     TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  PRIMARY KEY (chat_id, epoch, recipient_id)
);

CREATE TABLE IF NOT EXISTS media (
  id         TEXT PRIMARY KEY,
  owner_id   TEXT NOT NULL,
  chat_id    TEXT NOT NULL,
  size       INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
`;

export function openDatabase(file) {
  if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true });
  const db = new Database(file);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.exec(SCHEMA);
  return db;
}
