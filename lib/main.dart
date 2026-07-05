import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/router/router.dart';
import 'package:formtract/core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: FormtractApp()));
}

class FormtractApp extends ConsumerWidget {
  const FormtractApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Formtract',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
