import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp/module/ChatMessage.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _groupSearchController = TextEditingController();
  String? _currentUserCustomId;
  List<DocumentSnapshot> _searchResults = [];
  List<DocumentSnapshot> _groupSearchResults = [];
  List<Map<String, dynamic>> _createdGroups = [];

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // For notification management
  Set<String> _processedMessageIds = {};
  bool _isAppInForeground = true;
  Map<String, dynamic> _lastMessageTimestamps = {};

  // Add unread message counters
  Map<String, int> _unreadMessageCounts = {};

  // Notification plugin
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    // Start animations
    _fadeController.forward();
    _slideController.forward();

    WidgetsBinding.instance.addObserver(this);
    _initializeNotifications();
    _initializeUserCustomId();
    _loadCreatedGroups();
    _listenForNewMessages();
    _loadLastMessageTimestamps();
    _loadUnreadMessageCounts();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _groupSearchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    setState(() {
      _isAppInForeground = state == AppLifecycleState.resumed;
    });

    if (state == AppLifecycleState.resumed) {
      int totalUnread = 0;
      _unreadMessageCounts.forEach((key, value) {
        totalUnread += value;
      });
      if (totalUnread == 0) {
      }
    }
  }

  Future<void> _loadUnreadMessageCounts() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final unreadDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('unread_counts')
          .doc('counts')
          .get();

      if (unreadDoc.exists) {
        setState(() {
          _unreadMessageCounts = Map<String, int>.from(unreadDoc.data() ?? {});
        });
      }
    } catch (e) {
      print('Error loading unread counts: $e');
    }
  }

  void _listenForUnreadCounts() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('unread_counts')
        .doc('counts')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        setState(() {
          _unreadMessageCounts = Map<String, int>.from(snapshot.data() ?? {});
        });
      }
    });
  }

  Future<void> _resetUnreadCount(String chatId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('unread_counts')
          .doc('counts')
          .update({chatId: FieldValue.delete()});

      setState(() {
        _unreadMessageCounts.remove(chatId);
      });

      int totalUnread = 0;
      _unreadMessageCounts.forEach((key, value) {
        if (key != chatId) {
          totalUnread += value;
        }
      });
    } catch (e) {
      print('Error resetting unread count: $e');
    }
  }

  Future<void> _initializeNotifications() async {
    await _requestNotificationPermissions();

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (Platform.isAndroid) {
      await _createNotificationChannel();
    }

    await flutterLocalNotificationsPlugin.cancelAll();
  }

  Future<void> _requestNotificationPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (status.isDenied) {
        print('Notification permission denied');
      }
    } else if (Platform.isIOS) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'chat_messages',
      'Chat Messages',
      description: 'Notifications for new chat messages',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound('notification'),
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _onNotificationTapped(NotificationResponse notificationResponse) {
    final payload = notificationResponse.payload;
    if (payload != null) {
      try {
        final data = jsonDecode(payload);
        _navigateToChat(
          data['chatId'],
          data['chatName'],
          data,
        );
      } catch (e) {
        print('Error handling notification tap: $e');
      }
    }
  }

  Future<void> _sendLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    required int badgeCount,
  }) async {
    try {
      int totalUnread = 0;
      _unreadMessageCounts.forEach((key, value) {
        totalUnread += value;
      });

      AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        'chat_messages',
        'Chat Messages',
        channelDescription: 'Notifications for new chat messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF6C63FF),
        ledColor: const Color(0xFF6C63FF),
        ledOnMs: 1000,
        ledOffMs: 500,
        number: totalUnread,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: totalUnread > 1 ? '$totalUnread unread messages' : null,
        ),
      );

      DarwinNotificationDetails iOSPlatformChannelSpecifics =
      DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        badgeNumber: totalUnread,
      );

      NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        platformChannelSpecifics,
        payload: jsonEncode(payload),
      );
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  String _generateCustomId() {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final random = Random();
    String letterPart = List.generate(3, (_) => letters[random.nextInt(26)]).join();
    String numberPart = List.generate(3, (_) => random.nextInt(10).toString()).join();
    return '$letterPart$numberPart';
  }

  Future<void> _initializeUserCustomId() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('custom_ids')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        String customId;
        bool isUnique;
        do {
          customId = _generateCustomId();
          isUnique = (await FirebaseFirestore.instance
              .collection('custom_ids')
              .where('customId', isEqualTo: customId)
              .get())
              .docs
              .isEmpty;
        } while (!isUnique);

        await FirebaseFirestore.instance
            .collection('custom_ids')
            .doc(currentUser.uid)
            .set({
          'customId': customId,
          'userId': currentUser.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        setState(() {
          _currentUserCustomId = customId;
        });
      } else {
        setState(() {
          _currentUserCustomId = userDoc['customId'];
        });
      }

      _listenForUnreadCounts();
    } catch (e) {
      _showErrorSnackBar('Failed to initialize user ID: $e');
    }
  }

  Future<void> _loadLastMessageTimestamps() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final messagesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('messages')
          .get();

      final timestamps = <String, dynamic>{};
      for (var doc in messagesSnapshot.docs) {
        final data = doc.data();
        if (data['timestamp'] != null) {
          timestamps[doc.id] = data['timestamp'];
        }
      }

      setState(() {
        _lastMessageTimestamps = timestamps;
      });
    } catch (e) {
      print('Error loading message timestamps: $e');
    }
  }

  void _listenForNewMessages() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('messages')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          _handleMessageChange(change.doc);
        }
      }
    });
  }

  void _handleMessageChange(DocumentSnapshot messageDoc) async {
    final data = messageDoc.data() as Map<String, dynamic>?;
    if (data == null) return;

    final messageId = messageDoc.id;
    final currentTimestamp = data['timestamp'];
    final lastTimestamp = _lastMessageTimestamps[messageId];

    bool isNewMessage = false;

    if (lastTimestamp == null) {
      isNewMessage = true;
    } else if (currentTimestamp != null && lastTimestamp != null) {
      if (currentTimestamp is Timestamp && lastTimestamp is Timestamp) {
        isNewMessage = currentTimestamp.millisecondsSinceEpoch > lastTimestamp.millisecondsSinceEpoch;
      }
    }

    _lastMessageTimestamps[messageId] = currentTimestamp;

    if (isNewMessage && !_processedMessageIds.contains(messageId)) {
      _processedMessageIds.add(messageId);

      if (data['senderCustomId'] != _currentUserCustomId) {
        await _incrementUnreadCount(messageId);
      }

      _showNewMessageNotification(data);
    }
  }

  Future<void> _incrementUnreadCount(String chatId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('unread_counts')
          .doc('counts')
          .set({
        chatId: FieldValue.increment(1)
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error incrementing unread count: $e');
    }
  }

  void _showNewMessageNotification(Map<String, dynamic> data) {
    if (data['senderCustomId'] == _currentUserCustomId) return;

    final String chatId = data['groupId'] ?? data['receiverCustomId'] ?? 'Unknown';
    final String senderName = data['senderName'] ?? data['senderCustomId'] ?? 'Unknown User';
    final String messageType = data['type'] ?? 'text';

    String notificationContent;
    switch (messageType) {
      case 'image':
        notificationContent = '📷 Sent a photo';
        break;
      case 'file':
        notificationContent = '📎 Sent a file: ${data['fileName'] ?? 'Unknown file'}';
        break;
      case 'audio':
        notificationContent = '🎵 Sent an audio message';
        break;
      case 'video':
        notificationContent = '🎥 Sent a video';
        break;
      default:
        notificationContent = data['lastMessage'] ?? 'New message';
        if (notificationContent.length > 100) {
          notificationContent = '${notificationContent.substring(0, 97)}...';
        }
    }

    final bool isGroup = data['groupId'] != null;
    final String chatName = isGroup
        ? (data['groupName'] ?? 'Group $chatId')
        : senderName;

    String notificationTitle;
    String notificationBody;

    if (isGroup) {
      notificationTitle = chatName;
      notificationBody = '$senderName: $notificationContent';
    } else {
      notificationTitle = senderName;
      notificationBody = notificationContent;
    }

    int chatUnreadCount = _unreadMessageCounts[chatId] ?? 0;

    _sendLocalNotification(
      title: notificationTitle,
      body: notificationBody,
      payload: {
        'chatId': chatId,
        'chatName': chatName,
        'photoURL': data['photoURL'] ?? 'assets/default_avatar.png',
        'isGroup': isGroup,
        'senderName': senderName,
      },
      badgeCount: chatUnreadCount,
    );

    if (_isAppInForeground && mounted) {
      int totalUnread = 0;
      _unreadMessageCounts.forEach((key, value) {
        totalUnread += value;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    isGroup ? Icons.group_rounded : Icons.person_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notificationTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notificationBody,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (chatUnreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      chatUnreadCount > 99 ? '99+' : chatUnreadCount.toString(),
                      style: const TextStyle(
                        color: Color(0xFF6C63FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          backgroundColor: const Color(0xFF6C63FF),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            backgroundColor: Colors.white.withOpacity(0.15),
            onPressed: () => _navigateToChat(chatId, chatName, data),
          ),
        ),
      );

      _playNotificationFeedback();
    }
  }

  void _playNotificationFeedback() {
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  void _navigateToChat(String chatId, String chatName, Map<String, dynamic> data) {
    _resetUnreadCount(chatId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatMessage(
          currentUserCustomId: _currentUserCustomId!,
          selectedCustomId: chatId,
          selectedUserName: chatName,
          selectedUserPhotoURL: data['photoURL'] ?? 'assets/default_avatar.png',
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.error_outline_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: const TextStyle(fontSize: 14))),
            ],
          ),
          backgroundColor: const Color(0xFFFF6B6B),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: const TextStyle(fontSize: 14))),
            ],
          ),
          backgroundColor: const Color(0xFF4ECDC4),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );
    }
  }

  Future<void> _loadCreatedGroups() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final groupDocs = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('groups')
          .get();

      final groups = <Map<String, dynamic>>[];
      for (var doc in groupDocs.docs) {
        final groupId = doc['groupId'];
        final groupDoc = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .get();
        if (groupDoc.exists) {
          groups.add({
            'groupId': groupId,
            'name': groupDoc['name'] ?? 'Group $groupId',
            'photoURL': groupDoc['photoURL'] ?? 'assets/group_icon.png',
            'description': groupDoc['description'] ?? '',
          });
        }
      }

      setState(() {
        _createdGroups = groups;
      });
    } catch (e) {
      _showErrorSnackBar('Failed to load groups: $e');
    }
  }

  Future<void> _createGroup() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _currentUserCustomId == null) return;

    try {
      String groupId;
      bool isUnique;
      do {
        groupId = _generateCustomId();
        isUnique = (await FirebaseFirestore.instance
            .collection('group_ids')
            .where('groupId', isEqualTo: groupId)
            .get())
            .docs
            .isEmpty;
      } while (!isUnique);

      await FirebaseFirestore.instance
          .collection('group_ids')
          .doc(groupId)
          .set({
        'groupId': groupId,
        'creatorId': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .set({
        'groupId': groupId,
        'name': 'Group $groupId',
        'photoURL': 'assets/group_icon.png',
        'description': '',
        'creatorId': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('groups')
          .doc(groupId)
          .set({
        'groupId': groupId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(currentUser.uid)
          .set({
        'userId': currentUser.uid,
        'customId': _currentUserCustomId,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      await _addChat(
        groupId,
        'Group $groupId',
        'assets/group_icon.png',
        isGroup: true,
      );

      setState(() {
        _createdGroups.add({
          'groupId': groupId,
          'name': 'Group $groupId',
          'photoURL': 'assets/group_icon.png',
          'description': '',
        });
      });

      _showSuccessSnackBar('Group $groupId created successfully!');

      Clipboard.setData(ClipboardData(text: groupId));
      _showSuccessSnackBar('Group ID $groupId copied to clipboard');
    } catch (e) {
      _showErrorSnackBar('Failed to create group: $e');
    }
  }

  Future<void> _modifyGroup(String groupId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final groupDoc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .get();
    if (!groupDoc.exists || groupDoc['creatorId'] != currentUser.uid) {
      _showErrorSnackBar('Only the group creator can modify group details');
      return;
    }

    final nameController = TextEditingController(text: groupDoc['name']);
    final descriptionController = TextEditingController(text: groupDoc['description']);
    String? base64Image = groupDoc['photoURL'].startsWith('data:image') ? groupDoc['photoURL'] : null;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF6C63FF).withOpacity(0.08),
                const Color(0xFF4ECDC4).withOpacity(0.08),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  color: Color(0xFF6C63FF),
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Modify Group Details',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 28),
              _buildModernTextField(nameController, 'Group Name', Icons.group_rounded),
              const SizedBox(height: 20),
              _buildModernTextField(descriptionController, 'Group Description', Icons.description_rounded, maxLines: 3),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                    if (pickedFile != null) {
                      final bytes = await File(pickedFile.path).readAsBytes();
                      base64Image = 'data:image/png;base64,${base64Encode(bytes)}';
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.image_rounded, color: Colors.white, size: 20),
                  label: const Text('Pick Group Image', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w600, fontSize: 15)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await FirebaseFirestore.instance
                              .collection('groups')
                              .doc(groupId)
                              .update({
                            'name': nameController.text.trim(),
                            'description': descriptionController.text.trim(),
                            if (base64Image != null) 'photoURL': base64Image,
                          });

                          final memberDocs = await FirebaseFirestore.instance
                              .collection('groups')
                              .doc(groupId)
                              .collection('members')
                              .get();
                          for (var member in memberDocs.docs) {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(member['userId'])
                                .collection('chats')
                                .doc('chat_list')
                                .set({
                              'users': FieldValue.arrayUnion([
                                {
                                  'customId': groupId,
                                  'name': nameController.text.trim(),
                                  'photoURL': base64Image ?? 'assets/group_icon.png',
                                  'isGroup': true,
                                }
                              ])
                            }, SetOptions(merge: true));
                          }

                          setState(() {
                            final index = _createdGroups.indexWhere((g) => g['groupId'] == groupId);
                            if (index != -1) {
                              _createdGroups[index] = {
                                'groupId': groupId,
                                'name': nameController.text.trim(),
                                'photoURL': base64Image ?? 'assets/group_icon.png',
                                'description': descriptionController.text.trim(),
                              };
                            }
                          });

                          _showSuccessSnackBar('Group details updated successfully');
                          Navigator.pop(context);
                        } catch (e) {
                          _showErrorSnackBar('Failed to update group: $e');
                        }
                      },
                      child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4ECDC4),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernTextField(TextEditingController controller, String label, IconData icon, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF6C63FF), size: 18),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
          ),
          labelStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
        style: const TextStyle(fontSize: 15),
      ),
    );
  }

  Future<void> _deleteGroup(String groupId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final groupDoc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .get();
    if (!groupDoc.exists || groupDoc['creatorId'] != currentUser.uid) {
      _showErrorSnackBar('Only the group creator can delete the group');
      return;
    }

    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFFF6B6B).withOpacity(0.08),
                const Color(0xFFFF8E8E).withOpacity(0.08),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Color(0xFFFF6B6B),
                  size: 32,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Delete Group',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Are you sure you want to delete group ${groupDoc['name']} ($groupId)? This action cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w600, fontSize: 15)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B6B),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmDelete != true) return;

    try {
      await FirebaseFirestore.instance.collection('group_ids').doc(groupId).delete();
      await FirebaseFirestore.instance.collection('groups').doc(groupId).delete();

      final memberDocs = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .get();
      for (var member in memberDocs.docs) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(member['userId'])
            .collection('groups')
            .doc(groupId)
            .delete();

        final chatDocRef = FirebaseFirestore.instance
            .collection('users')
            .doc(member['userId'])
            .collection('chats')
            .doc('chat_list');
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final doc = await transaction.get(chatDocRef);
          if (doc.exists) {
            List<Map<String, dynamic>> updatedChatList =
            List<Map<String, dynamic>>.from(doc.data()?['users'] ?? []);
            updatedChatList.removeWhere((chat) => chat['customId'] == groupId);
            transaction.set(chatDocRef, {'users': updatedChatList}, SetOptions(merge: true));
          }
        });

        await FirebaseFirestore.instance
            .collection('users')
            .doc(member['userId'])
            .collection('messages')
            .doc(groupId)
            .delete();
      }

      setState(() {
        _createdGroups.removeWhere((group) => group['groupId'] == groupId);
      });

      _showSuccessSnackBar('Group $groupId deleted successfully');
    } catch (e) {
      _showErrorSnackBar('Failed to delete group: $e');
    }
  }

  Future<void> _addChat(String customId, String name, String photoURL, {bool isGroup = false}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _currentUserCustomId == null) return;

    try {
      final chatDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('chats')
          .doc('chat_list');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(chatDocRef);
        List<Map<String, dynamic>> updatedChatList = List<Map<String, dynamic>>.from(doc.data()?['users'] ?? []);
        final chatIndex = updatedChatList.indexWhere((chat) => chat['customId'] == customId);

        final chatData = {
          'customId': customId,
          'name': name,
          'photoURL': photoURL,
          'isGroup': isGroup,
        };

        if (chatIndex == -1) {
          updatedChatList.add(chatData);
        } else {
          updatedChatList[chatIndex] = chatData;
        }

        transaction.set(chatDocRef, {'users': updatedChatList}, SetOptions(merge: true));
      });
    } catch (e) {
      _showErrorSnackBar('Failed to add chat: $e');
    }
  }

  Future<void> _joinGroup(String groupId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _currentUserCustomId == null) return;

    try {
      final groupDoc = await FirebaseFirestore.instance
          .collection('group_ids')
          .doc(groupId)
          .get();

      if (!groupDoc.exists) {
        _showErrorSnackBar('Group $groupId does not exist');
        return;
      }

      final groupDetails = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();

      final groupDocRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(currentUser.uid);

      await groupDocRef.set({
        'userId': currentUser.uid,
        'customId': _currentUserCustomId,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('groups')
          .doc(groupId)
          .set({
        'groupId': groupId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _addChat(
        groupId,
        groupDetails['name'] ?? 'Group $groupId',
        groupDetails['photoURL'] ?? 'assets/group_icon.png',
        isGroup: true,
      );

      setState(() {
        if (!_createdGroups.any((group) => group['groupId'] == groupId)) {
          _createdGroups.add({
            'groupId': groupId,
            'name': groupDetails['name'] ?? 'Group $groupId',
            'photoURL': groupDetails['photoURL'] ?? 'assets/group_icon.png',
            'description': groupDetails['description'] ?? '',
          });
        }
      });

      _showSuccessSnackBar('Joined group $groupId successfully!');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatMessage(
            currentUserCustomId: _currentUserCustomId!,
            selectedCustomId: groupId,
            selectedUserName: groupDetails['name'] ?? 'Group $groupId',
            selectedUserPhotoURL: groupDetails['photoURL'] ?? 'assets/group_icon.png',
          ),
        ),
      );
    } catch (e) {
      _showErrorSnackBar('Failed to join group: $e');
    }
  }

  Future<void> _showGroupMembers(String groupId) async {
    try {
      final memberDocs = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .get();

      final members = <Map<String, dynamic>>[];
      for (var member in memberDocs.docs) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(member['userId'])
            .collection('profiledetails')
            .doc('profile')
            .get();
        members.add({
          'customId': member['customId'],
          'name': userDoc['name'] ?? 'Unknown',
        });
      }

      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF6C63FF).withOpacity(0.08),
                  const Color(0xFF4ECDC4).withOpacity(0.08),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.group_rounded,
                        color: Color(0xFF6C63FF),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Group Members',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.maxFinite,
                  height: 300,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF6C63FF),
                                    const Color(0xFF4ECDC4),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  member['name'][0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member['name'],
                                    style: const TextStyle(
                                      color: Color(0xFF2D3748),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID: ${member['customId']}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w600, fontSize: 15)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      _showErrorSnackBar('Failed to load group members: $e');
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    try {
      final idResult = await FirebaseFirestore.instance
          .collection('custom_ids')
          .where('customId', isEqualTo: query.toUpperCase())
          .get();

      final userDocs = <String, DocumentSnapshot>{};
      for (var customIdDoc in idResult.docs) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(customIdDoc['userId'])
            .collection('profiledetails')
            .doc('profile')
            .get();
        if (userDoc.exists) {
          userDocs[userDoc.reference.parent.parent!.id] = userDoc;
        }
      }

      setState(() {
        _searchResults = userDocs.values.toList();
      });
    } catch (e) {
      _showErrorSnackBar('Search failed: $e');
    }
  }

  Future<void> _searchGroups(String query) async {
    if (query.isEmpty) {
      setState(() {
        _groupSearchResults = [];
      });
      return;
    }

    try {
      final groupResult = await FirebaseFirestore.instance
          .collection('group_ids')
          .where('groupId', isEqualTo: query.toUpperCase())
          .get();

      setState(() {
        _groupSearchResults = groupResult.docs;
      });
    } catch (e) {
      _showErrorSnackBar('Group search failed: $e');
    }
  }

  void _copyCustomId() {
    if (_currentUserCustomId != null) {
      Clipboard.setData(ClipboardData(text: _currentUserCustomId!));
      _showSuccessSnackBar('ID $_currentUserCustomId copied to clipboard');
    }
  }

  void _shareCustomId() async {
    if (_currentUserCustomId != null) {
      try {
        await Share.share('My Chat ID: $_currentUserCustomId');
      } catch (e) {
        _showErrorSnackBar('Failed to share ID: $e');
      }
    }
  }

  void _copyGroupId(String groupId) {
    Clipboard.setData(ClipboardData(text: groupId));
    _showSuccessSnackBar('Group ID $groupId copied to clipboard');
  }

  void _shareGroupId(String groupId) async {
    try {
      await Share.share('Join my group chat! Group ID: $groupId');
    } catch (e) {
      _showErrorSnackBar('Failed to share group ID: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF8FAFF),
              Color(0xFFE8F4F8),
              Color(0xFFF0F8FF),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: CustomScrollView(
                slivers: [
                  // Header Section
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                      child: Column(
                        children: [
                          // App Title
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF6C63FF),
                                      const Color(0xFF4ECDC4),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF6C63FF).withOpacity(0.2),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 20),
                              const Text(
                                'ChatHub',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2D3748),
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // User ID Card
                          if (_currentUserCustomId != null)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF6C63FF),
                                    const Color(0xFF4ECDC4),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF6C63FF).withOpacity(0.3),
                                    blurRadius: 24,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Icon(
                                      Icons.badge_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Your Chat ID',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _currentUserCustomId!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: IconButton(
                                          icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
                                          onPressed: _copyCustomId,
                                          tooltip: 'Copy ID',
                                          padding: const EdgeInsets.all(12),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: IconButton(
                                          icon: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                                          onPressed: _shareCustomId,
                                          tooltip: 'Share ID',
                                          padding: const EdgeInsets.all(12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Search & Create Section
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          // Create Group Button
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4ECDC4).withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _createGroup,
                              icon: const Icon(Icons.group_add_rounded, color: Colors.white, size: 22),
                              label: const Text(
                                'Create New Group',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4ECDC4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                elevation: 0,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Search Fields
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Search users by ID (e.g., ABC123)',
                                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
                                prefixIcon: Container(
                                  margin: const EdgeInsets.all(16),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.search_rounded,
                                    color: Color(0xFF6C63FF),
                                    size: 20,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.1)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
                              ),
                              style: const TextStyle(fontSize: 15, color: Color(0xFF2D3748)),
                              onChanged: (query) => _searchUsers(query),
                            ),
                          ),

                          const SizedBox(height: 20),

                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _groupSearchController,
                              decoration: InputDecoration(
                                hintText: 'Join group by ID (e.g., ABC123)',
                                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
                                prefixIcon: Container(
                                  margin: const EdgeInsets.all(16),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4ECDC4).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.group_add_rounded,
                                    color: Color(0xFF4ECDC4),
                                    size: 20,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.1)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: const BorderSide(color: Color(0xFF4ECDC4), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
                              ),
                              style: const TextStyle(fontSize: 15, color: Color(0xFF2D3748)),
                              onSubmitted: (query) => _joinGroup(query.toUpperCase()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Your Groups Section
                  if (_createdGroups.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4ECDC4).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.group_work_rounded,
                                    color: Color(0xFF4ECDC4),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Your Groups',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2D3748),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            ..._createdGroups.map((group) {
                              final groupId = group['groupId'];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                const Color(0xFF4ECDC4),
                                                const Color(0xFF44A08D),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: const Icon(
                                            Icons.group_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                group['name'],
                                                style: const TextStyle(
                                                  color: Color(0xFF2D3748),
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'ID: $groupId',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF4ECDC4).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: IconButton(
                                              icon: const Icon(Icons.copy_rounded, color: Color(0xFF4ECDC4), size: 16),
                                              onPressed: () => _copyGroupId(groupId),
                                              padding: const EdgeInsets.all(12),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF6C63FF).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: IconButton(
                                              icon: const Icon(Icons.share_rounded, color: Color(0xFF6C63FF), size: 16),
                                              onPressed: () => _shareGroupId(groupId),
                                              padding: const EdgeInsets.all(12),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFB74D).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: IconButton(
                                              icon: const Icon(Icons.people_rounded, color: Color(0xFFFFB74D), size: 16),
                                              onPressed: () => _showGroupMembers(groupId),
                                              padding: const EdgeInsets.all(12),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        FutureBuilder<DocumentSnapshot>(
                                          future: FirebaseFirestore.instance
                                              .collection('groups')
                                              .doc(groupId)
                                              .get(),
                                          builder: (context, snapshot) {
                                            if (!snapshot.hasData || !snapshot.data!.exists) {
                                              return const SizedBox.shrink();
                                            }
                                            final isCreator = snapshot.data!['creatorId'] == currentUser?.uid;
                                            return Row(
                                              children: [
                                                if (isCreator) ...[
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF9C27B0).withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(16),
                                                    ),
                                                    child: IconButton(
                                                      icon: const Icon(Icons.edit_rounded, color: Color(0xFF9C27B0), size: 16),
                                                      onPressed: () => _modifyGroup(groupId),
                                                      padding: const EdgeInsets.all(12),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFFF6B6B).withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(16),
                                                    ),
                                                    child: IconButton(
                                                      icon: const Icon(Icons.delete_rounded, color: Color(0xFFFF6B6B), size: 16),
                                                      onPressed: () => _deleteGroup(groupId),
                                                      padding: const EdgeInsets.all(12),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),

                  // Search Results
                  if (_searchResults.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.search_rounded,
                                    color: Color(0xFF6C63FF),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Search Results',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2D3748),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Container(
                              height: 200,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final user = _searchResults[index];
                                  final userName = user['name'] ?? 'Unknown';
                                  final userPhotoURL = user['photoURL'] ?? 'assets/default_avatar.png';
                                  final userEmail = user['email'] ?? '';
                                  final userContact = user['phone'] ?? '';

                                  return FutureBuilder<DocumentSnapshot>(
                                    future: FirebaseFirestore.instance.collection('custom_ids').doc(user.reference.parent.parent!.id).get(),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) return const SizedBox.shrink();
                                      final customId = snapshot.data?['customId'] ?? 'Unknown';

                                      return Container(
                                        width: 280,
                                        margin: const EdgeInsets.only(right: 20),
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(24),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.04),
                                              blurRadius: 16,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 52,
                                                  height: 52,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        const Color(0xFF6C63FF),
                                                        const Color(0xFF4ECDC4),
                                                      ],
                                                    ),
                                                  ),
                                                  child: ClipOval(
                                                    child: userPhotoURL.startsWith('assets/')
                                                        ? Image.asset(userPhotoURL, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 24))
                                                        : Image.network(userPhotoURL, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 24)),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        userName,
                                                        style: const TextStyle(
                                                          color: Color(0xFF2D3748),
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'ID: $customId',
                                                        style: TextStyle(
                                                          color: Colors.grey[600],
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            if (userEmail.isNotEmpty) ...[
                                              Text(
                                                userEmail,
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 13,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                            ],
                                            if (userContact.isNotEmpty) ...[
                                              Text(
                                                userContact,
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                            ],
                                            const Spacer(),
                                            Container(
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(20),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFF6C63FF).withOpacity(0.2),
                                                    blurRadius: 12,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  _addChat(customId, userName, userPhotoURL);
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => ChatMessage(
                                                        currentUserCustomId: _currentUserCustomId!,
                                                        selectedCustomId: customId,
                                                        selectedUserName: userName,
                                                        selectedUserPhotoURL: userPhotoURL,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: const Text(
                                                  'Start Chat',
                                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF6C63FF),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                                  elevation: 0,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Recent Chats Section
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.chat_rounded,
                              color: Color(0xFF6C63FF),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Recent Chats',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2D3748),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Chat List
                  StreamBuilder<DocumentSnapshot>(
                    stream: currentUser != null
                        ? FirebaseFirestore.instance
                        .collection('users')
                        .doc(currentUser.uid)
                        .collection('chats')
                        .doc('chat_list')
                        .snapshots()
                        : Stream.empty(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: CircularProgressIndicator(
                                color: Color(0xFF6C63FF),
                                strokeWidth: 3,
                              ),
                            ),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return SliverToBoxAdapter(
                          child: Container(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6B6B).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Icon(
                                    Icons.error_outline_rounded,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Error loading chats',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData || !snapshot.data!.exists) {
                        return SliverToBoxAdapter(
                          child: Container(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(32),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(32),
                                  ),
                                  child: Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 48,
                                    color: const Color(0xFF6C63FF).withOpacity(0.6),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'No chats yet',
                                  style: TextStyle(
                                    color: Color(0xFF2D3748),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Search for users or join groups to start chatting',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final chatList = List<Map<String, dynamic>>.from(snapshot.data!['users'] ?? []);

                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) {
                              final chat = chatList[index];
                              final isGroup = chat['isGroup'] ?? false;
                              final chatId = chat['customId'];
                              final unreadCount = _unreadMessageCounts[chatId] ?? 0;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(24),
                                    onTap: () {
                                      _resetUnreadCount(chatId);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ChatMessage(
                                            currentUserCustomId: _currentUserCustomId!,
                                            selectedCustomId: chat['customId'],
                                            selectedUserName: chat['name'],
                                            selectedUserPhotoURL: chat['photoURL'],
                                          ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Row(
                                        children: [
                                          // Avatar with unread badge
                                          Stack(
                                            children: [
                                              Container(
                                                width: 58,
                                                height: 58,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(
                                                    colors: isGroup
                                                        ? [const Color(0xFF4ECDC4), const Color(0xFF44A08D)]
                                                        : [const Color(0xFF6C63FF), const Color(0xFF9C88FF)],
                                                  ),
                                                ),
                                                child: ClipOval(
                                                  child: chat['photoURL'].startsWith('assets/')
                                                      ? Image.asset(
                                                    chat['photoURL'],
                                                    width: 58,
                                                    height: 58,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Icon(
                                                      isGroup ? Icons.group_rounded : Icons.person_rounded,
                                                      color: Colors.white,
                                                      size: 28,
                                                    ),
                                                  )
                                                      : chat['photoURL'].startsWith('data:image')
                                                      ? Image.memory(
                                                    base64Decode(chat['photoURL'].split(',')[1]),
                                                    width: 58,
                                                    height: 58,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Icon(
                                                      isGroup ? Icons.group_rounded : Icons.person_rounded,
                                                      color: Colors.white,
                                                      size: 28,
                                                    ),
                                                  )
                                                      : Image.network(
                                                    chat['photoURL'],
                                                    width: 58,
                                                    height: 58,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Icon(
                                                      isGroup ? Icons.group_rounded : Icons.person_rounded,
                                                      color: Colors.white,
                                                      size: 28,
                                                    ),
                                                  ),
                                                ),
                                              ),

                                              // Unread badge
                                              if (unreadCount > 0)
                                                Positioned(
                                                  right: 0,
                                                  top: 0,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFFF6B6B),
                                                      borderRadius: BorderRadius.circular(16),
                                                      border: Border.all(color: Colors.white, width: 3),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: const Color(0xFFFF6B6B).withOpacity(0.3),
                                                          blurRadius: 8,
                                                          offset: const Offset(0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                    constraints: const BoxConstraints(
                                                      minWidth: 22,
                                                      minHeight: 22,
                                                    ),
                                                    child: Text(
                                                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),

                                          const SizedBox(width: 20),

                                          // Chat info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  chat['name'],
                                                  style: TextStyle(
                                                    color: const Color(0xFF2D3748),
                                                    fontSize: 17,
                                                    fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 6),
                                                isGroup
                                                    ? FutureBuilder<DocumentSnapshot>(
                                                  future: FirebaseFirestore.instance
                                                      .collection('groups')
                                                      .doc(chat['customId'])
                                                      .get(),
                                                  builder: (context, groupSnapshot) {
                                                    if (!groupSnapshot.hasData) return const SizedBox.shrink();
                                                    final description = groupSnapshot.data?['description'] ?? '';
                                                    return Text(
                                                      description.isNotEmpty ? description : 'Group Chat • ${chat['customId']}',
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 14,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    );
                                                  },
                                                )
                                                    : Text(
                                                  'ID: ${chat['customId']}',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Arrow icon
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              color: Colors.grey[500],
                                              size: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                            childCount: chatList.length,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}