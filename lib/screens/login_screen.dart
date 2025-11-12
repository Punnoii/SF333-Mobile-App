import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'register_screen.dart';
import 'change_password_screen.dart';

class LoginScreen extends StatefulWidget {
  static const String routeName = '/login';
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool rememberMe = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // Function to show error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('เกิดข้อผิดพลาด'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ตกลง'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Center(
              child: Container(
                width: math.min(420.0, MediaQuery.of(context).size.width - 32),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2B2B),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    const Center(
                      child: Text(
                        'เข้าสู่ระบบ',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('อีเมล'),
                    ),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('รหัสผ่าน'),
                    ),
                    TextField(
                      controller: passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility : Icons.visibility_off,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: rememberMe,
                              onChanged: (v) => setState(() => rememberMe = v ?? false),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const Text('จดจำฉันไว้'),
                          ],
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamed(context, ChangePasswordScreen.routeName);
                          },
                          child: const Text('ลืมรหัสผ่าน?'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.center,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
                        ),
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          try {
                            // Validate email format
                            final email = usernameController.text.trim();
                            if (email.isEmpty) {
                              _showErrorDialog('กรุณากรอกอีเมล');
                              return;
                            }
                            if (!RegExp(r'^[^@]+@[^\s]+\.[^\s]+$').hasMatch(email)) {
                              _showErrorDialog('รูปแบบอีเมลไม่ถูกต้อง');
                              return;
                            }
                            
                            // Validate password
                            if (passwordController.text.isEmpty) {
                              _showErrorDialog('กรุณากรอกรหัสผ่าน');
                              return;
                            }
                            
                            try {
                              await FirebaseAuth.instance.signInWithEmailAndPassword(
                                email: email,
                                password: passwordController.text,
                              );
                              if (!mounted) return;
                              navigator.pushReplacementNamed('/main');
                            } on FirebaseAuthException catch (e) {
                              if (!mounted) return;
                              String errorMessage = 'เกิดข้อผิดพลาดในการเข้าสู่ระบบ';
                              
                              if (e.code == 'user-not-found') {
                                errorMessage = 'ไม่พบผู้ใช้งานอีเมลนี้';
                              } else if (e.code == 'wrong-password') {
                                errorMessage = 'รหัสผ่านไม่ถูกต้อง';
                              } else if (e.code == 'user-disabled') {
                                errorMessage = 'บัญชีนี้ถูกระงับการใช้งาน';
                              } else if (e.code == 'too-many-requests') {
                                errorMessage = 'พยายามเข้าสู่ระบบหลายครั้งเกินไป กรุณาลองใหม่ในภายหลัง';
                              } else if (e.code == 'network-request-failed') {
                                errorMessage = 'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้ กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต';
                              }
                              
                              _showErrorDialog(errorMessage);
                            }
                          } catch (e) {
                            if (!mounted) return;
                            _showErrorDialog('เกิดข้อผิดพลาดที่ไม่คาดคิด กรุณาลองใหม่อีกครั้ง');
                          }
                        },
                        child: const Text('เข้าสู่ระบบ'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Center(
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, RegisterScreen.routeName),
                  child: const Text("ยังไม่มีบัญชี? สมัครสมาชิก"),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
