import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'DailySummaryPage.dart';
import 'WeeklySummaryPage.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  static GlobalKey<NavigatorState>? _navigatorKey;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Stream subscription for listening to new notifications
  StreamSubscription<QuerySnapshot>? _notificationSubscription;
  Timer? _scheduledNotificationTimer;
  Timer? _permissionCheckTimer;

  // Track processed notifications to avoid duplicates
  final Set<String> _processedNotifications = <String>{};

  // Add retry mechanism
  final Map<String, int> _retryAttempts = <String, int>{};
  static const int maxRetries = 3;

  // Notification channels
  static const String highPriorityChannel = 'high_priority_channel';
  static const String defaultChannel = 'default_channel';
  static const String summaryChannel = 'summary_channel';

  // Notification types
  static const String typeJobApplication = 'job_application';
  static const String typeCompletionRequest = 'completion_request';
  static const String typeDeadlineWarning = 'deadline_warning';
  static const String typeTaskAssigned = 'task_assigned';
  static const String typeStatusChanged = 'status_changed';
  static const String typePriorityAlert = 'priority_alert';
  static const String typeDailySummary = 'daily_summary';
  static const String typeWeeklySummary = 'weekly_summary';
  static const String typeJobCreated = 'job_created';
  static const String typeTaskDeadline = 'task_deadline';

  Future<void> initialize() async {
    try {
      print('Initializing NotificationService...');

      // Initialize timezone first
      tz.initializeTimeZones();
      print('Timezone initialized');

      // Request notification permissions FIRST with better error handling
      final permissionGranted = await _requestNotificationPermissionsEnhanced();
      print('Notification permission granted: $permissionGranted');

      // Initialize local notifications with better error handling
      await _initializeLocalNotifications();
      print('Flutter local notifications initialized');

      // Create notification channels
      await _createNotificationChannels();
      print('Notification channels created');

      // Initialize Firebase Messaging
      await _initializeFirebaseMessaging();
      print('Firebase messaging initialized');

      // Start listening to Firestore notifications with retry
      await _startListeningToFirestoreNotificationsEnhanced();
      print('Firestore notification listener started');

      // Start timer to check scheduled notifications every minute
      _scheduledNotificationTimer = Timer.periodic(
        const Duration(minutes: 1),
            (timer) => _processScheduledNotificationsEnhanced(),
      );
      print('Scheduled notification timer started');

      // Start permission check timer
      _permissionCheckTimer = Timer.periodic(
        const Duration(minutes: 10),
            (timer) => _checkAndRequestPermissions(),
      );
      print('Permission check timer started');

      // Initialize enhanced summary notifications
      await EnhancedSummaryNotificationService.initializeEnhancedSummaryNotifications();
      print('🚀 Enhanced summary notification service initialized');

      // Check immediately on startup
      _processScheduledNotificationsEnhanced();

      _isInitialized = true;
      print('✅ Enhanced summary notification service initialized');
      print('NotificationService initialization completed successfully');

    } catch (e) {
      print('Error initializing NotificationService: $e');
      print('Stack trace: ${StackTrace.current}');
      _isInitialized = false;
    }
  }

  Future<void> runNotificationTestSuite() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('No user logged in for testing');
      return;
    }

    print('🧪 Starting comprehensive notification test suite...');

    try {
      // Test 1: Basic notification
      print('Test 1: Basic notification');
      await createFirestoreNotification(
        userId: user.uid,
        title: '✅ Test 1: Basic Notification',
        body: 'This tests basic notification functionality with normal priority',
        data: {'test': '1', 'type': 'basic'},
        priority: NotificationPriority.normal,
      );
      await Future.delayed(const Duration(seconds: 2));

      // Test 2: Urgent notification
      print('Test 2: Urgent notification');
      await testUrgentNotification();
      await Future.delayed(const Duration(seconds: 3));

      // Test 3: Scheduled notification
      print('Test 3: Scheduled notification (30 seconds)');
      await createFirestoreNotification(
        userId: user.uid,
        title: '⏰ Test 3: Scheduled Notification',
        body: 'This notification was scheduled for 30 seconds after the test started',
        data: {'test': '3', 'type': 'scheduled'},
        priority: NotificationPriority.high,
        sendImmediately: false,
        scheduledFor: DateTime.now().add(const Duration(seconds: 30)),
      );

      // Test 4: Daily summary
      print('Test 4: Daily summary');
      await testDailySummary();
      await Future.delayed(const Duration(seconds: 2));

      // Test 5: Weekly summary
      print('Test 5: Weekly summary');
      await testWeeklySummary();

      print('🎉 Test suite completed! Check your notifications.');
      print('Note: Scheduled notification will appear in 30 seconds.');

    } catch (e) {
      print('❌ Test suite failed: $e');
      throw e;
    }
  }

  Future<void> testScheduledNotification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await createFirestoreNotification(
        userId: user.uid,
        title: '⏰ Scheduled Test Notification',
        body: 'This notification was scheduled for 30 seconds from when you pressed the test button!',
        data: {
          'type': 'test_scheduled',
          'scheduledTime': DateTime.now().add(const Duration(seconds: 30)).toIso8601String(),
          'testMessage': 'If you see this, scheduled notifications are working correctly!',
        },
        priority: NotificationPriority.high,
        sendImmediately: false,
        scheduledFor: DateTime.now().add(const Duration(seconds: 30)),
      );

      print('Scheduled notification created for 30 seconds from now');
    } catch (e) {
      print('Error creating scheduled test notification: $e');
      throw e;
    }
  }

  // Enhanced initialization for local notifications
  Future<void> _initializeLocalNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initializationSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final bool? initialized = await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      if (initialized != true) {
        throw Exception('Failed to initialize flutter_local_notifications');
      }

      // Test notification capability immediately
      await _testNotificationCapability();
    } catch (e) {
      print('Error initializing local notifications: $e');
      throw e;
    }
  }

  // Test if notifications can be shown
  Future<void> _testNotificationCapability() async {
    try {
      final hasPermission = await _checkNotificationPermissions();
      print('Notification capability test - Has permission: $hasPermission');

      if (hasPermission) {
        // Show a silent test notification that auto-cancels
        await _flutterLocalNotificationsPlugin.show(
          999999, // High ID to avoid conflicts
          'System Test',
          'Notification system ready',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'test_channel',
              'Test Channel',
              importance: Importance.min,
              priority: Priority.min,
              showWhen: false,
              autoCancel: true,
              playSound: false,
              enableVibration: false,
            ),
          ),
        );

        // Cancel the test notification after 1 second
        Timer(const Duration(seconds: 1), () {
          _flutterLocalNotificationsPlugin.cancel(999999);
        });

        print('✅ Notification capability test passed');
      }
    } catch (e) {
      print('⚠️ Notification capability test failed: $e');
    }
  }

  // Enhanced permission handling
  Future<bool> _requestNotificationPermissionsEnhanced() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        print('Android SDK: ${androidInfo.version.sdkInt}');

        // Android 13+ requires explicit notification permission
        if (androidInfo.version.sdkInt >= 33) {
          final status = await Permission.notification.request();
          print('Android 13+ notification permission status: $status');

          if (!status.isGranted) {
            if (status.isPermanentlyDenied) {
              print('Notification permission permanently denied - opening settings');
              await openAppSettings();
            }
            return false;
          }
        }

        // Check if notifications are enabled at system level
        final androidPlugin = _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin != null) {
          final areEnabled = await androidPlugin.areNotificationsEnabled();
          print('System notifications enabled: $areEnabled');
          return areEnabled ?? false;
        }
      }

      // iOS permission handling
      if (Platform.isIOS) {
        final settings = await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        print('iOS notification permission status: ${settings.authorizationStatus}');
        return settings.authorizationStatus == AuthorizationStatus.authorized;
      }

      return true;
    } catch (e) {
      print('Error requesting notification permissions: $e');
      return false;
    }
  }

  // Enhanced permission checking
  Future<bool> _checkNotificationPermissions() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 33) {
          final status = await Permission.notification.status;
          if (!status.isGranted) return false;
        }

        final androidPlugin = _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin != null) {
          final areEnabled = await androidPlugin.areNotificationsEnabled();
          return areEnabled ?? false;
        }
      }

      return true;
    } catch (e) {
      print('Error checking notification permissions: $e');
      return false;
    }
  }

  // Periodic permission check
  Future<void> _checkAndRequestPermissions() async {
    final hasPermissions = await _checkNotificationPermissions();
    if (!hasPermissions) {
      print('⚠️ Notification permissions lost - attempting to request again');
      await _requestNotificationPermissionsEnhanced();
    }
  }

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  // Enhanced Firestore listener with better error handling and deduplication
  Future<void> _startListeningToFirestoreNotificationsEnhanced() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('No user authenticated - cannot listen to notifications');
      return;
    }

    print('Starting to listen for notifications for user: ${user.uid}');

    _notificationSubscription?.cancel(); // Cancel any existing subscription

    _notificationSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('sent', isEqualTo: false)
        .orderBy('timestamp', descending: false) // Process oldest first
        .snapshots()
        .listen(
          (snapshot) async {
        print('Firestore notification snapshot received with ${snapshot.docs.length} documents');

        // Process only new notifications
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final doc = change.doc;
            final docId = doc.id;

            // Skip if already processed
            if (_processedNotifications.contains(docId)) {
              print('Notification $docId already processed, skipping');
              continue;
            }

            final notification = doc.data() as Map<String, dynamic>;
            await _processFirestoreNotificationEnhanced(docId, notification);
          }
        }
      },
      onError: (error) {
        print('Error listening to Firestore notifications: $error');
        // Restart listener after a delay
        Timer(const Duration(seconds: 5), () {
          print('Restarting Firestore notification listener...');
          _startListeningToFirestoreNotificationsEnhanced();
        });
      },
      cancelOnError: false,
    );
  }

  // Enhanced notification processing with retry logic
  Future<void> _processFirestoreNotificationEnhanced(String docId, Map<String, dynamic> notificationData) async {
    try {
      print('Processing Firestore notification: ${notificationData['title']}');

      // Check if should send immediately or is scheduled
      final sendImmediately = notificationData['sendImmediately'] as bool? ?? true;
      final scheduledForString = notificationData['scheduledFor'] as String?;

      if (!sendImmediately && scheduledForString != null) {
        final scheduledFor = DateTime.parse(scheduledForString);
        final now = DateTime.now();

        if (now.isBefore(scheduledFor)) {
          print('Notification scheduled for later: ${notificationData['title']} at $scheduledFor');
          return; // Don't process yet
        }
      }

      // Mark as processed to avoid duplicates
      _processedNotifications.add(docId);

      final title = notificationData['title'] as String? ?? 'Notification';
      final body = notificationData['body'] as String? ?? '';
      final data = notificationData['data'] as Map<String, dynamic>? ?? {};
      final priorityString = notificationData['priority'] as String? ?? 'normal';

      // Convert priority string to enum
      final priority = _stringToNotificationPriority(priorityString);

      // Check permissions before showing
      final hasPermissions = await _checkNotificationPermissions();
      if (!hasPermissions) {
        print('⚠️ No notification permissions - attempting to request');
        final granted = await _requestNotificationPermissionsEnhanced();
        if (!granted) {
          print('❌ Cannot show notification - no permissions');
          // Still mark as sent to avoid retrying
          await _markNotificationAsSent(docId);
          return;
        }
      }

      // Show the local notification with retry
      bool success = false;
      int attempts = 0;

      while (!success && attempts < maxRetries) {
        try {
          attempts++;
          await _showLocalNotificationEnhanced(
            title: title,
            body: body,
            payload: jsonEncode(data),
            priority: priority,
            docId: docId,
          );
          success = true;
          print('✅ Notification shown successfully on attempt $attempts');
        } catch (e) {
          print('❌ Attempt $attempts failed: $e');
          if (attempts < maxRetries) {
            await Future.delayed(Duration(seconds: attempts * 2)); // Exponential backoff
          }
        }
      }

      if (success) {
        // Mark as sent in Firestore
        await _markNotificationAsSent(docId);
        print('Notification processed and sent: $title');
      } else {
        print('❌ Failed to show notification after $maxRetries attempts');
        // Remove from processed set so it can be retried later
        _processedNotifications.remove(docId);
      }

    } catch (e) {
      print('Error processing Firestore notification: $e');
      // Remove from processed set so it can be retried
      _processedNotifications.remove(docId);
    }
  }

  // Enhanced local notification display
  Future<void> _showLocalNotificationEnhanced({
    required String title,
    required String body,
    required String payload,
    NotificationPriority priority = NotificationPriority.normal,
    bool showBigText = false,
    String? docId,
  }) async {
    try {
      print('Showing local notification: $title with priority: $priority');

      if (!_isInitialized) {
        throw Exception('Notification service not initialized');
      }

      // Double-check permissions
      final hasPermission = await _checkNotificationPermissions();
      if (!hasPermission) {
        throw Exception('No notification permissions');
      }

      // Generate unique ID
      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);

      // Enhanced notification details
      final notificationDetails = _getNotificationDetailsEnhanced(priority, showBigText: showBigText);

      await _flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      print('Local notification shown with ID: $id, Priority: $priority');

      // Log success for debugging
      if (docId != null) {
        print('✅ Successfully showed notification for doc: $docId');
      }

    } catch (e) {
      print('Error showing local notification: $e');
      print('Stack trace: ${StackTrace.current}');
      throw e; // Re-throw to trigger retry logic
    }
  }

  // Enhanced notification details with better Android 13+ support
  NotificationDetails _getNotificationDetailsEnhanced(NotificationPriority priority, {bool showBigText = false}) {
    final isUrgent = priority == NotificationPriority.urgent;
    final isHigh = priority == NotificationPriority.high;

    final androidDetails = AndroidNotificationDetails(
      _getChannelForPriority(priority),
      _getChannelNameForPriority(priority),
      channelDescription: 'Task management notifications',
      importance: _getImportanceForPriority(priority),
      priority: _getPriorityForNotificationPriority(priority),
      icon: '@mipmap/ic_launcher',
      color: isUrgent ? Colors.red : (isHigh ? Colors.orange : const Color(0xFF006D77)),
      ledColor: isUrgent ? Colors.red : (isHigh ? Colors.orange : const Color(0xFF006D77)),
      ledOnMs: isUrgent ? 1000 : 300,
      ledOffMs: isUrgent ? 500 : 1000,
      enableLights: true,
      enableVibration: true,
      playSound: true,
      vibrationPattern: isUrgent
          ? Int64List.fromList([0, 1000, 500, 1000, 500, 1000])
          : (isHigh ? Int64List.fromList([0, 500, 200, 500]) : null),
      styleInformation: showBigText
          ? BigTextStyleInformation(
        '',
        htmlFormatBigText: true,
        contentTitle: '',
        htmlFormatContentTitle: true,
      )
          : const DefaultStyleInformation(true, true),
      fullScreenIntent: isUrgent,
      visibility: NotificationVisibility.public,
      autoCancel: !isUrgent,
      ongoing: isUrgent,
      ticker: isUrgent ? '🚨 URGENT' : null,
      channelShowBadge: true,
      category: isUrgent
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.message,
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      // Android 13+ enhancements
      timeoutAfter: isUrgent ? null : 30000, // Auto-dismiss non-urgent after 30s
      groupKey: 'task_notifications',
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: isUrgent
          ? InterruptionLevel.critical
          : (isHigh ? InterruptionLevel.timeSensitive : InterruptionLevel.active),
      badgeNumber: null,
    );

    return NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  // Enhanced scheduled notification processing
  Future<void> _processScheduledNotificationsEnhanced() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final now = DateTime.now();
      print('🔄 Processing scheduled notifications at ${now.toString()}');

      // Query for scheduled notifications whose time has come
      final scheduledQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('sent', isEqualTo: false)
          .where('sendImmediately', isEqualTo: false)
          .limit(20) // Process in batches
          .get();

      int processed = 0;
      for (var doc in scheduledQuery.docs) {
        final data = doc.data();
        final scheduledForString = data['scheduledFor'] as String?;

        if (scheduledForString != null) {
          final scheduledFor = DateTime.parse(scheduledForString);

          if (now.isAfter(scheduledFor) || now.isAtSameMomentAs(scheduledFor)) {
            print('⏰ Processing scheduled notification: ${data['title']} (was scheduled for $scheduledFor)');
            await _processFirestoreNotificationEnhanced(doc.id, data);
            processed++;
          }
        }
      }

      if (processed > 0) {
        print('✅ Processed $processed scheduled notifications');
      }

    } catch (e) {
      print('❌ Error processing scheduled notifications: $e');
    }
  }

  // Mark notification as sent with retry
  Future<void> _markNotificationAsSent(String docId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .doc(docId)
          .update({
        'sent': true,
        'sentAt': FieldValue.serverTimestamp(),
      });

      print('Notification marked as sent: $docId');
    } catch (e) {
      print('Error marking notification as sent: $e');
      // Don't throw here - we don't want to fail the entire process
    }
  }

  // Create notification in Firestore with validation
  Future<void> createFirestoreNotification({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    NotificationPriority priority = NotificationPriority.normal,
    bool sendImmediately = true,
    DateTime? scheduledFor,
  }) async {
    try {
      print('Creating Firestore notification for user: $userId, title: $title');

      // Validate inputs
      if (userId.isEmpty || title.isEmpty) {
        throw ArgumentError('UserId and title cannot be empty');
      }

      final notificationData = {
        'title': title,
        'body': body,
        'data': data,
        'priority': priority.toString().split('.').last,
        'timestamp': FieldValue.serverTimestamp(),
        'sent': false,
        'read': false,
        'sendImmediately': sendImmediately,
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
        'version': 2, // Version for tracking
      };

      // Handle scheduling
      if (scheduledFor != null) {
        if (scheduledFor.isAfter(DateTime.now())) {
          notificationData['scheduledFor'] = scheduledFor.toIso8601String();
          notificationData['sendImmediately'] = false;
          print('Notification scheduled for: ${scheduledFor.toIso8601String()}');
        } else {
          print('Scheduled time is in the past, sending immediately');
          notificationData['sendImmediately'] = true;
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .add(notificationData);

      print('Notification created in Firestore successfully');
    } catch (e) {
      print('Error creating Firestore notification: $e');
      throw e;
    }
  }

  // Enhanced notification channel creation
  Future<void> _createNotificationChannels() async {
    final androidPlugin = _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // High priority channel for urgent notifications
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          highPriorityChannel,
          'High Priority Notifications',
          description: 'Urgent alerts and deadline warnings',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          showBadge: true,
        ),
      );

      // Default channel with high importance
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          defaultChannel,
          'Default Notifications',
          description: 'Regular task updates and reminders',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );

      // Summary channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          summaryChannel,
          'Summary Notifications',
          description: 'Daily and weekly task summaries',
          importance: Importance.low,
          showBadge: true,
        ),
      );

      print('✅ All notification channels created successfully');
    }
  }

  // Firebase Messaging initialization
  Future<void> _initializeFirebaseMessaging() async {
    try {
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _saveFCMToken(token);
      }

      _firebaseMessaging.onTokenRefresh.listen(_saveFCMToken);
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    } catch (e) {
      print('Error initializing Firebase Messaging: $e');
    }
  }

  Future<void> _saveFCMToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    print('Foreground FCM message received: ${message.notification?.title}');
  }

  static Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
    print('Background FCM message received: ${message.messageId}');
  }

  // Get user notification preferences
  Future<Map<String, dynamic>> _getUserNotificationPreferences(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('preferences')
          .doc('notifications')
          .get();

      if (doc.exists) {
        return doc.data()!;
      } else {
        return {
          'deadlineNotificationsEnabled': true,
          'deadlineWarningHours': 24,
          'secondWarningHours': 2,
          'dailySummaryEnabled': false,
          'weeklySummaryEnabled': false,
          'dailySummaryTime': '09:00',
          'soundEnabled': true,
          'vibrationEnabled': true,
          'highPriorityOnly': false,
          'taskAssignedNotifications': true,
          'statusChangeNotifications': true,
          'completionReviewNotifications': true,
          'milestoneNotifications': true,
        };
      }
    } catch (e) {
      print('Error getting user notification preferences: $e');
      return {
        'deadlineNotificationsEnabled': true,
        'deadlineWarningHours': 24,
        'secondWarningHours': 2,
      };
    }
  }

  // Save notification preferences
  Future<void> saveNotificationPreferences({
    required int deadlineWarningHours,
    required int secondWarningHours,
    required bool deadlineNotificationsEnabled,
    required bool dailySummaryEnabled,
    required bool weeklySummaryEnabled,
    required String dailySummaryTime,
    required bool soundEnabled,
    required bool vibrationEnabled,
    required bool highPriorityOnly,
    required bool taskAssignedNotifications,
    required bool statusChangeNotifications,
    required bool completionReviewNotifications,
    required bool milestoneNotifications,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final preferences = {
        'deadlineWarningHours': deadlineWarningHours,
        'secondWarningHours': secondWarningHours,
        'deadlineNotificationsEnabled': deadlineNotificationsEnabled,
        'dailySummaryEnabled': dailySummaryEnabled,
        'weeklySummaryEnabled': weeklySummaryEnabled,
        'dailySummaryTime': dailySummaryTime,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
        'highPriorityOnly': highPriorityOnly,
        'taskAssignedNotifications': taskAssignedNotifications,
        'statusChangeNotifications': statusChangeNotifications,
        'completionReviewNotifications': completionReviewNotifications,
        'milestoneNotifications': milestoneNotifications,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('preferences')
          .doc('notifications')
          .set(preferences, SetOptions(merge: true));

      print('Notification preferences saved successfully');
    } catch (e) {
      print('Error saving notification preferences: $e');
      throw e;
    }
  }

  // Schedule deadline reminders for employees
  Future<void> scheduleDeadlineRemindersForEmployees({
    required String taskId,
    required String taskTitle,
    required DateTime deadline,
    required List<String> employeeIds,
    String? employerUserId,
  }) async {
    try {
      print('Scheduling deadline reminders for employees: $employeeIds');

      for (String employeeId in employeeIds) {
        if (employerUserId != null && employeeId == employerUserId) {
          print('Skipping deadline notifications for employer: $employeeId');
          continue;
        }

        final preferences = await _getUserNotificationPreferences(employeeId);

        if (!preferences['deadlineNotificationsEnabled']) {
          print('Deadline notifications disabled for user: $employeeId');
          continue;
        }

        final int primaryWarningHours = preferences['deadlineWarningHours'] ?? 24;
        final int secondWarningHours = preferences['secondWarningHours'] ?? 2;

        final DateTime primaryWarningTime = deadline.subtract(Duration(hours: primaryWarningHours));
        final DateTime secondWarningTime = deadline.subtract(Duration(hours: secondWarningHours));
        final DateTime finalWarningTime = deadline.subtract(const Duration(minutes: 30));

        final now = DateTime.now();

        // Schedule primary warning
        if (primaryWarningTime.isAfter(now)) {
          await createFirestoreNotification(
            userId: employeeId,
            title: '⏰ Deadline Reminder',
            body: '$taskTitle deadline is in ${primaryWarningHours > 24 ? '${(primaryWarningHours / 24).toStringAsFixed(1)} days' : '${primaryWarningHours} hours'}',
            data: {
              'type': typeTaskDeadline,
              'taskId': taskId,
              'warningType': 'primary',
              'hoursRemaining': primaryWarningHours.toString(),
            },
            priority: NotificationPriority.normal,
            scheduledFor: primaryWarningTime,
          );
        }

        // Schedule second warning
        if (secondWarningTime.isAfter(now) && secondWarningHours != primaryWarningHours) {
          await createFirestoreNotification(
            userId: employeeId,
            title: '🚨 Urgent Deadline Alert',
            body: '$taskTitle deadline is in $secondWarningHours hours!',
            data: {
              'type': typeTaskDeadline,
              'taskId': taskId,
              'warningType': 'second',
              'hoursRemaining': secondWarningHours.toString(),
            },
            priority: NotificationPriority.high,
            scheduledFor: secondWarningTime,
          );
        }

      }
    } catch (e) {
      print('Error scheduling deadline reminders: $e');
    }
  }

  // Job creation notification to all users
  Future<void> showJobCreatedNotificationToAllUsers({
    required String jobId,
    required String jobTitle,
    required String jobLocation,
    required String employmentType,
    required double salary,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

      for (var userDoc in usersSnapshot.docs) {
        final userId = userDoc.id;
        if (userId == user.uid) continue;

        await createFirestoreNotification(
          userId: userId,
          title: '🆕 New Job Available!',
          body: '$jobTitle in $jobLocation - $employmentType - RM${salary.toStringAsFixed(2)}',
          data: {
            'type': typeJobCreated,
            'jobId': jobId,
            'jobTitle': jobTitle,
            'jobLocation': jobLocation,
            'employmentType': employmentType,
            'salary': salary,
          },
          priority: NotificationPriority.normal,
        );
      }

      await createFirestoreNotification(
        userId: user.uid,
        title: '✅ Job Posted Successfully!',
        body: 'New Job "$jobTitle" has been posted.',
        data: {
          'type': typeJobCreated,
          'jobId': jobId,
        },
        priority: NotificationPriority.normal,
      );
    } catch (e) {
      print('Error creating job notifications: $e');
    }
  }

  // Real-time notification
  Future<void> sendRealTimeNotification({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    await createFirestoreNotification(
      userId: userId,
      title: title,
      body: body,
      data: data,
      priority: priority,
      sendImmediately: true,
    );
  }

  // Completion request notification
  Future<void> sendCompletionRequestNotification({
    required String employerId,
    required String employeeId,
    required String employeeName,
    required String taskId,
    required String taskTitle,
    required String completionNotes,
  }) async {
    await createFirestoreNotification(
      userId: employerId,
      title: '✅ Task Completion Request',
      body: '$employeeName has requested completion review for "$taskTitle"',
      data: {
        'type': typeCompletionRequest,
        'taskId': taskId,
        'taskTitle': taskTitle,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'completionNotes': completionNotes,
      },
      priority: NotificationPriority.high,
    );
  }

  // Job application notification
  Future<void> sendJobApplicationNotification({
    required String employerId,
    required String applicantId,
    required String jobId,
    required String jobTitle,
    required String applicantName,
  }) async {
    await createFirestoreNotification(
      userId: employerId,
      title: '👤 New Job Application!',
      body: '$applicantName has applied for "$jobTitle". Review their application now.',
      data: {
        'type': typeJobApplication,
        'jobId': jobId,
        'jobTitle': jobTitle,
        'applicantId': applicantId,
        'applicantName': applicantName,
      },
      priority: NotificationPriority.high,
    );
  }

  // Send priority notification using Firestore
  Future<void> sendPriorityNotification({
    required String title,
    required String body,
    required String taskId,
    required String priority,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await createFirestoreNotification(
        userId: user.uid,
        title: title,
        body: body,
        data: {
          'type': typePriorityAlert,
          'taskId': taskId,
          'priority': priority,
        },
        priority: NotificationPriority.urgent,
        sendImmediately: true,
      );

      print('Priority notification created in Firestore');
    } catch (e) {
      print('Error sending priority notification: $e');
    }
  }

  // Helper method to convert string to NotificationPriority enum
  NotificationPriority _stringToNotificationPriority(String priorityString) {
    switch (priorityString.toLowerCase()) {
      case 'urgent':
        return NotificationPriority.urgent;
      case 'high':
        return NotificationPriority.high;
      case 'low':
        return NotificationPriority.low;
      default:
        return NotificationPriority.normal;
    }
  }

  String _getChannelForPriority(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.urgent:
      case NotificationPriority.high:
        return highPriorityChannel;
      case NotificationPriority.low:
        return summaryChannel;
      default:
        return defaultChannel;
    }
  }

  String _getChannelNameForPriority(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.urgent:
      case NotificationPriority.high:
        return 'High Priority Notifications';
      case NotificationPriority.low:
        return 'Summary Notifications';
      default:
        return 'Default Notifications';
    }
  }

  Importance _getImportanceForPriority(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.urgent:
        return Importance.max;
      case NotificationPriority.high:
        return Importance.high;
      case NotificationPriority.low:
        return Importance.low;
      default:
        return Importance.defaultImportance;
    }
  }

  Priority _getPriorityForNotificationPriority(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.urgent:
        return Priority.max;
      case NotificationPriority.high:
        return Priority.high;
      case NotificationPriority.low:
        return Priority.low;
      default:
        return Priority.defaultPriority;
    }
  }

  // Notification response handler with context safety
  void _onNotificationResponse(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        final type = data['type'] as String?;
        print('Notification tapped: $type');

        // Safely get context
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = _navigatorKey?.currentContext;
          if (context != null && context.mounted) {
            _handleNotificationTap(context, data);
          } else {
            print('No valid context available for navigation');
          }
        });
      } catch (e) {
        print('Error processing notification response: $e');
      }
    }
  }

  // Context-safe navigation handling
  void _handleNotificationTap(BuildContext context, Map<String, dynamic> data) {
    if (!context.mounted) {
      print('Context not mounted, cannot handle notification tap');
      return;
    }

    final type = data['type'] as String?;

    switch (type) {
      case typeDailySummary:
        _openDailySummary(context, data);
        break;
      case typeWeeklySummary:
        _openWeeklySummary(context, data);
        break;
      case typeJobApplication:
        _showJobApplicationAlert(context, data);
        break;
      case typeCompletionRequest:
        _showCompletionRequestAlert(context, data);
        break;
      case typeTaskDeadline:
        _showDeadlineAlert(context, data);
        break;
      case typeJobCreated:
        _showJobCreatedAlert(context, data);
        break;
      default:
        _showGenericAlert(context, data);
    }
  }

  void _openDailySummary(BuildContext context, Map<String, dynamic> data) {
    if (!context.mounted) return;

    try {
      final summaryData = {
        'date': data['date'],
        'totalJobs': data['totalJobs'] ?? data['totalTasks'] ?? 0,
        'completedJobs': data['completedJobs'] ?? data['completedTasks'] ?? 0,
        'inProgressJobs': data['inProgressJobs'] ?? data['inProgressTasks'] ?? 0,
        'pendingJobs': data['pendingJobs'] ?? data['overdueTasks'] ?? 0,
        'pointsEarned': data['pointsEarned'] ?? 0,
        'isFromNotification': true,
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DailySummaryPage(
            summaryData: summaryData,
            date: data['date'],
          ),
        ),
      );

      print('Navigated to Daily Summary with data: $summaryData');
    } catch (e) {
      print('Error opening daily summary: $e');
      _showSimpleAlert(context, 'Daily Summary', 'Your daily summary is ready to view!');
    }
  }

  void _openWeeklySummary(BuildContext context, Map<String, dynamic> data) {
    if (!context.mounted) return;

    try {
      final summaryData = {
        'weekStart': data['weekStart'],
        'weekEnd': data['weekEnd'],
        'totalJobs': data['totalJobs'] ?? data['totalTasks'] ?? 0,
        'completedJobs': data['completedJobs'] ?? data['completedTasks'] ?? 0,
        'pointsEarned': data['pointsEarned'] ?? 0,
        'completionRate': data['completionRate'] ?? 0.0,
        'isFromNotification': true,
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WeeklySummaryPage(
            summaryData: summaryData,
            weekStart: data['weekStart'],
          ),
        ),
      );

      print('Navigated to Weekly Summary');
    } catch (e) {
      print('Error opening weekly summary: $e');
      _showSimpleAlert(context, 'Weekly Summary', 'Your weekly summary is ready to view!');
    }
  }

  // Show job application alert
  void _showJobApplicationAlert(BuildContext context, Map<String, dynamic> data) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_add, color: Colors.blue),
            SizedBox(width: 8),
            Text('New Job Application'),
          ],
        ),
        content: Text(
          'New application for "${data['jobTitle'] ?? 'Unknown Job'}" from ${data['applicantName'] ?? 'Unknown Applicant'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSimpleAlert(context, 'Info', 'Navigate to job applications page');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('View Applications', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Show completion request alert
  void _showCompletionRequestAlert(BuildContext context, Map<String, dynamic> data) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.task_alt, color: Colors.green),
            SizedBox(width: 8),
            Text('Task Completion Request'),
          ],
        ),
        content: Text(
          '${data['employeeName'] ?? 'An employee'} has requested completion review for "${data['taskTitle'] ?? 'a task'}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSimpleAlert(context, 'Info', 'Navigate to task review page');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Review Task', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Show deadline alert
  void _showDeadlineAlert(BuildContext context, Map<String, dynamic> data) {
    if (!context.mounted) return;

    final warningType = data['warningType'] as String? ?? 'reminder';
    final hoursRemaining = data['hoursRemaining'] as String? ?? '0';

    Color alertColor = Colors.orange;
    IconData alertIcon = Icons.schedule;
    String alertTitle = 'Deadline Reminder';

    if (warningType == 'urgent' || warningType == 'second') {
      alertColor = Colors.deepOrange;
      alertIcon = Icons.warning;
      alertTitle = 'Urgent Deadline Alert';
    } else if (warningType == 'final') {
      alertColor = Colors.red;
      alertIcon = Icons.error;
      alertTitle = 'FINAL DEADLINE WARNING';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(alertIcon, color: alertColor),
            const SizedBox(width: 8),
            Text(alertTitle, style: TextStyle(color: alertColor)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Task: ${data['taskTitle'] ?? 'Unknown Task'}'),
            const SizedBox(height: 8),
            Text(
              'Deadline in: $hoursRemaining hours',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: alertColor,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSimpleAlert(context, 'Info', 'Navigate to task details');
            },
            style: ElevatedButton.styleFrom(backgroundColor: alertColor),
            child: const Text('View Task', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Show job created alert
  void _showJobCreatedAlert(BuildContext context, Map<String, dynamic> data) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.work, color: Colors.teal),
            SizedBox(width: 8),
            Text('New Job Available'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Job: ${data['jobTitle'] ?? 'Unknown Job'}'),
            Text('Location: ${data['jobLocation'] ?? 'N/A'}'),
            Text('Salary: RM${data['salary']?.toStringAsFixed(2) ?? '0.00'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSimpleAlert(context, 'Info', 'Navigate to job details');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('View Job', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Show generic alert
  void _showGenericAlert(BuildContext context, Map<String, dynamic> data) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications, color: Colors.blue),
            SizedBox(width: 8),
            Text('Notification'),
          ],
        ),
        content: Text('Notification type: ${data['type'] ?? 'Unknown'}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Helper method for simple alerts
  void _showSimpleAlert(BuildContext context, String title, String message) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Add debugging methods
  Future<void> debugNotificationSystem() async {
    print('=== NOTIFICATION SYSTEM DEBUG ===');
    print('Service initialized: $_isInitialized');
    print('Permissions: ${await _checkNotificationPermissions()}');
    print('Processed notifications count: ${_processedNotifications.length}');
    print('Retry attempts: $_retryAttempts');

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final pendingNotifications = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('sent', isEqualTo: false)
          .get();

      print('Pending notifications in Firestore: ${pendingNotifications.docs.length}');

      for (var doc in pendingNotifications.docs.take(3)) {
        final data = doc.data();
        print('  - ${data['title']} (${data['priority']}) - Immediate: ${data['sendImmediately']}');
      }
    }
    print('=== END DEBUG ===');
  }

  // Test methods for debugging
  Future<void> testNotificationFlow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    print('🧪 Testing complete notification flow...');

    await createFirestoreNotification(
      userId: user.uid,
      title: '🧪 Test Notification Flow',
      body: 'This tests the complete notification flow with enhanced error handling',
      data: {
        'type': 'test_flow',
        'timestamp': DateTime.now().toIso8601String(),
      },
      priority: NotificationPriority.high,
      sendImmediately: true,
    );

    print('✅ Test notification created');
  }

  // TEST METHODS
  Future<void> testUrgentNotification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await createFirestoreNotification(
      userId: user.uid,
      title: '🚨 URGENT TEST ALERT',
      body: 'This is an urgent notification test with enhanced reliability!',
      data: {
        'type': 'test_urgent',
        'urgency': 'critical',
        'timestamp': DateTime.now().toIso8601String(),
      },
      priority: NotificationPriority.urgent,
      sendImmediately: true,
    );

    print('Urgent test notification sent');
  }

  Future<void> testPriorityLevels() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final priorities = [
      {
        'priority': NotificationPriority.low,
        'title': '🔵 Low Priority Test',
        'body': 'This is a low priority notification with minimal styling'
      },
      {
        'priority': NotificationPriority.normal,
        'title': '⚪ Normal Priority Test',
        'body': 'This is a normal priority notification with standard styling'
      },
      {
        'priority': NotificationPriority.high,
        'title': '🟡 High Priority Test',
        'body': 'This is a high priority notification with orange styling and medium vibration'
      },
      {
        'priority': NotificationPriority.urgent,
        'title': '🔴 URGENT Priority Test',
        'body': 'This is an URGENT notification with red styling, strong vibration, and stays until dismissed!'
      },
    ];

    for (int i = 0; i < priorities.length; i++) {
      final priority = priorities[i];

      await createFirestoreNotification(
        userId: user.uid,
        title: priority['title'] as String,
        body: priority['body'] as String,
        data: {
          'type': 'test_priority',
          'level': priority['priority'].toString(),
          'index': i,
        },
        priority: priority['priority'] as NotificationPriority,
        sendImmediately: true,
      );

      await Future.delayed(const Duration(seconds: 3));
    }

    print('All priority level test notifications sent');
  }

  Future<void> testDailySummary() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    print('Testing daily summary notification...');

    final today = DateTime.now();
    final totalJobs = 8;
    final completedJobs = 5;
    final inProgressJobs = 2;
    final pendingJobs = 1;
    final pointsEarned = 250;

    String summaryTitle = '📊 Daily Summary Test - ${_formatDate(today)}';
    String summaryBody = _buildDailySummaryBody(
        totalJobs, completedJobs, inProgressJobs, pendingJobs, pointsEarned
    );

    await createFirestoreNotification(
      userId: user.uid,
      title: summaryTitle,
      body: summaryBody,
      data: {
        'type': typeDailySummary,
        'date': today.toIso8601String(),
        'totalJobs': totalJobs,
        'completedJobs': completedJobs,
        'inProgressJobs': inProgressJobs,
        'pendingJobs': pendingJobs,
        'pointsEarned': pointsEarned,
        'isTest': true,
      },
      priority: NotificationPriority.low,
      sendImmediately: true,
    );

    print('Daily summary test notification sent');
  }

  Future<void> testWeeklySummary() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    print('Testing weekly summary notification...');

    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);

    final weeklyTotalJobs = 25;
    final weeklyCompletedJobs = 18;
    final weeklyPointsEarned = 900;
    final completionRate = (weeklyCompletedJobs / weeklyTotalJobs) * 100;

    String summaryTitle = '📈 Weekly Summary Test - Week of ${_formatDate(weekStartDate)}';
    String summaryBody = _buildWeeklySummaryBody(
        weeklyTotalJobs, weeklyCompletedJobs, weeklyPointsEarned, completionRate
    );

    await createFirestoreNotification(
      userId: user.uid,
      title: summaryTitle,
      body: summaryBody,
      data: {
        'type': typeWeeklySummary,
        'weekStart': weekStartDate.toIso8601String(),
        'totalJobs': weeklyTotalJobs,
        'completedJobs': weeklyCompletedJobs,
        'pointsEarned': weeklyPointsEarned,
        'completionRate': completionRate,
        'isTest': true,
      },
      priority: NotificationPriority.low,
      sendImmediately: true,
    );

    print('Weekly summary test notification sent');
  }

  // Helper methods for summary formatting
  String _buildDailySummaryBody(int total, int completed, int inProgress, int pending, int points) {
    if (total == 0) {
      return '📝 No jobs scheduled for today. Take a well-deserved break!';
    }

    String emoji = completed == total ? '🎉' :
    completed > total / 2 ? '👍' :
    completed > 0 ? '💪' : '📝';

    return '$emoji Today: $completed/$total jobs completed'
        '${inProgress > 0 ? ', $inProgress in progress' : ''}'
        '${pending > 0 ? ', $pending pending' : ''}'
        '${points > 0 ? ' • $points points earned!' : ''}';
  }

  String _buildWeeklySummaryBody(int total, int completed, int points, double rate) {
    if (total == 0) {
      return '📅 No jobs this week. Perfect time to plan ahead!';
    }

    String emoji = rate >= 90 ? '🏆' :
    rate >= 70 ? '🌟' :
    rate >= 50 ? '👍' : '💪';

    return '$emoji This week: $completed/$total jobs (${rate.toStringAsFixed(1)}% completion)'
        '${points > 0 ? ' • $points points earned!' : ''}';
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }

  // Compatibility methods
  Future<void> generateDailySummary() async {
    print('generateDailySummary called');
  }

  Future<void> updateNotificationPreferences({
    int? deadlineWarningHours,
    int? secondWarningHours,
    bool? deadlineNotificationsEnabled,
    bool? dailySummaryEnabled,
    bool? weeklySummaryEnabled,
    String? dailySummaryTime,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? highPriorityOnly,
    bool? taskAssignedNotifications,
    bool? statusChangeNotifications,
    bool? completionReviewNotifications,
    bool? milestoneNotifications,
  }) async {
    print('updateNotificationPreferences called - redirecting to saveNotificationPreferences');

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final currentPrefs = await _getUserNotificationPreferences(user.uid);

    await saveNotificationPreferences(
      deadlineWarningHours: deadlineWarningHours ?? (currentPrefs['deadlineWarningHours'] as int? ?? 24),
      secondWarningHours: secondWarningHours ?? (currentPrefs['secondWarningHours'] as int? ?? 2),
      deadlineNotificationsEnabled: deadlineNotificationsEnabled ?? (currentPrefs['deadlineNotificationsEnabled'] as bool? ?? true),
      dailySummaryEnabled: dailySummaryEnabled ?? (currentPrefs['dailySummaryEnabled'] as bool? ?? false),
      weeklySummaryEnabled: weeklySummaryEnabled ?? (currentPrefs['weeklySummaryEnabled'] as bool? ?? false),
      dailySummaryTime: dailySummaryTime ?? (currentPrefs['dailySummaryTime'] as String? ?? '09:00'),
      soundEnabled: soundEnabled ?? (currentPrefs['soundEnabled'] as bool? ?? true),
      vibrationEnabled: vibrationEnabled ?? (currentPrefs['vibrationEnabled'] as bool? ?? true),
      highPriorityOnly: highPriorityOnly ?? (currentPrefs['highPriorityOnly'] as bool? ?? false),
      taskAssignedNotifications: taskAssignedNotifications ?? (currentPrefs['taskAssignedNotifications'] as bool? ?? true),
      statusChangeNotifications: statusChangeNotifications ?? (currentPrefs['statusChangeNotifications'] as bool? ?? true),
      completionReviewNotifications: completionReviewNotifications ?? (currentPrefs['completionReviewNotifications'] as bool? ?? true),
      milestoneNotifications: milestoneNotifications ?? (currentPrefs['milestoneNotifications'] as bool? ?? true),
    );
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String payload,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    print('scheduleNotification called');
  }

  Future<void> clearAllNotifications() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  Future<void> clearNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
  }

  @deprecated
  Future<void> scheduleDeadlineReminders({
    required String taskId,
    required String taskTitle,
    required DateTime deadline,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await scheduleDeadlineRemindersForEmployees(
      taskId: taskId,
      taskTitle: taskTitle,
      deadline: deadline,
      employeeIds: [user.uid],
    );
  }

  Future<bool> checkNotificationPermissions() async {
    return await _checkNotificationPermissions();
  }

  void dispose() {
    _notificationSubscription?.cancel();
    _scheduledNotificationTimer?.cancel();
    _permissionCheckTimer?.cancel();
    _processedNotifications.clear();
    _retryAttempts.clear();
    EnhancedSummaryNotificationService.dispose();
    print('NotificationService disposed');
  }
}

// Enhanced Summary Notification Service with better background handling
class EnhancedSummaryNotificationService {
  static Timer? _mainTimer;
  static Timer? _backgroundTimer;
  static bool _isInitialized = false;

  static Future<void> initializeEnhancedSummaryNotifications() async {
    if (_isInitialized) {
      print('🔄 Enhanced summary service already initialized, reinitializing...');
      dispose();
    }

    print('🚀 Initializing enhanced summary notification service...');

    try {
      // Main timer - checks every 5 minutes when app is active
      _mainTimer = Timer.periodic(
        const Duration(minutes: 5),
            (timer) async {
          print('⏰ Main timer tick - checking summaries...');
          await _checkAllSummaries();
        },
      );

      // Background timer - checks every 15 minutes for background processing
      _backgroundTimer = Timer.periodic(
        const Duration(minutes: 15),
            (timer) async {
          print('🌙 Background timer tick - checking summaries...');
          await _checkAllSummaries();
        },
      );

      // Initial check after a short delay
      Timer(const Duration(seconds: 10), () async {
        print('🎯 Initial summary check...');
        await _checkAllSummaries();
      });

      _isInitialized = true;
      print('✅ Enhanced summary notification service initialized');
    } catch (e) {
      print('❌ Failed to initialize enhanced summary service: $e');
      _isInitialized = false;
    }
  }

  static Future<void> _checkAllSummaries() async {
    try {
      // Check both daily and weekly summaries
      await Future.wait([
        _checkDailySummaryWithRetry(),
        _checkWeeklySummaryWithRetry(),
      ], eagerError: false);

    } catch (e) {
      print('❌ Error in summary check cycle: $e');
    }
  }

  static Future<void> _checkDailySummaryWithRetry() async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        print('🔍 Daily summary check attempt ${retryCount + 1}');

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          print('❌ No authenticated user for daily summary');
          return;
        }

        // Get preferences with timeout
        final preferencesDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('preferences')
            .doc('notifications')
            .get()
            .timeout(const Duration(seconds: 10));

        if (!preferencesDoc.exists) {
          print('ℹ️ No notification preferences found');
          return;
        }

        final prefs = preferencesDoc.data()!;
        final dailySummaryEnabled = prefs['dailySummaryEnabled'] as bool? ?? false;
        final dailySummaryTime = prefs['dailySummaryTime'] as String? ?? '09:00';

        print('📊 Daily summary - Enabled: $dailySummaryEnabled, Time: $dailySummaryTime');

        if (!dailySummaryEnabled) {
          print('🚫 Daily summary is disabled');
          return;
        }

        final timeParts = dailySummaryTime.split(':');
        final summaryHour = int.parse(timeParts[0]);
        final summaryMinute = int.parse(timeParts[1]);

        final now = DateTime.now();
        final summaryTime = DateTime(now.year, now.month, now.day, summaryHour, summaryMinute);

        print('🕐 Current: ${now.hour}:${now.minute.toString().padLeft(2, '0')}, Target: $summaryHour:${summaryMinute.toString().padLeft(2, '0')}');

        // More flexible time window - check if we're within 30 minutes of the target time
        final timeDiff = now.difference(summaryTime).abs();
        if (timeDiff.inMinutes > 30) {
          print('⏰ Not time for daily summary yet. Time difference: ${timeDiff.inMinutes} minutes');
          return;
        }

        // Check if we already sent a summary today
        final today = DateTime(now.year, now.month, now.day);
        final todayKey = 'daily_${today.toIso8601String().split('T')[0]}';

        final lastSummaryDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('summaryHistory')
            .doc(todayKey)
            .get()
            .timeout(const Duration(seconds: 10));

        if (lastSummaryDoc.exists) {
          print('✅ Daily summary already sent today');
          return;
        }

        print('🎯 Conditions met - generating daily summary');
        await _generateAndSendDailySummaryWithRetry(user.uid);
        return; // Success, exit retry loop

      } catch (e) {
        retryCount++;
        print('❌ Daily summary check attempt $retryCount failed: $e');

        if (retryCount < maxRetries) {
          await Future.delayed(Duration(seconds: retryCount * 2)); // Exponential backoff
        } else {
          print('💀 Daily summary check failed after $maxRetries attempts');
        }
      }
    }
  }

  static Future<void> _checkWeeklySummaryWithRetry() async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        print('🔍 Weekly summary check attempt ${retryCount + 1}');

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          print('❌ No authenticated user for weekly summary');
          return;
        }

        final preferencesDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('preferences')
            .doc('notifications')
            .get()
            .timeout(const Duration(seconds: 10));

        if (!preferencesDoc.exists) {
          print('ℹ️ No notification preferences found');
          return;
        }

        final prefs = preferencesDoc.data()!;
        final weeklySummaryEnabled = prefs['weeklySummaryEnabled'] as bool? ?? false;

        print('📈 Weekly summary enabled: $weeklySummaryEnabled');

        if (!weeklySummaryEnabled) {
          print('🚫 Weekly summary is disabled');
          return;
        }

        final now = DateTime.now();

        // Send weekly summary on Monday between 8 AM and 11 AM
        if (now.weekday != DateTime.monday) {
          print('📅 Not Monday - skipping weekly summary. Current day: ${now.weekday}');
          return;
        }

        if (now.hour < 8 || now.hour > 11) {
          print('🕐 Not the right time for weekly summary. Current hour: ${now.hour}');
          return;
        }

        // Get the start of this week (Monday)
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final weekStart = DateTime(monday.year, monday.month, monday.day);
        final weekKey = 'weekly_${weekStart.toIso8601String().split('T')[0]}';

        final lastWeeklySummaryDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('summaryHistory')
            .doc(weekKey)
            .get()
            .timeout(const Duration(seconds: 10));

        if (lastWeeklySummaryDoc.exists) {
          print('✅ Weekly summary already sent this week');
          return;
        }

        print('🎯 Conditions met - generating weekly summary');
        await _generateAndSendWeeklySummaryWithRetry(user.uid);
        return; // Success, exit retry loop

      } catch (e) {
        retryCount++;
        print('❌ Weekly summary check attempt $retryCount failed: $e');

        if (retryCount < maxRetries) {
          await Future.delayed(Duration(seconds: retryCount * 2)); // Exponential backoff
        } else {
          print('💀 Weekly summary check failed after $maxRetries attempts');
        }
      }
    }
  }

  static Future<void> _generateAndSendDailySummaryWithRetry(String userId) async {
    try {
      print('📊 Generating enhanced daily summary for user: $userId');

      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // Get jobs for today with timeout
      final jobsQuery = await FirebaseFirestore.instance
          .collection('jobs')
          .where('acceptedApplicants', arrayContains: userId)
          .get()
          .timeout(const Duration(seconds: 15));

      // Filter jobs by today's date
      final todayJobs = jobsQuery.docs.where((doc) {
        try {
          final data = doc.data();
          final startDate = data['startDate'] as String?;
          if (startDate != null) {
            final jobStartDate = DateTime.parse(startDate);
            return jobStartDate.year == today.year &&
                jobStartDate.month == today.month &&
                jobStartDate.day == today.day;
          }
        } catch (e) {
          print('⚠️ Error parsing job date: $e');
        }
        return false;
      }).toList();

      int totalJobs = todayJobs.length;
      int completedJobs = todayJobs.where((doc) {
        try {
          return doc.data()['isCompleted'] == true;
        } catch (e) {
          return false;
        }
      }).length;

      int inProgressJobs = todayJobs.where((doc) {
        try {
          final data = doc.data();
          return data['isCompleted'] != true && (data['progressPercentage'] ?? 0) > 0;
        } catch (e) {
          return false;
        }
      }).length;

      int pendingJobs = todayJobs.where((doc) {
        try {
          return (doc.data()['progressPercentage'] ?? 0) == 0;
        } catch (e) {
          return false;
        }
      }).length;

      // Get points earned today with timeout
      int pointsEarnedToday = 0;
      try {
        final pointsHistoryQuery = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('pointsHistory')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
            .where('timestamp', isLessThan: Timestamp.fromDate(todayEnd))
            .get()
            .timeout(const Duration(seconds: 10));

        pointsEarnedToday = pointsHistoryQuery.docs.fold(0, (sum, doc) {
          try {
            return sum + (doc.data()['points'] as int? ?? 0);
          } catch (e) {
            return sum;
          }
        });
      } catch (e) {
        print('⚠️ Error getting points: $e');
      }

      print('📈 Daily summary stats: Total: $totalJobs, Completed: $completedJobs, InProgress: $inProgressJobs, Points: $pointsEarnedToday');

      String summaryTitle = '📊 Daily Summary - ${_formatDate(today)}';
      String summaryBody = _buildDailySummaryBody(
          totalJobs, completedJobs, inProgressJobs, pendingJobs, pointsEarnedToday
      );

      // Create notification with enhanced data
      final notificationService = NotificationService();
      await notificationService.createFirestoreNotification(
        userId: userId,
        title: summaryTitle,
        body: summaryBody,
        data: {
          'type': NotificationService.typeDailySummary,
          'date': today.toIso8601String(),
          'totalJobs': totalJobs,
          'completedJobs': completedJobs,
          'inProgressJobs': inProgressJobs,
          'pendingJobs': pendingJobs,
          'pointsEarned': pointsEarnedToday,
          'completionRate': totalJobs > 0 ? (completedJobs / totalJobs) * 100 : 0.0,
          'isAutoGenerated': true,
        },
        priority: NotificationPriority.low,
        sendImmediately: true,
      );

      // Mark as sent in summary history
      final todayKey = 'daily_${todayStart.toIso8601String().split('T')[0]}';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('summaryHistory')
          .doc(todayKey)
          .set({
        'type': 'daily',
        'sentAt': FieldValue.serverTimestamp(),
        'totalJobs': totalJobs,
        'completedJobs': completedJobs,
        'inProgressJobs': inProgressJobs,
        'pendingJobs': pendingJobs,
        'pointsEarned': pointsEarnedToday,
        'completionRate': totalJobs > 0 ? (completedJobs / totalJobs) * 100 : 0.0,
      }).timeout(const Duration(seconds: 10));

      print('✅ Enhanced daily summary sent successfully');

    } catch (e) {
      print('❌ Error generating enhanced daily summary: $e');
      throw e; // Re-throw to trigger retry if needed
    }
  }

  static Future<void> _generateAndSendWeeklySummaryWithRetry(String userId) async {
    try {
      print('📈 Generating enhanced weekly summary for user: $userId');

      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final weekEndDate = weekStartDate.add(const Duration(days: 7));

      // Get jobs for this week with timeout
      final jobsQuery = await FirebaseFirestore.instance
          .collection('jobs')
          .where('acceptedApplicants', arrayContains: userId)
          .get()
          .timeout(const Duration(seconds: 15));

      // Filter jobs by this week
      final weekJobs = jobsQuery.docs.where((doc) {
        try {
          final data = doc.data();
          final startDate = data['startDate'] as String?;
          if (startDate != null) {
            final jobStartDate = DateTime.parse(startDate);
            return jobStartDate.isAfter(weekStartDate.subtract(const Duration(days: 1))) &&
                jobStartDate.isBefore(weekEndDate);
          }
        } catch (e) {
          print('⚠️ Error parsing job date: $e');
        }
        return false;
      }).toList();

      // Get points for this week with timeout
      int weeklyPointsEarned = 0;
      try {
        final pointsQuery = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('pointsHistory')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStartDate))
            .where('timestamp', isLessThan: Timestamp.fromDate(weekEndDate))
            .get()
            .timeout(const Duration(seconds: 10));

        weeklyPointsEarned = pointsQuery.docs.fold(0, (sum, doc) {
          try {
            return sum + (doc.data()['points'] as int? ?? 0);
          } catch (e) {
            return sum;
          }
        });
      } catch (e) {
        print('⚠️ Error getting weekly points: $e');
      }

      int weeklyTotalJobs = weekJobs.length;
      int weeklyCompletedJobs = weekJobs.where((doc) {
        try {
          return doc.data()['isCompleted'] == true;
        } catch (e) {
          return false;
        }
      }).length;

      double completionRate = weeklyTotalJobs > 0
          ? (weeklyCompletedJobs / weeklyTotalJobs) * 100
          : 0;

      print('📊 Weekly summary stats: Total: $weeklyTotalJobs, Completed: $weeklyCompletedJobs, Points: $weeklyPointsEarned, Rate: ${completionRate.toStringAsFixed(1)}%');

      String summaryTitle = '📈 Weekly Summary - Week of ${_formatDate(weekStartDate)}';
      String summaryBody = _buildWeeklySummaryBody(
          weeklyTotalJobs, weeklyCompletedJobs, weeklyPointsEarned, completionRate
      );

      final notificationService = NotificationService();
      await notificationService.createFirestoreNotification(
        userId: userId,
        title: summaryTitle,
        body: summaryBody,
        data: {
          'type': NotificationService.typeWeeklySummary,
          'weekStart': weekStartDate.toIso8601String(),
          'weekEnd': weekEndDate.toIso8601String(),
          'totalJobs': weeklyTotalJobs,
          'completedJobs': weeklyCompletedJobs,
          'pointsEarned': weeklyPointsEarned,
          'completionRate': completionRate,
          'isAutoGenerated': true,
        },
        priority: NotificationPriority.low,
        sendImmediately: true,
      );

      // Mark as sent
      final weekKey = 'weekly_${weekStartDate.toIso8601String().split('T')[0]}';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('summaryHistory')
          .doc(weekKey)
          .set({
        'type': 'weekly',
        'sentAt': FieldValue.serverTimestamp(),
        'weekStart': weekStartDate.toIso8601String(),
        'weekEnd': weekEndDate.toIso8601String(),
        'totalJobs': weeklyTotalJobs,
        'completedJobs': weeklyCompletedJobs,
        'pointsEarned': weeklyPointsEarned,
        'completionRate': completionRate,
      }).timeout(const Duration(seconds: 10));

      print('✅ Enhanced weekly summary sent successfully');

    } catch (e) {
      print('❌ Error generating enhanced weekly summary: $e');
      throw e; // Re-throw to trigger retry if needed
    }
  }

  static String _buildDailySummaryBody(int total, int completed, int inProgress, int pending, int points) {
    if (total == 0) {
      return '📝 No jobs scheduled for today. Take a well-deserved break!';
    }

    String emoji = completed == total ? '🎉' :
    completed > total / 2 ? '👍' :
    completed > 0 ? '💪' : '📝';

    return '$emoji Today: $completed/$total jobs completed'
        '${inProgress > 0 ? ', $inProgress in progress' : ''}'
        '${pending > 0 ? ', $pending pending' : ''}'
        '${points > 0 ? ' • $points points earned!' : ''}';
  }

  static String _buildWeeklySummaryBody(int total, int completed, int points, double rate) {
    if (total == 0) {
      return '📅 No jobs this week. Perfect time to plan ahead!';
    }

    String emoji = rate >= 90 ? '🏆' :
    rate >= 70 ? '🌟' :
    rate >= 50 ? '👍' : '💪';

    return '$emoji This week: $completed/$total jobs (${rate.toStringAsFixed(1)}% completion)'
        '${points > 0 ? ' • $points points earned!' : ''}';
  }

  static String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }

  static void dispose() {
    _mainTimer?.cancel();
    _backgroundTimer?.cancel();
    _isInitialized = false;
    print('🛑 Enhanced summary notification service disposed');
  }
}

enum NotificationPriority {
  low,
  normal,
  high,
  urgent,
}