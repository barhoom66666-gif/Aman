import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session();
  runApp(ChangeNotifierProvider<Session>.value(value: session, child: const NajwaApp()));
  session.init();
}
