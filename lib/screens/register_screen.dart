import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  static const String routeName = '/register';
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController disabilityController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  bool agree = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _showDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 8),
              Text(title),
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
    usernameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    disabilityController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
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
                              'สมัครสมาชิก',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text('ชื่อผู้ใช้'),
                          const SizedBox(height: 8),
                          TextField(controller: usernameController),
                          const SizedBox(height: 16),
                          const Text('อีเมล'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                          const Text('เบอร์โทรศัพท์'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 16),
                          const Text('ประเภทความพิการ (ไม่จำเป็นต้องกรอก)'),
                          const SizedBox(height: 8),
                          TextField(controller: disabilityController),
                          const SizedBox(height: 16),
                          const Text('รหัสผ่าน'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                  color: Colors.grey,
                                ),
                                onPressed: () =>
                                    setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('ยืนยันรหัสผ่าน'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                                  color: Colors.grey,
                                ),
                                onPressed: () => setState(
                                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Checkbox(
                                value: agree,
                                onChanged: (v) => setState(() => agree = v ?? false),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const Expanded(child: Text('ยอมรับเงื่อนไขและข้อตกลง')),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.center,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
                              ),
                              onPressed: agree
                                  ? () async {
                                      final navigator = Navigator.of(context);
                                      if (passwordController.text != confirmPasswordController.text) {
                                        await _showDialog(
                                          title: 'เกิดข้อผิดพลาด',
                                          message: 'รหัสผ่านไม่ตรงกัน',
                                          icon: Icons.error_outline,
                                          iconColor: Colors.red,
                                        );
                                        return;
                                      }

                                      try {
                                        final credential = await FirebaseAuth.instance
                                            .createUserWithEmailAndPassword(
                                          email: emailController.text.trim(),
                                          password: passwordController.text,
                                        );

                                        // Create user profile in Firestore
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(credential.user!.uid)
                                            .set({
                                          'username': usernameController.text.trim(),
                                          'email': emailController.text.trim(),
                                          'phoneNumber': phoneController.text.trim(),
                                          'disabilityType': disabilityController.text.trim(),
                                          'createdAt': FieldValue.serverTimestamp(),
                                          'profileImageUrl': '', // Local path will be set when user uploads image
                                        });

                                        if (!mounted) return;
                                        await _showDialog(
                                          title: 'สำเร็จ',
                                          message: 'สมัครสมาชิกสำเร็จ กรุณาเข้าสู่ระบบ',
                                          icon: Icons.check_circle_outline,
                                          iconColor: Colors.green,
                                        );
                                        if (!mounted) return;
                                        navigator.pop();
                                      } on FirebaseAuthException catch (e) {
                                        if (!mounted) return;
                                        String errorMessage = 'ไม่สามารถสมัครสมาชิกได้';
                                        if (e.code == 'email-already-in-use') {
                                          errorMessage = 'อีเมลนี้ถูกใช้สมัครไว้แล้ว';
                                        } else if (e.code == 'weak-password') {
                                          errorMessage = 'รหัสผ่านไม่ปลอดภัย กรุณาตั้งรหัสผ่านที่คาดเดายาก';
                                        } else if (e.code == 'invalid-email') {
                                          errorMessage = 'รูปแบบอีเมลไม่ถูกต้อง';
                                        } else if (e.code == 'operation-not-allowed') {
                                          errorMessage = 'ไม่สามารถเปิดใช้การสมัครสมาชิกได้ในขณะนี้';
                                        } else if (e.code == 'network-request-failed') {
                                          errorMessage = 'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้ กรุณาตรวจสอบอินเทอร์เน็ต';
                                        } else if (e.message != null && e.message!.isNotEmpty) {
                                          errorMessage = e.message!;
                                        }
                                        await _showDialog(
                                          title: 'เกิดข้อผิดพลาด',
                                          message: errorMessage,
                                          icon: Icons.error_outline,
                                          iconColor: Colors.red,
                                        );
                                      }
                                    }
                                  : null,
                              child: const Text('สมัครสมาชิก'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
