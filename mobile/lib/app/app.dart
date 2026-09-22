import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/app/router/app_router.dart';
import 'package:nadr_mobile/app/theme/nadr_theme.dart';

class NadrApp extends ConsumerWidget {
  const NadrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'NADR',
      debugShowCheckedModeBanner: false,
      theme: NadrTheme.light,
      darkTheme: NadrTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
