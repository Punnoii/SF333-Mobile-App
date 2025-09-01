import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Center(
              child: SingleChildScrollView(
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
                          'Register',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Username'),
                      TextField(controller: usernameController),
                      const SizedBox(height: 12),
                      const Text('Email'),
                      TextField(controller: emailController, keyboardType: TextInputType.emailAddress),
                      const SizedBox(height: 12),
                      const Text('Phone number'),
                      TextField(controller: phoneController, keyboardType: TextInputType.phone),
                      const SizedBox(height: 12),
                      const Text('Type of disability (not required)'),
                      TextField(controller: disabilityController),
                      const SizedBox(height: 12),
                      const Text('Password'),
                      TextField(controller: passwordController, obscureText: true),
                      const SizedBox(height: 12),
                      const Text('Confirm Password'),
                      TextField(controller: confirmPasswordController, obscureText: true),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Checkbox(
                            value: agree,
                            onChanged: (v) => setState(() => agree = v ?? false),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const Expanded(child: Text('Agree to terms & conditions')),
                        ],
                      ),
                      const SizedBox(height: 6),
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
                                  try {
                                    await FirebaseAuth.instance.createUserWithEmailAndPassword(
                                      email: emailController.text.trim(),
                                      password: passwordController.text,
                                    );
                                    if (!mounted) return;
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Registered. Please login.')),
                                    );
                                  } on FirebaseAuthException catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.message ?? 'Register failed')),
                                    );
                                  }
                                }
                              : null,
                          child: const Text('Register'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Already have an account? Login'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


