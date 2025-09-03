import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'comment_screen.dart';
import 'user_profile_screen.dart';
import '../services/cloudinary_service.dart';
import '../services/theme_service.dart';

class ForumScreen extends StatefulWidget {
  static const String routeName = '/forum';
  const ForumScreen({super.key});

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  final TextEditingController _postController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _selectedImage = File(image.path);
    });
  }

  Future<void> _createPost() async {
    if (_postController.text.trim().isEmpty && _selectedImage == null) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      String? imageUrl;
      
      // Upload image if selected
      if (_selectedImage != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        imageUrl = await CloudinaryService.uploadProfileImage(_selectedImage!, 'post_${user.uid}_$timestamp');
      }

      await _firestore.collection('posts').add({
        'content': _postController.text.trim(),
        'authorId': user.uid,
        'authorEmail': user.email,
        'imageUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0,
        'comments': 0,
      });
      
      _postController.clear();
      setState(() {
        _selectedImage = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating post: $e')),
        );
      }
    }
  }

  Future<void> _toggleLike(String postId, bool isLiked, int currentLikes) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final postRef = _firestore.collection('posts').doc(postId);
      final likesRef = postRef.collection('likes').doc(user.uid);

      // Check if user already liked this post
      final likeDoc = await likesRef.get();
      final hasLiked = likeDoc.exists;

      if (hasLiked) {
        // Unlike
        await likesRef.delete();
        await postRef.update({'likes': FieldValue.increment(-1)});
      } else {
        // Like
        await likesRef.set({'timestamp': FieldValue.serverTimestamp()});
        await postRef.update({'likes': FieldValue.increment(1)});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating like: $e')),
        );
      }
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      // Just delete the post - Firestore will handle subcollections
      await _firestore.collection('posts').doc(postId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting post: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;
    
    return Scaffold(
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.tealAccent, Colors.cyan],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Forum',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        backgroundColor: isDark ? Colors.black.withOpacity(0.9) : Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark ? [
                Colors.black.withOpacity(0.9),
                Colors.grey[900]!.withOpacity(0.9),
              ] : [
                Colors.white,
                Colors.grey[50]!,
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Post creation area with enhanced styling
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark ? [
                  const Color(0xFF2B2B2B),
                  Colors.grey[800]!,
                ] : [
                  Colors.white,
                  Colors.grey[100]!,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.tealAccent.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(FirebaseAuth.instance.currentUser?.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final profileImageUrl = snapshot.data?.data() != null
                        ? (snapshot.data!.data() as Map<String, dynamic>)['profileImageUrl']
                        : null;
                    
                    return CircleAvatar(
                      radius: 20,
                      backgroundImage: profileImageUrl != null && profileImageUrl.toString().isNotEmpty
                          ? CachedNetworkImageProvider(profileImageUrl)
                          : null,
                      child: profileImageUrl == null || profileImageUrl.toString().isEmpty
                          ? const Icon(Icons.person)
                          : null,
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        controller: _postController,
                        decoration: const InputDecoration(
                          hintText: 'What\'s on your mind?',
                          border: InputBorder.none,
                        ),
                        maxLines: 3,
                      ),
                      if (_selectedImage != null) ...[
                        const SizedBox(height: 8),
                        Stack(
                          children: [
                            Container(
                              height: 100,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                image: DecorationImage(
                                  image: FileImage(_selectedImage!),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedImage = null;
                                  });
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image, color: Colors.tealAccent),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.tealAccent, Colors.cyan],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.tealAccent.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _createPost,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: const Text(
                          'Post',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Posts list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('posts')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final posts = snapshot.data?.docs ?? [];

                if (posts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.forum_outlined, size: 64, color: isDark ? Colors.grey[600] : Colors.grey[500]),
                        const SizedBox(height: 16),
                        Text('No posts yet', style: TextStyle(fontSize: 18, color: isDark ? Colors.grey[400] : Colors.grey[700])),
                        const SizedBox(height: 8),
                        Text('Be the first to share something!', style: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[600])),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    final data = post.data() as Map<String, dynamic>;
                    final postId = post.id;

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: _PostWidget(
                        postId: postId,
                        content: data['content'] ?? '',
                        authorEmail: data['authorEmail'] ?? 'Unknown',
                        authorId: data['authorId'] ?? '',
                        imageUrl: data['imageUrl'],
                        timestamp: data['timestamp'] as Timestamp?,
                        likes: data['likes'] ?? 0,
                        comments: data['comments'] ?? 0,
                        onLike: (isLiked) => _toggleLike(postId, isLiked, data['likes'] ?? 0),
                        onComment: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CommentScreen(postId: postId),
                            ),
                          );
                        },
                        onDelete: () => _deletePost(postId),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PostWidget extends StatefulWidget {
  final String postId;
  final String content;
  final String authorEmail;
  final String authorId;
  final String? imageUrl;
  final Timestamp? timestamp;
  final int likes;
  final int comments;
  final Function(bool) onLike;
  final VoidCallback onComment;
  final VoidCallback onDelete;

  const _PostWidget({
    required this.postId,
    required this.content,
    required this.authorEmail,
    required this.authorId,
    this.imageUrl,
    required this.timestamp,
    required this.likes,
    required this.comments,
    required this.onLike,
    required this.onComment,
    required this.onDelete,
  });

  @override
  State<_PostWidget> createState() => _PostWidgetState();
}

class _PostWidgetState extends State<_PostWidget> {
  bool isLiked = false;

  @override
  void initState() {
    super.initState();
    _checkIfLiked();
  }

  Future<void> _checkIfLiked() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('likes')
          .doc(user.uid)
          .get();
      
      if (mounted) {
        setState(() {
          isLiked = doc.exists;
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 8,
        shadowColor: Colors.tealAccent.withOpacity(0.2),
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF2B2B2B),
                Colors.grey[800]!.withOpacity(0.9),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.tealAccent.withOpacity(0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
            children: [
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.authorId)
                    .get(),
                builder: (context, snapshot) {
                  final profileImageUrl = snapshot.data?.data() != null
                      ? (snapshot.data!.data() as Map<String, dynamic>)['profileImageUrl']
                      : null;
                  
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserProfileScreen(
                            userId: widget.authorId,
                            userName: widget.authorEmail.split('@')[0],
                          ),
                        ),
                      );
                    },
                    child: CircleAvatar(
                      radius: 16,
                      backgroundImage: profileImageUrl != null && profileImageUrl.toString().isNotEmpty
                          ? CachedNetworkImageProvider(profileImageUrl)
                          : null,
                      child: profileImageUrl == null || profileImageUrl.toString().isEmpty
                          ? const Icon(Icons.person, size: 20)
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.authorId)
                          .get(),
                      builder: (context, snapshot) {
                        final userData = snapshot.data?.data() as Map<String, dynamic>?;
                        final displayName = userData?['username'] ?? userData?['fullName'] ?? widget.authorEmail.split('@')[0];
                        
                        return Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                    if (widget.timestamp != null)
                      Text(
                        DateFormat('MMM d, y • h:mm a').format(widget.timestamp!.toDate()),
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                  ],
                ),
              ),
              // Three-dot menu for post owner
              if (widget.authorId == FirebaseAuth.instance.currentUser?.uid)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  onSelected: (value) {
                    if (value == 'delete') {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Post'),
                          content: const Text('Are you sure you want to delete this post?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onDelete();
                              },
                              child: const Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete Post'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(widget.content),
          if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: widget.imageUrl!,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) => Container(
                  height: 200,
                  color: Colors.grey[800],
                  child: const Center(child: Icon(Icons.broken_image, size: 50)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              AnimatedScale(
                scale: isLiked ? 1.2 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.red : Colors.grey,
                  ),
                  onPressed: () {
                    widget.onLike(!isLiked);
                  },
                ),
              ),
              Text('${widget.likes}'),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.comment_outlined),
                onPressed: widget.onComment,
              ),
              Text('${widget.comments}'),
              const Spacer(),
            ],
          ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
