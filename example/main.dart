import 'package:flutter/material.dart';
import 'package:morphui/morphui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MorphProvider(
      licenseKey: 'morph-free-demo',
      baseTheme: ThemeData.light(),
      child: Builder(
        builder: (ctx) {
          final mode = ctx.maybeMorph?.theme.mode ?? ThemeMode.system;
          final generated = ctx.maybeMorph?.theme.generated;
          return MaterialApp(
            title: 'Morph demo',
            themeMode: mode,
            theme: generated != null && generated.brightness == 'light'
                ? ThemeData.light().copyWith(colorScheme: generated.toColorScheme())
                : ThemeData.light(),
            darkTheme: generated != null && generated.brightness == 'dark'
                ? ThemeData.dark().copyWith(colorScheme: generated.toColorScheme())
                : ThemeData.dark(),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Morph SDK')),
      body: const MorphReorderableColumn(
        zones: [
          MorphZone(
            id: 'hero',
            type: MorphZoneType.section,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Hero — auto-reordered when users prefer it'),
              ),
            ),
          ),
          MorphZone(
            id: 'cta',
            type: MorphZoneType.card,
            child: Card(
              child: ListTile(title: Text('Tap me')),
            ),
          ),
        ],
      ),
    );
  }
}
