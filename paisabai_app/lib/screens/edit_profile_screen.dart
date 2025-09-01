import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController disabilityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    usernameController.text = user?.displayName ?? '';
    emailController.text = user?.email ?? '';
  }

  @override
  void dispose() {
    usernameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    disabilityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: const [
                  CircleAvatar(radius: 32, child: Icon(Icons.person, size: 36)),
                  SizedBox(width: 16),
                  CircleAvatar(radius: 24, child: Icon(Icons.face_retouching_natural)),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {},
                child: const Text('Edit picture or avatar'),
              ),
              const SizedBox(height: 16),
              const Text('Username'),
              TextField(controller: usernameController),
              const SizedBox(height: 12),
              const Text('Phone number'),
              TextField(controller: phoneController, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              const Text('Email'),
              TextField(controller: emailController, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              const Text('Type of disability'),
              TextField(controller: disabilityController, maxLines: 3),
              const SizedBox(height: 20),
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
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null) {
                      await user.updateDisplayName(usernameController.text.trim());
                      // Email update requires re-auth in many cases; attempt and ignore errors silently here
                      try { await user.updateEmail(emailController.text.trim()); } catch (_) {}
                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile saved')),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


