import 'dart:convert';

class User {
  final String id;
  final String username;
  final String displayName;
  final String? phone;
  final String? avatarUrl;
  final String avatarColor;
  final String? identityKey;
  final int lastSeen;
  final int lastReadAt;
  bool online;

  User({
    required this.id,
    required this.username,
    required this.displayName,
    this.phone,
    this.avatarUrl,
    required this.avatarColor,
    this.identityKey,
    this.lastSeen = 0,
    this.lastReadAt = 0,
    this.online = false,
  });

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return parts.first.characters2(1);
    return parts.first.characters2(1) + parts[1].characters2(1);
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? json['username'] as String? ?? '',
      phone: json['phone'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      avatarColor: json['avatarColor'] as String? ?? '#0EA5A4',
      identityKey: json['identityKey'] as String?,
      lastSeen: (json['lastSeen'] as num?)?.toInt() ?? 0,
      lastReadAt: (json['lastReadAt'] as num?)?.toInt() ?? 0,
      online: json['online'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'phone': phone,
        'avatarUrl': avatarUrl,
        'avatarColor': avatarColor,
        'identityKey': identityKey,
        'lastSeen': lastSeen,
        'lastReadAt': lastReadAt,
        'online': online,
      };

  User copyWith({String? displayName, String? phone, String? avatarUrl, bool? online, int? lastSeen, int? lastReadAt, String? identityKey}) => User(
        id: id,
        username: username,
        displayName: displayName ?? this.displayName,
        phone: phone ?? this.phone,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        avatarColor: avatarColor,
        identityKey: identityKey ?? this.identityKey,
        lastSeen: lastSeen ?? this.lastSeen,
        lastReadAt: lastReadAt ?? this.lastReadAt,
        online: online ?? this.online,
      );
}

extension on String {
  String characters2(int n) => length <= n ? this : substring(0, n).toUpperCase();
}

class Chat {
  final String id;
  final String type; // direct | group
  final String title;
  final String avatarColor;
  final int epoch;
  final List<User> members;
  final int unreadCount;
  final int lastReadAt;
  final int updatedAt;
  final Message? lastMessage;
  final String createdBy;

  Chat({
    required this.id,
    required this.type,
    required this.title,
    required this.avatarColor,
    required this.epoch,
    required this.members,
    required this.unreadCount,
    required this.lastReadAt,
    required this.updatedAt,
    this.lastMessage,
    this.createdBy = '',
  });

  bool get isGroup => type == 'group';

  User? peerFor(String myId) {
    for (final m in members) {
      if (m.id != myId) return m;
    }
    return null;
  }

  User? memberById(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  Chat copyWith({
    String? title,
    int? epoch,
    List<User>? members,
    int? unreadCount,
    int? lastReadAt,
    int? updatedAt,
    Message? lastMessage,
  }) =>
      Chat(
        id: id,
        type: type,
        title: title ?? this.title,
        avatarColor: avatarColor,
        epoch: epoch ?? this.epoch,
        members: members ?? this.members,
        unreadCount: unreadCount ?? this.unreadCount,
        lastReadAt: lastReadAt ?? this.lastReadAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastMessage: lastMessage ?? this.lastMessage,
        createdBy: createdBy,
      );

  factory Chat.fromJson(Map<String, dynamic> json) => Chat(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'direct',
        title: json['title'] as String? ?? 'محادثة',
        avatarColor: json['avatarColor'] as String? ?? '#0EA5A4',
        epoch: (json['epoch'] as num?)?.toInt() ?? 1,
        members: ((json['members'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(User.fromJson)
            .toList(),
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
        lastReadAt: (json['lastReadAt'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
        lastMessage: json['lastMessage'] is Map<String, dynamic>
            ? Message.fromJson(json['lastMessage'] as Map<String, dynamic>)
            : null,
        createdBy: json['createdBy'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'avatarColor': avatarColor,
        'epoch': epoch,
        'members': members.map((m) => m.toJson()).toList(),
        'unreadCount': unreadCount,
        'lastReadAt': lastReadAt,
        'updatedAt': updatedAt,
        'lastMessage': lastMessage?.toJson(),
        'createdBy': createdBy,
      };
}

class MediaInfo {
  final String id;
  final String key; // base64
  final String nonce; // base64
  final String name;
  final String mime;
  final int size;
  final int? width;
  final int? height;

  MediaInfo({
    required this.id,
    required this.key,
    required this.nonce,
    required this.name,
    required this.mime,
    required this.size,
    this.width,
    this.height,
  });

  bool get isImage => mime.startsWith('image/');

  factory MediaInfo.fromJson(Map<String, dynamic> json) => MediaInfo(
        id: json['id'] as String,
        key: json['key'] as String,
        nonce: json['nonce'] as String,
        name: json['name'] as String? ?? 'ملف',
        mime: json['mime'] as String? ?? 'application/octet-stream',
        size: (json['size'] as num?)?.toInt() ?? 0,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'nonce': nonce,
        'name': name,
        'mime': mime,
        'size': size,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };
}

class AdminNotice {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String title;
  final String body;
  final int createdAt;
  final bool archived;

  AdminNotice({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.title,
    required this.body,
    required this.createdAt,
    this.archived = false,
  });

  AdminNotice copyWith({
    String? title,
    String? body,
    int? createdAt,
    bool? archived,
  }) =>
      AdminNotice(
        id: id,
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        title: title ?? this.title,
        body: body ?? this.body,
        createdAt: createdAt ?? this.createdAt,
        archived: archived ?? this.archived,
      );

  factory AdminNotice.fromJson(Map<String, dynamic> json) => AdminNotice(
        id: json['id'] as String? ?? '',
        chatId: json['chatId'] as String? ?? '',
        senderId: json['senderId'] as String? ?? '',
        senderName: json['senderName'] as String? ?? 'مشرف',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        archived: json['archived'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'senderName': senderName,
        'title': title,
        'body': body,
        'createdAt': createdAt,
        'archived': archived,
      };
}

class Message {
  String id;
  final String chatId;
  final String senderId;
  final String kind; // text | media
  final int? epoch;
  Map<String, dynamic> envelope;
  int createdAt;
  final String? clientId;

  // الحالة المحلية (لا تُرسل للخادم)
  String? text;
  MediaInfo? media;
  AdminNotice? adminNotice;
  String? localPath;
  bool pending;
  bool failed;
  bool undecryptable;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.kind,
    required this.envelope,
    required this.createdAt,
    this.epoch,
    this.clientId,
    this.text,
    this.media,
    this.adminNotice,
    this.localPath,
    this.pending = false,
    this.failed = false,
    this.undecryptable = false,
  });

  bool get isMedia => kind == 'media';
  bool get isAdminNotice => adminNotice != null || (text != null && text!.startsWith('__admin_notice__:'));

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        chatId: json['chatId'] as String? ?? '',
        senderId: json['senderId'] as String? ?? '',
        kind: json['kind'] as String? ?? 'text',
        epoch: (json['epoch'] as num?)?.toInt(),
        envelope: (json['envelope'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        clientId: json['clientId'] as String?,
        text: json['text'] as String?,
        media: json['media'] is Map<String, dynamic>
            ? MediaInfo.fromJson(json['media'] as Map<String, dynamic>)
            : null,
        adminNotice: json['adminNotice'] is Map<String, dynamic>
            ? AdminNotice.fromJson(json['adminNotice'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'kind': kind,
        'epoch': epoch,
        'envelope': envelope,
        'createdAt': createdAt,
        'clientId': clientId,
        if (text != null) 'text': text,
        if (media != null) 'media': media!.toJson(),
        if (adminNotice != null) 'adminNotice': adminNotice!.toJson(),
      };
}

String encodePayload(Map<String, dynamic> payload) => jsonEncode(payload);

Map<String, dynamic> decodePayload(String raw) {
  final decoded = jsonDecode(raw);
  return (decoded as Map).cast<String, dynamic>();
}
