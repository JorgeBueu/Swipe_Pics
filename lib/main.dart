import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SwipePicsApp());
}

class SwipePicsApp extends StatelessWidget {
  const SwipePicsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swipe Pics',
      debugShowCheckedModeBanner: false,
      theme: _buildDarkTheme(),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF7C4DFF),
      scaffoldBackgroundColor: const Color(0xFF0D0D0D),
    );
  }
}
