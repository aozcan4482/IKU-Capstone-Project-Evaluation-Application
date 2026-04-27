import 'package:flutter/material.dart';
import 'package:capstone_evaluationapp/screens/login_screen.dart';
import 'package:capstone_evaluationapp/screens/home_screen.dart';
import 'package:capstone_evaluationapp/screens/student_screen.dart';
import 'package:capstone_evaluationapp/screens/admin_screen.dart';

void main() {
  runApp(const IkuApp());
}

class IkuApp extends StatelessWidget {
  const IkuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IKU Capstone Evaluation',
      theme: ThemeData(useMaterial3: true),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/student': (context) => const StudentScreen(),
        '/admin': (context) => const AdminScreen(),
      },
    );
  }
}