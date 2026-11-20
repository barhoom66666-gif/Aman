import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/chat_wallpaper.dart';
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
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('التقاط صورة'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.camera);
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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final me = session.me;
    if (me == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          children: [
            // عنوان "أنا" في الأعلى على اليمين كما في JERNAS
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Text(
                'أنا',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
            ),
            // رأس الملف الشخصي: الصورة على اليمين، الاسم والرقم بالمنتصف، وزر الباركود الدائري على اليسار
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _busy ? null : () => _photoSheet(session),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Avatar(
                          name: me.displayName,
                          color: me.avatarColor,
                          imageUrl: me.avatarUrl,
                          size: 76,
                        ),
                        if (_busy)
                          const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          me.displayName,
                          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          userHandle(phone: me.phone, username: me.username),
                          textDirection: TextDirection.ltr,
                          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MyQrScreen()),
                    ),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF222634)
                            : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.qr_code_rounded,
                        size: 22,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // المجموعة الأولى: الحساب، الخصوصية والأمن، إدارة الأجهزة
            _JernasMenuRow(
              icon: Icons.account_circle_outlined,
              title: 'الحساب',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
            _JernasMenuRow(
              icon: Icons.verified_user_outlined,
              title: 'الخصوصية والأمن',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivacySecurityScreen()),
              ),
            ),
            _JernasMenuRow(
              icon: Icons.devices_rounded,
              title: 'إدارة الأجهزة',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DevicesScreen()),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Divider(),
            ),

            // المجموعة الثانية: إشعارات، البيانات والتخزين، المحادثات، المكالمات
            _JernasMenuRow(
              icon: Icons.notifications_none_rounded,
              title: 'إشعارات',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsSettingsScreen()),
              ),
            ),
            _JernasMenuRow(
              icon: Icons.storage_rounded,
              title: 'البيانات والتخزين',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DataStorageScreen()),
              ),
            ),
            _JernasMenuRow(
              icon: Icons.sms_outlined,
              title: 'المحادثات',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChatsSettingsScreen()),
              ),
            ),
            _JernasMenuRow(
              icon: Icons.call_outlined,
              title: 'المكالمات',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CallsSettingsScreen()),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Divider(),
            ),

            // المجموعة الثالثة: عام، حول التطبيق والمساعدة
            _JernasMenuRow(
              icon: Icons.settings_outlined,
              title: 'عام',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GeneralSettingsScreen()),
              ),
            ),
            _JernasMenuRow(
              icon: Icons.info_outline_rounded,
              title: 'حول التطبيق والمساعدة',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JernasMenuRow extends StatelessWidget {
  const _JernasMenuRow({
    required this.icon,
    required this.title,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      leading: Icon(icon, size: 25, color: scheme.onSurface.withValues(alpha: 0.9)),
      title: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// شاشة "الخصوصية والأمن" المطابقة للصورة تماماً.
class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});

  Future<void> _pickOption(
    BuildContext context, {
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onSelected,
  }) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ...options.map(
              (opt) => ListTile(
                title: Text(opt),
                trailing: opt == current
                    ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, opt),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen != null) onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('الخصوصية والأمن')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('قائمة المحظورين', style: TextStyle(fontSize: 16.5)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('لا يوجد مستخدمون في قائمة المحظورين')),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 16),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            title: const Text('آخر ظهور وعبر الإنترنت', style: TextStyle(fontSize: 16.5)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'عند إيقاف التشغيل، لن تتمكن من مشاركة أو رؤية آخر ظهور وحالات الاتصال بالإنترنت.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
            value: session.showLastSeen,
            onChanged: (v) {
              session.showLastSeen = v;
              session.savePrefs();
            },
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            title: const Text('ايصالات القراءة', style: TextStyle(fontSize: 16.5)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'عند إيقاف التشغيل، لن ترسل أو تستقبل إيصالات القراءة. يتم دائمًا إرسال إيصالات القراءة للمحادثات الجماعية.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
            value: session.readReceipts,
            onChanged: (v) {
              session.readReceipts = v;
              session.savePrefs();
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            title: const Text('مؤقت الرسائل الافتراضي', style: TextStyle(fontSize: 16.5)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ابدأ محادثات فردية جديدة ستبدأ برسائل تختفي تلقائيًا عند ضبط المؤقت الخاص بك.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session.defaultSelfDestruct,
                  style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
            onTap: () => _pickOption(
              context,
              title: 'مؤقت الرسائل الافتراضي',
              options: const ['إيقاف', '24 ساعة', 'أسبوع واحد', 'شهر واحد'],
              current: session.defaultSelfDestruct,
              onSelected: (v) {
                session.defaultSelfDestruct = v;
                session.savePrefs();
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 16),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            title: const Text('قفل الشاشة', style: TextStyle(fontSize: 16.5)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'استخدم Touch ID أو Face ID لفتح AMAN.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            value: session.screenLock,
            onChanged: (v) {
              session.screenLock = v;
              session.savePrefs();
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('مدة قفل الشاشة', style: TextStyle(fontSize: 16.5)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session.screenLockTimeout,
                  style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
            onTap: () => _pickOption(
              context,
              title: 'مدة قفل الشاشة',
              options: const ['فوراً', 'دقيقة واحدة', '5 دقائق', '15 دقيقة', 'ساعة واحدة'],
              current: session.screenLockTimeout,
              onSelected: (v) {
                session.screenLockTimeout = v;
                session.savePrefs();
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 16),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('لا يمكن الإضافة عبر المجموعات', style: TextStyle(fontSize: 16.5)),
            value: session.blockGroupAdd,
            onChanged: (v) {
              session.blockGroupAdd = v;
              session.savePrefs();
            },
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('لا يمكن أن تضاف عبر الرقم', style: TextStyle(fontSize: 16.5)),
            value: session.blockPhoneAdd,
            onChanged: (v) {
              session.blockPhoneAdd = v;
              session.savePrefs();
            },
          ),
        ],
      ),
    );
  }
}

/// شاشة "إشعارات" المطابقة للصورة تماماً.
class NotificationsSettingsScreen extends StatelessWidget {
  const NotificationsSettingsScreen({super.key});

  Future<void> _pickSound(
    BuildContext context, {
    required String current,
    required ValueChanged<String> onSelected,
  }) async {
    const sounds = ['صافرة', 'نغمة هادئة', 'رنين كلاسيكي', 'نبض', 'بدون صوت'];
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('اختر نغمة الإشعار', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ...sounds.map(
              (s) => ListTile(
                title: Text(s),
                trailing: s == current
                    ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen != null) onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('إشعارات')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'الرسائل',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('إظهار الإخطار', style: TextStyle(fontSize: 16.5)),
            value: session.msgShowNotification,
            onChanged: (v) {
              session.msgShowNotification = v;
              session.savePrefs();
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('صوت', style: TextStyle(fontSize: 16.5)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(session.msgSound, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
            onTap: () => _pickSound(
              context,
              current: session.msgSound,
              onSelected: (v) {
                session.msgSound = v;
                session.savePrefs();
              },
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('إشعارات التفاعل', style: TextStyle(fontSize: 16.5)),
            value: session.msgReactionNotifications,
            onChanged: (v) {
              session.msgReactionNotifications = v;
              session.savePrefs();
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Divider(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Text(
              'المجموعات',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('إظهار الإخطار', style: TextStyle(fontSize: 16.5)),
            value: session.grpShowNotification,
            onChanged: (v) {
              session.grpShowNotification = v;
              session.savePrefs();
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('صوت', style: TextStyle(fontSize: 16.5)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(session.grpSound, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
            onTap: () => _pickSound(
              context,
              current: session.grpSound,
              onSelected: (v) {
                session.grpSound = v;
                session.savePrefs();
              },
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('إشعارات التفاعل', style: TextStyle(fontSize: 16.5)),
            value: session.grpReactionNotifications,
            onChanged: (v) {
              session.grpReactionNotifications = v;
              session.savePrefs();
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Divider(),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('عرض المعاينة', style: TextStyle(fontSize: 16.5)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'معاينة نص الرسالة في إشعارات الرسائل الجديدة.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            value: session.showNotificationPreview,
            onChanged: (v) {
              session.showNotificationPreview = v;
              session.savePrefs();
            },
          ),
        ],
      ),
    );
  }
}

/// شاشة "المحادثات" (النسخ الاحتياطي للمحادثة، نقل أو استعادة الدردشات، خلفية) المطابقة للصورة.
class ChatsSettingsScreen extends StatelessWidget {
  const ChatsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('المحادثات')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Text(
              'إعدادات الدردشة',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('النسخ الاحتياطي للمحادثة', style: TextStyle(fontSize: 16.5)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم حفظ نسخة احتياطية مشفّرة محليًا على الجهاز')),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('نقل أو استعادة الدردشات', style: TextStyle(fontSize: 16.5)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('جميع الدردشات المحلية متزامنة ومشفّرة')),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Divider(),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('خلفية', style: TextStyle(fontSize: 16.5)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WallpaperSettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// شاشة "خلفية" المطابقة للصورة (اختر خلفية، اختر من الصور، التقاط صورة، إعادة تعيين جميع الخلفيات).
class WallpaperSettingsScreen extends StatelessWidget {
  const WallpaperSettingsScreen({super.key, this.chatId});

  final String? chatId;

  String get _targetKey => chatId ?? '__global__';

  Future<void> _choosePreset(BuildContext context, Session session) async {
    final current = session.wallpaperFor(_targetKey);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final dark = Theme.of(sheetContext).brightness == Brightness.dark;
        Widget swatch(String id, String label) {
          final wallpaper = wallpaperById(id);
          final selected = (current ?? 'default') == id;
          final base = wallpaper == null
              ? scheme.surfaceContainerHighest
              : (dark ? wallpaper.dark : wallpaper.light);
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(sheetContext).pop(id),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: wallpaper == null ? base : null,
                      gradient: wallpaper == null
                          ? null
                          : wallpaperDecoration(sheetContext, wallpaper.id).gradient,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? scheme.primary : scheme.outlineVariant,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                        : null,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('اختر خلفية', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                  children: [
                    swatch('default', 'افتراضي'),
                    ...chatWallpapers.map((w) => swatch(w.id, w.name)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null) return;
    await session.setWallpaper(_targetKey, choice == 'default' ? null : choice);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث خلفية المحادثة')),
      );
    }
  }

  Future<void> _pickFromCameraOrGallery(BuildContext context, Session session, ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1440, imageQuality: 85);
    if (picked == null || !context.mounted) return;
    await session.setWallpaper(_targetKey, 'sky');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تطبيق الخلفية المختارة')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('خلفية')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('اختر خلفية', style: TextStyle(fontSize: 16.5)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: () => _choosePreset(context, session),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('اختر من الصور', style: TextStyle(fontSize: 16.5)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: () => _pickFromCameraOrGallery(context, session, ImageSource.gallery),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('التقاط صورة', style: TextStyle(fontSize: 16.5)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: () => _pickFromCameraOrGallery(context, session, ImageSource.camera),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Divider(),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: Text(
              'إعادة تعيين جميع الخلفيات',
              style: TextStyle(fontSize: 16.5, color: scheme.error, fontWeight: FontWeight.w500),
            ),
            onTap: () async {
              await session.resetAllWallpapers();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تمت إعادة تعيين جميع الخلفيات')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

/// شاشة "عام" المطابقة للصورة (لغة، اختيار موضوع، ملحوظات، تقويم).
class GeneralSettingsScreen extends StatelessWidget {
  const GeneralSettingsScreen({super.key});

  void _themeSheet(BuildContext context, Session session) {
    final options = <(ThemeMode, String)>[
      (ThemeMode.system, 'النظام الافتراضي'),
      (ThemeMode.dark, 'داكن'),
      (ThemeMode.light, 'فاتح'),
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
              child: Text('اختيار موضوع', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ...options.map(
              (option) => ListTile(
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
    final scheme = Theme.of(context).colorScheme;
    final themeLabel = switch (session.themeMode) {
      ThemeMode.light => 'فاتح',
      ThemeMode.dark => 'النظام الافتراضي',
      ThemeMode.system => 'النظام الافتراضي',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('عام')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('لغة', style: TextStyle(fontSize: 16.5)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('النظام الافتراضي', style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('اللغة الحالية: العربية (النظام الافتراضي)')),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: const Text('اختيار موضوع', style: TextStyle(fontSize: 16.5)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(themeLabel, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
            onTap: () => _themeSheet(context, session),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            title: const Text('ملحوظات', style: TextStyle(fontSize: 16.5)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'عرض إدخال الملاحظات في أعلى الصفحة الرئيسية.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            value: session.showNotesInHeader,
            onChanged: (v) {
              session.showNotesInHeader = v;
              session.savePrefs();
            },
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            title: const Text('تقويم', style: TextStyle(fontSize: 16.5)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'عرض إدخالات التقويم في أعلى الصفحة الرئيسية.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            value: session.showCalendarInHeader,
            onChanged: (v) {
              session.showCalendarInHeader = v;
              session.savePrefs();
            },
          ),
        ],
      ),
    );
  }
}

/// شاشة "البيانات والتخزين"
class DataStorageScreen extends StatelessWidget {
  const DataStorageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('البيانات والتخزين')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: const Icon(Icons.dns_outlined),
            title: const Text('عنوان الخادم', style: TextStyle(fontSize: 16.5)),
            subtitle: Text(session.serverUrl, textDirection: TextDirection.ltr),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: () => showServerDialog(context),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('مسح التخزين المؤقت والرسائل المحلية', style: TextStyle(fontSize: 16.5)),
            subtitle: const Text('حذف نسخة الرسائل المخزّنة محليًا على هذا الجهاز'),
            onTap: () async {
              await session.wipeLocalData();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم مسح البيانات المحلية')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

/// شاشة إعدادات "المكالمات" من قائمة "أنا"
class CallsSettingsScreen extends StatefulWidget {
  const CallsSettingsScreen({super.key});

  @override
  State<CallsSettingsScreen> createState() => _CallsSettingsScreenState();
}

class _CallsSettingsScreenState extends State<CallsSettingsScreen> {
  bool _muteIncoming = false;
  bool _lowData = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('المكالمات')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            title: const Text('كتم صوت المكالمات الواردة', style: TextStyle(fontSize: 16.5)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'يؤدي تمكين الحساب إلى إخفاء إشعارات المكالمات الواردة، وإظهار سجلات المكالمات الفائتة فقط في التطبيق.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
            value: _muteIncoming,
            onChanged: (v) => setState(() => _muteIncoming = v),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            title: const Text('توفير البيانات في المكالمات', style: TextStyle(fontSize: 16.5)),
            value: _lowData,
            onChanged: (v) => setState(() => _lowData = v),
          ),
        ],
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
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
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
            'يُستبدل مفتاح التشفير القديم.',
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
      appBar: AppBar(title: const Text('حول التطبيق والمساعدة')),
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
                Text('AMAN', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('الإصدار 0.5.0', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'مراسلة خاصة ومشفّرة من الطرف إلى الطرف بتصميم JERNAS. الرسائل والصور والملفات '
            'تُشفَّر على جهازك قبل الإرسال، والخادم لا يرى المحتوى.',
            style: TextStyle(fontSize: 13.5, height: 1.8),
          ),
        ],
      ),
    );
  }
}
