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

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<User> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await context.read<Session>().api.searchUsers(query.trim());
      if (!mounted) return;
      setState(() {
        _users = rows.map(User.fromJson).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(value));
  }

  Future<void> _open(User user) async {
    final session = context.read<Session>();
    try {
      final chat = await session.openDirect(user.username);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
      );
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('جهات الاتصال'),
        actions: [
          IconButton(
            tooltip: 'مسح باركود',
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'ابحث برقم الهاتف أو الاسم…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(_search.text),
              child: _users.isEmpty && !_loading
                  ? ListView(
                      children: const [
                        SizedBox(height: 70),
                        EmptyState(
                          icon: Icons.contacts_outlined,
                          title: 'لا جهات اتصال بعد',
                          subtitle: 'كل من ينشئ حسابًا على نفس الخادم يظهر هنا. '
                              'ابحث برقم الهاتف أو الاسم، أو امسح باركود صديقك.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const Divider(indent: 76, endIndent: 16),
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return ListTile(
                          leading: Avatar(
                            name: user.displayName,
                            color: user.avatarColor,
                            imageUrl: user.avatarUrl,
                            size: 48,
                            online: user.online,
                          ),
                          title: Text(
                            user.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            userHandle(phone: user.phone, username: user.username),
                            textDirection: TextDirection.ltr,
                          ),
                          trailing: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                          onTap: () => _open(user),
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
