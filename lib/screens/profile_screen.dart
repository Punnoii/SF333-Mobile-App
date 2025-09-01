import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userProfile;

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
        setState(() {
          _userProfile = doc.data() as Map<String, dynamic>;
        });
      } else if (mounted) {
        // Create user profile if it doesn't exist
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'username': user.displayName ?? 'User',
          'email': user.email ?? '',
          'profileImageUrl': '',
          'phoneNumber': '',
          'disabilityType': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        _loadUserProfile(); // Reload after creation
      }
    } catch (e) {
      print('Error loading profile: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return const Center(child: Text('Please login to view your profile'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Profile Picture and Basic Info
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              final profileImageUrl = snapshot.data?.data() != null
                  ? (snapshot.data!.data() as Map<String, dynamic>)['profileImageUrl']
                  : null;
              
              return CircleAvatar(
                radius: 50,
                backgroundImage: profileImageUrl != null && profileImageUrl.toString().isNotEmpty
                    ? CachedNetworkImageProvider(profileImageUrl)
                    : null,
                child: profileImageUrl == null || profileImageUrl.toString().isEmpty
                    ? const Icon(Icons.person, size: 50)
                    : null,
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            _userProfile?['username'] ?? 'Username',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            user.email ?? 'No email',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          
          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                  ).then((_) => _loadUserProfile());
                },
                child: const Text('Edit Profile'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (!mounted) return;
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/login',
                    (route) => false,
                  );
                },
                child: const Text('Logout'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          // Profile Stats/Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2B2B2B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Activity History',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('posts')
                      .where('authorId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final postCount = snapshot.data?.docs.length ?? 0;
                    return _buildActivityItem('Posts', '$postCount');
                  },
                ),
                StreamBuilder<int>(
                  stream: _getCommentCountStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return _buildActivityItem('Comments', '...');
                    }
                    
                    final commentCount = snapshot.data ?? 0;
                    return _buildActivityItem('Comments', '$commentCount');
                  },
                ),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('posts')
                      .where('authorId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    int totalLikes = 0;
                    if (snapshot.hasData) {
                      for (var doc in snapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        totalLikes += (data['likes'] ?? 0) as int;
                      }
                    }
                    return _buildActivityItem('Total Likes', '$totalLikes');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Additional Info
          if (_userProfile?['disabilityType']?.isNotEmpty == true)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Accessibility Information',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(_userProfile!['disabilityType']),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Stream<int> _getCommentCountStream() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return Stream.value(0);
    
    // Listen to ALL comments changes across all posts
    return FirebaseFirestore.instance
        .collectionGroup('comments')
        .where('authorId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Widget _buildActivityItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
