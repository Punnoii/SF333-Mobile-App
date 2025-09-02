import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload profile when returning from edit screen
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
        // Check if fullName exists, if not, use username or displayName as fallback
        if (data['fullName'] == null || data['fullName'] == '') {
          data['fullName'] = data['username'] ?? user.displayName ?? 'User';
          // Update Firestore with the fallback name
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'fullName': data['fullName']});
        }
        setState(() {
          _userProfile = data;
        });
        print('Loaded user profile: $_userProfile');
      } else if (mounted) {
        // Create user profile if it doesn't exist
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'username': user.displayName ?? 'User',
          'fullName': user.displayName ?? 'New User',
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.tealAccent),
            onPressed: () {
              Navigator.pushNamed(context, '/edit-profile');
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Profile Image with enhanced design
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser?.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final userData = snapshot.data?.data() as Map<String, dynamic>?;
                final profileImageUrl = userData?['profileImageUrl'];
                
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.tealAccent, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.tealAccent.withOpacity(0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[800],
                    child: profileImageUrl != null && profileImageUrl.toString().isNotEmpty
                        ? ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: profileImageUrl.toString(),
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const CircularProgressIndicator(),
                              errorWidget: (context, url, error) => const Icon(Icons.person, size: 60),
                            ),
                          )
                        : const Icon(Icons.person, size: 60),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              _userProfile?['fullName'] ?? _userProfile?['username'] ?? FirebaseAuth.instance.currentUser?.displayName ?? 'User',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              user.email ?? 'No email',
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
            ),
            const SizedBox(height: 32),
            
            // Activity Stats
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[800]!, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics_outlined, color: Colors.tealAccent, size: 24),
                      const SizedBox(width: 8),
                      const Text(
                        'Activity Stats',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
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
                          totalLikes += (data['likes'] as int? ?? 0);
                        }
                      }
                      return _buildActivityItem('Total Likes', '$totalLikes');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Accessibility Info
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser?.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final userData = snapshot.data?.data() as Map<String, dynamic>?;
                final disabilityType = userData?['disabilityType'] ?? '';
                
                // Only show if there's disability information
                if (disabilityType.isEmpty) return const SizedBox.shrink();
                
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[800]!, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.accessibility_new, color: Colors.tealAccent, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Accessibility Information',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          disabilityType,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[400], fontSize: 16),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.tealAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.tealAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
