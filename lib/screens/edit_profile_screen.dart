import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import '../services/cloudinary_service.dart';

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
  final ImagePicker _picker = ImagePicker();
  String? _selectedAvatar;
  String? _currentProfileImageUrl;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _currentProfileImageUrl = data['profileImageUrl'];
          usernameController.text = data['username'] ?? '';
          phoneController.text = data['phoneNumber'] ?? '';
          emailController.text = data['email'] ?? user.email ?? '';
          disabilityController.text = data['disabilityType'] ?? '';
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _selectedImage = File(image.path);
      _selectedAvatar = null; // Clear avatar selection
    });
  }

  void _selectAvatar(String avatarName) {
    setState(() {
      _selectedAvatar = avatarName;
      _selectedImage = null; // Clear selected image
    });
  }

  void _showAvatarPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Avatar'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: CloudinaryService.getAvatarOptions().length,
            itemBuilder: (context, index) {
              final avatarName = CloudinaryService.getAvatarOptions()[index];
              return GestureDetector(
                onTap: () {
                  _selectAvatar(avatarName);
                  Navigator.pop(context);
                },
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _selectedAvatar == avatarName ? Colors.blue : Colors.grey,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: CloudinaryService.getAvatarUrl(avatarName, width: 100, height: 100),
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const CircularProgressIndicator(),
                      errorWidget: (context, url, error) => const Icon(Icons.error),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
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
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 32,
                      backgroundImage: _selectedImage != null
                          ? FileImage(_selectedImage!)
                          : (_selectedAvatar != null
                              ? CachedNetworkImageProvider(CloudinaryService.getAvatarUrl(_selectedAvatar!))
                              : (_currentProfileImageUrl?.isNotEmpty == true
                                  ? CachedNetworkImageProvider(_currentProfileImageUrl!)
                                  : null)),
                      child: _selectedImage == null && _selectedAvatar == null && (_currentProfileImageUrl?.isEmpty ?? true)
                          ? const Icon(Icons.person, size: 36)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: _showAvatarPicker,
                    child: CircleAvatar(
                      radius: 24,
                      backgroundImage: _selectedAvatar != null
                          ? CachedNetworkImageProvider(CloudinaryService.getAvatarUrl(_selectedAvatar!))
                          : null,
                      child: _selectedAvatar == null
                          ? const Icon(Icons.face_retouching_natural)
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: _pickImage,
                    child: const Text('Upload Photo'),
                  ),
                  TextButton(
                    onPressed: _showAvatarPicker,
                    child: const Text('Choose Avatar'),
                  ),
                ],
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
                    if (user == null) return;

                    try {
                      String? finalImageUrl;
                      
                      // Upload image to Cloudinary if selected
                      if (_selectedImage != null) {
                        finalImageUrl = await CloudinaryService.uploadProfileImage(_selectedImage!, user.uid);
                      } else if (_selectedAvatar != null) {
                        finalImageUrl = CloudinaryService.getAvatarUrl(_selectedAvatar!);
                      } else {
                        finalImageUrl = _currentProfileImageUrl;
                      }
                      
                      // Update Firestore profile
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .set({
                        'username': usernameController.text.trim(),
                        'phoneNumber': phoneController.text.trim(),
                        'disabilityType': disabilityController.text.trim(),
                        'profileImageUrl': finalImageUrl ?? '',
                        'email': user.email ?? '',
                        'updatedAt': FieldValue.serverTimestamp(),
                        'createdAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile saved successfully')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error saving profile: $e')),
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
