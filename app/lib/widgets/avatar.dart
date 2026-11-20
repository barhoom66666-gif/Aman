import 'package:flutter/material.dart';

import '../core/config.dart';
import '../utils.dart';

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '؟';
  if (parts.length == 1) {
    final word = parts.first;
    return word.substring(0, word.isNotEmpty ? 1 : 0).toUpperCase();
  }
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    required this.color,
    this.imageUrl,
    this.size = 48,
    this.online = false,
    this.showOnline = false,
    this.icon,
  });

  final String name;
  final String color;
  final String? imageUrl;
  final double size;
  final bool online;
  final bool showOnline;
  final IconData? icon;

  String? get _resolvedImage {
    final value = imageUrl;
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return '${AppConfig.base}$value';
  }

  /// أسلوب JERNAS: خلفية دائرية بلون داكن من لون المستخدم، وأيقونة شخص ملونة بالداخل.
  Widget _placeholder(Color accent) {
    final iconData = icon ?? Icons.person_rounded;
    return Icon(
      iconData,
      color: accent,
      size: size * 0.56,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = jernasAccentFor(name.isEmpty ? color : name, color);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final circleBg = isDark
        ? Color.lerp(const Color(0xFF1A1E2B), accent, 0.24)!
        : Color.lerp(const Color(0xFFEFF2FA), accent, 0.22)!;
    final dot = size * 0.25;
    final image = _resolvedImage;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: circleBg,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(child: _placeholder(accent)),
                if (image != null)
                  Image.network(
                    image,
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
          if (showOnline && online)
            Positioned(
              left: 1,
              bottom: 1,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: dot * 0.16,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// يختار لونًا متناسقًا مع ألوان الأفاتار في JERNAS (أزرق، ذهبي، بنفسجي، برتقالي، أخضر).
Color jernasAccentFor(String seed, String fallbackHex) {
  const palette = <Color>[
    Color(0xFF4299E1), // أزرق
    Color(0xFFD69E2E), // ذهبي/أصفر
    Color(0xFF9F7AEA), // بنفسجي
    Color(0xFFED8936), // برتقالي
    Color(0xFF38B2AC), // تركوازي/أخضر
    Color(0xFF667EEA), // نيلي
  ];
  var hash = 0;
  for (final code in seed.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  if (hash == 0) return colorFromHex(fallbackHex);
  return palette[hash % palette.length];
}
