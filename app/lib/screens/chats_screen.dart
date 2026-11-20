import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../models.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import 'settings_screen.dart';

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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Avatar(
              name: me?.displayName ?? 'مستخدم',
              color: me?.avatarColor ?? '#0E9F9A',
              imageUrl: me?.avatarUrl,
              size: 38,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aman'),
                Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 11, color: scheme.primary),
                    const SizedBox(width: 3),
                    Text(
                      session.connected ? 'متصل ومشفّر' : 'جارٍ الاتصال…',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NewChatScreen()),
        ),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('محادثة جديدة'),
      ),
      body: Column(
        children: [
          if ((me?.phone ?? '').isEmpty)
            Material(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'بحث في المحادثات…',
                prefixIcon: const Icon(Icons.search),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: [
                _FilterChip(
                  label: 'الكل',
                  selected: _filter == _ChatFilter.all,
                  onTap: () => setState(() => _filter = _ChatFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'غير مقروءة',
                  selected: _filter == _ChatFilter.unread,
                  onTap: () => setState(() => _filter = _ChatFilter.unread),
                ),
                const SizedBox(width: 8),
                _FilterChip(
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
                    subtitle: 'ابحث برقم الهاتف أو الاسم وابدأ محادثة مشفّرة، أو أنشئ مجموعة — حتى بدون إضافة جهات اتصال.',
                    action: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NewChatScreen()),
                      ),
                      icon: const Icon(Icons.add_comment_outlined),
                      label: const Text('ابدأ الآن'),
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
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: chats.length,
                          separatorBuilder: (_, __) => const Divider(indent: 84, endIndent: 16),
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
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
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
    if (message == null) {
      return chat.isGroup ? 'مجموعة جديدة' : 'ابدأ المحادثة';
    }
    String body;
    if (message.undecryptable) {
      body = 'رسالة غير متاحة على هذا الجهاز';
    } else if (message.isMedia) {
      body = (message.media?.isImage ?? true) ? 'صورة' : 'ملف';
    } else {
      body = message.text ?? '';
    }
    final mine = message.senderId == session.me?.id;
    if (mine) return 'أنت: $body';
    if (chat.isGroup) {
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

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: Avatar(
        name: chat.title,
        color: chat.avatarColor,
        imageUrl: peer?.avatarUrl,
        size: 52,
        online: online,
        icon: chat.isGroup ? Icons.groups_rounded : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.lock_rounded, size: 11, color: scheme.onSurfaceVariant),
                if (pinned) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.push_pin_rounded, size: 12, color: scheme.primary),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            chat.updatedAt > 0 ? formatChatTime(chat.updatedAt) : '',
            style: TextStyle(
              fontSize: 11.5,
              color: hasUnread ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            if (chat.lastMessage?.isMedia ?? false) ...[
              Icon(Icons.attach_file_rounded, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 2),
            ],
            Expanded(
              child: Text(
                _preview(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
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
