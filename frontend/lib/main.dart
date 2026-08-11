import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const Safe360App());
}

class Safe360App extends StatelessWidget {
  const Safe360App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Safe360',
      debugShowCheckedModeBanner: false,
      theme: buildSafe360Theme(),
      home: const LoginScreen(),
    );
  }
}
