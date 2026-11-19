import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/session.dart';
import '../widgets/avatar.dart';

/// يستخرج اسم المستخدم من محتوى الباركود.
/// يقبل: `aman:u:name` أو `aman://u/name` أو رابطًا فيه `/u/name` أو الاسم وحده.
String? usernameFromQr(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;
  value = value.replaceFirst(RegExp(r'^aman:/*'), '');
  if (value.startsWith('u:') || value.startsWith('u/')) value = value.substring(2);
  final marker = value.indexOf('/u/');
  if (marker >= 0) value = value.substring(marker + 3);
  value = value.replaceFirst(RegExp(r'^@'), '');
  value = value.split('?').first.split('#').first.trim();
  if (RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(value.toLowerCase())) return value.toLowerCase();
  return null;
}

class MyQrScreen extends StatelessWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final me = session.me;
    final scheme = Theme.of(context).colorScheme;
    final payload = me == null ? '' : 'aman:u:${me.username}';

    return Scaffold(
      appBar: AppBar(title: const Text('باركودي')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            children: [
              Avatar(name: me?.displayName ?? '', color: me?.avatarColor ?? '#0E9F9A', size: 72),
              const SizedBox(height: 12),
              Text(
                me?.displayName ?? '',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              if ((me?.phone ?? '').isNotEmpty)
                Text(
                  '+${me!.phone}',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 230,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'اطلب من صديقك فتح «محادثة جديدة» ← «مسح باركود»، ثم مسح هذه الشاشة.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.6,
                    ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: '@${me?.username ?? ''}'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ اسم المستخدم')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('نسخ اسم المستخدم'),
              ),
              const SizedBox(height: 10),
              Text(
                '@${me?.username ?? ''}',
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    String? value;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        value = raw.trim();
        break;
      }
    }
    if (value == null) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('مسح باركود'),
        actions: [
          IconButton(
            tooltip: 'الكشاف',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: scheme.primary, width: 3),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'وجّه الكاميرا نحو باركود Aman',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
