import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/cloudinary_service.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserName;
  final String otherUserId;
  
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserName,
    required this.otherUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  late AnimationController _sendButtonController;
  late Animation<double> _sendButtonAnimation;

  @override
  void initState() {
    super.initState();
    _markChatAsRead();
    _sendButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _sendButtonAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _sendButtonController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _sendButtonController.dispose();
    super.dispose();
  }

  Future<void> _markChatAsRead() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        'lastRead_${currentUser.uid}': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error marking chat as read: $e');
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _selectedImage = File(image.path);
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty && _selectedImage == null) return;
    
    _sendButtonController.forward().then((_) => _sendButtonController.reverse());
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      String? imageUrl;
      
      if (_selectedImage != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        imageUrl = await CloudinaryService.uploadProfileImage(_selectedImage!, 'chat_${user.uid}_$timestamp');
      }

      await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'content': messageText,
        'senderId': user.uid,
        'senderEmail': user.email,
        'imageUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('chats').doc(widget.chatId).update({
        'lastMessage': imageUrl != null ? '📷 Photo' : messageText,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'lastSenderId': user.uid,
      });

      setState(() {
        _selectedImage = null;
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending message: $e')),
        );
      }
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting message: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.otherUserId)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.exists) {
                  final userData = snapshot.data!.data() as Map<String, dynamic>;
                  final username = userData['username'] ?? '';
                  final fullName = userData['fullName'] ?? '';
                  final displayName = username.isNotEmpty ? username : 
                                    (fullName.isNotEmpty ? fullName : widget.otherUserName);
                  
                  return ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.tealAccent, Colors.cyan],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  );
                } else {
                  return ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.tealAccent, Colors.cyan],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: Text(
                      widget.otherUserName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
        backgroundColor: Colors.black.withOpacity(0.9),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.black.withOpacity(0.9),
                Colors.grey[900]!.withOpacity(0.9),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.tealAccent),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet. Start the conversation!',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final data = message.data() as Map<String, dynamic>;
                    final messageId = message.id;
                    final isMe = data['senderId'] == user?.uid;

                    return TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 300 + (index * 50)),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: Opacity(
                            opacity: value,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isMe) ...[
                                    FutureBuilder<DocumentSnapshot>(
                                      future: FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(data['senderId'])
                                          .get(),
                                      builder: (context, snapshot) {
                                        final userData = snapshot.data?.data() as Map<String, dynamic>?;
                                        final profileImageUrl = userData?['profileImageUrl'];
                                        
                                        return Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.tealAccent.withOpacity(0.2),
                                                blurRadius: 8,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                          child: CircleAvatar(
                                            radius: 16,
                                            backgroundColor: Colors.grey[800],
                                            child: profileImageUrl != null && profileImageUrl.isNotEmpty
                                                ? ClipOval(
                                                    child: CachedNetworkImage(
                                                      imageUrl: profileImageUrl,
                                                      width: 32,
                                                      height: 32,
                                                      fit: BoxFit.cover,
                                                      placeholder: (context, url) => const CircularProgressIndicator(),
                                                      errorWidget: (context, url, error) => const Icon(Icons.person, size: 20),
                                                    ),
                                                  )
                                                : const Icon(Icons.person, size: 20),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: GestureDetector(
                                      onLongPress: isMe ? () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            backgroundColor: Colors.grey[900],
                                            title: const Text('Delete Message'),
                                            content: const Text('Are you sure you want to delete this message?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Cancel'),
                                              ),
                                              Container(
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(
                                                    colors: [Colors.red, Colors.redAccent],
                                                  ),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: TextButton(
                                                  onPressed: () {
                                                    Navigator.pop(context);
                                                    _deleteMessage(messageId);
                                                  },
                                                  child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      } : null,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(
                                          gradient: isMe 
                                              ? const LinearGradient(
                                                  colors: [Colors.tealAccent, Colors.cyan],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                )
                                              : LinearGradient(
                                                  colors: [
                                                    const Color(0xFF2B2B2B),
                                                    Colors.grey[800]!,
                                                  ],
                                                ),
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: isMe 
                                                  ? Colors.tealAccent.withOpacity(0.3)
                                                  : Colors.black.withOpacity(0.2),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (data['imageUrl'] != null && data['imageUrl'].toString().isNotEmpty) ...[
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black.withOpacity(0.2),
                                                        blurRadius: 8,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: CachedNetworkImage(
                                                    imageUrl: data['imageUrl'],
                                                    width: 200,
                                                    fit: BoxFit.cover,
                                                    placeholder: (context, url) => Container(
                                                      height: 100,
                                                      child: const Center(
                                                        child: CircularProgressIndicator(color: Colors.tealAccent),
                                                      ),
                                                    ),
                                                    errorWidget: (context, url, error) => Container(
                                                      height: 100,
                                                      color: Colors.grey[800],
                                                      child: const Icon(Icons.broken_image),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (data['content'] != null && data['content'].toString().isNotEmpty)
                                                const SizedBox(height: 8),
                                            ],
                                            if (data['content'] != null && data['content'].toString().isNotEmpty)
                                              Text(
                                                data['content'],
                                                style: TextStyle(
                                                  color: isMe ? Colors.black : Colors.white,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            if (data['timestamp'] != null)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 6),
                                                child: Text(
                                                  DateFormat('h:mm a').format(
                                                    (data['timestamp'] as Timestamp).toDate(),
                                                  ),
                                                  style: TextStyle(
                                                    color: isMe ? Colors.black54 : Colors.grey,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 8),
                                    FutureBuilder<DocumentSnapshot>(
                                      future: FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(user!.uid)
                                          .get(),
                                      builder: (context, snapshot) {
                                        final profileImageUrl = snapshot.data?.data() != null
                                            ? (snapshot.data!.data() as Map<String, dynamic>)['profileImageUrl']
                                            : null;
                                        
                                        return Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.tealAccent.withOpacity(0.2),
                                                blurRadius: 8,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
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
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF2B2B2B),
                  Colors.grey[900]!,
                ],
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.tealAccent.withOpacity(0.2),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                if (_selectedImage != null) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Stack(
                      children: [
                        Container(
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            image: DecorationImage(
                              image: FileImage(_selectedImage!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedImage = null;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.red, Colors.redAccent],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(6),
                              child: const Icon(Icons.close, color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.tealAccent, Colors.cyan],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.tealAccent.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, color: Colors.black),
                        onPressed: _pickImage,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: Colors.tealAccent.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(color: Colors.grey),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          maxLines: null,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedBuilder(
                      animation: _sendButtonAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _sendButtonAnimation.value,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.tealAccent, Colors.cyan],
                              ),
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.tealAccent.withOpacity(0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.send, color: Colors.black),
                              onPressed: _sendMessage,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
