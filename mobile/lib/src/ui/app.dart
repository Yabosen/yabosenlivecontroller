import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'theme.dart';

class YabosenControllerApp extends StatelessWidget {
  const YabosenControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = buildAppTheme();
    return MaterialApp(
      title: 'Yabosen Controller',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
