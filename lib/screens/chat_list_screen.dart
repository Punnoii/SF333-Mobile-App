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
  final Map<String, Map<String, dynamic>> _userCache = {};

  Future<Map<String, dynamic>?> _getUserData(String userId) async {
    if (_userCache.containsKey(userId)) {
      return _userCache[userId];
    }
    
    final doc = await _firestore.collection('users').doc(userId).get();
    if (doc.exists) {
      final userData = doc.data() as Map<String, dynamic>;
      _userCache[userId] = userData;
      return userData;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final isDark = themeService.isDarkMode;
        final user = FirebaseAuth.instance.currentUser;
        
        if (user == null) {
          return const Scaffold(
            body: Center(child: Text('Please log in')),
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
                  // TODO: Implement new chat dialog
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
              
              // Sort chats by last message timestamp (client-side sorting)
              chats.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aTime = aData['lastMessageTimestamp'] as Timestamp?;
                final bTime = bData['lastMessageTimestamp'] as Timestamp?;
                
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                
                return bTime.compareTo(aTime); // Descending order (newest first)
              });

              if (chats.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: isDark ? Colors.grey[600] : Colors.grey[500]),
                      const SizedBox(height: 16),
                      Text('No chats yet', style: TextStyle(fontSize: 18, color: isDark ? Colors.grey[400] : Colors.grey[700])),
                      const SizedBox(height: 8),
                      Text('Start a conversation!', style: TextStyle(fontSize: 14, color: isDark ? Colors.grey[500] : Colors.grey[600])),
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
                  final otherUserId = participants.firstWhere((id) => id != user.uid, orElse: () => '');
                  
                  if (otherUserId.isEmpty) return const SizedBox.shrink();

                  return FutureBuilder<Map<String, dynamic>?>(
                    future: _getUserData(otherUserId),
                    builder: (context, userSnapshot) {
                      if (!userSnapshot.hasData) {
                        return const ListTile(
                          leading: CircleAvatar(child: Icon(Icons.person)),
                          title: Text('Loading...'),
                        );
                      }

                      final userData = userSnapshot.data;
                      final otherUserName = userData?['fullName'] ?? userData?['username'] ?? 'Unknown User';
                      final profileImageUrl = userData?['profileImageUrl'];

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        elevation: 2,
                        color: isDark ? Colors.grey[850] : Colors.white,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isDark ? Colors.grey[700] : Colors.grey[300],
                            child: profileImageUrl != null
                                ? ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: profileImageUrl,
                                      width: 40,
                                      height: 40,
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
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (data['lastMessageTimestamp'] != null)
                                    Text(
                                      DateFormat('MMM d').format(
                                        (data['lastMessageTimestamp'] as Timestamp).toDate(),
                                      ),
                                      style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontSize: 12),
                                    ),
                                  const SizedBox(width: 8),
                                  // Unread message indicator with debouncing to prevent flickering
                                  StreamBuilder<QuerySnapshot>(
                                    stream: _firestore
                                        .collection('chats')
                                        .doc(chatId)
                                        .collection('messages')
                                        .where('timestamp', isGreaterThan: data['lastRead_${user.uid}'] ?? Timestamp.fromDate(DateTime(2020)))
                                        .snapshots(),
                                    builder: (context, unreadSnapshot) {
                                      // Show loading state briefly to prevent flickering
                                      if (unreadSnapshot.connectionState == ConnectionState.waiting && !unreadSnapshot.hasData) {
                                        return const SizedBox.shrink();
                                      }
                                      
                                      if (!unreadSnapshot.hasData) return const SizedBox.shrink();
                                      
                                      // Filter messages from other users client-side
                                      final unreadFromOthers = unreadSnapshot.data!.docs.where((doc) {
                                        final messageData = doc.data() as Map<String, dynamic>;
                                        return messageData['senderId'] != user.uid;
                                      }).length;
                                      
                                      if (unreadFromOthers > 0) {
                                        return AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.red.withValues(alpha: 0.3),
                                                blurRadius: 4,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 20,
                                            minHeight: 20,
                                          ),
                                          child: Text(
                                            unreadFromOthers > 99 ? '99+' : unreadFromOthers.toString(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(
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
      },
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
              final navigator = Navigator.of(context);
              await _startNewChat(emailController.text.trim());
              navigator.pop();
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
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

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
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('User not found')),
        );
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

      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId!,
            otherUserName: userData['username'] ?? userData['fullName'] ?? userData['email']?.split('@')[0] ?? 'Unknown',
            otherUserId: otherUserId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error starting chat: $e')),
      );
    }
  }
}
