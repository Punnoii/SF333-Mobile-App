import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserName;
  
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _markChatAsRead();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      // Add message to chat
      await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'content': messageText,
        'senderId': user.uid,
        'senderEmail': user.email,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update chat with last message info
      await _firestore.collection('chats').doc(widget.chatId).update({
        'lastMessage': messageText,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'lastSenderId': user.uid,
      });

      // Scroll to bottom
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .get(),
              builder: (context, chatSnapshot) {
                if (!chatSnapshot.hasData) {
                  return const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.person, size: 20),
                  );
                }
                
                final chatData = chatSnapshot.data!.data() as Map<String, dynamic>?;
                final participants = List<String>.from(chatData?['participants'] ?? []);
                final otherUserId = participants.firstWhere(
                  (id) => id != user?.uid,
                  orElse: () => '',
                );
                
                if (otherUserId.isEmpty) {
                  return const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.person, size: 20),
                  );
                }
                
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(otherUserId)
                      .get(),
                  builder: (context, userSnapshot) {
                    if (!userSnapshot.hasData) {
                      return const CircleAvatar(
                        radius: 16,
                        child: Icon(Icons.person, size: 20),
                      );
                    }
                    
                    final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                    final profileImageUrl = userData?['profileImageUrl'];
                    
                    return CircleAvatar(
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
                    );
                  },
                );
              },
            ),
            const SizedBox(width: 8),
            Text(widget.otherUserName),
          ],
        ),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {
              // TODO: Implement call functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // TODO: Implement more options
            },
          ),
        ],
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
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data?.docs ?? [];

                if (messages.isEmpty) {
                  return const Center(child: Text('No messages yet. Start the conversation!'));
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final data = message.data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == user?.uid;

                    return Container(
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
                                
                                return CircleAvatar(
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
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe ? Colors.tealAccent : const Color(0xFF2B2B2B),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data['content'] ?? '',
                                    style: TextStyle(
                                      color: isMe ? Colors.black : Colors.white,
                                    ),
                                  ),
                                  if (data['timestamp'] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
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
                                
                                return CircleAvatar(
                                  radius: 16,
                                  backgroundImage: profileImageUrl != null && profileImageUrl.toString().isNotEmpty
                                      ? CachedNetworkImageProvider(profileImageUrl)
                                      : null,
                                  child: profileImageUrl == null || profileImageUrl.toString().isEmpty
                                      ? const Icon(Icons.person, size: 20)
                                      : null,
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF2B2B2B),
              border: Border(top: BorderSide(color: Colors.grey, width: 0.5)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  onPressed: () {
                    // TODO: Implement image sharing
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                    ),
                    maxLines: null,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
