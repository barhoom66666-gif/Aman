import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../models.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';

class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  void _showCallNotice(BuildContext context, Chat chat, {required bool video}) {
    final session = context.read<Session>();
    final peer = chat.isGroup ? null : chat.peerFor(session.me?.id ?? '');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Avatar(
                  name: chat.title,
                  color: chat.avatarColor,
                  imageUrl: peer?.avatarUrl,
                  size: 72,
                  icon: chat.isGroup ? Icons.groups_rounded : null,
                ),
                const SizedBox(height: 12),
                Text(
                  chat.title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  video ? 'مكالمة فيديو مشفّرة' : 'مكالمة صوتية مشفّرة',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('فتح المحادثة المشفّرة'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final chats = session.chatList;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('المكالمات', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'مكالمة جديدة',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NewChatScreen()),
            ),
            icon: const Icon(Icons.add_ic_call_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: chats.isEmpty
          ? EmptyState(
              icon: Icons.call_outlined,
              title: 'لا توجد مكالمات حديثة',
              subtitle: 'ستظهر سجلات المكالمات مع جهات اتصالك ومجموعاتك هنا.',
              action: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NewChatScreen()),
                ),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('بدء تواصل جديد'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(top: 6, bottom: 28),
              itemCount: chats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                final chat = chats[index];
                final peer = chat.isGroup ? null : chat.peerFor(session.me?.id ?? '');
                final missed = index.isOdd;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Avatar(
                    name: chat.title,
                    color: chat.avatarColor,
                    imageUrl: peer?.avatarUrl,
                    size: 54,
                    icon: chat.isGroup ? Icons.groups_rounded : null,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: missed ? scheme.error : scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.lock_outline_rounded, size: 15, color: scheme.onSurfaceVariant),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          missed ? Icons.phone_missed_rounded : Icons.phone_callback_rounded,
                          size: 15,
                          color: missed ? scheme.error : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '[مكالمة] · ${chat.updatedAt > 0 ? formatChatTime(chat.updatedAt) : 'اليوم'}',
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  trailing: IconButton(
                    onPressed: () => _showCallNotice(context, chat, video: false),
                    icon: Icon(Icons.call_outlined, color: scheme.primary),
                  ),
                  onTap: () => _showCallNotice(context, chat, video: false),
                );
              },
            ),
    );
  }
}
