import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:capstone_evaluationapp/config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'cats_username': _usernameController.text.trim(),
          'password': _passwordController.text,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (!mounted) return;
        final role = data['role'];
        if (role == 'Jury') {
          Navigator.pushReplacementNamed(
            context,
            '/home',
            arguments: data,
          );
        } else if (role == 'Student') {
          Navigator.pushReplacementNamed(
            context,
            '/student',
            arguments: data,
          );
        } else if (role == 'Admin') {
          Navigator.pushReplacementNamed(context, '/admin', arguments: data);
        }
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Login failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not connect to server. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showServerSettings() {
    final ipController = TextEditingController(text: AppConfig.currentIp);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.settings_ethernet, color: ikuRed, size: 20),
            SizedBox(width: 8),
            Text('Server Settings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ikuGrey)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter the IP address of the server:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 10),
            TextField(
              controller: ipController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Server IP',
                hintText: '192.168.43.105',
                filled: true,
                fillColor: Colors.grey.shade50,
                prefixIcon: const Icon(Icons.computer, color: ikuRed, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            Text('Current: ${AppConfig.baseUrl}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: ikuGrey)),
          ),
          ElevatedButton(
            onPressed: () {
              final ip = ipController.text.trim();
              if (ip.isNotEmpty) {
                AppConfig.setBaseUrl(ip);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Server: ${AppConfig.baseUrl}'),
                    backgroundColor: const Color(0xFF27AE60),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ikuRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Image.asset(
                      'assets/logooom.png',
                      height: 140,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const Spacer(),
                  Column(
                    children: [
                      const Text(
                        "Department of Computer Engineering",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ikuGrey,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Capstone Project Evaluation",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: ikuRed,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 40),
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          filled: true,
                          fillColor: Colors.grey[50],
                          prefixIcon:
                              const Icon(Icons.person_outline, color: ikuRed),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          filled: true,
                          fillColor: Colors.grey[50],
                          prefixIcon:
                              const Icon(Icons.lock_outline, color: ikuRed),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),

                      // Hata mesajı
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: ikuRed),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: ikuRed),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      const SizedBox(height: 15),

                      ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ikuRed,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 55),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text(
                                "LOG IN",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _showServerSettings,
                        icon: Icon(Icons.settings_ethernet, size: 16, color: Colors.grey.shade400),
                        label: Text('Server Settings',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60),                    
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}