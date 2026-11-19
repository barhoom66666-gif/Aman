import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;

  ApiException(this.status, this.code, this.message);

  bool get isNetwork => status == 0;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({this.token});

  String? token;
  final http.Client _client = http.Client();

  Map<String, String> get _headers => {
        if (token != null) 'authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    List<int>? rawBytes,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final uri = AppConfig.api(path, query);
    http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(_headers);
      if (rawBytes != null) {
        request.headers['content-type'] = 'application/octet-stream';
        request.bodyBytes = Uint8List.fromList(rawBytes);
      } else if (body != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'انتهت مهلة الاتصال بالخادم');
    } catch (_) {
      throw ApiException(0, 'network', 'تعذّر الوصول إلى الخادم. تحقّق من الاتصال وعنوان الخادم.');
    }

    Map<String, dynamic> data = const {};
    if (response.bodyBytes.isNotEmpty) {
      try {
        data = (jsonDecode(utf8.decode(response.bodyBytes)) as Map).cast<String, dynamic>();
      } catch (_) {
        data = const {};
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;

    throw ApiException(
      response.statusCode,
      (data['error'] as String?) ?? 'error',
      (data['message'] as String?) ?? 'حدث خطأ غير متوقع (${response.statusCode})',
    );
  }

  // ---------- الحساب ----------

  Future<Map<String, dynamic>> register({
    required String phone,
    required String password,
    required String displayName,
    required String identityKey,
    String device = 'android',
  }) =>
      _send('POST', '/api/auth/register', body: {
        'phone': phone,
        'password': password,
        'displayName': displayName,
        'identityKey': identityKey,
        'device': device,
      });

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) =>
      _send('POST', '/api/auth/login', body: {
        'identifier': identifier,
        'password': password,
        'device': 'android',
      });

  Future<void> logout() => _send('POST', '/api/auth/logout');

  Future<Map<String, dynamic>> me() => _send('GET', '/api/me');

  Future<Map<String, dynamic>> updateProfile({String? displayName, String? phone}) =>
      _send('PATCH', '/api/me', body: {
        if (displayName != null) 'displayName': displayName,
        if (phone != null) 'phone': phone,
      });

  Future<void> updateIdentityKey(String identityKey) =>
      _send('POST', '/api/me/identity', body: {'identityKey': identityKey});

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final data = await _send('GET', '/api/users', query: {'q': query});
    return ((data['users'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();
  }

  // ---------- المحادثات ----------

  Future<List<Map<String, dynamic>>> chats() async {
    final data = await _send('GET', '/api/chats');
    return ((data['chats'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> chat(String id) async {
    final data = await _send('GET', '/api/chats/$id');
    return (data['chat'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> createDirect(String username) async {
    final data = await _send('POST', '/api/chats/direct', body: {'username': username});
    return (data['chat'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> createGroup(String title, List<String> members) async {
    final data = await _send('POST', '/api/chats/group', body: {'title': title, 'members': members});
    return (data['chat'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> addMembers(String chatId, List<String> usernames) async {
    final data = await _send('POST', '/api/chats/$chatId/members', body: {'usernames': usernames});
    return (data['chat'] as Map).cast<String, dynamic>();
  }

  Future<void> leaveChat(String chatId) => _send('POST', '/api/chats/$chatId/leave');

  // ---------- الرسائل ----------

  Future<Map<String, dynamic>> messages(
    String chatId, {
    int? before,
    int limit = 40,
  }) =>
      _send('GET', '/api/chats/$chatId/messages', query: {
        'limit': '$limit',
        if (before != null) 'before': '$before',
      });

  Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String clientId,
    required String kind,
    required Map<String, dynamic> envelope,
    int? epoch,
  }) async {
    final data = await _send('POST', '/api/chats/$chatId/messages', body: {
      'clientId': clientId,
      'kind': kind,
      'envelope': envelope,
      if (epoch != null) 'epoch': epoch,
    });
    return (data['message'] as Map).cast<String, dynamic>();
  }

  Future<void> markRead(String chatId) => _send('POST', '/api/chats/$chatId/read');

  Future<void> postGroupKeys(String chatId, int epoch, Map<String, dynamic> envelopes) =>
      _send('POST', '/api/chats/$chatId/keys', body: {'epoch': epoch, 'envelopes': envelopes});

  Future<Map<String, dynamic>?> getGroupKey(String chatId, int epoch) async {
    try {
      return await _send('GET', '/api/chats/$chatId/keys/$epoch');
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  // ---------- الوسائط ----------

  Future<Map<String, dynamic>> uploadMedia(String chatId, List<int> bytes) =>
      _send('POST', '/api/media', query: {'chatId': chatId}, rawBytes: bytes, timeout: const Duration(seconds: 90));

  Future<Uint8List> downloadMedia(String id) async {
    try {
      final response = await _client
          .get(AppConfig.media(id), headers: _headers)
          .timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        throw ApiException(response.statusCode, 'media', 'تعذّر تنزيل الملف');
      }
      return response.bodyBytes;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(0, 'network', 'تعذّر تنزيل الملف. تحقّق من الاتصال.');
    }
  }
}
