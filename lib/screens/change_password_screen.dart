import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChangePasswordScreen extends StatefulWidget {
  static const String routeName = '/change-password';
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final TextEditingController emailController = TextEditingController();
  bool _isSending = false;

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
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    final email = emailController.text.trim();
    
    if (email.isEmpty) {
      _showErrorDialog('กรุณากรอกที่อยู่อีเมล');
      return;
    }

    if (!RegExp(r'^[^@]+@[^\s]+\.[^\s]+$').hasMatch(email)) {
      _showErrorDialog('รูปแบบอีเมลไม่ถูกต้อง');
      return;
    }
    
    setState(() => _isSending = true);
    FocusScope.of(context).unfocus();

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('ส่งลิงก์เรียบร้อย'),
              ],
            ),
            content: Text('เราได้ส่งลิงก์รีเซ็ตรหัสผ่านไปที่ $email แล้ว'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('ตกลง'),
              ),
            ],
          );
        },
      );
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'ไม่สามารถส่งลิงก์รีเซ็ตรหัสผ่านได้';
      if (e.code == 'user-not-found') {
        errorMessage = 'ไม่พบผู้ใช้งานอีเมลนี้';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'รูปแบบอีเมลไม่ถูกต้อง';
      } else if (e.code == 'network-request-failed') {
        errorMessage = 'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้';
      }
      _showErrorDialog(errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Center(
              child: Container(
                width: 320,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2B2B),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: Text(
                        'รีเซ็ตรหัสผ่าน',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('อีเมล'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'กรอกที่อยู่อีเมลของคุณ',
                        fillColor: Colors.white.withOpacity(0.05),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'เราจะส่งลิงก์รีเซ็ตรหัสผ่านไปยังอีเมลของคุณ',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _isSending ? null : _sendResetLink,
                      child: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text(
                              'ส่งลิงก์รีเซ็ตรหัสผ่าน',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}