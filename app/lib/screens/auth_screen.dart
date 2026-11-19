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
  final _identifier = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();

  late bool _register = widget.registerMode;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identifier.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  static String _phoneDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final session = context.read<Session>();
    try {
      if (_register) {
        await session.register(
          phone: _phoneDigits(_identifier.text),
          password: _password.text,
          displayName: _displayName.text.trim(),
        );
      } else {
        await session.login(
          identifier: _identifier.text.trim(),
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
                      ? 'رقم هاتفك هو هويتك في Aman. مفتاحك الخاص يبقى على جهازك.'
                      : 'أدخل رقم هاتفك وكلمة المرور للمتابعة.',
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
                  controller: _identifier,
                  textInputAction: TextInputAction.next,
                  textDirection: TextDirection.ltr,
                  keyboardType: _register ? TextInputType.phone : TextInputType.text,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: _register ? 'رقم الهاتف' : 'رقم الهاتف أو اسم المستخدم',
                    hintText: _register ? '+971 50 123 4567' : null,
                    prefixIcon: Icon(_register ? Icons.phone_iphone_rounded : Icons.person_outline),
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return 'أدخل رقم هاتفك';
                    if (_register) {
                      final digits = _phoneDigits(value);
                      if (digits.length < 7 || digits.length > 15) {
                        return 'رقم غير صحيح — أدخله مع رمز الدولة (7 إلى 15 رقمًا)';
                      }
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
                    final value = v ?? '';
                    if (_register && value.length < 8) return 'كلمة المرور 8 أحرف على الأقل';
                    if (!_register && value.isEmpty) return 'أدخل كلمة المرور';
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
