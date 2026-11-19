import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import 'crypto.dart';

class LocalDb {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'aman.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chats (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            chat_id TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_messages_chat ON messages(chat_id, created_at)');
        await db.execute('''
          CREATE TABLE outbox (
            client_id TEXT PRIMARY KEY,
            chat_id TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE group_keys (
            chat_id TEXT NOT NULL,
            epoch INTEGER NOT NULL,
            data TEXT NOT NULL,
            PRIMARY KEY (chat_id, epoch)
          )
        ''');
      },
    );
    return _db!;
  }

  // ---------- المحادثات ----------

  static Future<void> saveChat(Chat chat) async {
    final db = await instance;
    await db.insert(
      'chats',
      {
        'id': chat.id,
        'data': jsonEncode(chat.toJson()),
        'updated_at': chat.updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> saveChats(Iterable<Chat> chats) async {
    for (final chat in chats) {
      await saveChat(chat);
    }
  }

  static Future<List<Chat>> loadChats() async {
    final db = await instance;
    final rows = await db.query('chats', orderBy: 'updated_at DESC');
    final result = <Chat>[];
    for (final row in rows) {
      try {
        result.add(Chat.fromJson(decodePayload(row['data'] as String)));
      } catch (_) {}
    }
    return result;
  }

  static Future<void> deleteChat(String id) async {
    final db = await instance;
    await db.delete('chats', where: 'id = ?', whereArgs: [id]);
    await db.delete('messages', where: 'chat_id = ?', whereArgs: [id]);
    await db.delete('group_keys', where: 'chat_id = ?', whereArgs: [id]);
  }

  // ---------- الرسائل ----------

  static Future<void> saveMessage(Message message) async {
    final db = await instance;
    await db.insert(
      'messages',
      {
        'id': message.id,
        'chat_id': message.chatId,
        'data': jsonEncode(message.toJson()),
        'created_at': message.createdAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Message>> loadMessages(String chatId, {int limit = 300}) async {
    final db = await instance;
    final rows = await db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    final result = <Message>[];
    for (final row in rows) {
      try {
        result.add(Message.fromJson(decodePayload(row['data'] as String)));
      } catch (_) {}
    }
    return result;
  }

  static Future<void> deleteMessage(String id) async {
    final db = await instance;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- صندوق الصادر ----------

  static Future<void> enqueue(Message message) async {
    final db = await instance;
    await db.insert(
      'outbox',
      {
        'client_id': message.clientId,
        'chat_id': message.chatId,
        'data': jsonEncode(message.toJson()),
        'created_at': message.createdAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Message>> loadOutbox() async {
    final db = await instance;
    final rows = await db.query('outbox', orderBy: 'created_at ASC');
    final result = <Message>[];
    for (final row in rows) {
      try {
        result.add(Message.fromJson(decodePayload(row['data'] as String)));
      } catch (_) {}
    }
    return result;
  }

  static Future<void> dequeue(String clientId) async {
    final db = await instance;
    await db.delete('outbox', where: 'client_id = ?', whereArgs: [clientId]);
  }

  // ---------- مفاتيح المجموعات (مشفّرة محليًا) ----------

  static Future<void> saveGroupKey(String chatId, int epoch, String keyB64) async {
    final db = await instance;
    final encrypted = await CryptoService.encryptLocal(keyB64);
    await db.insert(
      'group_keys',
      {'chat_id': chatId, 'epoch': epoch, 'data': encrypted},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<String?> loadGroupKey(String chatId, int epoch) async {
    final db = await instance;
    final rows = await db.query(
      'group_keys',
      where: 'chat_id = ? AND epoch = ?',
      whereArgs: [chatId, epoch],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return await CryptoService.decryptLocal(rows.first['data'] as String);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearGroupKeys(String chatId) async {
    final db = await instance;
    await db.delete('group_keys', where: 'chat_id = ?', whereArgs: [chatId]);
  }

  static Future<void> wipe() async {
    final db = await instance;
    await db.delete('messages');
    await db.delete('chats');
    await db.delete('outbox');
    await db.delete('group_keys');
  }
}
