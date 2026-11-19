import 'package:flutter/material.dart';

/// ألوان فقاعات المحادثة المستقلة عن ColorScheme، حتى يبقى الوضع الفاتح
/// بهوية نجوى التركوازية ويأخذ الوضع الداكن لوحة الأخضر الداكن.
@immutable
class ChatColors extends ThemeExtension<ChatColors> {
  const ChatColors({
    required this.outBubble,
    required this.onOutBubble,
    required this.inBubble,
    required this.readTick,
    required this.composerField,
  });

  /// فقاعة رسائلي.
  final Color outBubble;
  final Color onOutBubble;

  /// فقاعة الرسائل الواردة.
  final Color inBubble;

  /// لون علامتي القراءة بعد وصول الطرف الآخر.
  final Color readTick;

  /// خلفية حقل كتابة الرسالة أسفل المحادثة.
  final Color composerField;

  factory ChatColors.light(ColorScheme scheme) => ChatColors(
        outBubble: scheme.primary,
        onOutBubble: scheme.onPrimary,
        inBubble: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        readTick: const Color(0xFF67E8F9),
        composerField: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      );

  static const ChatColors dark = ChatColors(
    outBubble: Color(0xFF005C4B),
    onOutBubble: Color(0xFFE9EDEF),
    inBubble: Color(0xFF202C33),
    readTick: Color(0xFF53BDEB),
    composerField: Color(0xFF1F2C34),
  );

  @override
  ChatColors copyWith({
    Color? outBubble,
    Color? onOutBubble,
    Color? inBubble,
    Color? readTick,
    Color? composerField,
  }) {
    return ChatColors(
      outBubble: outBubble ?? this.outBubble,
      onOutBubble: onOutBubble ?? this.onOutBubble,
      inBubble: inBubble ?? this.inBubble,
      readTick: readTick ?? this.readTick,
      composerField: composerField ?? this.composerField,
    );
  }

  @override
  ChatColors lerp(ThemeExtension<ChatColors>? other, double t) {
    if (other is! ChatColors) return this;
    return ChatColors(
      outBubble: Color.lerp(outBubble, other.outBubble, t)!,
      onOutBubble: Color.lerp(onOutBubble, other.onOutBubble, t)!,
      inBubble: Color.lerp(inBubble, other.inBubble, t)!,
      readTick: Color.lerp(readTick, other.readTick, t)!,
      composerField: Color.lerp(composerField, other.composerField, t)!,
    );
  }
}

class AppTheme {
  static const Color seed = Color(0xFF0E9F9A);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return _base(scheme, const Color(0xFFF6F7F9), ChatColors.light(scheme));
  }

  static ThemeData dark() {
    // لوحة أخضر داكن مريحة للعين، مبنية على أساس Material 3 ثم مُعدّلة يدويًا.
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    final scheme = base.copyWith(
      primary: const Color(0xFF00A884),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF005C4B),
      onPrimaryContainer: const Color(0xFFD7F7EC),
      surface: const Color(0xFF0B141A),
      onSurface: const Color(0xFFE9EDEF),
      surfaceContainerHighest: const Color(0xFF202C33),
      surfaceContainerHigh: const Color(0xFF1A242B),
      surfaceContainer: const Color(0xFF131E24),
      surfaceContainerLow: const Color(0xFF0F191F),
      secondaryContainer: const Color(0xFF1F2C34),
      onSecondaryContainer: const Color(0xFFD9E2E7),
      onSurfaceVariant: const Color(0xFF93A2AB),
      outline: const Color(0xFF8696A0),
      outlineVariant: const Color(0xFF3B4A54),
      error: const Color(0xFFF15C6D),
      onError: const Color(0xFF3A0910),
      errorContainer: const Color(0xFF5C1A22),
      onErrorContainer: const Color(0xFFFFDAD6),
      inverseSurface: const Color(0xFFE9EDEF),
      onInverseSurface: const Color(0xFF0B141A),
    );
    return _base(scheme, const Color(0xFF0B141A), ChatColors.dark);
  }

  static ThemeData _base(ColorScheme scheme, Color background, ChatColors chatColors) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[chatColors],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 0.6,
        space: 1,
      ),
    );
  }
}
