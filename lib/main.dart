import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/home_screen.dart';

void main() => runApp(const ProviderScope(child: FollowMzApp()));

class FollowMzApp extends StatelessWidget {
  const FollowMzApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Follow MZ', debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: _theme(Brightness.light), darkTheme: _theme(Brightness.dark),
    home: const HomeScreen(),
  );

  ThemeData _theme(Brightness brightness) => ThemeData(
    useMaterial3: true, brightness: brightness,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6554C0), brightness: brightness),
    scaffoldBackgroundColor: brightness == Brightness.light
      ? const Color(0xFFF8F7FC) : const Color(0xFF14121B),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}
