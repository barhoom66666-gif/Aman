import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../widgets/server_dialog.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.registerMode});

  final bool registerMode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();

  late bool _register = widget.registerMode;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final session = context.read<Session>();
    try {
      if (_register) {
        await session.register(
          username: _username.text.trim().toLowerCase(),
          password: _password.text,
          displayName: _displayName.text.trim(),
        );
      } else {
        await session.login(
          username: _username.text.trim().toLowerCase(),
          password: _password.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, 'تعذّر إكمال العملية: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = context.watch<Session>();

    return Scaffold(
      appBar: AppBar(title: Text(_register ? 'حساب جديد' : 'تسجيل الدخول')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(child: AmanLogo(size: 64)),
                const SizedBox(height: 22),
                Text(
                  _register ? 'انضم إلى Aman' : 'أهلًا بعودتك',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  _register
                      ? 'اسم مستخدم قصير، وكلمة مرور قوية. مفتاحك الخاص يبقى على جهازك.'
                      : 'أدخل بيانات حسابك للمتابعة.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                ),
                const SizedBox(height: 26),
                if (_register) ...[
                  TextFormField(
                    controller: _displayName,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'الاسم الظاهر',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.length < 2) return 'أدخل اسمًا لا يقل عن حرفين';
                      if (value.length > 40) return 'الاسم طويل جدًا';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _username,
                  textInputAction: TextInputAction.next,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    prefixText: '@ ',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim().toLowerCase();
                    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(value)) {
                      return '3-20 حرفًا: حروف لاتينية صغيرة أو أرقام أو _';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _loading ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    ),
                  ),
                  validator: (v) {
                    if ((v ?? '').length < 8) return 'كلمة المرور 8 أحرف على الأقل';
                    return null;
                  },
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(_register ? 'إنشاء الحساب' : 'دخول'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _register = !_register;
                          }),
                  child: Text(_register ? 'لديّ حساب — تسجيل الدخول' : 'ليس لديّ حساب — إنشاء حساب'),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () => showServerDialog(context),
                    icon: const Icon(Icons.dns_outlined, size: 18),
                    label: Text(
                      session.serverUrl.replaceFirst(RegExp('^https?://'), ''),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
