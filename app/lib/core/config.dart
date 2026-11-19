import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _define = String.fromEnvironment('AMAN_API', defaultValue: '');
  static String? _runtime;

  static String get defaultBase {
    if (_define.isNotEmpty) return normalize(_define);
    if (kIsWeb) return Uri.base.origin;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 10.0.2.2 = localhost الخاص بجهاز الكمبيوتر من داخل محاكي أندرويد
      return 'http://10.0.2.2:8080';
    }
    return 'http://127.0.0.1:8080';
  }

  static String get base => _runtime ?? defaultBase;

  static void setBase(String value) => _runtime = normalize(value);

  static String normalize(String value) {
    var v = value.trim();
    if (v.isEmpty) return defaultBase;
    if (!v.startsWith('http://') && !v.startsWith('https://')) v = 'http://$v';
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  static Uri api(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$base$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  static Uri media(String id) => api('/api/media/$id');

  static Uri ws(String token) {
    final wsBase = base.replaceFirst(RegExp('^http'), 'ws');
    return Uri.parse('$wsBase/ws').replace(queryParameters: {'token': token});
  }
}
