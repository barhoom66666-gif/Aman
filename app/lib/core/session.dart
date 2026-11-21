import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models.dart';
import 'api.dart';
import 'config.dart';
import 'crypto.dart';
import 'db.dart';

const _kToken = 'aman.token';
const _kUser = 'aman.user';
const _kServer = 'aman.server';
const _kTheme = 'aman.theme';
const _kPins = 'aman.pins';
const _kWalls = 'aman.wallpapers';
const _kPrefs = 'aman.prefs';

class Session extends ChangeNotifier {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final ApiClient api = ApiClient();
  final Uuid _uuid = const Uuid();

  User? me;
  String? token;
  bool initialized = false;
  String? connectionError;
  bool connected = false;
  ThemeMode themeMode = ThemeMode.dark;
  final Set<String> pinnedChatIds = {};
  final Map<String, String> chatWallpapers = {};

  // إعدادات وتفضيلات واجهة JERNAS المحلية
  bool showNotesInHeader = true;
  bool showCalendarInHeader = true;
  bool showLastSeen = true;
  bool readReceipts = true;
  String defaultSelfDestruct = 'إيقاف';
  bool screenLock = true;
  String screenLockTimeout = '5 دقائق';
  bool blockGroupAdd = false;
  bool blockPhoneAdd = false;
  bool msgShowNotification = true;
  String msgSound = 'صافرة';
  bool msgReactionNotifications = true;
  bool grpShowNotification = true;
  String grpSound = 'صافرة';
  bool grpReactionNotifications = true;
  bool showNotificationPreview = true;
  final Set<String> mutedChatIds = {};
  final Set<String> mutedCallChatIds = {};
  final Map<String, String> chatSelfDestruct = {};
  final Map<String, String> chatAdminMessage = {};
  final Map<String, List<AdminNotice>> chatAdminNotices = {};
  final Set<String> seenAdminNoticeIds = {};
  final Set<String> dismissedAdminBannerIds = {};
  final Map<String, String> chatTask = {};
  final Set<String> starredMessageIds = {};
  final List<Map<String, dynamic>> personalNotes = [];
  final List<Map<String, dynamic>> calendarEvents = [];

  final Map<String, Chat> chats = {};
  final Map<String, List<Message>> messagesByChat = {};
  final Map<String, Map<String, int>> typingUntil = {};
  final Set<String> _activeChats = {};
  final Map<String, Future<List<int>?>> _groupKeyLocks = {};

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _reconnect;
  Timer? _ping;
  Timer? _typingTicker;
  int _backoff = 0;
  bool _disposed = false;
  bool _closingByUser = false;

  // ---------- دورة الحياة ----------

  Future<void> init() async {
    _typingTicker ??= Timer.periodic(const Duration(seconds: 1), (_) => _purgeTyping());
    try {
      final savedServer = await _storage.read(key: _kServer);
      if (savedServer != null && savedServer.isNotEmpty) {
        AppConfig.setBase(savedServer);
      }
      await CryptoService.loadOrCreateIdentity();

      final savedTheme = await _storage.read(key: _kTheme);
      themeMode = switch (savedTheme) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
      final savedPins = await _storage.read(key: _kPins);
      if (savedPins != null && savedPins.isNotEmpty) {
        try {
          pinnedChatIds.addAll((jsonDecode(savedPins) as List).cast<String>());
        } catch (_) {
          // تجاهل التخزين التالف بدل منع تسجيل الدخول
        }
      }
      final savedWalls = await _storage.read(key: _kWalls);
      if (savedWalls != null && savedWalls.isNotEmpty) {
        try {
          chatWallpapers.addAll(
            (jsonDecode(savedWalls) as Map).map((key, value) => MapEntry('$key', '$value')),
          );
        } catch (_) {
          // تجاهل التخزين التالف
        }
      }
      final savedPrefs = await _storage.read(key: _kPrefs);
      if (savedPrefs != null && savedPrefs.isNotEmpty) {
        try {
          _applyPrefsJson((jsonDecode(savedPrefs) as Map).cast<String, dynamic>());
        } catch (_) {}
      }

      final savedToken = await _storage.read(key: _kToken);
      final savedUser = await _storage.read(key: _kUser);
      if (savedToken != null && savedUser != null) {
        token = savedToken;
        api.token = savedToken;
        me = User.fromJson(decodePayload(savedUser));
        final localChats = await LocalDb.loadChats();
        for (final chat in localChats) {
          chats[chat.id] = chat;
        }
        _connect();
        // تحديث بالخلفية دون حجب الواجهة
        unawaited(refreshChats().then((_) => _retryOutbox()));
      }
    } catch (e) {
      debugPrint('init error: $e');
    }
    initialized = true;
    _notify();
  }

  Future<void> setServer(String value) async {
    final normalized = AppConfig.normalize(value);
    AppConfig.setBase(normalized);
    await _storage.write(key: _kServer, value: normalized);
    _notify();
  }

  String get serverUrl => AppConfig.base;

  Future<void> register({
    required String phone,
    required String password,
    required String displayName,
  }) async {
    final identityKey = await CryptoService.loadOrCreateIdentity();
    final data = await api.register(
      phone: phone,
      password: password,
      displayName: displayName,
      identityKey: identityKey,
    );
    await _finishAuth(data);
  }

  Future<void> login({required String identifier, required String password}) async {
    await CryptoService.loadOrCreateIdentity();
    final data = await api.login(identifier: identifier, password: password);
    await _finishAuth(data);
    // نشر مفتاح هذا الجهاز حتى يشفّر الآخرون له (جهاز واحد لكل حساب).
    try {
      await api.updateIdentityKey(await CryptoService.myPublicKey());
    } catch (_) {}
  }

  Future<void> _finishAuth(Map<String, dynamic> data) async {
    token = data['token'] as String;
    api.token = token;
    me = User.fromJson((data['user'] as Map).cast<String, dynamic>());
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kUser, value: jsonEncode(me!.toJson()));
    await _storage.write(key: _kServer, value: AppConfig.base);
    chats.clear();
    messagesByChat.clear();
    _connect();
    await refreshChats();
    _notify();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {}
    _closingByUser = true;
    await _wsSub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _wsSub = null;
    _ping?.cancel();
    _reconnect?.cancel();
    token = null;
    api.token = null;
    me = null;
    chats.clear();
    messagesByChat.clear();
    typingUntil.clear();
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUser);
    _notify();
  }

  Future<void> wipeLocalData() async {
    await LocalDb.wipe();
    messagesByChat.clear();
    _notify();
  }

  Future<void> updateDisplayName(String name) => _applyProfile(displayName: name);

  Future<void> updatePhone(String phone) => _applyProfile(phone: phone);

  Future<void> _applyProfile({String? displayName, String? phone}) async {
    final data = await api.updateProfile(displayName: displayName, phone: phone);
    me = User.fromJson((data['user'] as Map).cast<String, dynamic>());
    await _storage.write(key: _kUser, value: jsonEncode(me!.toJson()));
    _notify();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _storage.write(key: _kTheme, value: mode.name);
    _notify();
  }

  bool isPinned(String chatId) => pinnedChatIds.contains(chatId);

  Future<void> togglePin(String chatId) async {
    if (!pinnedChatIds.remove(chatId)) pinnedChatIds.add(chatId);
    await _storage.write(key: _kPins, value: jsonEncode(pinnedChatIds.toList()));
    _notify();
  }

  String? wallpaperFor(String chatId) => chatWallpapers[chatId] ?? chatWallpapers['__global__'];

  Future<void> setWallpaper(String chatId, String? style) async {
    if (style == null || style.isEmpty || style == 'default') {
      chatWallpapers.remove(chatId);
    } else {
      chatWallpapers[chatId] = style;
    }
    await _storage.write(key: _kWalls, value: jsonEncode(chatWallpapers));
    _notify();
  }

  Future<void> resetAllWallpapers() async {
    chatWallpapers.clear();
    await _storage.delete(key: _kWalls);
    _notify();
  }

  void _applyPrefsJson(Map<String, dynamic> map) {
    showNotesInHeader = map['showNotesInHeader'] as bool? ?? showNotesInHeader;
    showCalendarInHeader = map['showCalendarInHeader'] as bool? ?? showCalendarInHeader;
    showLastSeen = map['showLastSeen'] as bool? ?? showLastSeen;
    readReceipts = map['readReceipts'] as bool? ?? readReceipts;
    defaultSelfDestruct = map['defaultSelfDestruct'] as String? ?? defaultSelfDestruct;
    screenLock = map['screenLock'] as bool? ?? screenLock;
    screenLockTimeout = map['screenLockTimeout'] as String? ?? screenLockTimeout;
    blockGroupAdd = map['blockGroupAdd'] as bool? ?? blockGroupAdd;
    blockPhoneAdd = map['blockPhoneAdd'] as bool? ?? blockPhoneAdd;
    msgShowNotification = map['msgShowNotification'] as bool? ?? msgShowNotification;
    msgSound = map['msgSound'] as String? ?? msgSound;
    msgReactionNotifications = map['msgReactionNotifications'] as bool? ?? msgReactionNotifications;
    grpShowNotification = map['grpShowNotification'] as bool? ?? grpShowNotification;
    grpSound = map['grpSound'] as String? ?? grpSound;
    grpReactionNotifications = map['grpReactionNotifications'] as bool? ?? grpReactionNotifications;
    showNotificationPreview = map['showNotificationPreview'] as bool? ?? showNotificationPreview;
    if (map['mutedChatIds'] is List) {
      mutedChatIds
        ..clear()
        ..addAll((map['mutedChatIds'] as List).map((e) => '$e'));
    }
    if (map['mutedCallChatIds'] is List) {
      mutedCallChatIds
        ..clear()
        ..addAll((map['mutedCallChatIds'] as List).map((e) => '$e'));
    }
    if (map['chatSelfDestruct'] is Map) {
      chatSelfDestruct
        ..clear()
        ..addAll((map['chatSelfDestruct'] as Map).map((k, v) => MapEntry('$k', '$v')));
    }
    if (map['chatAdminMessage'] is Map) {
      chatAdminMessage
        ..clear()
        ..addAll((map['chatAdminMessage'] as Map).map((k, v) => MapEntry('$k', '$v')));
    }
    if (map['chatAdminNotices'] is Map) {
      chatAdminNotices.clear();
      for (final entry in (map['chatAdminNotices'] as Map).entries) {
        final rawList = entry.value;
        if (rawList is List) {
          chatAdminNotices['${entry.key}'] = rawList
              .whereType<Map>()
              .map((m) => AdminNotice.fromJson(m.cast<String, dynamic>()))
              .toList();
        }
      }
    }
    if (map['seenAdminNoticeIds'] is List) {
      seenAdminNoticeIds
        ..clear()
        ..addAll((map['seenAdminNoticeIds'] as List).map((e) => '$e'));
    }
    if (map['dismissedAdminBannerIds'] is List) {
      dismissedAdminBannerIds
        ..clear()
        ..addAll((map['dismissedAdminBannerIds'] as List).map((e) => '$e'));
    }
    if (map['chatTask'] is Map) {
      chatTask
        ..clear()
        ..addAll((map['chatTask'] as Map).map((k, v) => MapEntry('$k', '$v')));
    }
    if (map['starredMessageIds'] is List) {
      starredMessageIds
        ..clear()
        ..addAll((map['starredMessageIds'] as List).map((e) => '$e'));
    }
    if (map['personalNotes'] is List) {
      personalNotes
        ..clear()
        ..addAll((map['personalNotes'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()));
    }
    if (map['calendarEvents'] is List) {
      calendarEvents
        ..clear()
        ..addAll((map['calendarEvents'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()));
    }
  }

  Future<void> savePrefs() async {
    final data = {
      'showNotesInHeader': showNotesInHeader,
      'showCalendarInHeader': showCalendarInHeader,
      'showLastSeen': showLastSeen,
      'readReceipts': readReceipts,
      'defaultSelfDestruct': defaultSelfDestruct,
      'screenLock': screenLock,
      'screenLockTimeout': screenLockTimeout,
      'blockGroupAdd': blockGroupAdd,
      'blockPhoneAdd': blockPhoneAdd,
      'msgShowNotification': msgShowNotification,
      'msgSound': msgSound,
      'msgReactionNotifications': msgReactionNotifications,
      'grpShowNotification': grpShowNotification,
      'grpSound': grpSound,
      'grpReactionNotifications': grpReactionNotifications,
      'showNotificationPreview': showNotificationPreview,
      'mutedChatIds': mutedChatIds.toList(),
      'mutedCallChatIds': mutedCallChatIds.toList(),
      'chatSelfDestruct': chatSelfDestruct,
      'chatAdminMessage': chatAdminMessage,
      'chatAdminNotices': chatAdminNotices.map(
        (key, list) => MapEntry(key, list.map((n) => n.toJson()).toList()),
      ),
      'seenAdminNoticeIds': seenAdminNoticeIds.toList(),
      'dismissedAdminBannerIds': dismissedAdminBannerIds.toList(),
      'chatTask': chatTask,
      'starredMessageIds': starredMessageIds.toList(),
      'personalNotes': personalNotes,
      'calendarEvents': calendarEvents,
    };
    await _storage.write(key: _kPrefs, value: jsonEncode(data));
    _notify();
  }

  bool isChatMuted(String chatId) => mutedChatIds.contains(chatId);

  Future<void> toggleChatMuted(String chatId) async {
    if (!mutedChatIds.remove(chatId)) mutedChatIds.add(chatId);
    await savePrefs();
  }

  bool isCallMuted(String chatId) => mutedCallChatIds.contains(chatId);

  Future<void> toggleCallMuted(String chatId) async {
    if (!mutedCallChatIds.remove(chatId)) mutedCallChatIds.add(chatId);
    await savePrefs();
  }

  String selfDestructFor(String chatId) => chatSelfDestruct[chatId] ?? '٤ أسابيع';

  Future<void> setSelfDestructFor(String chatId, String value) async {
    chatSelfDestruct[chatId] = value;
    await savePrefs();
  }

  List<AdminNotice> adminNoticesFor(String chatId, {bool includeArchived = false}) {
    final list = chatAdminNotices[chatId] ?? const [];
    final filtered = includeArchived ? [...list] : list.where((n) => !n.archived).toList();
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  AdminNotice? latestAdminNoticeFor(String chatId) {
    final list = adminNoticesFor(chatId);
    return list.isEmpty ? null : list.first;
  }

  String adminMessageFor(String chatId) {
    final latest = latestAdminNoticeFor(chatId);
    if (latest != null) return latest.title;
    return chatAdminMessage[chatId] ?? '';
  }

  Future<void> setAdminMessageFor(String chatId, String value) async {
    chatAdminMessage[chatId] = value;
    await savePrefs();
  }

  bool isAdminNoticeSeen(String noticeId) => seenAdminNoticeIds.contains(noticeId);

  Future<void> markAdminNoticeSeen(String noticeId) async {
    if (seenAdminNoticeIds.add(noticeId)) {
      await savePrefs();
    }
  }

  bool isAdminBannerDismissed(String noticeId) => dismissedAdminBannerIds.contains(noticeId);

  Future<void> dismissAdminBanner(String noticeId) async {
    if (dismissedAdminBannerIds.add(noticeId)) {
      await savePrefs();
    }
  }

  void _upsertLocalAdminNotice(AdminNotice notice, {bool notify = true}) {
    final list = chatAdminNotices.putIfAbsent(notice.chatId, () => []);
    final idx = list.indexWhere((n) => n.id == notice.id);
    if (idx >= 0) {
      list[idx] = notice;
    } else {
      list.insert(0, notice);
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // إزالة الإخفاء السابق عند تعديل الرسالة أو نشر رسالة جديدة
    dismissedAdminBannerIds.remove(notice.id);
    unawaited(savePrefs());
    if (notify) _notify();
  }

  Future<AdminNotice> publishAdminNotice({
    required String chatId,
    required String title,
    required String body,
    String? noticeId,
  }) async {
    final chat = chats[chatId];
    if (chat == null || me == null) {
      throw ApiException(0, 'not_found', 'المحادثة غير متاحة');
    }
    final id = (noticeId != null && noticeId.isNotEmpty) ? noticeId : _uuid.v4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final notice = AdminNotice(
      id: id,
      chatId: chatId,
      senderId: me!.id,
      senderName: me!.displayName,
      title: title.trim(),
      body: body.trim(),
      createdAt: nowMs,
      archived: false,
    );
    // عند التعديل، نحذف حالة المشاهدة حتى تظهر للأعضاء من جديد
    seenAdminNoticeIds.remove(id);
    _upsertLocalAdminNotice(notice, notify: false);

    // بث رسالة المشرف المشفّرة إلى أعضاء المجموعة
    final clientId = _uuid.v4();
    final message = Message(
      id: 'local_$clientId',
      chatId: chatId,
      senderId: me!.id,
      kind: 'text',
      envelope: const {},
      createdAt: nowMs,
      clientId: clientId,
      text: '__admin_notice__:${notice.title}',
      adminNotice: notice,
      pending: true,
    );
    _appendLocal(chat, message);
    await _dispatch(chat, message, {
      't': 'admin_notice',
      'notice': notice.toJson(),
    });
    return notice;
  }

  Future<void> archiveAdminNotice(String chatId, String noticeId) async {
    final list = chatAdminNotices[chatId];
    if (list == null) return;
    final idx = list.indexWhere((n) => n.id == noticeId);
    if (idx < 0) return;
    final updated = list[idx].copyWith(archived: true);
    list[idx] = updated;
    await savePrefs();

    final chat = chats[chatId];
    if (chat != null && me != null) {
      final clientId = _uuid.v4();
      final message = Message(
        id: 'local_$clientId',
        chatId: chatId,
        senderId: me!.id,
        kind: 'text',
        envelope: const {},
        createdAt: DateTime.now().millisecondsSinceEpoch,
        clientId: clientId,
        text: '__admin_notice__:${updated.title}',
        adminNotice: updated,
        pending: true,
      );
      _appendLocal(chat, message);
      unawaited(_dispatch(chat, message, {
        't': 'admin_notice',
        'notice': updated.toJson(),
      }));
    }
  }

  String taskFor(String chatId) => chatTask[chatId] ?? '';

  Future<void> setTaskFor(String chatId, String value) async {
    chatTask[chatId] = value;
    await savePrefs();
  }

  bool isStarred(String messageId) => starredMessageIds.contains(messageId);

  Future<void> toggleStarred(String messageId) async {
    if (!starredMessageIds.remove(messageId)) starredMessageIds.add(messageId);
    await savePrefs();
  }

  List<Message> starredMessagesIn(String chatId) {
    final all = messagesByChat[chatId] ?? const [];
    return all.where((m) => starredMessageIds.contains(m.id)).toList();
  }

  List<Message> get allStarredMessages {
    final result = <Message>[];
    for (final list in messagesByChat.values) {
      for (final msg in list) {
        if (starredMessageIds.contains(msg.id)) result.add(msg);
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<void> uploadAvatar(Uint8List bytes, String mime) async {
    final data = await api.uploadAvatar(bytes, mime);
    me = User.fromJson((data['user'] as Map).cast<String, dynamic>());
    await _storage.write(key: _kUser, value: jsonEncode(me!.toJson()));
    _notify();
  }

  Future<void> removeAvatar() async {
    final data = await api.removeAvatar();
    me = User.fromJson((data['user'] as Map).cast<String, dynamic>());
    await _storage.write(key: _kUser, value: jsonEncode(me!.toJson()));
    _notify();
  }

  // ---------- المحادثات ----------

  List<Chat> get chatList {
    final list = chats.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<void> refreshChats() async {
    try {
      final rows = await api.chats();
      for (final row in rows) {
        _mergeChat(Chat.fromJson(row), notify: false);
      }
      connectionError = null;
      _notify();
    } on ApiException catch (e) {
      connectionError = e.message;
      _notify();
    }
  }

  Chat? chatById(String id) => chats[id];

  Future<Chat> openDirect(String username) async {
    final row = await api.createDirect(username);
    final chat = Chat.fromJson(row);
    _mergeChat(chat);
    return chats[chat.id] ?? chat;
  }

  Future<Chat> createGroup(String title, List<String> usernames) async {
    final row = await api.createGroup(title, usernames);
    final chat = Chat.fromJson(row);
    _mergeChat(chat);
    // إنشاء مفتاح المجموعة وتوزيعه على الأعضاء
    try {
      await _ensureGroupKey(chats[chat.id] ?? chat, chat.epoch);
    } catch (e) {
      debugPrint('group key error: $e');
    }
    return chats[chat.id] ?? chat;
  }

  Future<Chat> addMembers(String chatId, List<String> usernames) async {
    final row = await api.addMembers(chatId, usernames);
    final chat = Chat.fromJson(row);
    _mergeChat(chat);
    try {
      await _ensureGroupKey(chats[chatId] ?? chat, chat.epoch);
    } catch (e) {
      debugPrint('group key rotate error: $e');
    }
    return chats[chatId] ?? chat;
  }

  void _mergeChat(Chat chat, {bool notify = true}) {
    final existing = chats[chat.id];
    if (existing != null) {
      // الحفاظ على العدّاد المحلي إذا كان أحدث
      if (chat.unreadCount == 0 && existing.unreadCount > 0 && existing.lastMessage?.id == chat.lastMessage?.id) {
        chat = chat.copyWith(unreadCount: existing.unreadCount);
      }
      if (chat.lastMessage != null && existing.lastMessage != null && chat.lastMessage!.id == existing.lastMessage!.id) {
        final local = existing.lastMessage!;
        if (local.text != null && chat.lastMessage!.text == null) {
          chat.lastMessage!.text = local.text;
        }
        if (local.media != null && chat.lastMessage!.media == null) {
          chat.lastMessage!.media = local.media;
        }
      }
    }
    chats[chat.id] = chat;
    unawaited(LocalDb.saveChat(chat));
    if (notify) _notify();
  }

  // ---------- الرسائل ----------

  List<Message> messagesOf(String chatId) =>
      (messagesByChat[chatId] ?? const []).where((m) => !m.isAdminNotice).toList();

  Future<void> loadMessages(String chatId) async {
    final chat = chats[chatId];
    if (chat == null) return;
    final local = await LocalDb.loadMessages(chatId);
    final list = messagesByChat.putIfAbsent(chatId, () => []);
    for (final m in local) {
      if (m.adminNotice != null) {
        _upsertLocalAdminNotice(m.adminNotice!, notify: false);
      }
      if (!list.any((x) => x.id == m.id || (m.clientId != null && x.clientId == m.clientId))) {
        list.add(m);
      }
    }
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _notify();

    try {
      final page = await api.messages(chatId, limit: 40);
      final rows = ((page['messages'] as List?) ?? const []).whereType<Map<String, dynamic>>();
      for (final row in rows) {
        await _ingest(chat, Message.fromJson(row));
      }
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _notify();
    } on ApiException catch (e) {
      connectionError = e.message;
      _notify();
    }
  }

  Future<void> loadOlder(String chatId) async {
    final list = messagesByChat[chatId];
    final chat = chats[chatId];
    if (list == null || list.isEmpty || chat == null) return;
    final oldest = list.first.createdAt;
    try {
      final page = await api.messages(chatId, before: oldest, limit: 40);
      final rows = ((page['messages'] as List?) ?? const []).whereType<Map<String, dynamic>>();
      for (final row in rows) {
        await _ingest(chat, Message.fromJson(row));
      }
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _notify();
    } catch (_) {}
  }

  Future<void> _ingest(Chat chat, Message incoming) async {
    final list = messagesByChat.putIfAbsent(chat.id, () => []);
    var message = incoming;
    final index = list.indexWhere(
      (m) => m.id == message.id || (message.clientId != null && m.clientId == message.clientId),
    );
    if (index >= 0) {
      final existing = list[index];
      if (existing.text != null) message.text = existing.text;
      if (existing.media != null) message.media = existing.media;
      if (existing.localPath != null) message.localPath = existing.localPath;
      list[index] = message;
    } else {
      list.add(message);
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    await _decrypt(chat, message);
    if (message.text == null && message.media == null && !message.pending) {
      message.undecryptable = true;
    }
    await LocalDb.saveMessage(message);
    if (!message.isAdminNotice && chats[chat.id] != null) {
      final current = chats[chat.id]!;
      if (current.lastMessage == null || message.createdAt >= current.lastMessage!.createdAt) {
        chats[chat.id] = current.copyWith(lastMessage: message, updatedAt: message.createdAt);
      }
    }
  }

  Future<void> _decrypt(Chat chat, Message message) async {
    if (message.text != null || message.media != null) return;
    try {
      Uint8List clear;
      if (chat.type == 'direct') {
        if (me != null && message.senderId == me!.id) {
          message.undecryptable = true;
          return;
        }
        clear = await CryptoService.open(
          chatId: chat.id,
          senderId: message.senderId,
          recipientId: me!.id,
          envelope: message.envelope,
        );
      } else {
        final epoch = message.epoch ?? chat.epoch;
        final key = await _ensureGroupKey(chat, epoch);
        if (key == null) {
          message.undecryptable = true;
          return;
        }
        try {
          clear = await CryptoService.openGroupMessage(
            chatId: chat.id,
            epoch: epoch,
            senderId: message.senderId,
            groupKey: key,
            envelope: message.envelope,
          );
        } catch (_) {
          // قد يكون مفتاح هذا الجيل تغيّر على الخادم — أعد الجلب مرة واحدة.
          final fresh = await _ensureGroupKey(chat, epoch, forceRefresh: true);
          if (fresh == null) rethrow;
          clear = await CryptoService.openGroupMessage(
            chatId: chat.id,
            epoch: epoch,
            senderId: message.senderId,
            groupKey: fresh,
            envelope: message.envelope,
          );
        }
      }
      final payload = decodePayload(utf8.decode(clear));
      if (payload['t'] == 'text') {
        message.text = payload['body'] as String? ?? '';
      } else if (payload['t'] == 'media') {
        message.media = MediaInfo.fromJson(payload);
      } else if (payload['t'] == 'admin_notice' && payload['notice'] is Map) {
        final notice = AdminNotice.fromJson((payload['notice'] as Map).cast<String, dynamic>());
        message.adminNotice = notice;
        message.text = '__admin_notice__:${notice.title}';
        _upsertLocalAdminNotice(notice, notify: false);
      }
    } catch (e) {
      debugPrint('decrypt failed: $e');
    }
  }

  Future<List<int>?> _ensureGroupKey(Chat chat, int epoch, {bool forceRefresh = false}) {
    if (forceRefresh) return _loadGroupKey(chat, epoch, forceRefresh: true);
    final lockKey = '${chat.id}:$epoch';
    final inFlight = _groupKeyLocks[lockKey];
    if (inFlight != null) return inFlight;
    final future = _loadGroupKey(chat, epoch, forceRefresh: false);
    _groupKeyLocks[lockKey] = future;
    future.whenComplete(() => _groupKeyLocks.remove(lockKey));
    return future;
  }

  Future<List<int>?> _loadGroupKey(Chat chat, int epoch, {required bool forceRefresh}) async {
    if (!forceRefresh) {
      final cached = await LocalDb.loadGroupKey(chat.id, epoch);
      if (cached != null) return CryptoService.fromB64(cached);
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final data = await api.getGroupKey(chat.id, epoch);
        if (data != null) {
          final senderId = data['senderId'] as String;
          final envelope = (data['envelope'] as Map).cast<String, dynamic>();
          final clear = await CryptoService.open(
            chatId: chat.id,
            senderId: senderId,
            recipientId: me!.id,
            envelope: envelope,
            info: CryptoService.groupKeyInfo,
          );
          await LocalDb.saveGroupKey(chat.id, epoch, base64Encode(clear));
          return clear;
        }
      } catch (e) {
        debugPrint('fetch group key failed: $e');
      }

      // لا يوجد مفتاح بعد: منشئ المجموعة ينشئه ويوزّعه
      if (me != null && chat.createdBy == me!.id) {
        final key = CryptoService.newGroupKey();
        final envelopes = <String, dynamic>{};
        for (final member in chat.members) {
          final identityKey = member.identityKey;
          if (identityKey == null) continue;
          envelopes[member.username] = await CryptoService.seal(
            chatId: chat.id,
            senderId: me!.id,
            recipientId: member.id,
            recipientPublicKey: identityKey,
            plaintext: key,
            info: CryptoService.groupKeyInfo,
          );
        }
        if (envelopes.isNotEmpty) {
          await api.postGroupKeys(chat.id, epoch, envelopes);
        }
        await LocalDb.saveGroupKey(chat.id, epoch, base64Encode(key));
        return key;
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
    return null;
  }

  Future<Map<String, dynamic>> _sealPayload(Chat chat, Map<String, dynamic> payload) async {
    final plain = utf8.encode(jsonEncode(payload));
    if (chat.isGroup) {
      final key = await _ensureGroupKey(chat, chat.epoch);
      if (key == null) {
        throw ApiException(0, 'no_group_key', 'لم يُوزَّع مفتاح المجموعة بعد، حاول بعد لحظات');
      }
      return CryptoService.sealGroupMessage(
        chatId: chat.id,
        epoch: chat.epoch,
        senderId: me!.id,
        groupKey: key,
        plaintext: plain,
      );
    }
    final peer = chat.peerFor(me!.id);
    final identityKey = peer?.identityKey;
    if (peer == null || identityKey == null) {
      throw ApiException(0, 'no_peer_key', 'لا يوجد مفتاح للمستلم');
    }
    return CryptoService.seal(
      chatId: chat.id,
      senderId: me!.id,
      recipientId: peer.id,
      recipientPublicKey: identityKey,
      plaintext: plain,
    );
  }

  Future<void> sendText(String chatId, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final chat = chats[chatId];
    if (chat == null || me == null) return;

    final clientId = _uuid.v4();
    final message = Message(
      id: 'local_$clientId',
      chatId: chatId,
      senderId: me!.id,
      kind: 'text',
      envelope: const {},
      createdAt: DateTime.now().millisecondsSinceEpoch,
      clientId: clientId,
      text: body,
      pending: true,
    );
    _appendLocal(chat, message);
    await _dispatch(chat, message, {'t': 'text', 'body': body});
  }

  Future<void> sendMedia(
    String chatId,
    List<int> bytes, {
    required String name,
    required String mime,
    int? width,
    int? height,
  }) async {
    final chat = chats[chatId];
    if (chat == null || me == null) return;

    final clientId = _uuid.v4();
    final message = Message(
      id: 'local_$clientId',
      chatId: chatId,
      senderId: me!.id,
      kind: 'media',
      envelope: const {},
      createdAt: DateTime.now().millisecondsSinceEpoch,
      clientId: clientId,
      pending: true,
      media: MediaInfo(
        id: 'pending',
        key: '',
        nonce: '',
        name: name,
        mime: mime,
        size: bytes.length,
        width: width,
        height: height,
      ),
    );
    _appendLocal(chat, message);

    try {
      final encrypted = await CryptoService.encryptFile(bytes);
      final uploaded = await api.uploadMedia(chatId, encrypted.bytes);
      final mediaId = uploaded['id'] as String;
      final info = MediaInfo(
        id: mediaId,
        key: base64Encode(encrypted.key),
        nonce: base64Encode(encrypted.nonce),
        name: name,
        mime: mime,
        size: bytes.length,
        width: width,
        height: height,
      );
      message.media = info;
      message.localPath = await _cacheFile(mediaId, bytes);
      await _dispatch(chat, message, {'t': 'media', ...info.toJson()});
    } catch (e) {
      message.pending = false;
      message.failed = true;
      await LocalDb.saveMessage(message);
      await LocalDb.enqueue(message);
      _notify();
    }
  }

  Future<void> _dispatch(Chat chat, Message message, Map<String, dynamic> payload) async {
    try {
      message.envelope = await _sealPayload(chat, payload);
      await _sendEnvelope(chat, message);
    } on ApiException catch (e) {
      if (e.code == 'epoch_mismatch') {
        try {
          await refreshChats();
          final fresh = chats[chat.id] ?? chat;
          message.envelope = await _sealPayload(fresh, payload);
          await _sendEnvelope(fresh, message);
          return;
        } catch (retryError) {
          debugPrint('retry failed: $retryError');
        }
      }
      message.pending = false;
      message.failed = true;
      await LocalDb.saveMessage(message);
      await LocalDb.enqueue(message);
      connectionError = e.message;
      _notify();
    } catch (e) {
      message.pending = false;
      message.failed = true;
      await LocalDb.saveMessage(message);
      await LocalDb.enqueue(message);
      _notify();
    }
  }

  Future<void> _sendEnvelope(Chat chat, Message message) async {
    final previousId = message.id;
    final saved = await api.sendMessage(
      chatId: chat.id,
      clientId: message.clientId!,
      kind: message.kind,
      envelope: message.envelope,
      epoch: chat.isGroup ? chat.epoch : null,
    );
    message.id = saved['id'] as String;
    message.createdAt = (saved['createdAt'] as num?)?.toInt() ?? message.createdAt;
    message.pending = false;
    message.failed = false;
    if (previousId != message.id) {
      await LocalDb.deleteMessage(previousId);
    }
    await LocalDb.saveMessage(message);
    await LocalDb.dequeue(message.clientId!);
    final current = chats[chat.id];
    if (current != null && !message.isAdminNotice) {
      chats[chat.id] = current.copyWith(lastMessage: message, updatedAt: message.createdAt);
      await LocalDb.saveChat(chats[chat.id]!);
    }
    _notify();
  }

  Future<void> _retryOutbox() async {
    final queued = await LocalDb.loadOutbox();
    for (final message in queued) {
      final chat = chats[message.chatId];
      if (chat == null) continue;
      if (message.envelope.isEmpty) continue;
      try {
        await _sendEnvelope(chat, message);
      } catch (_) {
        break;
      }
    }
  }

  void _appendLocal(Chat chat, Message message) {
    final list = messagesByChat.putIfAbsent(chat.id, () => []);
    list.add(message);
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (!message.isAdminNotice) {
      chats[chat.id] = chat.copyWith(lastMessage: message, updatedAt: message.createdAt);
    }
    unawaited(LocalDb.saveMessage(message));
    unawaited(LocalDb.saveChat(chats[chat.id]!));
    _notify();
  }

  Future<void> retry(Message message) async {
    final chat = chats[message.chatId];
    if (chat == null) return;
    message.pending = true;
    message.failed = false;
    _notify();
    final payload = message.isMedia && message.media != null
        ? {'t': 'media', ...message.media!.toJson()}
        : {'t': 'text', 'body': message.text ?? ''};
    await _dispatch(chat, message, payload);
  }

  Future<void> markRead(String chatId) async {
    final chat = chats[chatId];
    if (chat == null) return;
    _activeChats.add(chatId);
    if (chat.unreadCount != 0) {
      chats[chatId] = chat.copyWith(unreadCount: 0);
      _notify();
    }
    try {
      await api.markRead(chatId);
    } catch (_) {}
  }

  void setActiveChat(String? chatId) {
    _activeChats.clear();
    if (chatId != null) _activeChats.add(chatId);
  }

  // ---------- الوسائط ----------

  Future<Directory> _mediaDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'media'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> _cacheFile(String id, List<int> bytes) async {
    final dir = await _mediaDir();
    final file = File(p.join(dir.path, id));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Uint8List?> localMedia(Message message) async {
    if (message.localPath != null) {
      final file = File(message.localPath!);
      if (await file.exists()) return file.readAsBytes();
    }
    final media = message.media;
    if (media == null) return null;
    return null;
  }

  Future<Uint8List?> downloadMedia(Message message) async {
    final media = message.media;
    if (media == null) return null;
    try {
      final encrypted = await api.downloadMedia(media.id);
      final clear = await CryptoService.decryptFile(
        cipherBytes: encrypted,
        keyB64: media.key,
        nonceB64: media.nonce,
      );
      message.localPath = await _cacheFile(media.id, clear);
      await LocalDb.saveMessage(message);
      _notify();
      return clear;
    } catch (e) {
      debugPrint('download media failed: $e');
      return null;
    }
  }

  // ---------- الكتابة والإشعارات ----------

  void notifyTyping(String chatId) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({'type': 'typing', 'chatId': chatId}));
    } catch (_) {}
  }

  List<String> typistsIn(String chatId) {
    final map = typingUntil[chatId];
    if (map == null) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    return map.entries.where((e) => e.value > now && e.key != me?.id).map((e) => e.key).toList();
  }

  void _purgeTyping() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final entry in typingUntil.entries) {
      final before = entry.value.length;
      entry.value.removeWhere((_, until) => until <= now);
      if (entry.value.length != before) changed = true;
    }
    if (changed) _notify();
  }

  // ---------- WebSocket ----------

  void _connect() {
    if (token == null) return;
    _closingByUser = false;
    _reconnect?.cancel();
    _ping?.cancel();
    unawaited(_wsSub?.cancel());
    try {
      final channel = WebSocketChannel.connect(AppConfig.ws(token!));
      _channel = channel;
      _wsSub = channel.stream.listen(
        _onWsData,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
      connected = true;
      _backoff = 0;
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          channel.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      });
      _notify();
    } catch (e) {
      debugPrint('ws connect error: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    connected = false;
    _notify();
    if (_closingByUser || _disposed || token == null) return;
    _reconnect?.cancel();
    _backoff = (_backoff + 1).clamp(1, 8);
    final delay = Duration(seconds: 1 << (_backoff - 1));
    _reconnect = Timer(delay, () {
      if (_disposed || token == null) return;
      _connect();
      unawaited(refreshChats());
      unawaited(_retryOutbox());
    });
  }

  void _onWsData(dynamic raw) {
    Map<String, dynamic> event;
    try {
      event = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (event['type']) {
      case 'ready':
        connected = true;
        final online = (event['online'] as List?)?.whereType<String>().toSet() ?? <String>{};
        for (final chat in chats.values.toList()) {
          final members = chat.members
              .map((m) => online.contains(m.id) ? m.copyWith(online: true) : m)
              .toList();
          chats[chat.id] = chat.copyWith(members: members);
        }
        _notify();
        break;
      case 'presence':
        final userId = event['userId'] as String?;
        final online = event['online'] as bool? ?? false;
        if (userId == null) break;
        for (final chat in chats.values.toList()) {
          if (chat.members.any((m) => m.id == userId)) {
            chats[chat.id] = chat.copyWith(
              members: chat.members
                  .map((m) => m.id == userId ? m.copyWith(online: online) : m)
                  .toList(),
            );
          }
        }
        _notify();
        break;
      case 'message':
        final chatId = event['chatId'] as String?;
        final payload = event['message'];
        if (chatId == null || payload is! Map) break;
        unawaited(_onIncoming(chatId, Message.fromJson(payload.cast<String, dynamic>())));
        break;
      case 'typing':
        final chatId = event['chatId'] as String?;
        final userId = event['userId'] as String?;
        if (chatId == null || userId == null) break;
        typingUntil.putIfAbsent(chatId, () => {})[userId] =
            DateTime.now().millisecondsSinceEpoch + 3500;
        _notify();
        break;
      case 'read':
        final chatId = event['chatId'] as String?;
        final userId = event['userId'] as String?;
        final at = (event['at'] as num?)?.toInt() ?? 0;
        final chat = chats[chatId];
        if (chat == null || userId == null) break;
        chats[chat.id] = chat.copyWith(
          members: chat.members.map((m) => m.id == userId ? m.copyWith(lastReadAt: at) : m).toList(),
        );
        _notify();
        break;
      case 'chat':
        final payload = event['chat'];
        if (payload is Map) _mergeChat(Chat.fromJson(payload.cast<String, dynamic>()));
        break;
      case 'chat_update':
        final chatId = event['chatId'] as String?;
        if (chatId != null) unawaited(_refreshChat(chatId));
        break;
      case 'keys':
        break;
      case 'removed':
        final chatId = event['chatId'] as String?;
        if (chatId != null) {
          chats.remove(chatId);
          messagesByChat.remove(chatId);
          unawaited(LocalDb.deleteChat(chatId));
          _notify();
        }
        break;
    }
  }

  Future<void> _refreshChat(String chatId) async {
    try {
      final row = await api.chat(chatId);
      final chat = Chat.fromJson(row);
      _mergeChat(chat);
      // إذا كان المستخدم منشئ المجموعة ولم يوجد مفتاح للجيل الجديد، وزّعه.
      if (chat.isGroup && me != null && chat.createdBy == me!.id) {
        unawaited(_ensureGroupKey(chat, chat.epoch));
      }
    } catch (_) {}
  }

  Future<void> _onIncoming(String chatId, Message message) async {
    var chat = chats[chatId];
    if (chat == null) {
      await refreshChats();
      chat = chats[chatId];
      if (chat == null) return;
    }
    await _ingest(chat, message);
    final isMine = me != null && message.senderId == me!.id;
    if (!isMine) {
      if (_activeChats.contains(chatId)) {
        unawaited(markRead(chatId));
      } else {
        final current = chats[chatId];
        if (current != null) {
          chats[chatId] = current.copyWith(unreadCount: current.unreadCount + 1);
        }
      }
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _closingByUser = true;
    _ping?.cancel();
    _reconnect?.cancel();
    _typingTicker?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
