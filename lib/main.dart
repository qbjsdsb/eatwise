import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/error/sentry_init.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSentry();
  runApp(const ProviderScope(child: EatWiseApp()));
}
