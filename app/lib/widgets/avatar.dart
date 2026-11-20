import 'package:flutter/material.dart';

import '../core/config.dart';
import '../utils.dart';

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '؟';
  if (parts.length == 1) {
    final word = parts.first;
    return word.substring(0, word.length >= 1 ? 1 : 0).toUpperCase();
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
    this.showOnline = true,
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

  Widget _initials() {
    if (icon != null) return Icon(icon, color: Colors.white, size: size * 0.46);
    return Text(
      initialsOf(name),
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.36,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = colorFromHex(color);
    final dot = size * 0.26;
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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bg, Color.lerp(bg, Colors.black, 0.22)!],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(child: _initials()),
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
