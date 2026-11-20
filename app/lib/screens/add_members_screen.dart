import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../models.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';

Future<bool?> showAddMembersSheet(BuildContext context, String chatId) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AddMembersSheet(chatId: chatId),
  );
}

class AddMembersSheet extends StatefulWidget {
  const AddMembersSheet({super.key, required this.chatId});

  final String chatId;

  @override
  State<AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<AddMembersSheet> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<User> _users = const [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _saving = false;
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
      final chat = context.read<Session>().chats[widget.chatId];
      final existing = chat?.members.map((m) => m.id).toSet() ?? <String>{};
      setState(() {
        _users = rows
            .map(User.fromJson)
            .where((user) => !existing.contains(user.id))
            .toList();
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

  Future<void> _save() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await context.read<Session>().addMembers(widget.chatId, _selected.toList());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'إضافة أعضاء',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اختر شخصًا أو أكثر — سيحصلون على مفتاح المجموعة الجديد.',
                            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: _onChanged,
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ),
              Expanded(
                child: _loading && _users.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _users.isEmpty
                        ? const EmptyState(
                            icon: Icons.person_search_outlined,
                            title: 'لا يوجد من يمكن إضافته',
                            subtitle: 'كل من أنشأ حسابًا على نفس الخادم يظهر هنا. '
                                'جرّب البحث برقم الهاتف أو الاسم.',
                          )
                        : ListView.builder(
                            itemCount: _users.length,
                            itemBuilder: (context, index) {
                              final user = _users[index];
                              final checked = _selected.contains(user.username);
                              return CheckboxListTile(
                                value: checked,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selected.add(user.username);
                                    } else {
                                      _selected.remove(user.username);
                                    }
                                  });
                                },
                                secondary: Avatar(
                                  name: user.displayName,
                                  color: user.avatarColor,
                                  imageUrl: user.avatarUrl,
                                  size: 42,
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
                              );
                            },
                          ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selected.isEmpty || _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(
                      _selected.isEmpty ? 'اختر أعضاء' : 'إضافة (${_selected.length})',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
