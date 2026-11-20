import 'package:flutter/material.dart';

class ChatWallpaper {
  const ChatWallpaper({
    required this.id,
    required this.name,
    required this.light,
    required this.dark,
  });

  final String id;
  final String name;
  final Color light;
  final Color dark;
}

const chatWallpapers = <ChatWallpaper>[
  ChatWallpaper(
    id: 'sand',
    name: 'رملي',
    light: Color(0xFFF3E8D5),
    dark: Color(0xFF2B251C),
  ),
  ChatWallpaper(
    id: 'mint',
    name: 'نعناعي',
    light: Color(0xFFDFF1E8),
    dark: Color(0xFF15251F),
  ),
  ChatWallpaper(
    id: 'sky',
    name: 'سماوي',
    light: Color(0xFFE0EDF7),
    dark: Color(0xFF14202B),
  ),
  ChatWallpaper(
    id: 'rose',
    name: 'وردي',
    light: Color(0xFFF6E4E7),
    dark: Color(0xFF2B1A1E),
  ),
  ChatWallpaper(
    id: 'olive',
    name: 'زيتوني',
    light: Color(0xFFE9EDD8),
    dark: Color(0xFF23261A),
  ),
  ChatWallpaper(
    id: 'graphite',
    name: 'رمادي',
    light: Color(0xFFE9E9E6),
    dark: Color(0xFF1B1E1D),
  ),
];

ChatWallpaper? wallpaperById(String? id) {
  if (id == null || id.isEmpty || id == 'default') return null;
  for (final wallpaper in chatWallpapers) {
    if (wallpaper.id == id) return wallpaper;
  }
  return null;
}

BoxDecoration wallpaperDecoration(BuildContext context, String? id) {
  final wallpaper = wallpaperById(id);
  if (wallpaper == null) return const BoxDecoration();
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base = dark ? wallpaper.dark : wallpaper.light;
  final top = Color.lerp(base, Colors.white, dark ? 0.04 : 0.16)!;
  final bottom = Color.lerp(base, Colors.black, dark ? 0.12 : 0.035)!;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, base, bottom],
    ),
  );
}
