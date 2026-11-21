import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../models.dart';
import '../utils.dart';

/// شاشة قائمة "رسالة المشرف" للمجموعة (مع زر + لإنشاء رسالة جديدة، وتعديل أو أرشفة الرسائل).
class AdminMessageListScreen extends StatefulWidget {
  const AdminMessageListScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<AdminMessageListScreen> createState() => _AdminMessageListScreenState();
}

class _AdminMessageListScreenState extends State<AdminMessageListScreen> {
  bool _showArchived = false;

  Future<void> _openEditor({AdminNotice? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminMessageEditScreen(
          chatId: widget.chatId,
          existing: existing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final notices = session
        .adminNoticesFor(widget.chatId, includeArchived: true)
        .where((n) => _showArchived ? n.archived : !n.archived)
        .toList();
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'أرشيف رسائل المشرف' : 'رسالة المشرف'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'الرسائل الحالية' : 'الأرشيف',
            onPressed: () => setState(() => _showArchived = !_showArchived),
            icon: Icon(
              _showArchived ? Icons.campaign_outlined : Icons.inventory_2_outlined,
              size: 24,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _showArchived
          ? null
          : SizedBox(
              width: 60,
              height: 60,
              child: FloatingActionButton(
                onPressed: () => _openEditor(),
                backgroundColor: const Color(0xFF6B7BFF),
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                elevation: 4,
                child: const Icon(Icons.add_rounded, size: 32),
              ),
            ),
      body: notices.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 146,
                      height: 146,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? const Color(0xFF212534)
                            : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.campaign_rounded,
                          size: 74,
                          color: Color(0xFF3E4B8E),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _showArchived
                          ? 'لا توجد رسائل مؤرشفة للمشرف'
                          : 'لا توجد رسائل مباشرة للمشرف',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'تظهر رسالة المشرف الجديدة والمعدلة عندما يفتح عضو المجموعة محادثة جماعية.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
              itemCount: notices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final notice = notices[index];
                final isMine = notice.senderId == session.me?.id;
                final senderLabel = isMine ? 'أنت' : notice.senderName;
                final timeLabel = formatRelativeAdminTime(notice.createdAt);

                return Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1F2330)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            '$senderLabel · $timeLabel',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          if (!notice.archived) ...[
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _openEditor(existing: notice),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.edit_outlined,
                                  size: 20,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => session.archiveAdminNotice(widget.chatId, notice.id),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  size: 20,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        notice.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notice.body,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: scheme.onSurface.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// شاشة إنشاء أو تعديل "رسالة المشرف" (العنوان 0/80، النص 0/3000، وزر نشر).
class AdminMessageEditScreen extends StatefulWidget {
  const AdminMessageEditScreen({
    super.key,
    required this.chatId,
    this.existing,
  });

  final String chatId;
  final AdminNotice? existing;

  @override
  State<AdminMessageEditScreen> createState() => _AdminMessageEditScreenState();
}

class _AdminMessageEditScreenState extends State<AdminMessageEditScreen> {
  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.existing?.body ?? '',
  );
  bool _publishing = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _canPublish =>
      !_publishing && _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;

  Future<void> _publish() async {
    if (!_canPublish) return;
    setState(() => _publishing = true);
    final session = context.read<Session>();
    try {
      await session.publishAdminNotice(
        chatId: widget.chatId,
        title: _title.text,
        body: _body.text,
        noticeId: widget.existing?.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _publishing = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleLen = _title.text.characters.length;
    final bodyLen = _body.text.characters.length;
    final active = _canPublish;

    return Scaffold(
      appBar: AppBar(title: const Text('رسالة المشرف')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_title.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          'العنوان',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    TextField(
                      controller: _title,
                      maxLength: 80,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'العنوان',
                        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16.5),
                        filled: false,
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(color: scheme.outlineVariant),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: scheme.outlineVariant),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: scheme.primary, width: 1.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        '$titleLen/80',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 235,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1F2330)
                            : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _body,
                              maxLength: 3000,
                              maxLines: null,
                              expands: true,
                              onChanged: (_) => setState(() {}),
                              style: const TextStyle(fontSize: 16, height: 1.45),
                              decoration: InputDecoration(
                                hintText: 'ضع الرسالة هنا',
                                hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
                                filled: false,
                                counterText: '',
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          Align(
                            alignment: AlignmentDirectional.bottomEnd,
                            child: Text(
                              '$bodyLen/3000',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 22),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: active ? _publish : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7585FF),
                    disabledBackgroundColor: isDark
                        ? const Color(0xFF1F2330)
                        : scheme.surfaceContainerHighest,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: _publishing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Text(
                          'نشر',
                          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// نافذة منبثقة تظهر للعضو عند دخوله المجموعة لأول مرة بعد نشر رسالة المشرف أو عند الضغط على الشريط العلوي.
Future<void> showAdminNoticePopup(
  BuildContext context, {
  required AdminNotice notice,
  required bool isMine,
  required VoidCallback onShowAll,
}) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final senderLabel = isMine ? 'أنت' : notice.senderName;
  final timeLabel = formatRelativeAdminTime(notice.createdAt);

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => Dialog(
      backgroundColor: isDark ? const Color(0xFF1C202C) : scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'رسالة المشرف',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7BFF),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$senderLabel · $timeLabel',
              style: TextStyle(
                fontSize: 13.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              notice.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Text(
                  notice.body,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.5,
                    color: scheme.onSurface.withValues(alpha: 0.92),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    onShowAll();
                  },
                  child: const Text(
                    'اظهار الكل',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7BFF),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text(
                    'موافق',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7BFF),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
