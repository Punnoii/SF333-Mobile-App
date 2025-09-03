import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'chat_screen.dart';
import '../services/theme_service.dart';

class ChatListScreen extends StatefulWidget {
  static const String routeName = '/chatlist';
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, DocumentSnapshot> _userCache = {};

  Future<DocumentSnapshot> _getUserData(String userId) async {
    if (_userCache.containsKey(userId)) {
      return _userCache[userId]!;
    }
    
    final doc = await _firestore.collection('users').doc(userId).get();
    _userCache[userId] = doc;
    return doc;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;
    
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view chats')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: isDark ? Colors.tealAccent : Colors.teal),
            onPressed: () {
              _showNewChatDialog();
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('chats')
            .where('participants', arrayContains: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data?.docs ?? [];

          if (chats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: isDark ? Colors.grey[600] : Colors.grey[500]),
                  const SizedBox(height: 16),
                  Text('No chats yet', style: TextStyle(fontSize: 18, color: isDark ? Colors.grey[400] : Colors.grey[700])),
                  const SizedBox(height: 8),
                  Text('Tap + to start a new conversation', style: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[600])),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              final data = chat.data() as Map<String, dynamic>;
              final chatId = chat.id;
              
              final participants = List<String>.from(data['participants'] ?? []);
              final otherUserId = participants.firstWhere(
                (id) => id != user.uid,
                orElse: () => '',
              );

              return FutureBuilder<DocumentSnapshot>(
                key: ValueKey(otherUserId), // Add key to prevent rebuilds
                future: _getUserData(otherUserId),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[900] : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!, width: 0.5),
                        boxShadow: isDark ? [] : [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        title: Text('Loading...', style: TextStyle(color: Colors.grey)),
                      ),
                    );
                  }
                  
                  final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                  final otherUserName = userData?['username'] ?? userData?['fullName'] ?? userData?['email']?.split('@')[0] ?? 'Unknown';

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[900] : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!, width: 0.5),
                      boxShadow: isDark ? [] : [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                        child: userData?['profileImageUrl'] != null
                            ? ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: userData!['profileImageUrl'],
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const CircularProgressIndicator(),
                                  errorWidget: (context, url, error) => const Icon(Icons.person),
                                ),
                              )
                            : const Icon(Icons.person),
                      ),
                      title: Text(
                        otherUserName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600, 
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          data['lastMessage'] ?? 'No messages yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14),
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (data['lastMessageTime'] != null)
                            Text(
                              DateFormat('MMM d').format(
                                (data['lastMessageTime'] as Timestamp).toDate(),
                              ),
                              style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontSize: 12),
                            ),
                          const SizedBox(height: 4),
                          Icon(Icons.chevron_right, color: isDark ? Colors.grey[600] : Colors.grey[500], size: 20),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              chatId: chatId,
                              otherUserName: otherUserName,
                              otherUserId: otherUserId,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showNewChatDialog();
        },
        backgroundColor: isDark ? Colors.tealAccent : Colors.teal,
        foregroundColor: isDark ? Colors.black : Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showNewChatDialog() {
    final emailController = TextEditingController();
    
    final themeService = Provider.of<ThemeService>(context, listen: false);
    final isDark = themeService.isDarkMode;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Start New Chat',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Enter email or full name',
                hintStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: isDark ? Colors.grey[600]! : Colors.grey[400]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: isDark ? Colors.grey[600]! : Colors.grey[400]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: isDark ? Colors.tealAccent : Colors.teal),
                ),
                helperText: 'You can search by email or full name',
                helperStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
          ),
          TextButton(
            onPressed: () async {
              await _startNewChat(emailController.text.trim());
              Navigator.pop(context);
            },
            child: Text(
              'Start Chat',
              style: TextStyle(color: isDark ? Colors.tealAccent : Colors.teal),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startNewChat(String searchTerm) async {
    if (searchTerm.isEmpty) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Search by email first
      QuerySnapshot userQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: searchTerm)
          .get();

      // If no results by email, search by fullName
      if (userQuery.docs.isEmpty) {
        userQuery = await _firestore
            .collection('users')
            .where('fullName', isEqualTo: searchTerm)
            .get();
      }

      // If still no results, search by username
      if (userQuery.docs.isEmpty) {
        userQuery = await _firestore
            .collection('users')
            .where('username', isEqualTo: searchTerm)
            .get();
      }

      if (userQuery.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not found')),
          );
        }
        return;
      }

      final otherUserId = userQuery.docs.first.id;
      final userData = userQuery.docs.first.data() as Map<String, dynamic>;
      final participants = [user.uid, otherUserId]..sort();

      // Check if chat already exists
      final existingChat = await _firestore
          .collection('chats')
          .where('participants', arrayContains: user.uid)
          .get();

      String? chatId;
      for (var doc in existingChat.docs) {
        final data = doc.data();
        final chatParticipants = List<String>.from(data['participants'] ?? []);
        if (chatParticipants.contains(otherUserId)) {
          chatId = doc.id;
          break;
        }
      }

      if (chatId == null) {
        // Create new chat
        final chatRef = await _firestore.collection('chats').add({
          'participants': participants,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
        });
        chatId = chatRef.id;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId: chatId!,
              otherUserName: userData['username'] ?? userData['fullName'] ?? userData['email']?.split('@')[0] ?? 'Unknown',
              otherUserId: otherUserId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting chat: $e')),
        );
      }
    }
  }
}
