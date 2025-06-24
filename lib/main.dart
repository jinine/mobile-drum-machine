import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/editor_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drum Pad',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurpleAccent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF181A20),
        cardColor: const Color(0xFF23242B),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF23242B),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 1.2,
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white, fontFamily: 'RobotoMono'),
          bodyMedium: TextStyle(color: Colors.white70, fontFamily: 'RobotoMono'),
          titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurpleAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        dialogBackgroundColor: const Color(0xFF23242B),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
