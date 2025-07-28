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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _groupSearchController = TextEditingController();
  String? _currentUserCustomId;
  List<DocumentSnapshot> _searchResults = [];
  List<DocumentSnapshot> _groupSearchResults = [];
  List<Map<String, dynamic>> _createdGroups = [];

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

    // Clear badge when app comes to foreground if all messages are read
    if (state == AppLifecycleState.resumed) {
      int totalUnread = 0;
      _unreadMessageCounts.forEach((key, value) {
        totalUnread += value;
      });
      if (totalUnread == 0) {
      }
    }
  }

  // Load unread message counts from Firestore
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

  // Listen for unread count changes
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

  // Reset unread count when opening a chat
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

      // Update badge count after resetting
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

  // Initialize local notifications
  Future<void> _initializeNotifications() async {
    // Request notification permissions
    await _requestNotificationPermissions();

    // Android initialization settings with importance high for badges
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings with badge permission
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

    // Create notification channel for Android with badge support
    if (Platform.isAndroid) {
      await _createNotificationChannel();
    }

    // Clear any existing badges on app start
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  // Request notification permissions
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

  // Create notification channel for Android
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

  // Handle notification tap
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

  // Send local notification with badge count
  Future<void> _sendLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    required int badgeCount,
  }) async {
    try {
      // Calculate total unread messages across all chats
      int totalUnread = 0;
      _unreadMessageCounts.forEach((key, value) {
        totalUnread += value;
      });

      // Android notification with badge support
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
        color: const Color(0xFF00796B), // Teal color
        ledColor: const Color(0xFF00796B),
        ledOnMs: 1000,
        ledOffMs: 500,
        number: totalUnread, // This shows the badge count on Android
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: totalUnread > 1 ? '$totalUnread unread messages' : null,
        ),
      );

      // iOS notification with badge support
      DarwinNotificationDetails iOSPlatformChannelSpecifics =
      DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        badgeNumber: totalUnread, // This sets the app icon badge on iOS
      );

      NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      // Show notification even when app is in foreground for better UX
      await flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        platformChannelSpecifics,
        payload: jsonEncode(payload),
      );

      // Update app badge number
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

      // Start listening for unread counts after getting custom ID
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

    // Check if this is actually a new message
    bool isNewMessage = false;

    if (lastTimestamp == null) {
      // First time seeing this message
      isNewMessage = true;
    } else if (currentTimestamp != null && lastTimestamp != null) {
      // Compare timestamps to see if message was updated
      if (currentTimestamp is Timestamp && lastTimestamp is Timestamp) {
        isNewMessage = currentTimestamp.millisecondsSinceEpoch > lastTimestamp.millisecondsSinceEpoch;
      }
    }

    // Update our local timestamp record
    _lastMessageTimestamps[messageId] = currentTimestamp;

    // Only show notification and increment unread count for genuinely new messages
    if (isNewMessage && !_processedMessageIds.contains(messageId)) {
      _processedMessageIds.add(messageId);

      // Don't increment if message is from current user
      if (data['senderCustomId'] != _currentUserCustomId) {
        // Increment unread count
        await _incrementUnreadCount(messageId);
      }

      _showNewMessageNotification(data);
    }
  }

  // Increment unread count for a chat
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
    // Don't show notifications if the message is from the current user
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
        // Truncate long messages
        if (notificationContent.length > 100) {
          notificationContent = '${notificationContent.substring(0, 97)}...';
        }
    }

    final bool isGroup = data['groupId'] != null;
    final String chatName = isGroup
        ? (data['groupName'] ?? 'Group $chatId')
        : senderName;

    // Prepare notification title and body
    String notificationTitle;
    String notificationBody;

    if (isGroup) {
      notificationTitle = chatName;
      notificationBody = '$senderName: $notificationContent';
    } else {
      notificationTitle = senderName;
      notificationBody = notificationContent;
    }

    // Get current unread count for this chat
    int chatUnreadCount = _unreadMessageCounts[chatId] ?? 0;

    // Send local notification with badge count
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

    // Show in-app notification if app is in foreground
    if (_isAppInForeground && mounted) {
      // Calculate total unread for display
      int totalUnread = 0;
      _unreadMessageCounts.forEach((key, value) {
        totalUnread += value;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notificationTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notificationBody,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (chatUnreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    chatUnreadCount > 99 ? '99+' : chatUnreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          backgroundColor: Colors.teal[700],
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () => _navigateToChat(chatId, chatName, data),
          ),
        ),
      );

      // Play notification feedback
      _playNotificationFeedback();
    }
  }

  void _playNotificationFeedback() {
    // Add haptic feedback
    HapticFeedback.lightImpact();

    // Play system sound
    SystemSound.play(SystemSoundType.click);
  }

  void _navigateToChat(String chatId, String chatName, Map<String, dynamic> data) {
    // Reset unread count when navigating to chat
    _resetUnreadCount(chatId);

    // Navigate to the specific chat
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
          content: Text(message),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.teal[700],
          duration: const Duration(seconds: 3),
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
      builder: (context) => AlertDialog(
        title: const Text('Modify Group Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Group Name'),
              ),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Group Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  final picker = ImagePicker();
                  final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                  if (pickedFile != null) {
                    final bytes = await File(pickedFile.path).readAsBytes();
                    base64Image = 'data:image/png;base64,${base64Encode(bytes)}';
                    setState(() {});
                  }
                },
                child: const Text('Pick Group Image'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
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

                // Update chat list for all group members
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
            child: const Text('Save'),
          ),
        ],
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
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Are you sure you want to delete group ${groupDoc['name']} ($groupId)? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmDelete != true) return;

    try {
      // Delete from group_ids
      await FirebaseFirestore.instance
          .collection('group_ids')
          .doc(groupId)
          .delete();

      // Delete from groups
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .delete();

      // Delete from all members' groups and chat list
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

        // Remove from member's chat list
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

        // Delete last message notification
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
        builder: (context) => AlertDialog(
          title: const Text('Group Members'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                return ListTile(
                  title: Text(
                    member['name'],
                    style: TextStyle(
                      color: Colors.teal[900],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'ID: ${member['customId']}',
                    style: TextStyle(color: Colors.teal[600]),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFFB2DFDB), Colors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 16.0),
                child: Column(
                  children: [
                    const Text(
                      'Chat',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_currentUserCustomId != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Your ID: $_currentUserCustomId',
                              style: TextStyle(
                                color: Colors.teal[900],
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: Icon(Icons.copy, color: Colors.teal[700], size: 28),
                              onPressed: _copyCustomId,
                              tooltip: 'Copy ID',
                            ),
                            IconButton(
                              icon: Icon(Icons.share, color: Colors.teal[700], size: 28),
                              onPressed: _shareCustomId,
                              tooltip: 'Share ID',
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _createGroup,
                      icon: Icon(Icons.group_add, color: Colors.white, size: 28),
                      label: const Text(
                        'Create Group Chat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[800],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        elevation: 6,
                        shadowColor: Colors.black26,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_createdGroups.isNotEmpty)
                      Column(
                        children: _createdGroups.map((group) {
                          final groupId = group['groupId'];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Group: ${group['name']}',
                                          style: TextStyle(
                                            color: Colors.teal[900],
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'ID: $groupId',
                                          style: TextStyle(
                                            color: Colors.teal[600],
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.copy, color: Colors.teal[700], size: 28),
                                        onPressed: () => _copyGroupId(groupId),
                                        tooltip: 'Copy Group ID',
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.share, color: Colors.teal[700], size: 28),
                                        onPressed: () => _shareGroupId(groupId),
                                        tooltip: 'Share Group ID',
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.group, color: Colors.teal[700], size: 28),
                                        onPressed: () => _showGroupMembers(groupId),
                                        tooltip: 'View Members',
                                      ),
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
                                              if (isCreator)
                                                IconButton(
                                                  icon: Icon(Icons.edit, color: Colors.teal[700], size: 28),
                                                  onPressed: () => _modifyGroup(groupId),
                                                  tooltip: 'Edit Group',
                                                ),
                                              if (isCreator)
                                                IconButton(
                                                  icon: Icon(Icons.delete, color: Colors.red[700], size: 28),
                                                  onPressed: () => _deleteGroup(groupId),
                                                  tooltip: 'Delete Group',
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Enter user ID (e.g., ABC123)',
                    hintStyle: TextStyle(color: Colors.teal[500], fontSize: 18),
                    prefixIcon: Icon(Icons.search, color: Colors.teal[800], size: 30),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.teal[400]!, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.teal[800]!, width: 3),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                  ),
                  style: TextStyle(fontSize: 18, color: Colors.teal[900]),
                  onChanged: (query) {
                    _searchUsers(query);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: TextField(
                  controller: _groupSearchController,
                  decoration: InputDecoration(
                    hintText: 'Enter group ID (e.g., ABC123)',
                    hintStyle: TextStyle(color: Colors.teal[500], fontSize: 18),
                    prefixIcon: Icon(Icons.group, color: Colors.teal[800], size: 30),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.teal[400]!, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.teal[800]!, width: 3),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                  ),
                  style: TextStyle(fontSize: 18, color: Colors.teal[900]),
                  onSubmitted: (query) {
                    _joinGroup(query.toUpperCase());
                  },
                ),
              ),
              if (_searchResults.isNotEmpty)
                Container(
                  height: 140,
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final user = _searchResults[index];
                      final userName = user['name'] ?? 'Unknown';
                      final userPhotoURL = user['photoURL'] ?? 'assets/default_avatar.png';
                      final userGmail = user['email'] ?? '';
                      final userContact = user['phone'] ?? '';
                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('custom_ids').doc(user.reference.parent.parent!.id).get(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox.shrink();
                          final customId = snapshot.data?['customId'] ?? 'Unknown';
                          return Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            color: Colors.white.withOpacity(0.95),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: userPhotoURL.startsWith('assets/')
                                    ? AssetImage(userPhotoURL) as ImageProvider
                                    : NetworkImage(userPhotoURL),
                                radius: 20,
                                onBackgroundImageError: (_, __) => AssetImage('assets/default_avatar.png'),
                              ),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userName,
                                    style: TextStyle(
                                      color: Colors.teal[900],
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Email: $userGmail\nPhone: $userContact',
                                    style: TextStyle(
                                      color: Colors.teal[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'ID: $customId',
                                style: TextStyle(
                                  color: Colors.teal[800],
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () {
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
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
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
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading chats: ${snapshot.error}',
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      );
                    }
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return const Center(
                        child: Text(
                          'No chats available',
                          style: TextStyle(color: Colors.teal, fontSize: 16),
                        ),
                      );
                    }

                    final chatList = List<Map<String, dynamic>>.from(snapshot.data!['users'] ?? []);

                    return ListView.builder(
                      itemCount: chatList.length,
                      itemBuilder: (context, index) {
                        final chat = chatList[index];
                        final isGroup = chat['isGroup'] ?? false;
                        final chatId = chat['customId'];
                        final unreadCount = _unreadMessageCounts[chatId] ?? 0;

                        return Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          color: Colors.white.withOpacity(0.95),
                          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
                          child: ListTile(
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  backgroundImage: chat['photoURL'].startsWith('assets/')
                                      ? AssetImage(chat['photoURL']) as ImageProvider
                                      : (chat['photoURL'].startsWith('data:image')
                                      ? MemoryImage(base64Decode(chat['photoURL'].split(',')[1]))
                                      : NetworkImage(chat['photoURL'])) as ImageProvider,
                                  radius: 20,
                                  onBackgroundImageError: (_, __) => AssetImage('assets/default_avatar.png'),
                                ),
                                // Unread message badge
                                if (unreadCount > 0)
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 20,
                                        minHeight: 20,
                                      ),
                                      child: Center(
                                        child: Text(
                                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              chat['name'],
                              style: TextStyle(
                                color: Colors.teal[900],
                                fontSize: 18,
                                fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w600,
                              ),
                            ),
                            subtitle: isGroup
                                ? FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('groups')
                                  .doc(chat['customId'])
                                  .get(),
                              builder: (context, groupSnapshot) {
                                if (!groupSnapshot.hasData) return const SizedBox.shrink();
                                final description = groupSnapshot.data?['description'] ?? '';
                                return Text(
                                  description.isNotEmpty ? description : 'Group ID: ${chat['customId']}',
                                  style: TextStyle(
                                    color: Colors.teal[800],
                                    fontSize: 12,
                                  ),
                                );
                              },
                            )
                                : Text(
                              'ID: ${chat['customId']}',
                              style: TextStyle(
                                color: Colors.teal[800],
                                fontSize: 12,
                              ),
                            ),
                            onTap: () {
                              // Reset unread count when opening chat
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
    );
  }
}