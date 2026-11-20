import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/crypto.dart';
import '../core/session.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/server_dialog.dart';
import 'qr_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _fingerprint;

  @override
  void initState() {
    super.initState();
    _loadFingerprint();
  }

  Future<void> _loadFingerprint() async {
    final key = await CryptoService.myPublicKey();
    if (!mounted) return;
    setState(() {
      _fingerprint = key.length > 24 ? '${key.substring(0, 12)}…${key.substring(key.length - 8)}' : key;
    });
  }

  Future<void> _editName(Session session) async {
    final controller = TextEditingController(text: session.me?.displayName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل الاسم'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'الاسم الظاهر')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      try {
        await session.updateDisplayName(name);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  Future<void> _editPhone(Session session) async {
    final controller = TextEditingController(
      text: session.me?.phone == null ? '' : '+${session.me!.phone}',
    );
    final phone = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رقم الهاتف'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'الرقم مع رمز الدولة',
                hintText: '+971 50 123 4567',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'يستخدمه الآخرون للعثور عليك. لا يظهر إلا لمن يبحث عنك بالرقم.',
              style: TextStyle(fontSize: 11.5),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (phone == null) return;
    final digits = phoneDigits(phone);
    if (digits.length < 7 || digits.length > 15) {
      if (mounted) showError(context, 'أدخل الرقم مع رمز الدولة (7 إلى 15 رقمًا)، مثال: +971501234567');
      return;
    }
    try {
      await session.updatePhone(digits);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ رقم الهاتف')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _logout(Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج؟'),
        content: const Text('ستحتاج إلى كلمة المرور للدخول مجددًا. رسائلك المحلية تبقى على الجهاز.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('خروج')),
        ],
      ),
    );
    if (confirmed == true) {
      await session.logout();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _wipe(Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح الرسائل المحلية؟'),
        content: const Text('سيتم حذف نسخة الرسائل المخزّنة على هذا الجهاز فقط. تبقى الرسائل على الخادم.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('مسح')),
        ],
      ),
    );
    if (confirmed == true) {
      await session.wipeLocalData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم مسح البيانات المحلية')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final me = session.me;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Avatar(
                    name: me?.displayName ?? '',
                    color: me?.avatarColor ?? '#0E9F9A',
                    imageUrl: me?.avatarUrl,
                    size: 62,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          me?.displayName ?? '',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          userHandle(phone: me?.phone, username: me?.username),
                          textDirection: TextDirection.ltr,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.lock_rounded, size: 12, color: scheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'مفتاحك الخاص على هذا الجهاز فقط',
                              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MyQrScreen()),
                    ),
                    icon: const Icon(Icons.qr_code_2_rounded),
                    tooltip: 'باركودي',
                  ),
                  IconButton(
                    onPressed: () => _editName(session),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'تعديل الاسم',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: 'حسابي'),
          _SettingTile(
            icon: Icons.phone_iphone_rounded,
            title: 'رقم الهاتف',
            subtitle: (me?.phone ?? '').isEmpty
                ? 'أضف رقمك ليتمكن الآخرون من إيجادك والبحث عنك'
                : '+${me!.phone}',
            onTap: () => _editPhone(session),
          ),
          _SettingTile(
            icon: Icons.qr_code_2_rounded,
            title: 'باركودي',
            subtitle: 'اعرض باركودك ليضيفك الآخرون بمسح واحد',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyQrScreen()),
            ),
          ),
          _SettingTile(
            icon: Icons.alternate_email_rounded,
            title: 'اسم المستخدم',
            subtitle: '@${me?.username ?? ''}',
            trailing: IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: '@${me?.username ?? ''}'));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ اسم المستخدم')),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: 'الأمان'),
          _SettingTile(
            icon: Icons.enhanced_encryption_outlined,
            title: 'التشفير من الطرف إلى الطرف',
            subtitle: 'X25519 + HKDF-SHA256 + AES-256-GCM',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('مُفعّل', style: TextStyle(color: scheme.primary, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
          _SettingTile(
            icon: Icons.fingerprint_rounded,
            title: 'بصمة مفتاح الهوية',
            subtitle: _fingerprint ?? '…',
            trailing: IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () async {
                final key = await CryptoService.myPublicKey();
                await Clipboard.setData(ClipboardData(text: key));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ المفتاح العام')));
                }
              },
            ),
          ),
          const _SettingTile(
            icon: Icons.no_sim_outlined,
            title: 'بدون مكالمات',
            subtitle: 'هذه النسخة تركز على المراسلة فقط، لا صوت ولا فيديو.',
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: 'الاتصال'),
          _SettingTile(
            icon: Icons.dns_outlined,
            title: 'عنوان الخادم',
            subtitle: session.serverUrl,
            onTap: () => showServerDialog(context),
          ),
          _SettingTile(
            icon: Icons.wifi_tethering_rounded,
            title: 'حالة الاتصال',
            subtitle: session.connected ? 'متصل بقناة فورية (WebSocket)' : 'غير متصل — تتم إعادة المحاولة',
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: 'البيانات'),
          _SettingTile(
            icon: Icons.delete_sweep_outlined,
            title: 'مسح الرسائل المحلية',
            subtitle: 'حذف نسخة هذا الجهاز من الرسائل والوسائط',
            onTap: () => _wipe(session),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _logout(session),
            icon: Icon(Icons.logout_rounded, color: scheme.error),
            label: Text('تسجيل الخروج', style: TextStyle(color: scheme.error)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: scheme.error.withValues(alpha: 0.4))),
          ),
          const SizedBox(height: 22),
          Center(
            child: Column(
              children: [
                Text('Aman 0.4.0', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(
                  'لا مكالمات · لا إعلانات · لا تتبّع',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, right: 4, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_left_rounded, size: 18)),
      ),
    );
  }
}
