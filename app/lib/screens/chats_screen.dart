import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../models.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import 'qr_screen.dart';
import 'settings_screen.dart';
import 'tools_screens.dart';

enum _ChatFilter { all, unread, groups }

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _search = TextEditingController();
  _ChatFilter _filter = _ChatFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Chat> _visible(Session session) {
    final query = _search.text.trim().toLowerCase();
    final list = session.chatList.where((chat) {
      if (_filter == _ChatFilter.unread && chat.unreadCount == 0) return false;
      if (_filter == _ChatFilter.groups && !chat.isGroup) return false;
      if (query.isEmpty) return true;
      if (chat.title.toLowerCase().contains(query)) return true;
      final last = chat.lastMessage?.text?.toLowerCase() ?? '';
      return last.contains(query);
    }).toList();

    list.sort((a, b) {
      final pinnedA = session.isPinned(a.id);
      final pinnedB = session.isPinned(b.id);
      if (pinnedA != pinnedB) return pinnedA ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  void _open(Chat chat) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
    );
  }

  Future<void> _scanQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (raw == null || !mounted) return;
    final username = usernameFromQr(raw);
    if (username == null) {
      showError(context, 'باركود غير صالح — تأكد أنه باركود Aman');
      return;
    }
    final session = context.read<Session>();
    try {
      final chat = await session.openDirect(username);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
      );
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  void _showTopMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBg = isDark ? const Color(0xFF1F2330) : Theme.of(context).colorScheme.surface;
    showMenu<String>(
      context: context,
      color: menuBg,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      position: const RelativeRect.fromLTRB(16, 88, 120, 0),
      items: const [
        PopupMenuItem(
          value: 'secret_chat',
          child: _PopupRow(icon: Icons.maps_ugc_outlined, label: 'محادثة سرية جديدة'),
        ),
        PopupMenuItem(
          value: 'new_group',
          child: _PopupRow(icon: Icons.group_add_outlined, label: 'مجموعة جديدة'),
        ),
        PopupMenuItem(
          value: 'add_friends',
          child: _PopupRow(icon: Icons.person_add_alt_1_outlined, label: 'إضافة أصدقاء'),
        ),
        PopupMenuItem(
          value: 'broadcast',
          child: _PopupRow(icon: Icons.campaign_outlined, label: 'قوائم البث'),
        ),
        PopupMenuItem(
          value: 'starred',
          child: _PopupRow(icon: Icons.star_border_rounded, label: 'المميزة بنجمة'),
        ),
        PopupMenuItem(
          value: 'calendar',
          child: _PopupRow(icon: Icons.calendar_today_outlined, label: 'تقويم'),
        ),
        PopupMenuItem(
          value: 'notes',
          child: _PopupRow(icon: Icons.menu_book_outlined, label: 'ملحوظات'),
        ),
        PopupMenuItem(
          value: 'scan',
          child: _PopupRow(icon: Icons.qr_code_scanner_rounded, label: 'مسح ذكي'),
        ),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      switch (value) {
        case 'secret_chat':
        case 'add_friends':
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewChatScreen(initialTab: 0)),
          );
          break;
        case 'new_group':
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewChatScreen(initialTab: 1)),
          );
          break;
        case 'broadcast':
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BroadcastListsScreen()),
          );
          break;
        case 'starred':
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StarredMessagesScreen()),
          );
          break;
        case 'calendar':
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CalendarScreen()),
          );
          break;
        case 'notes':
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NotesScreen()),
          );
          break;
        case 'scan':
          _scanQr();
          break;
      }
    });
  }

  void _chatMenu(Chat chat, Session session) {
    final pinned = session.isPinned(chat.id);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
              title: Text(pinned ? 'إلغاء تثبيت المحادثة' : 'تثبيت المحادثة'),
              onTap: () {
                Navigator.pop(sheetContext);
                session.togglePin(chat.id);
              },
            ),
            if (chat.unreadCount > 0)
              ListTile(
                leading: const Icon(Icons.mark_chat_read_outlined),
                title: const Text('تحديد كمقروءة'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  session.markRead(chat.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('فتح المحادثة'),
              onTap: () {
                Navigator.pop(sheetContext);
                _open(chat);
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
    final all = session.chatList;
    final chats = _visible(session);
    final me = session.me;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // شريط علوي مطابق لتصميم JERNAS: الاسم على اليمين، وأيقونات التقويم والملاحظات والقائمة على اليسار
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 18, 4),
              child: Row(
                children: [
                  Text(
                    'AMAN',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: isDark ? AppTheme.brandText : scheme.primary,
                    ),
                  ),
                  const Spacer(),
                  if (session.showCalendarInHeader)
                    IconButton(
                      tooltip: 'تقويم',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CalendarScreen()),
                      ),
                      icon: Icon(
                        Icons.calendar_today_outlined,
                        size: 24,
                        color: scheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  if (session.showNotesInHeader)
                    IconButton(
                      tooltip: 'ملحوظات',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NotesScreen()),
                      ),
                      icon: Icon(
                        Icons.menu_book_outlined,
                        size: 24,
                        color: scheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  IconButton(
                    tooltip: 'القائمة',
                    onPressed: _showTopMenu,
                    icon: Icon(
                      Icons.pending_outlined,
                      size: 27,
                      color: scheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            if ((me?.phone ?? '').isEmpty)
              Material(
                color: scheme.primaryContainer.withValues(alpha: 0.45),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                    child: Row(
                      children: [
                        Icon(Icons.phone_iphone_rounded, size: 18, color: scheme.primary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'أضف رقم هاتفك ليتمكن الآخرون من إيجادك والبحث عنك',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        Icon(Icons.chevron_left_rounded, size: 18, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
            if (session.connectionError != null)
              Container(
                width: double.infinity,
                color: scheme.errorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  session.connectionError!,
                  style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
                ),
              ),
            // شريط البحث الدائري
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'بحث',
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
                    prefixIcon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant, size: 22),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                  ),
                ),
              ),
            ),
            // فلاتر المحادثات بأسلوب JERNAS: الجميع | غير مقروءة | المجموعات
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  _JernasFilterPill(
                    label: 'الجميع',
                    selected: _filter == _ChatFilter.all,
                    onTap: () => setState(() => _filter = _ChatFilter.all),
                  ),
                  const SizedBox(width: 10),
                  _JernasFilterPill(
                    label: 'غير مقروءة',
                    selected: _filter == _ChatFilter.unread,
                    onTap: () => setState(() => _filter = _ChatFilter.unread),
                  ),
                  const SizedBox(width: 10),
                  _JernasFilterPill(
                    label: 'المجموعات',
                    selected: _filter == _ChatFilter.groups,
                    onTap: () => setState(() => _filter = _ChatFilter.groups),
                  ),
                ],
              ),
            ),
            Expanded(
              child: all.isEmpty
                  ? EmptyState(
                      icon: Icons.forum_outlined,
                      title: 'لا محادثات بعد',
                      subtitle:
                          'اضغط على القائمة (•••) في الأعلى لبدء محادثة سرية جديدة أو إنشاء مجموعة مشفّرة.',
                      action: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const NewChatScreen()),
                        ),
                        icon: const Icon(Icons.add_comment_outlined),
                        label: const Text('محادثة سرية جديدة'),
                      ),
                    )
                  : chats.isEmpty
                      ? EmptyState(
                          icon: _filter == _ChatFilter.unread
                              ? Icons.mark_chat_read_outlined
                              : _filter == _ChatFilter.groups
                                  ? Icons.groups_outlined
                                  : Icons.search_off_rounded,
                          title: 'لا نتائج',
                          subtitle: _search.text.trim().isEmpty
                              ? 'لا توجد محادثات في هذا التصنيف.'
                              : 'لا توجد محادثة تطابق «${_search.text.trim()}».',
                        )
                      : RefreshIndicator(
                          onRefresh: session.refreshChats,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(top: 4, bottom: 24),
                            itemCount: chats.length,
                            itemBuilder: (context, index) {
                              final chat = chats[index];
                              return _ChatTile(
                                chat: chat,
                                session: session,
                                pinned: session.isPinned(chat.id),
                                onTap: () => _open(chat),
                                onLongPress: () => _chatMenu(chat, session),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopupRow extends StatelessWidget {
  const _PopupRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 22, color: scheme.onSurface),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JernasFilterPill extends StatelessWidget {
  const _JernasFilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bg = selected
        ? (isDark ? const Color(0xFF282F66) : scheme.primaryContainer)
        : (isDark ? const Color(0xFF1F2330) : scheme.surfaceContainerHighest.withValues(alpha: 0.6));
    final fg = selected
        ? (isDark ? const Color(0xFF6B7BFF) : scheme.primary)
        : scheme.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.session,
    required this.pinned,
    required this.onTap,
    required this.onLongPress,
  });

  final Chat chat;
  final Session session;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  String _preview() {
    final message = chat.lastMessage;
    if (message == null || message.isAdminNotice) {
      return 'تغيير مؤقت التدمير الذاتي';
    }
    String body;
    if (message.undecryptable) {
      body = 'تغيير مؤقت التدمير الذاتي';
    } else if (message.isMedia) {
      body = (message.media?.isImage ?? true) ? '[صورة]' : '[ملف]';
    } else {
      body = message.text ?? '';
    }
    if (chat.isGroup && message.senderId != session.me?.id) {
      final sender = chat.memberById(message.senderId)?.displayName;
      return sender == null ? body : '$sender: $body';
    }
    return body;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peer = chat.isGroup ? null : chat.peerFor(session.me?.id ?? '');
    final online = peer?.online ?? false;
    final hasUnread = chat.unreadCount > 0;
    final lastMsg = chat.lastMessage;
    final isMine = lastMsg != null && lastMsg.senderId == session.me?.id;
    final readByPeer = !chat.isGroup &&
        peer != null &&
        lastMsg != null &&
        peer.lastReadAt >= lastMsg.createdAt &&
        !lastMsg.pending;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      leading: Avatar(
        name: chat.title,
        color: chat.avatarColor,
        imageUrl: peer?.avatarUrl,
        size: 58,
        online: online,
        icon: chat.isGroup ? Icons.groups_rounded : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16.5),
                  ),
                ),
                if (pinned) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.push_pin_rounded, size: 13, color: scheme.primary),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            chat.updatedAt > 0 ? formatChatTime(chat.updatedAt) : '',
            style: TextStyle(
              fontSize: 12.5,
              color: hasUnread ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(
          children: [
            if (isMine) ...[
              Icon(
                lastMsg.pending
                    ? Icons.schedule_rounded
                    : readByPeer
                        ? Icons.done_all_rounded
                        : Icons.done_rounded,
                size: 16,
                color: readByPeer ? AppTheme.readGreen : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
            ],
            if (chat.lastMessage?.isMedia ?? false) ...[
              Icon(Icons.attach_file_rounded, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 3),
            ],
            Expanded(
              child: Text(
                _preview(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: hasUnread ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (hasUnread) ...[
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 21),
                height: 21,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
