import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/server_dialog.dart';
import 'qr_screen.dart';
import 'settings_screen.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  bool _busy = false;

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 82,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final name = picked.name.toLowerCase();
    final mime = picked.mimeType ?? (name.endsWith('.png') ? 'image/png' : 'image/jpeg');
    setState(() => _busy = true);
    try {
      await context.read<Session>().uploadAvatar(bytes, mime);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _busy = true);
    try {
      await context.read<Session>().removeAvatar();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _photoSheet(Session session) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من المعرض'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if ((session.me?.avatarUrl ?? '').isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                title: Text('إزالة الصورة', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removePhoto();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _themeSheet(Session session) {
    final options = <(ThemeMode, String, IconData)>[
      (ThemeMode.system, 'حسب النظام', Icons.brightness_auto_rounded),
      (ThemeMode.light, 'فاتح', Icons.light_mode_outlined),
      (ThemeMode.dark, 'داكن', Icons.dark_mode_outlined),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('المظهر', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ...options.map(
              (option) => ListTile(
                leading: Icon(option.$3),
                title: Text(option.$2),
                trailing: session.themeMode == option.$1
                    ? Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  session.setThemeMode(option.$1);
                  Navigator.pop(sheetContext);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final me = session.me;
    if (me == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('أنا'),
        actions: [
          IconButton(
            tooltip: 'باركودي',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyQrScreen()),
            ),
            icon: const Icon(Icons.qr_code_2_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _busy ? null : () => _photoSheet(session),
                  child: Stack(
                    alignment: Alignment.bottomLeft,
                    children: [
                      Avatar(
                        name: me.displayName,
                        color: me.avatarColor,
                        imageUrl: me.avatarUrl,
                        size: 104,
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 2),
                        ),
                        child: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(7),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.photo_camera_rounded, size: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  me.displayName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  userHandle(phone: me.phone, username: me.username),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _busy ? null : () => _photoSheet(session),
                  icon: const Icon(Icons.photo_camera_outlined, size: 17),
                  label: const Text('تغيير الصورة'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _MenuTile(
            icon: Icons.manage_accounts_outlined,
            title: 'الحساب والخصوصية',
            subtitle: 'الاسم، رقم الهاتف، الأمان والخادم',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          _MenuTile(
            icon: Icons.qr_code_2_rounded,
            title: 'باركودي',
            subtitle: 'اعرض باركودك ليضيفك الآخرون',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyQrScreen()),
            ),
          ),
          _MenuTile(
            icon: Icons.dark_mode_outlined,
            title: 'المظهر',
            subtitle: switch (session.themeMode) {
              ThemeMode.light => 'فاتح',
              ThemeMode.dark => 'داكن',
              ThemeMode.system => 'حسب النظام',
            },
            onTap: () => _themeSheet(session),
          ),
          _MenuTile(
            icon: Icons.devices_outlined,
            title: 'الأجهزة',
            subtitle: 'هذا الجهاز — جهاز واحد لكل حساب',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DevicesScreen()),
            ),
          ),
          _MenuTile(
            icon: Icons.dns_outlined,
            title: 'الخادم',
            subtitle: session.serverUrl.replaceFirst(RegExp('^https?://'), ''),
            onTap: () => showServerDialog(context),
          ),
          _MenuTile(
            icon: Icons.info_outline_rounded,
            title: 'حول Aman',
            subtitle: 'الإصدار 0.4.0',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'Aman 0.4.0',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, color: scheme.onSurfaceVariant),
        title: Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle!,
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ),
        trailing: const Icon(Icons.chevron_left_rounded, size: 18),
      ),
    );
  }
}

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الأجهزة')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: const ListTile(
              leading: Icon(Icons.phone_android_rounded),
              title: Text('هذا الجهاز'),
              subtitle: Text('أندرويد · متصل الآن'),
              trailing: Icon(Icons.verified_user_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'النسخة الحالية تدعم جهازًا واحدًا لكل حساب. عند تسجيل الدخول من جهاز آخر، '
            'يُستبدل مفتاح التشفير القديم. سنضيف إدارة أجهزة متعددة لاحقًا.',
            style: TextStyle(fontSize: 12.5, height: 1.7, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('حول Aman')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.lock_rounded, color: Colors.white, size: 42),
                ),
                const SizedBox(height: 14),
                Text('Aman', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('الإصدار 0.4.0', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'مراسلة خاصة ومشفّرة من الطرف إلى الطرف. الرسائل والصور والملفات '
            'تُشفَّر على جهازك قبل الإرسال، والخادم لا يرى المحتوى.',
            style: TextStyle(fontSize: 13.5, height: 1.8),
          ),
          const SizedBox(height: 14),
          const Text(
            'المزايا الحالية:\n'
            '• محادثات فردية ومجموعات مشفّرة.\n'
            '• إنشاء مجموعة بدون أعضاء، وإضافتهم لاحقًا.\n'
            '• البحث برقم الهاتف أو الاسم، والباركود.\n'
            '• صور وملفات مشفّرة، مع ردود وقراءة.\n'
            '• خلفيات محادثة وتثبيت للمحادثات.\n'
            '• لا يحتوي التطبيق على مكالمات صوتية أو فيديو.',
            style: TextStyle(fontSize: 13, height: 1.9),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'نسخة تجريبية: التوقيع تجريبي، ولا يوجد تحقق برمز SMS بعد. '
              'الخطة المجانية للخادم قد تفقد البيانات عند إعادة النشر.',
              style: TextStyle(fontSize: 11.5, height: 1.7, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
