import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// طبقة التشفير في التطبيق.
///
/// المخطط (v1):
///  * لكل مستخدم مفتاح هوية X25519 (32 بايت) يُخزَّن في Keystore/Keychain،
///    ويُنشر المفتاح العام فقط على الخادم.
///  * الرسالة الفردية: المرسل يولّد مفتاحًا مؤقتًا (ephemeral) لكل رسالة،
///    يحسب ECDH(ephemeral, identity المستقبِل) ثم HKDF-SHA256 ثم AES-256-GCM.
///  * مفتاح المجموعة: مفتاح متماثل عشوائي لكل "جيل" (epoch)، يُوزَّع مشفّرًا
///    لكل عضو على حدة بنفس مخطط ECDH (مغلف لكل مستلم).
///  * الوسائط: تُشفَّر في الجهاز بمفتاح عشوائي قبل الرفع، ويُرسَل المفتاح
///    داخل نص الرسالة المشفّر فقط.
class CryptoService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String pairwiseInfo = 'aman/v1/pairwise';
  static const String groupKeyInfo = 'aman/v1/groupkey';

  static final X25519 _x25519 = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static SimpleKeyPairData? _identity;
  static Uint8List? _deviceKey;

  static final Random _random = Random.secure();

  static Uint8List randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  static String b64(List<int> bytes) => base64Encode(bytes);

  static Uint8List fromB64(String value) => base64Decode(value);

  /// يحمّل هوية الجهاز أو ينشئها. يعيد المفتاح العام (base64).
  static Future<String> loadOrCreateIdentity() async {
    if (_identity != null) {
      final pub = await _identity!.extractPublicKey();
      return b64(pub.bytes);
    }
    var seedB64 = await _storage.read(key: 'aman.identity_seed');
    if (seedB64 == null || seedB64.isEmpty) {
      seedB64 = b64(randomBytes(32));
      await _storage.write(key: 'aman.identity_seed', value: seedB64);
    }
    final seed = fromB64(seedB64);
    final pair = await _x25519.newKeyPairFromSeed(seed);
    final pub = await pair.extractPublicKey();
    _identity = SimpleKeyPairData(
      await pair.extractPrivateKeyBytes(),
      publicKey: pub,
      type: KeyPairType.x25519,
    );
    return b64(pub.bytes);
  }

  static Future<SimpleKeyPairData> _identityOrThrow() async {
    if (_identity == null) await loadOrCreateIdentity();
    return _identity!;
  }

  static Future<String> myPublicKey() async {
    final kp = await _identityOrThrow();
    return b64(kp.publicKey.bytes);
  }

  static Future<void> wipeIdentity() async {
    _identity = null;
    await _storage.delete(key: 'aman.identity_seed');
  }

  static String _aad(String chatId, String senderId, String recipientId) =>
      'aman/v1|$chatId|$senderId|$recipientId';

  /// يشفّر بيانات لمستلم واحد (رسالة فردية أو مفتاح مجموعة).
  static Future<Map<String, dynamic>> seal({
    required String chatId,
    required String senderId,
    required String recipientId,
    required String recipientPublicKey,
    required List<int> plaintext,
    String info = pairwiseInfo,
  }) async {
    final ephemeral = await _x25519.newKeyPair();
    final ephemeralPub = await ephemeral.extractPublicKey();
    final remote = SimplePublicKey(fromB64(recipientPublicKey), type: KeyPairType.x25519);
    final shared = await _x25519.sharedSecretKey(keyPair: ephemeral, remotePublicKey: remote);
    final sharedBytes = await shared.extractBytes();

    final salt = randomBytes(16);
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: salt,
      info: utf8.encode(info),
    );
    final nonce = randomBytes(12);
    final box = await _aes.encrypt(
      plaintext,
      secretKey: derived,
      nonce: nonce,
      aad: utf8.encode(_aad(chatId, senderId, recipientId)),
    );

    final ct = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
    return {
      'v': 1,
      'alg': 'x25519-aesgcm',
      'epk': b64(ephemeralPub.bytes),
      'salt': b64(salt),
      'nonce': b64(box.nonce),
      'ct': b64(ct),
    };
  }

  static Future<Uint8List> open({
    required String chatId,
    required String senderId,
    required String recipientId,
    required Map<String, dynamic> envelope,
    String info = pairwiseInfo,
  }) async {
    final kp = await _identityOrThrow();
    final ephemeralPub = SimplePublicKey(
      fromB64(envelope['epk'] as String),
      type: KeyPairType.x25519,
    );
    final shared = await _x25519.sharedSecretKey(keyPair: kp, remotePublicKey: ephemeralPub);
    final sharedBytes = await shared.extractBytes();
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: fromB64(envelope['salt'] as String),
      info: utf8.encode(info),
    );

    final raw = fromB64(envelope['ct'] as String);
    if (raw.length < 17) throw const FormatException('ciphertext تالف');
    final mac = raw.sublist(raw.length - 16);
    final ct = raw.sublist(0, raw.length - 16);
    final box = SecretBox(
      ct,
      nonce: fromB64(envelope['nonce'] as String),
      mac: Mac(mac),
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: derived,
      aad: utf8.encode(_aad(chatId, senderId, recipientId)),
    );
    return Uint8List.fromList(clear);
  }

  static Uint8List newGroupKey() => randomBytes(32);

  static List<int> _groupAad(String chatId, int epoch, String senderId) =>
      utf8.encode('aman/v1/group|$chatId|$epoch|$senderId');

  static Future<Map<String, dynamic>> sealGroupMessage({
    required String chatId,
    required int epoch,
    required String senderId,
    required List<int> groupKey,
    required List<int> plaintext,
  }) async {
    final nonce = randomBytes(12);
    final box = await _aes.encrypt(
      plaintext,
      secretKey: SecretKey(groupKey),
      nonce: nonce,
      aad: _groupAad(chatId, epoch, senderId),
    );
    final ct = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
    return {
      'v': 1,
      'alg': 'senderkey-aesgcm',
      'nonce': b64(box.nonce),
      'ct': b64(ct),
    };
  }

  static Future<Uint8List> openGroupMessage({
    required String chatId,
    required int epoch,
    required String senderId,
    required List<int> groupKey,
    required Map<String, dynamic> envelope,
  }) async {
    final raw = fromB64(envelope['ct'] as String);
    if (raw.length < 17) throw const FormatException('ciphertext تالف');
    final box = SecretBox(
      raw.sublist(0, raw.length - 16),
      nonce: fromB64(envelope['nonce'] as String),
      mac: Mac(raw.sublist(raw.length - 16)),
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: SecretKey(groupKey),
      aad: _groupAad(chatId, epoch, senderId),
    );
    return Uint8List.fromList(clear);
  }

  // ---------- الوسائط ----------

  static Future<EncryptedFile> encryptFile(List<int> bytes) async {
    final key = randomBytes(32);
    final nonce = randomBytes(12);
    final box = await _aes.encrypt(bytes, secretKey: SecretKey(key), nonce: nonce);
    final ct = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
    return EncryptedFile(key: key, nonce: nonce, bytes: ct);
  }

  static Future<Uint8List> decryptFile({
    required List<int> cipherBytes,
    required String keyB64,
    required String nonceB64,
  }) async {
    final raw = Uint8List.fromList(cipherBytes);
    if (raw.length < 17) throw const FormatException('ملف تالف');
    final box = SecretBox(
      raw.sublist(0, raw.length - 16),
      nonce: fromB64(nonceB64),
      mac: Mac(raw.sublist(raw.length - 16)),
    );
    final clear = await _aes.decrypt(box, secretKey: SecretKey(fromB64(keyB64)));
    return Uint8List.fromList(clear);
  }

  // ---------- تخزين محلي مشفّر (مفاتيح المجموعات) ----------

  static Future<Uint8List> _deviceKeyOrCreate() async {
    if (_deviceKey != null) return _deviceKey!;
    var stored = await _storage.read(key: 'aman.device_key');
    if (stored == null || stored.isEmpty) {
      stored = b64(randomBytes(32));
      await _storage.write(key: 'aman.device_key', value: stored);
    }
    _deviceKey = fromB64(stored);
    return _deviceKey!;
  }

  static Future<String> encryptLocal(String plaintext) async {
    final key = await _deviceKeyOrCreate();
    final nonce = randomBytes(12);
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: utf8.encode('aman/storage'),
    );
    return b64(nonce) + ':' + b64([...box.cipherText, ...box.mac.bytes]);
  }

  static Future<String> decryptLocal(String stored) async {
    final key = await _deviceKeyOrCreate();
    final parts = stored.split(':');
    if (parts.length != 2) throw const FormatException('بيانات محلية تالفة');
    final raw = fromB64(parts[1]);
    final box = SecretBox(
      raw.sublist(0, raw.length - 16),
      nonce: fromB64(parts[0]),
      mac: Mac(raw.sublist(raw.length - 16)),
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: utf8.encode('aman/storage'),
    );
    return utf8.decode(clear);
  }
}

class EncryptedFile {
  final Uint8List key;
  final Uint8List nonce;
  final Uint8List bytes;

  EncryptedFile({required this.key, required this.nonce, required this.bytes});
}
