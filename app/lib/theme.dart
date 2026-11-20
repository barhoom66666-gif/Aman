import 'package:flutter/material.dart';

/// ألوان فقاعات المحادثة المستقلة عن ColorScheme، حتى يبقى الوضع الفاتح
/// والداكن بهوية JERNAS الكحلية/البنفسجية.
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
        outBubble: const Color(0xFF4C59B8),
        onOutBubble: Colors.white,
        inBubble: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        readTick: const Color(0xFF2CC56F),
        composerField: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      );

  static const ChatColors dark = ChatColors(
    outBubble: Color(0xFF39448E),
    onOutBubble: Color(0xFFF1F5F9),
    inBubble: Color(0xFF1F2333),
    readTick: Color(0xFF2CC56F),
    composerField: Color(0xFF1E2231),
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
  static const Color seed = Color(0xFF6B7BFF);
  static const Color brandText = Color(0xFF5D6FE2);
  static const Color activePill = Color(0xFF282F66);
  static const Color activeIcon = Color(0xFF6B7BFF);
  static const Color readGreen = Color(0xFF2CC56F);

  static ThemeData light() {
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    final scheme = base.copyWith(
      primary: const Color(0xFF5263D8),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE0E4FF),
      onPrimaryContainer: const Color(0xFF1D2559),
      secondaryContainer: const Color(0xFFE0E4FF),
      onSecondaryContainer: const Color(0xFF3B49B8),
    );
    return _base(scheme, const Color(0xFFF6F7FB), ChatColors.light(scheme));
  }

  static ThemeData dark() {
    // لوحة JERNAS الكحلية الداكنة مع أزرق/بنفسجي ناعم للأزرار والفلاتر.
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    final scheme = base.copyWith(
      primary: const Color(0xFF6B7BFF),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF282F66),
      onPrimaryContainer: const Color(0xFF9BA8FF),
      surface: const Color(0xFF151821),
      onSurface: const Color(0xFFF1F5F9),
      surfaceContainerHighest: const Color(0xFF232736),
      surfaceContainerHigh: const Color(0xFF1F2330),
      surfaceContainer: const Color(0xFF1B1E2B),
      surfaceContainerLow: const Color(0xFF171A24),
      secondaryContainer: const Color(0xFF282F66),
      onSecondaryContainer: const Color(0xFF7D8EFF),
      onSurfaceVariant: const Color(0xFF8E95A5),
      outline: const Color(0xFF687082),
      outlineVariant: const Color(0xFF282C3A),
      error: const Color(0xFFEF4444),
      onError: const Color(0xFF3A0910),
      errorContainer: const Color(0xFF5C1A22),
      onErrorContainer: const Color(0xFFFFDAD6),
      inverseSurface: const Color(0xFFF1F5F9),
      onInverseSurface: const Color(0xFF151821),
    );
    return _base(scheme, const Color(0xFF151821), ChatColors.dark);
  }

  static ThemeData _base(ColorScheme scheme, Color background, ChatColors chatColors) {
    final isDark = scheme.brightness == Brightness.dark;
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
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF13161F) : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: isDark ? const Color(0xFF272D61) : const Color(0xFFE2E6FF),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFF6B7BFF) : scheme.primary,
            );
          }
          return TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFFC8CDD8) : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              color: isDark ? const Color(0xFF6B7BFF) : scheme.primary,
              size: 24,
            );
          }
          return IconThemeData(
            color: isDark ? const Color(0xFFD5DAE4) : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return const Color(0xFFB8BEC9);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF6B7BFF);
          }
          return isDark ? const Color(0xFF353947) : const Color(0xFFD5D9E2);
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF1E222F)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: scheme.primary, width: 1.3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.65),
        thickness: 0.6,
        space: 1,
      ),
    );
  }
}
