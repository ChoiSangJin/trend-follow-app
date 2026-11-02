import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/briefing_store.dart';
import 'state/briefing_provider.dart';
import 'ui/netflix_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BriefingStore store;
  try {
    store = PreferencesStore(await SharedPreferences.getInstance());
  } catch (_) {
    store = MemoryStore();
  }
  runApp(
    ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const MalmunApp(),
    ),
  );
}

class MalmunApp extends StatelessWidget {
  const MalmunApp({super.key, this.home});
  final Widget? home;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '말문',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: home ?? const NetflixHomeScreen(),
  );
  ThemeData _theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFB32638),
      brightness: brightness,
    ),
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF9F7F1)
        : const Color(0xFF121C1A),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}
