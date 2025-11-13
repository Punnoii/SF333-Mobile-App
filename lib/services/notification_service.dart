import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'logging_service.dart';

class NotificationService {
  static const String _logCategory = 'NotificationService';
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  
  static Future<void> initialize() async {
    await _initializeLocalNotifications();
    await _setupFirebaseMessaging();
    await _requestIOSPermissions();
  }
  
  static Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    
    // Request permissions
    await _requestPermissions();
  }
  
  static Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
    
    // Request Firebase messaging permissions
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
  }
  
  static Future<void> _setupFirebaseMessaging() async {
    // Get FCM token
    String? token = await _messaging.getToken();
    if (token != null) {
      await _saveTokenToFirestore(token);
    }
    
    // Listen for token refresh
    _messaging.onTokenRefresh.listen(_saveTokenToFirestore);
    
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
    
    // Handle notification taps when app is terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message);
    });
    
    // Check for initial message when app is opened from terminated state
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }
  
  static Future<void> _saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'fcmToken': token});
    }
  }
  
  static void _handleForegroundMessage(RemoteMessage message) {
    showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: message.notification?.title ?? 'New Message',
      body: message.notification?.body ?? 'You have a new message',
      payload: message.data['chatId'],
    );
  }
  
  static void _handleNotificationTap(RemoteMessage message) {
    // Handle notification tap - navigate to chat screen
    final chatId = message.data['chatId'];
    if (chatId != null) {
      // TODO: Navigate to specific chat screen
      LoggingService.info('Notification tapped for chat: $chatId', category: _logCategory);
    }
  }
  
  static Future<void> _requestIOSPermissions() async {
    if (Platform.isIOS) {
      await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      
      // Set notification presentation options for iOS
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }
  
  static Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'chat_channel',
      'Chat Notifications',
      channelDescription: 'Notifications for new chat messages',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF00BCD4), // Teal color
    );
    
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'chat_category',
      threadIdentifier: 'chat_thread',
    );
    
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(id, title, body, details, payload: payload);
  }
  
  static void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - navigate to chat
    final chatId = response.payload;
    if (chatId != null) {
      // This will be handled by the main app navigation
      _navigateToChat(chatId);
    }
  }
  
  static void _navigateToChat(String chatId) {
    // This will be implemented in the main app
    LoggingService.info('Navigate to chat: $chatId', category: _logCategory);
  }
  
  static Future<void> sendChatNotification({
    required String recipientId,
    required String senderName,
    required String message,
    required String chatId,
  }) async {
    // Get recipient's FCM token
    final recipientDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(recipientId)
        .get();
    
    final fcmToken = recipientDoc.data()?['fcmToken'] as String?;
    
    if (fcmToken == null || fcmToken.isEmpty) {
      LoggingService.warning(
        'No FCM token for user $recipientId, skip push notification',
        category: _logCategory,
      );
      return;
    }

    // Store notification data for auditing/inbox purposes.
    // A backend process (e.g. Cloud Function) should watch this collection and
    // deliver the actual push via the server-side FCM Admin SDK.
    await FirebaseFirestore.instance.collection('notifications').add({
      'recipientId': recipientId,
      'senderId': FirebaseAuth.instance.currentUser?.uid,
      'senderName': senderName,
      'message': message,
      'chatId': chatId,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
      'fcmToken': fcmToken,
    });
    LoggingService.info(
      'Queued push notification for user $recipientId via backend processor.',
      category: _logCategory,
    );
  }
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  LoggingService.info(
    'Handling background message: ${message.messageId}',
    category: NotificationService._logCategory,
  );
}
