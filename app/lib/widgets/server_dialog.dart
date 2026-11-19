import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';

Future<void> showServerDialog(BuildContext context) async {
  final session = context.read<Session>();
  final controller = TextEditingController(text: session.serverUrl);
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('عنوان الخادم'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: controller,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'http://192.168.1.10:8080',
              ),
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.isEmpty) return 'أدخل عنوان الخادم';
                if (!v.startsWith('http://') && !v.startsWith('https://')) {
                  return 'يجب أن يبدأ بـ http:// أو https://';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Text(
              'ضع عنوان جهاز الخادم على الشبكة نفسها. للإنتاج استخدم https.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(context, true);
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );

  if (result == true) {
    await session.setServer(controller.text);
  }
}
