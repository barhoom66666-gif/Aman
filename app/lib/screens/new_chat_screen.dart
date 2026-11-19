import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../models.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'qr_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('محادثة جديدة'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'محادثة فردية'),
            Tab(text: 'مجموعة'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _DirectTab(),
          _GroupTab(),
        ],
      ),
    );
  }
}

class _DirectTab extends StatefulWidget {
  const _DirectTab();

  @override
  State<_DirectTab> createState() => _DirectTabState();
}

class _DirectTabState extends State<_DirectTab> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<User> _results = const [];
  bool _loading = false;
  String? _opening;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      try {
        final api = context.read<Session>().api;
        final rows = await api.searchUsers(query.trim());
        if (mounted) setState(() => _results = rows.map(User.fromJson).toList());
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<void> _open(User user) => _openUsername(user.username);

  Future<void> _openUsername(String username) async {
    setState(() => _opening = username);
    final session = context.read<Session>();
    try {
      final chat = await session.openDirect(username);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
      );
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (raw == null || !mounted) return;
    final username = usernameFromQr(raw);
    if (username == null) {
      showError(context, 'باركود غير صالح — تأكد أنه باركود Aman');
      return;
    }
    await _openUsername(username);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'ابحث برقم الهاتف أو الاسم…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                tooltip: 'مسح باركود',
              ),
            ],
          ),
        ),
        Expanded(
          child: _results.isEmpty
              ? const EmptyState(
                  icon: Icons.person_search_outlined,
                  title: 'ابحث عن شخص',
                  subtitle: 'اكتب رقم هاتفه مع رمز الدولة أو اسمه، أو امسح باركوده. '
                      'لا يظهر هنا إلا من أنشأ حسابًا على نفس الخادم.',
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final user = _results[index];
                    return ListTile(
                      leading: Avatar(
                        name: user.displayName,
                        color: user.avatarColor,
                        size: 46,
                        online: user.online,
                      ),
                      title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        userHandle(phone: user.phone, username: user.username),
                        textDirection: TextDirection.ltr,
                      ),
                      trailing: _opening == user.username
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                      onTap: () => _open(user),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _GroupTab extends StatefulWidget {
  const _GroupTab();

  @override
  State<_GroupTab> createState() => _GroupTabState();
}

class _GroupTabState extends State<_GroupTab> {
  final _title = TextEditingController();
  final _search = TextEditingController();
  final Map<String, User> _selected = {};
  Timer? _debounce;
  List<User> _results = const [];
  bool _loading = false;
  bool _creating = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _search.dispose();
    super.dispose();
  }

  void _runSearch(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      try {
        final rows = await context.read<Session>().api.searchUsers(query.trim());
        if (mounted) setState(() => _results = rows.map(User.fromJson).toList());
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty || _selected.isEmpty) return;
    setState(() => _creating = true);
    final session = context.read<Session>();
    try {
      final chat = await session.createGroup(title, _selected.keys.toList());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
      );
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: TextField(
            controller: _title,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'اسم المجموعة',
              prefixIcon: Icon(Icons.groups_outlined),
            ),
          ),
        ),
        if (_selected.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selected.values
                  .map(
                    (user) => Chip(
                      label: Text(user.displayName),
                      onDeleted: () => setState(() => _selected.remove(user.username)),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _runSearch,
            decoration: InputDecoration(
              hintText: 'أضف عضوًا برقم الهاتف أو الاسم…',
              prefixIcon: const Icon(Icons.person_add_alt_1_outlined),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: _results.isEmpty
              ? const EmptyState(
                  icon: Icons.group_add_outlined,
                  title: 'أنشئ مجموعة',
                  subtitle: 'اختر اسمًا للمجموعة، ثم ابحث برقم الهاتف أو الاسم وأضف الأعضاء. '
                      'لا تحتاج إلى إضافتهم إلى جهات الاتصال أولًا.',
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final user = _results[index];
                    final selected = _selected.containsKey(user.username);
                    return ListTile(
                      leading: Avatar(name: user.displayName, color: user.avatarColor, size: 44),
                      title: Text(user.displayName),
                      subtitle: Text(
                        userHandle(phone: user.phone, username: user.username),
                        textDirection: TextDirection.ltr,
                      ),
                      trailing: Checkbox(
                        value: selected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selected[user.username] = user;
                            } else {
                              _selected.remove(user.username);
                            }
                          });
                        },
                      ),
                      onTap: () {
                        setState(() {
                          if (selected) {
                            _selected.remove(user.username);
                          } else {
                            _selected[user.username] = user;
                          }
                        });
                      },
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'عدد الأعضاء المختارين: ${_selected.length}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: (_creating || _selected.isEmpty || _title.text.trim().isEmpty) ? null : _create,
                  icon: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: const Text('إنشاء المجموعة'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
