import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../models.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// شاشة الملحوظات (تُفتح من أيقونة الدفتر أعلى الصفحة الرئيسية أو قائمة الثلاث نقاط).
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  Future<void> _addNote(BuildContext context, Session session) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ملحوظة جديدة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'اكتب ملحوظتك هنا…'),
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
    if (text != null && text.isNotEmpty) {
      session.personalNotes.insert(0, {
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'text': text,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      await session.savePrefs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final notes = session.personalNotes;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ملحوظات'),
        actions: [
          IconButton(
            onPressed: () => _addNote(context, session),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'إضافة ملحوظة',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addNote(context, session),
        child: const Icon(Icons.note_add_outlined),
      ),
      body: notes.isEmpty
          ? EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'لا توجد ملحوظات بعد',
              subtitle: 'احفظ ملاحظاتك الخاصة المشفّرة محليًا على جهازك.',
              action: FilledButton.icon(
                onPressed: () => _addNote(context, session),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة ملحوظة'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final note = notes[index];
                final createdAt = (note['createdAt'] as num?)?.toInt() ?? 0;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${note['text'] ?? ''}',
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            createdAt > 0 ? formatChatTime(createdAt) : '',
                            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                          ),
                          const Spacer(),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error),
                            onPressed: () async {
                              session.personalNotes.removeAt(index);
                              await session.savePrefs();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// شاشة التقويم (تُفتح من أيقونة التقويم أعلى الصفحة الرئيسية أو قائمة الثلاث نقاط).
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();

  Future<void> _addEvent(Session session) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة موعد في التقويم'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'عنوان الموعد أو التذكير…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) {
      session.calendarEvents.insert(0, {
        'title': title,
        'date': _selectedDate.millisecondsSinceEpoch,
      });
      await session.savePrefs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final scheme = Theme.of(context).colorScheme;
    final events = session.calendarEvents;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تقويم'),
        actions: [
          IconButton(
            onPressed: () => _addEvent(session),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addEvent(session),
        child: const Icon(Icons.event_available_outlined),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(18),
            ),
            child: CalendarDatePicker(
              initialDate: _selectedDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
              onDateChanged: (date) => setState(() => _selectedDate = date),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'المواعيد والتذكيرات (${events.length})',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'لا توجد إدخالات في التقويم بعد.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else
            ...events.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final millis = (item['date'] as num?)?.toInt() ?? 0;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                child: ListTile(
                  leading: Icon(Icons.event_note_outlined, color: scheme.primary),
                  title: Text('${item['title'] ?? ''}'),
                  subtitle: Text(millis > 0 ? formatDaySeparator(millis) : ''),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error),
                    onPressed: () async {
                      session.calendarEvents.removeAt(idx);
                      await session.savePrefs();
                    },
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// شاشة الرسائل المميزة بنجمة (تُفتح من قائمة الثلاث نقاط أو من معلومات المحادثة).
class StarredMessagesScreen extends StatelessWidget {
  const StarredMessagesScreen({super.key, this.chatId});

  final String? chatId;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final List<Message> messages =
        chatId != null ? session.starredMessagesIn(chatId!) : session.allStarredMessages;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('المميزة بنجمة')),
      body: messages.isEmpty
          ? const EmptyState(
              icon: Icons.star_border_rounded,
              title: 'لا توجد رسائل مميزة بنجمة',
              subtitle: 'اضغط مطولًا على أي رسالة داخل المحادثة لتمييزها بنجمة والرجوع إليها بسهولة.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final msg = messages[index];
                final chat = session.chats[msg.chatId];
                return ListTile(
                  leading: Icon(Icons.star_rounded, color: scheme.primary),
                  title: Text(
                    msg.text ?? (msg.isMedia ? 'ملف وسائط' : 'رسالة مشفّرة'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${chat?.title ?? 'محادثة'} · ${formatChatTime(msg.createdAt)}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  onTap: chat == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
                          ),
                );
              },
            ),
    );
  }
}

/// شاشة قوائم البث (تُفتح من قائمة الثلاث نقاط).
class BroadcastListsScreen extends StatelessWidget {
  const BroadcastListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final chats = session.chatList.where((c) => !c.isGroup).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('قوائم البث')),
      body: chats.isEmpty
          ? const EmptyState(
              icon: Icons.campaign_outlined,
              title: 'لا توجد قوائم بث',
              subtitle: 'أرسل رسالة مشفّرة لعدة جهات اتصال في آن واحد عبر قوائم البث.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'اختر محادثة لإرسال رسالة بث مشفّرة:',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ...chats.map(
                  (chat) => ListTile(
                    leading: const Icon(Icons.campaign_outlined),
                    title: Text(chat.title),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
