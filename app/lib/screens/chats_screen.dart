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

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final chats = session.chatList;
    final me = session.me;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Avatar(
              name: me?.displayName ?? 'مستخدم',
              color: me?.avatarColor ?? '#0E9F9A',
              size: 38,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aman'),
                Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 11, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 3),
                    Text(
                      session.connected ? 'متصل ومشفّر' : 'جارٍ الاتصال…',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                  child: Row(
                    children: [
                      Icon(Icons.phone_iphone_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'أضف رقم هاتفك ليتمكن الآخرون من إيجادك والبحث عنك',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      Icon(Icons.chevron_left_rounded, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          if (session.connectionError != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                session.connectionError!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          Expanded(
            child: chats.isEmpty
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
                : RefreshIndicator(
                    onRefresh: session.refreshChats,
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: chats.length,
                      separatorBuilder: (_, __) => const Divider(indent: 84, endIndent: 16),
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        return _ChatTile(chat: chat, session: session);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.session});

  final Chat chat;
  final Session session;

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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
      ),
      leading: Avatar(
        name: chat.title,
        color: chat.avatarColor,
        size: 52,
        online: online,
        icon: chat.isGroup ? Icons.groups_rounded : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              chat.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
