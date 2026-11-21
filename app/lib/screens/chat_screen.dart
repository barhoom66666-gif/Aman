import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../models.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/chat_wallpaper.dart';
import 'add_members_screen.dart';
import 'admin_message_screen.dart';
import 'me_screen.dart';
import 'qr_screen.dart';
import 'tools_screens.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late Session _session;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _lastTypingSent = 0;
  bool _loading = true;
  String _searchQuery = '';
  bool _searching = false;
  bool _popupShowing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = context.read<Session>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    _session.addListener(_onSessionChanged);
    _session.setActiveChat(widget.chatId);
    await _session.loadMessages(widget.chatId);
    await _session.markRead(widget.chatId);
    if (mounted) setState(() => _loading = false);
    _jumpToBottom();
    _checkUnseenAdminNotice();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final chat = _session.chats[widget.chatId];
    if (chat != null && chat.unreadCount > 0 && ModalRoute.of(context)?.isCurrent == true) {
      _session.markRead(widget.chatId);
    }
    _checkUnseenAdminNotice();
  }

  void _checkUnseenAdminNotice() {
    if (!mounted || _popupShowing || ModalRoute.of(context)?.isCurrent != true) return;
    final chat = _session.chats[widget.chatId];
    if (chat == null || !chat.isGroup) return;
    final notice = _session.latestAdminNoticeFor(widget.chatId);
    if (notice == null) return;
    if (_session.isAdminNoticeSeen(notice.id)) return;

    _popupShowing = true;
    _session.markAdminNoticeSeen(notice.id);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _popupShowing = false;
        return;
      }
      await showAdminNoticePopup(
        context,
        notice: notice,
        isMine: notice.senderId == _session.me?.id,
        onShowAll: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AdminMessageListScreen(chatId: widget.chatId)),
          );
        },
      );
      _popupShowing = false;
    });
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _session.setActiveChat(null);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await _session.sendText(widget.chatId, text);
    _jumpToBottom();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 88, maxWidth: 2048);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    await _session.sendMedia(widget.chatId, bytes, name: picked.name, mime: picked.mimeType ?? 'image/jpeg');
    _jumpToBottom();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    await _session.sendMedia(
      widget.chatId,
      bytes,
      name: file.name,
      mime: 'application/octet-stream',
    );
    _jumpToBottom();
  }

  void _showAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('صورة من المعرض'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('التقاط صورة'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: const Text('ملف'),
              onTap: () {
                Navigator.pop(context);
                _pickFile();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _onInputChanged(String value) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTypingSent > 2500 && value.trim().isNotEmpty) {
      _lastTypingSent = now;
      _session.notifyTyping(widget.chatId);
    }
  }

  void _onMessageAction(Message message) {
    final starred = _session.isStarred(message.id);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((message.text ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('نسخ النص'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: message.text!));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النسخ')));
                },
              ),
            ListTile(
              leading: Icon(starred ? Icons.star_rounded : Icons.star_border_rounded),
              title: Text(starred ? 'إزالة النجمة' : 'تمييز بنجمة'),
              onTap: () {
                Navigator.pop(ctx);
                _session.toggleStarred(message.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openChatInfo(Chat chat) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ChatInfoScreen(chatId: chat.id)),
    );
    if (result == 'search' && mounted) {
      setState(() => _searching = true);
    }
  }

  Future<void> _pickSelfDestructDialog(Session session, Chat chat) async {
    const options = ['إيقاف', 'ساعة واحدة', '24 ساعة', 'أسبوع واحد', '٤ أسابيع'];
    final current = session.selfDestructFor(chat.id);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('رسائل التدمير الذاتي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
    if (chosen != null) {
      await session.setSelfDestructFor(chat.id, chosen);
    }
  }

  String _timerBadgeText(String selfDestruct) {
    if (selfDestruct.contains('٤') || selfDestruct.contains('4')) return '٤أ';
    if (selfDestruct.contains('أسبوع')) return '١أ';
    if (selfDestruct.contains('24') || selfDestruct.contains('٢٤')) return '١ي';
    if (selfDestruct.contains('ساعة')) return '١س';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final chat = session.chats[widget.chatId];
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (chat == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('المحادثة غير متاحة')),
      );
    }

    final allMessages = session.messagesOf(chat.id);
    final messages = _searchQuery.trim().isEmpty
        ? allMessages
        : allMessages
            .where((m) => (m.text ?? '').toLowerCase().contains(_searchQuery.trim().toLowerCase()))
            .toList();
    final typists = session.typistsIn(chat.id);
    final peer = chat.isGroup ? null : chat.peerFor(session.me?.id ?? '');
    final selfDestruct = session.selfDestructFor(chat.id);
    final timerBadge = _timerBadgeText(selfDestruct);
    final latestNotice = chat.isGroup ? session.latestAdminNoticeFor(chat.id) : null;
    final showTopAdminBanner =
        latestNotice != null && !session.isAdminBannerDismissed(latestNotice.id);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: _searching
            ? TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'بحث في المحادثة…',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() {
                      _searching = false;
                      _searchQuery = '';
                    }),
                  ),
                ),
              )
            : InkWell(
                onTap: () => _openChatInfo(chat),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      // صورة المحادثة مع شارة مؤقت التدمير الذاتي الدائرية المنقطة كما في JERNAS
                      SizedBox(
                        width: 46,
                        height: 44,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              right: 0,
                              top: 1,
                              child: Avatar(
                                name: chat.title,
                                color: chat.avatarColor,
                                imageUrl: peer?.avatarUrl,
                                size: 40,
                                online: peer?.online ?? false,
                                icon: chat.isGroup ? Icons.groups_rounded : null,
                              ),
                            ),
                            if (timerBadge.isNotEmpty)
                              Positioned(
                                left: -2,
                                bottom: -1,
                                child: Container(
                                  width: 21,
                                  height: 21,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).scaffoldBackgroundColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: scheme.onSurfaceVariant,
                                      width: 1.3,
                                    ),
                                  ),
                                  child: Text(
                                    timerBadge,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.lock_outline_rounded, size: 17, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            if (typists.isNotEmpty)
                              Text(
                                chat.isGroup ? 'يكتب أحد الأعضاء…' : 'يكتب…',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: scheme.primary),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'مكالمة مشفّرة',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('مكالمة صوتية مشفّرة')),
            ),
            icon: const Icon(Icons.call_outlined, size: 24),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          // شريط رسالة المشرف المثبت في أعلى المحادثة كما في صورة JERNAS
          if (showTopAdminBanner)
            Material(
              color: isDark ? const Color(0xFF1A1E2A) : scheme.surfaceContainerHighest,
              child: InkWell(
                onTap: () => showAdminNoticePopup(
                  context,
                  notice: latestNotice,
                  isMine: latestNotice.senderId == session.me?.id,
                  onShowAll: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AdminMessageListScreen(chatId: chat.id)),
                    );
                  },
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 9, 16, 9),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                        width: 0.7,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.campaign_outlined,
                        color: Color(0xFF6B7BFF),
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              latestNotice.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              latestNotice.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'إخفاء الشريط',
                        onPressed: () => session.dismissAdminBanner(latestNotice.id),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // خلفية المحادثة مع نقش أيقونات JERNAS الخفيف
                Container(
                  decoration: wallpaperDecoration(context, session.wallpaperFor(chat.id)),
                  child: CustomPaint(
                    painter: _JernasDoodlePainter(isDark: isDark),
                  ),
                ),
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        itemCount: messages.length + 1,
                        itemBuilder: (context, index) {
                          // بطاقات النظام العلوية (التشفير + اليوم + إنشاء المجموعة + التدمير الذاتي)
                          if (index == messages.length) {
                            return _JernasSystemHeader(
                              chat: chat,
                              isCreator: chat.createdBy == session.me?.id,
                              selfDestruct: selfDestruct,
                              onTapSelfDestruct: () => _pickSelfDestructDialog(session, chat),
                            );
                          }
                          final message = messages[messages.length - 1 - index];
                          final older =
                              index + 1 < messages.length ? messages[messages.length - 2 - index] : null;
                          final mine = message.senderId == session.me?.id;
                          final showDay = older != null && !isSameDay(older.createdAt, message.createdAt);
                          final sender = chat.memberById(message.senderId);
                          final readByPeer = !chat.isGroup &&
                              peer != null &&
                              peer.lastReadAt >= message.createdAt &&
                              !message.pending;
                          return Column(
                            children: [
                              if (showDay) _DaySeparator(millis: message.createdAt),
                              _MessageBubble(
                                message: message,
                                mine: mine,
                                showSender: chat.isGroup && !mine,
                                senderName: sender?.displayName ?? '',
                                senderColor: sender?.avatarColor ?? '#6B7BFF',
                                readByPeer: readByPeer,
                                starred: session.isStarred(message.id),
                                onRetry: () => session.retry(message),
                                onLongPress: () => _onMessageAction(message),
                                session: session,
                              ),
                            ],
                          );
                        },
                      ),
              ],
            ),
          ),
          _Composer(
            controller: _input,
            onChanged: _onInputChanged,
            onSend: _send,
            onAttach: _showAttachSheet,
            onCamera: () => _pickImage(ImageSource.camera),
          ),
        ],
      ),
    );
  }
}

/// بطاقات النظام في بداية المحادثة كما في صورة JERNAS:
/// 1) بطاقة التشفير بقفل أزرق
/// 2) شارة "اليوم" و"أنت أنشأت هذه المجموعة"
/// 3) بطاقة مؤقت التدمير الذاتي مع رابط "انقر للتغيير."
class _JernasSystemHeader extends StatelessWidget {
  const _JernasSystemHeader({
    required this.chat,
    required this.isCreator,
    required this.selfDestruct,
    required this.onTapSelfDestruct,
  });

  final Chat chat;
  final bool isCreator;
  final String selfDestruct;
  final VoidCallback onTapSelfDestruct;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF1F2330).withValues(alpha: 0.94)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.9);
    final pillColor = isDark
        ? const Color(0xFF232736).withValues(alpha: 0.95)
        : scheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 4),
      child: Column(
        children: [
          // بطاقة التشفير
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF6B7BFF),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'الرسائل مشفرة بالكامل. لا يمكن لأي شخص خارج هذه المحادثة ولا حتى AMAN يمكنه قراءتها أو الاستماع إليها.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // شارة اليوم
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: pillColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              'اليوم',
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (chat.isGroup) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                isCreator ? 'أنت أنشأت هذه المجموعة' : 'تمت إضافتك إلى هذه المجموعة',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // بطاقة مؤقت التدمير الذاتي
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTapSelfDestruct,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_toggle_off_rounded,
                    color: Color(0xFF6B7BFF),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: scheme.onSurfaceVariant,
                        ),
                        children: [
                          TextSpan(
                            text: selfDestruct == 'إيقاف'
                                ? 'مؤقت التدمير الذاتي للرسائل متوقف حاليًا في هذه الدردشة. '
                                : 'الوقت الافتراضي للتدمير الذاتي هو $selfDestruct. ستختفي جميع الرسائل الجديدة من هذه الدردشة بعد $selfDestruct. ',
                          ),
                          const TextSpan(
                            text: 'انقر للتغيير.',
                            style: TextStyle(
                              color: Color(0xFF6B7BFF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// رسام نقش خلفية المحادثة الخفيف (أقفال، فقاعات، هواتف، شموس) كما في خلفية JERNAS.
class _JernasDoodlePainter extends CustomPainter {
  const _JernasDoodlePainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final color = isDark
        ? Colors.white.withValues(alpha: 0.032)
        : Colors.black.withValues(alpha: 0.035);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const cell = 76.0;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final cx = c * cell + (r.isOdd ? cell * 0.5 : cell * 0.25);
        final cy = r * cell + cell * 0.45;
        final kind = (r * 3 + c) % 4;
        if (kind == 0) {
          // قفل صغير
          final rect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy + 4), width: 18, height: 14),
            const Radius.circular(3),
          );
          canvas.drawRRect(rect, paint);
          canvas.drawArc(
            Rect.fromCenter(center: Offset(cx, cy - 3), width: 11, height: 11),
            math.pi,
            math.pi,
            false,
            paint,
          );
        } else if (kind == 1) {
          // فقاعة محادثة دائرية
          canvas.drawOval(
            Rect.fromCenter(center: Offset(cx, cy), width: 20, height: 16),
            paint,
          );
        } else if (kind == 2) {
          // بطاقة مستطيلة
          final rect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy), width: 20, height: 14),
            const Radius.circular(2.5),
          );
          canvas.drawRRect(rect, paint);
          canvas.drawLine(Offset(cx - 10, cy - 2), Offset(cx + 10, cy - 2), paint);
        } else {
          // شمس/نجمة صغيرة
          canvas.drawCircle(Offset(cx, cy), 5.5, paint);
          for (var i = 0; i < 8; i++) {
            final angle = i * math.pi / 4;
            final p1 = Offset(cx + math.cos(angle) * 8, cy + math.sin(angle) * 8);
            final p2 = Offset(cx + math.cos(angle) * 10.5, cy + math.sin(angle) * 10.5);
            canvas.drawLine(p1, p2, paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _JernasDoodlePainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.millis});

  final int millis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        formatDaySeparator(millis),
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.showSender,
    required this.senderName,
    required this.senderColor,
    required this.readByPeer,
    required this.starred,
    required this.onRetry,
    required this.onLongPress,
    required this.session,
  });

  final Message message;
  final bool mine;
  final bool showSender;
  final String senderName;
  final String senderColor;
  final bool readByPeer;
  final bool starred;
  final VoidCallback onRetry;
  final VoidCallback onLongPress;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chat = Theme.of(context).extension<ChatColors>() ?? ChatColors.light(scheme);
    final bubbleColor = mine ? chat.outBubble : chat.inBubble;
    final textColor = mine ? chat.onOutBubble : scheme.onSurface;

    Widget content;
    if (message.media != null) {
      content = _MediaContent(message: message, session: session, mine: mine);
    } else if (message.text != null) {
      content = Text(
        message.text!,
        style: TextStyle(color: textColor, fontSize: 15, height: 1.45),
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: textColor.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'رسالة غير متاحة على هذا الجهاز',
              style: TextStyle(color: textColor.withValues(alpha: 0.8), fontSize: 13, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      );
    }

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (starred) ...[
          Icon(Icons.star_rounded, size: 12, color: textColor.withValues(alpha: 0.75)),
          const SizedBox(width: 3),
        ],
        Text(
          formatTime(message.createdAt),
          style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.65)),
        ),
        if (mine) ...[
          const SizedBox(width: 4),
          Icon(
            message.pending
                ? Icons.schedule_rounded
                : message.failed
                    ? Icons.error_outline_rounded
                    : readByPeer
                        ? Icons.done_all_rounded
                        : Icons.done_rounded,
            size: 13,
            color: message.failed
                ? scheme.error
                : message.pending
                    ? textColor.withValues(alpha: 0.55)
                    : readByPeer
                        ? chat.readTick
                        : textColor.withValues(alpha: 0.55),
          ),
        ],
      ],
    );

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: onLongPress,
        onTap: message.failed ? onRetry : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(16),
              topEnd: const Radius.circular(16),
              bottomStart: Radius.circular(mine ? 16 : 4),
              bottomEnd: Radius.circular(mine ? 4 : 16),
            ),
            border: message.failed
                ? Border.all(color: scheme.error.withValues(alpha: 0.7), width: 1)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSender)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    senderName,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: colorFromHex(senderColor),
                    ),
                  ),
                ),
              content,
              const SizedBox(height: 3),
              Align(alignment: AlignmentDirectional.centerEnd, child: meta),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaContent extends StatelessWidget {
  const _MediaContent({required this.message, required this.session, required this.mine});

  final Message message;
  final Session session;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final media = message.media!;
    final scheme = Theme.of(context).colorScheme;
    final chat = Theme.of(context).extension<ChatColors>() ?? ChatColors.light(scheme);
    final onBubble = mine ? chat.onOutBubble : scheme.onSurface;
    if (!media.isImage) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: mine ? chat.onOutBubble : scheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  media.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onBubble,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  humanSize(media.size),
                  style: TextStyle(
                    color: onBubble.withValues(alpha: 0.65),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => session.downloadMedia(message),
            icon: Icon(Icons.download_rounded, color: mine ? chat.onOutBubble : scheme.primary),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FutureBuilder<Uint8List?>(
        future: _bytes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Container(
              width: 220,
              height: 160,
              color: scheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return Container(
              padding: const EdgeInsets.all(12),
              child: Text('تعذّر تحميل الصورة', style: TextStyle(color: scheme.error, fontSize: 12)),
            );
          }
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => _ImageViewer(bytes: bytes)),
            ),
            child: Image.memory(bytes, width: 240, fit: BoxFit.cover),
          );
        },
      ),
    );
  }

  Future<Uint8List?> _bytes() async {
    if (message.localPath != null) {
      final file = File(message.localPath!);
      if (await file.exists()) return file.readAsBytes();
    }
    return session.downloadMedia(message);
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image.memory(bytes),
        ),
      ),
    );
  }
}

/// شريط كتابة الرسالة السفلي المطابق لتصميم JERNAS:
/// كبسولة موحدة بداخلها (إيموجي، حقل "رسالة"، زر توسيع، كاميرا، +، وزر الميكروفون/الإرسال الدائري البنفسجي).
class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.onChanged,
    required this.onSend,
    required this.onAttach,
    required this.onCamera,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onCamera;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = isDark ? const Color(0xFF1F2330) : scheme.surfaceContainerHighest;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // أيقونة الإيموجي على اليمين
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  widget.controller.text = '${widget.controller.text}😊';
                  widget.controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: widget.controller.text.length),
                  );
                  widget.onChanged(widget.controller.text);
                },
                icon: Icon(
                  Icons.sentiment_satisfied_alt_rounded,
                  color: scheme.onSurfaceVariant,
                  size: 25,
                ),
              ),
              // حقل كتابة الرسالة
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  onChanged: widget.onChanged,
                  minLines: _expanded ? 3 : 1,
                  maxLines: _expanded ? 8 : 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'رسالة',
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              // زر التوسيع، الكاميرا، والإرفاق (+)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'توسيع الحقل',
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.fullscreen_exit_rounded : Icons.crop_free_rounded,
                  color: scheme.onSurfaceVariant,
                  size: 21,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'كاميرا',
                onPressed: widget.onCamera,
                icon: Icon(
                  Icons.camera_alt_outlined,
                  color: scheme.onSurfaceVariant,
                  size: 23,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'إرفاق',
                onPressed: widget.onAttach,
                icon: Icon(
                  Icons.add_circle_outline_rounded,
                  color: scheme.onSurfaceVariant,
                  size: 24,
                ),
              ),
              const SizedBox(width: 4),
              // الزر الدائري البنفسجي على اليسار (ميكروفون عند الفراغ، وإرسال عند الكتابة)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.controller,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return InkWell(
                    customBorder: const CircleBorder(),
                    onTap: hasText
                        ? widget.onSend
                        : () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('اكتب رسالتك لإرسالها مشفّرة')),
                            ),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6B7BFF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasText ? Icons.send_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شاشة معلومات المحادثة / المجموعة الكاملة المطابقة لصور JERNAS تماماً.
class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  bool _busy = false;

  Future<void> _addMembers(BuildContext context) async {
    final added = await showAddMembersSheet(context, widget.chatId);
    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إضافة الأعضاء وتحديث مفتاح المجموعة')),
      );
    }
  }

  Future<void> _editTaskText(
    BuildContext context, {
    required String title,
    required String initial,
    required ValueChanged<String> onSaved,
  }) async {
    final controller = TextEditingController(text: initial);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: title),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (res != null) onSaved(res);
  }

  Future<void> _pickSelfDestruct(BuildContext context, Session session, String chatId) async {
    const options = ['إيقاف', 'ساعة واحدة', '24 ساعة', 'أسبوع واحد', '٤ أسابيع'];
    final current = session.selfDestructFor(chatId);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('رسائل التدمير الذاتي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
    if (chosen != null) {
      await session.setSelfDestructFor(chatId, chosen);
    }
  }

  Future<void> _leave(BuildContext context) async {
    final session = context.read<Session>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مغادرة المجموعة؟'),
        content: const Text('لن تصلك رسائل هذه المجموعة بعد المغادرة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('مغادرة')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await session.api.leaveChat(widget.chatId);
      session.chats.remove(widget.chatId);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMediaSheet(BuildContext context, Session session, Chat chat) {
    final mediaMessages = session.messagesOf(chat.id).where((m) => m.isMedia).toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('الوسائط والروابط والملفات', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (mediaMessages.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('لا توجد وسائط أو ملفات مشتركة في هذه المحادثة بعد.')),
                )
              else
                ...mediaMessages.take(8).map(
                  (m) => ListTile(
                    leading: Icon(m.media?.isImage == true ? Icons.image_outlined : Icons.insert_drive_file_outlined),
                    title: Text(m.media?.name ?? 'ملف'),
                    subtitle: Text(humanSize(m.media?.size ?? 0)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final chat = session.chats[widget.chatId];
    final scheme = Theme.of(context).colorScheme;
    if (chat == null) return const Scaffold();
    final peer = chat.isGroup ? null : chat.peerFor(session.me?.id ?? '');
    final pinned = session.isPinned(chat.id);
    final mutedMsg = session.isChatMuted(chat.id);
    final mutedCalls = session.isCallMuted(chat.id);
    final selfDestruct = session.selfDestructFor(chat.id);
    final adminMsg = session.adminMessageFor(chat.id);
    final taskMsg = session.taskFor(chat.id);
    final starredCount = session.starredMessagesIn(chat.id).length;

    // ترتيب الأعضاء بحيث يظهر "أنت" أولاً كما في JERNAS
    final orderedMembers = [...chat.members];
    orderedMembers.sort((a, b) {
      if (a.id == session.me?.id) return -1;
      if (b.id == session.me?.id) return 1;
      return 0;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          IconButton(
            tooltip: 'باركود',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyQrScreen()),
            ),
            icon: const Icon(Icons.qr_code_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          // الصورة الدائرية الكبيرة في المنتصف
          Center(
            child: Avatar(
              name: chat.title,
              color: chat.avatarColor,
              imageUrl: peer?.avatarUrl,
              size: 98,
              icon: chat.isGroup ? Icons.groups_rounded : null,
            ),
          ),
          const SizedBox(height: 14),
          // الاسم وبجانبه قفل التشفير
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  chat.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // الأزرار الدائرية الثلاثة بأسلوب JERNAS: مكالمة، فيديو، دردشة
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionCircleButton(
                icon: Icons.call_outlined,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('مكالمة صوتية مشفّرة')),
                ),
              ),
              const SizedBox(width: 28),
              _ActionCircleButton(
                icon: Icons.videocam_outlined,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('مكالمة فيديو مشفّرة')),
                ),
              ),
              const SizedBox(width: 28),
              _ActionCircleButton(
                icon: Icons.sms_outlined,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(),
          ),

          if (chat.isGroup) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              title: const Text('إدارة المجموعة', style: TextStyle(fontSize: 16.5)),
              trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              onTap: () => _addMembers(context),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              title: const Text('رسالة المشرف', style: TextStyle(fontSize: 16.5)),
              subtitle: adminMsg.isEmpty
                  ? null
                  : Text(adminMsg, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
              trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AdminMessageListScreen(chatId: chat.id)),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              title: const Text('مهمة', style: TextStyle(fontSize: 16.5)),
              subtitle: taskMsg.isEmpty
                  ? null
                  : Text(taskMsg, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
              trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              onTap: () => _editTaskText(
                context,
                title: 'مهمة المجموعة',
                initial: taskMsg,
                onSaved: (v) => session.setTaskFor(chat.id, v),
              ),
            ),
          ],

          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('كتم إشعارات الرسائل', style: TextStyle(fontSize: 16.5)),
            value: mutedMsg,
            onChanged: (_) => session.toggleChatMuted(chat.id),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            title: const Text('كتم صوت المكالمات الواردة', style: TextStyle(fontSize: 16.5)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'يؤدي تمكين الحساب إلى إخفاء إشعارات المكالمات الواردة، وإظهار سجلات المكالمات الفائتة فقط في التطبيق',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
            value: mutedCalls,
            onChanged: (_) => session.toggleCallMuted(chat.id),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('تثبيت المحادثة', style: TextStyle(fontSize: 16.5)),
            value: pinned,
            onChanged: (_) => session.togglePin(chat.id),
          ),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('رسائل التدمير الذاتي', style: TextStyle(fontSize: 16.5)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(selfDestruct, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
            onTap: () => _pickSelfDestruct(context, session, chat.id),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('الوسائط والروابط والملفات', style: TextStyle(fontSize: 16.5)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: () => _showMediaSheet(context, session, chat),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('المميزة بنجمة', style: TextStyle(fontSize: 16.5)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$starredCount', style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StarredMessagesScreen(chatId: chat.id)),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('بحث المحادثة', style: TextStyle(fontSize: 16.5)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, size: 22, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
            onTap: () => Navigator.of(context).pop('search'),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            title: const Text('خلفية', style: TextStyle(fontSize: 16.5)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => WallpaperSettingsScreen(chatId: chat.id)),
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Divider(),
          ),

          if (chat.isGroup) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                '${chat.members.length} عضو',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            // شبكة الأعضاء من 3 أعمدة كما في JERNAS مع زر (+) الدائري لإضافة عضو
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemCount: orderedMembers.length + 1,
                itemBuilder: (context, index) {
                  if (index == orderedMembers.length) {
                    return _AddMemberGridItem(
                      onTap: _busy ? null : () => _addMembers(context),
                    );
                  }
                  final member = orderedMembers[index];
                  final isMe = member.id == session.me?.id;
                  return _MemberGridItem(
                    member: member,
                    label: isMe ? 'أنت' : member.displayName,
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextButton.icon(
                onPressed: _busy ? null : () => _leave(context),
                icon: Icon(Icons.logout_rounded, color: scheme.error),
                label: Text('مغادرة المجموعة', style: TextStyle(color: scheme.error)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionCircleButton extends StatelessWidget {
  const _ActionCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: const BoxDecoration(
          color: Color(0xFF6B7BFF),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 27),
      ),
    );
  }
}

class _MemberGridItem extends StatelessWidget {
  const _MemberGridItem({required this.member, required this.label});

  final User member;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Avatar(
          name: member.displayName,
          color: member.avatarColor,
          imageUrl: member.avatarUrl,
          size: 68,
          online: member.online,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: scheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

class _AddMemberGridItem extends StatelessWidget {
  const _AddMemberGridItem({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? const Color(0xFF222634)
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            ),
            child: Icon(Icons.add_rounded, size: 32, color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'إضافة',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
