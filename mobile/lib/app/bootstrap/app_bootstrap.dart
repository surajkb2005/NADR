import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/app/app.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';

Future<void> bootstrap({AppEnvironment? environment}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final resolvedEnvironment = environment ?? AppEnvironment.fromDartDefines();

  runApp(
    ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(resolvedEnvironment),
      ],
      child: const NadrApp(),
    ),
  );
}
