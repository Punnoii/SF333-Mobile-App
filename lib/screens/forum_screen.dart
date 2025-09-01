import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'comment_screen.dart';
import 'user_profile_screen.dart';

class ForumScreen extends StatefulWidget {
  static const String routeName = '/forum';
  const ForumScreen({super.key});

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  final TextEditingController _postController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  Future<void> _createPost() async {
    if (_postController.text.trim().isEmpty) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('posts').add({
        'content': _postController.text.trim(),
        'authorId': user.uid,
        'authorEmail': user.email,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0,
        'comments': 0,
      });
      _postController.clear();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forum'),
        backgroundColor: Colors.black,
      ),
      body: Column(
        children: [
          // Post creation area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF2B2B2B),
              border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
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
                  child: TextField(
                    controller: _postController,
                    decoration: const InputDecoration(
                      hintText: 'What do you want to post?',
                      border: InputBorder.none,
                    ),
                    maxLines: null,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _createPost,
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
                  return const Center(child: Text('No posts yet. Be the first to post!'));
                }

                return ListView.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    final data = post.data() as Map<String, dynamic>;
                    final postId = post.id;

                    return _PostWidget(
                      postId: postId,
                      content: data['content'] ?? '',
                      authorEmail: data['authorEmail'] ?? 'Unknown',
                      authorId: data['authorId'] ?? '',
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(12),
      ),
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
                    Text(
                      widget.authorEmail.split('@')[0],
                      style: const TextStyle(fontWeight: FontWeight.bold),
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
                              child: GestureDetector(
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
                                  backgroundImage: CachedNetworkImageProvider('https://picsum.photos/200/300'),
                                  child: const Icon(Icons.person, size: 20),
                                ),
                              ),
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
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  isLiked ? Icons.favorite : Icons.favorite_border,
                  color: isLiked ? Colors.red : Colors.grey,
                ),
                onPressed: () {
                  widget.onLike(!isLiked);
                },
              ),
              Text('${widget.likes}'),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.comment_outlined),
                onPressed: widget.onComment,
              ),
              Text('${widget.comments}'),
              const Spacer(),
              TextButton(
                onPressed: widget.onComment,
                child: const Text('Reply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
