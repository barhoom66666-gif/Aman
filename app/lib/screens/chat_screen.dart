import 'dart:async';
import 'dart:io';

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
import '../widgets/common.dart';

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
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final chat = _session.chats[widget.chatId];
    if (chat != null && chat.unreadCount > 0 && ModalRoute.of(context)?.isCurrent == true) {
      _session.markRead(widget.chatId);
    }
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

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 2048);
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
              title: const Text('صورة'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
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

  void _copy(Message message) {
    final text = message.text;
    if (text == null || text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النسخ')));
  }

  Future<void> _showChatInfo(Chat chat) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ChatInfoSheet(chatId: chat.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final chat = session.chats[widget.chatId];
    final scheme = Theme.of(context).colorScheme;

    if (chat == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('المحادثة غير متاحة')),
      );
    }

    final messages = session.messagesOf(chat.id);
    final typists = session.typistsIn(chat.id);
    final peer = chat.isGroup ? null : chat.peerFor(session.me?.id ?? '');

    String subtitle;
    if (typists.isNotEmpty) {
      subtitle = chat.isGroup ? 'يكتب أحد الأعضاء…' : 'يكتب…';
    } else if (chat.isGroup) {
      subtitle = '${chat.members.length} أعضاء';
    } else if (peer?.online == true) {
      subtitle = 'متصل الآن';
    } else {
      subtitle = lastSeenText(peer?.lastSeen ?? 0);
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => _showChatInfo(chat),
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              Avatar(
                name: chat.title,
                color: chat.avatarColor,
                imageUrl: peer?.avatarUrl,
                size: 40,
                online: peer?.online ?? false,
                icon: chat.isGroup ? Icons.groups_rounded : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: typists.isNotEmpty ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _showChatInfo(chat),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const EmptyState(
                        icon: Icons.lock_outline_rounded,
                        title: 'محادثة مشفّرة',
                        subtitle: 'الرسائل مشفّرة من الطرف إلى الطرف. اكتب أول رسالة.',
                      )
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[messages.length - 1 - index];
                          final older = index + 1 < messages.length ? messages[messages.length - 2 - index] : null;
                          final mine = message.senderId == session.me?.id;
                          final showDay = older == null || !isSameDay(older.createdAt, message.createdAt);
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
                                senderColor: sender?.avatarColor ?? '#0E9F9A',
                                readByPeer: readByPeer,
                                onRetry: () => session.retry(message),
                                onCopy: () => _copy(message),
                                session: session,
                              ),
                            ],
                          );
                        },
                      ),
          ),
          if (typists.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                chat.isGroup ? 'أحد الأعضاء يكتب…' : 'يكتب…',
                style: TextStyle(fontSize: 11.5, color: scheme.primary),
              ),
            ),
          _Composer(
            controller: _input,
            onChanged: _onInputChanged,
            onSend: _send,
            onAttach: _showAttachSheet,
          ),
        ],
      ),
    );
  }
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
    required this.onRetry,
    required this.onCopy,
    required this.session,
  });

  final Message message;
  final bool mine;
  final bool showSender;
  final String senderName;
  final String senderColor;
  final bool readByPeer;
  final VoidCallback onRetry;
  final VoidCallback onCopy;
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
        onLongPress: onCopy,
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onChanged,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chat = Theme.of(context).extension<ChatColors>() ?? ChatColors.light(scheme);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4), width: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: onAttach,
              icon: Icon(Icons.add_circle_outline_rounded, color: scheme.primary),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'رسالة…',
                  filled: true,
                  fillColor: chat.composerField,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final active = value.text.trim().isNotEmpty;
                return Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  child: IconButton.filled(
                    onPressed: active ? onSend : null,
                    icon: const Icon(Icons.send_rounded, size: 20),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInfoSheet extends StatefulWidget {
  const _ChatInfoSheet({required this.chatId});

  final String chatId;

  @override
  State<_ChatInfoSheet> createState() => _ChatInfoSheetState();
}

class _ChatInfoSheetState extends State<_ChatInfoSheet> {
  bool _busy = false;

  Future<void> _addMembers(BuildContext context) async {
    final session = context.read<Session>();
    final controller = TextEditingController();
    List<User> results = [];
    final selected = <String>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> search(String value) async {
            if (value.trim().length < 2) {
              setDialogState(() => results = []);
              return;
            }
            try {
              final rows = await session.api.searchUsers(value.trim());
              setDialogState(() => results = rows.map(User.fromJson).toList());
            } catch (_) {}
          }

          return AlertDialog(
            title: const Text('إضافة أعضاء'),
            content: SizedBox(
              width: 360,
              height: 380,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    onChanged: search,
                    decoration: const InputDecoration(hintText: 'ابحث باسم المستخدم…'),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final user = results[index];
                        return CheckboxListTile(
                          value: selected.contains(user.username),
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                selected.add(user.username);
                              } else {
                                selected.remove(user.username);
                              }
                            });
                          },
                          title: Text(user.displayName),
                          subtitle: Text('@${user.username}', textDirection: TextDirection.ltr),
                          secondary: Avatar(name: user.displayName, color: user.avatarColor, imageUrl: user.avatarUrl, size: 38),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(dialogContext);
                        setState(() => _busy = true);
                        try {
                          await session.addMembers(widget.chatId, selected.toList());
                        } catch (e) {
                          if (mounted) showError(context, e);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('إضافة'),
              ),
            ],
          );
        },
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final chat = session.chats[widget.chatId];
    final scheme = Theme.of(context).colorScheme;
    if (chat == null) return const SizedBox.shrink();
    final peer = chat.isGroup ? null : chat.peerFor(session.me?.id ?? '');

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Avatar(
                  name: chat.title,
                  color: chat.avatarColor,
                  imageUrl: peer?.avatarUrl,
                  size: 76,
                  icon: chat.isGroup ? Icons.groups_rounded : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                chat.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                chat.isGroup ? '${chat.members.length} أعضاء · جيل التشفير ${chat.epoch}' : 'محادثة فردية مشفّرة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              if (chat.isGroup) ...[
                Text('الأعضاء', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...chat.members.map(
                  (member) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Avatar(
                      name: member.displayName,
                      color: member.avatarColor,
                      imageUrl: member.avatarUrl,
                      size: 40,
                      online: member.online,
                    ),
                    title: Text(member.displayName),
                    subtitle: Text(userHandle(phone: member.phone, username: member.username), textDirection: TextDirection.ltr),
                    trailing: member.id == chat.createdBy
                        ? const Chip(label: Text('منشئ', style: TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact)
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _addMembers(context),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('إضافة أعضاء'),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _busy ? null : () => _leave(context),
                  icon: Icon(Icons.logout_rounded, color: scheme.error),
                  label: Text('مغادرة المجموعة', style: TextStyle(color: scheme.error)),
                ),
              ] else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_rounded, size: 14, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'التشفير من الطرف إلى الطرف مُفعّل',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
