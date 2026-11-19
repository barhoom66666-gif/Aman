import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Color colorFromHex(String value) {
  var hex = value.replaceAll('#', '').trim();
  if (hex.length == 6) hex = 'FF$hex';
  final parsed = int.tryParse(hex, radix: 16);
  return Color(parsed ?? 0xFF0E9F9A);
}

String formatTime(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  return DateFormat('HH:mm', 'ar').format(date);
}

String formatChatTime(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat('HH:mm', 'ar').format(date);
  if (diff == 1) return 'أمس';
  if (diff < 7) return DateFormat('EEEE', 'ar').format(date);
  return DateFormat('dd/MM/yyyy', 'ar').format(date);
}

String formatDaySeparator(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  return DateFormat('EEEE، d MMMM yyyy', 'ar').format(date);
}

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes بايت';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} كيلوبايت';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميجابايت';
}

String lastSeenText(int millis) {
  if (millis <= 0) return 'غير متصل';
  final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(millis));
  if (diff.inMinutes < 1) return 'آخر ظهور الآن';
  if (diff.inHours < 1) return 'آخر ظهور قبل ${diff.inMinutes} دقيقة';
  if (diff.inDays < 1) return 'آخر ظهور قبل ${diff.inHours} ساعة';
  return 'آخر ظهور ${DateFormat('dd/MM HH:mm', 'ar').format(DateTime.fromMillisecondsSinceEpoch(millis))}';
}

bool isSameDay(int a, int b) {
  final da = DateTime.fromMillisecondsSinceEpoch(a);
  final db = DateTime.fromMillisecondsSinceEpoch(b);
  return da.year == db.year && da.month == db.month && da.day == db.day;
}

void showError(BuildContext context, Object error) {
  final text = error.toString();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// يعرض رقم الهاتف بصيغة دولية بسيطة، أو اسم المستخدم إن لم يُضف رقم.
String userHandle({String? phone, String? username}) {
  final digits = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isNotEmpty) return '+$digits';
  return '@${username ?? ''}';
}
