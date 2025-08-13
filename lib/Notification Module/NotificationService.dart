// NotificationService.dart - FIXED timer functionality with proper test/automatic separation
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

      // Start timer to check scheduled notifications every minute (FIXED for precise timing)
      _scheduledNotificationTimer = Timer.periodic(
        const Duration(minutes: 1), // Changed from 2 minutes to 1 minute for better precision
            (timer) => _processScheduledNotificationsEnhanced(),
      );
      print('Scheduled notification timer started (every 1 minute for precise timing)');

      // Start permission check timer
      _permissionCheckTimer = Timer.periodic(
        const Duration(minutes: 10),
            (timer) => _checkAndRequestPermissions(),
      );
      print('Permission check timer started');

      // Initialize enhanced summary notifications (FIXED timer system)
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

  Future<void> debugDeadlineNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ DEBUG: No user logged in');
      return;
    }

    print('🔍 DEBUG: Starting deadline notification debug for user: ${user.uid}');

    try {
      // 1. Check user preferences
      final preferences = await _getUserNotificationPreferences(user.uid);
      print('🔍 DEBUG: User preferences: $preferences');

      // 2. Check pending notifications in Firestore
      final pendingNotifications = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('sent', isEqualTo: false)
          .get();

      print('🔍 DEBUG: Pending notifications count: ${pendingNotifications.docs.length}');

      for (var doc in pendingNotifications.docs) {
        final data = doc.data();
        print('🔍 DEBUG: Pending notification: ${data['title']} - Type: ${data['type']} - Priority: ${data['priority']} - Scheduled: ${data['scheduledFor']} - SendImmediate: ${data['sendImmediately']}');
      }

      // 3. Check deadline-specific notifications
      final deadlineNotifications = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('data.type', isEqualTo: typeTaskDeadline)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      print('🔍 DEBUG: Recent deadline notifications count: ${deadlineNotifications.docs.length}');

      for (var doc in deadlineNotifications.docs) {
        final data = doc.data();
        final notificationData = data['data'] as Map<String, dynamic>? ?? {};
        print('🔍 DEBUG: Deadline notification: ${data['title']} - Warning Type: ${notificationData['warningType']} - Sent: ${data['sent']} - Priority: ${data['priority']}');
      }

      // 4. Test urgent notification immediately
      print('🔍 DEBUG: Testing immediate urgent notification...');
      await createFirestoreNotification(
        userId: user.uid,
        title: '🔍 DEBUG: Urgent Test',
        body: 'This is a debug test of urgent notifications. If you see this, urgent notifications are working!',
        data: {
          'type': typeTaskDeadline,
          'warningType': 'debug_urgent',
          'isDebug': true,
        },
        priority: NotificationPriority.urgent,
        sendImmediately: true,
      );

      // 5. Test scheduled urgent notification (1 minute from now)
      print('🔍 DEBUG: Testing scheduled urgent notification (1 minute)...');
      await createFirestoreNotification(
        userId: user.uid,
        title: '🔍 DEBUG: Scheduled Urgent Test',
        body: 'This urgent notification was scheduled for 1 minute after the debug test started!',
        data: {
          'type': typeTaskDeadline,
          'warningType': 'debug_scheduled_urgent',
          'isDebug': true,
        },
        priority: NotificationPriority.urgent,
        sendImmediately: false,
        scheduledFor: DateTime.now().add(const Duration(minutes: 1)),
      );

      print('✅ DEBUG: Debug tests completed. Check your notifications!');

    } catch (e) {
      print('❌ DEBUG ERROR: $e');
      print('❌ DEBUG STACK: ${StackTrace.current}');
    }
  }

//method to create a realistic deadline scenario
  Future<void> testRealDeadlineScenario() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    print('🧪 TESTING: Creating realistic deadline scenario...');

    // Create a fake deadline 3 minutes from now
    final testDeadline = DateTime.now().add(const Duration(minutes: 3));

    print('🧪 TESTING: Test deadline set for: $testDeadline');
    print('🧪 TESTING: This should trigger a 2-hour warning (immediate) and other warnings as configured');

    await scheduleDeadlineRemindersForEmployees(
      taskId: 'test_task_${DateTime.now().millisecondsSinceEpoch}',
      taskTitle: 'TEST URGENT DEADLINE TASK',
      deadline: testDeadline,
      employeeIds: [user.uid],
    );

    print('✅ TESTING: Test deadline scenario created. You should see notifications based on your settings.');
    print('💡 TESTING: If your urgent warning is set to 2 hours, it should fire immediately since the deadline is only 3 minutes away.');
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

  // Save notification preferences (PRESERVING ORIGINAL FUNCTION NAME AND SIGNATURE)
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

      // FIXED: Reinitialize the summary service to pick up new preferences
      EnhancedSummaryNotificationService.dispose();
      await EnhancedSummaryNotificationService.initializeEnhancedSummaryNotifications();
      print('📱 Summary service reinitialized with new preferences');

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
      print('🚨 DEADLINE REMINDERS: Scheduling for task "$taskTitle" with deadline: $deadline');
      print('🚨 DEADLINE REMINDERS: Employee IDs: $employeeIds');

      for (String employeeId in employeeIds) {
        if (employerUserId != null && employeeId == employerUserId) {
          print('🚨 DEADLINE REMINDERS: Skipping employer: $employeeId');
          continue;
        }

        print('🚨 DEADLINE REMINDERS: Processing employee: $employeeId');

        final preferences = await _getUserNotificationPreferences(employeeId);
        print('🚨 DEADLINE REMINDERS: User preferences: $preferences');

        if (!preferences['deadlineNotificationsEnabled']) {
          print('🚨 DEADLINE REMINDERS: Deadline notifications disabled for user: $employeeId');
          continue;
        }

        final int primaryWarningHours = preferences['deadlineWarningHours'] ?? 24;
        final int secondWarningHours = preferences['secondWarningHours'] ?? 2;

        print('🚨 DEADLINE REMINDERS: Primary warning: $primaryWarningHours hours, Second warning: $secondWarningHours hours');

        final DateTime primaryWarningTime = deadline.subtract(Duration(hours: primaryWarningHours));
        final DateTime secondWarningTime = deadline.subtract(Duration(hours: secondWarningHours));
        final DateTime finalWarningTime = deadline.subtract(const Duration(minutes: 30));

        final now = DateTime.now();
        print('🚨 DEADLINE REMINDERS: Current time: $now');
        print('🚨 DEADLINE REMINDERS: Primary warning time: $primaryWarningTime');
        print('🚨 DEADLINE REMINDERS: Second warning time: $secondWarningTime');
        print('🚨 DEADLINE REMINDERS: Final warning time: $finalWarningTime');

        // FIXED: Schedule primary warning (only if it's in the future)
        if (primaryWarningTime.isAfter(now)) {
          print('✅ DEADLINE REMINDERS: Scheduling PRIMARY warning for $primaryWarningTime');
          await createFirestoreNotification(
            userId: employeeId,
            title: '⏰ Deadline Reminder',
            body: '$taskTitle deadline is in ${primaryWarningHours > 24 ? '${(primaryWarningHours / 24).toStringAsFixed(1)} days' : '${primaryWarningHours} hours'}',
            data: {
              'type': typeTaskDeadline,
              'taskId': taskId,
              'taskTitle': taskTitle,
              'warningType': 'primary',
              'hoursRemaining': primaryWarningHours.toString(),
              'deadlineTime': deadline.toIso8601String(),
            },
            priority: NotificationPriority.normal,
            scheduledFor: primaryWarningTime,
            sendImmediately: false,
          );
          print('✅ DEADLINE REMINDERS: Primary warning scheduled successfully');
        } else {
          print('⚠️ DEADLINE REMINDERS: Primary warning time has passed, not scheduling');
        }

        // FIXED: Schedule second warning with better logic
        // Remove the condition that they must be different - user might want same time for testing
        if (secondWarningTime.isAfter(now)) {
          print('✅ DEADLINE REMINDERS: Scheduling URGENT warning for $secondWarningTime');
          await createFirestoreNotification(
            userId: employeeId,
            title: '🚨 URGENT Deadline Alert',
            body: '⚠️ URGENT: $taskTitle deadline is in $secondWarningHours hours! Please complete immediately.',
            data: {
              'type': typeTaskDeadline,
              'taskId': taskId,
              'taskTitle': taskTitle,
              'warningType': 'urgent', // Changed from 'second' to 'urgent'
              'hoursRemaining': secondWarningHours.toString(),
              'deadlineTime': deadline.toIso8601String(),
              'isUrgent': true, // Add urgent flag
            },
            priority: NotificationPriority.urgent, // Changed from high to urgent
            scheduledFor: secondWarningTime,
            sendImmediately: false,
          );
          print('✅ DEADLINE REMINDERS: Urgent warning scheduled successfully');
        } else {
          print('⚠️ DEADLINE REMINDERS: Urgent warning time has passed, not scheduling');

          // FIXED: If urgent time has passed but we're still before deadline, send immediately
          if (now.isBefore(deadline)) {
            print('🚨 DEADLINE REMINDERS: Urgent warning time passed but deadline not reached - sending immediately!');
            await createFirestoreNotification(
              userId: employeeId,
              title: '🚨 IMMEDIATE Deadline Alert',
              body: '⚠️ CRITICAL: $taskTitle deadline is VERY SOON! Complete immediately!',
              data: {
                'type': typeTaskDeadline,
                'taskId': taskId,
                'taskTitle': taskTitle,
                'warningType': 'immediate',
                'hoursRemaining': deadline.difference(now).inHours.toString(),
                'deadlineTime': deadline.toIso8601String(),
                'isUrgent': true,
                'isImmediate': true,
              },
              priority: NotificationPriority.urgent,
              sendImmediately: true, // Send immediately
            );
            print('✅ DEADLINE REMINDERS: Immediate urgent warning sent');
          }
        }

        // FIXED: Schedule final warning (30 minutes before deadline)
        if (finalWarningTime.isAfter(now) && finalWarningTime.isAfter(secondWarningTime.add(Duration(minutes: 15)))) {
          print('✅ DEADLINE REMINDERS: Scheduling FINAL warning for $finalWarningTime');
          await createFirestoreNotification(
            userId: employeeId,
            title: '🔴 FINAL Deadline Warning',
            body: '🔴 FINAL WARNING: $taskTitle deadline in 30 minutes! COMPLETE NOW!',
            data: {
              'type': typeTaskDeadline,
              'taskId': taskId,
              'taskTitle': taskTitle,
              'warningType': 'final',
              'hoursRemaining': '0.5',
              'deadlineTime': deadline.toIso8601String(),
              'isUrgent': true,
              'isFinal': true,
            },
            priority: NotificationPriority.urgent,
            scheduledFor: finalWarningTime,
            sendImmediately: false,
          );
          print('✅ DEADLINE REMINDERS: Final warning scheduled successfully');
        } else {
          print('⚠️ DEADLINE REMINDERS: Final warning not needed or time has passed');
        }

        print('✅ DEADLINE REMINDERS: All applicable warnings scheduled for employee: $employeeId');
      }

      print('✅ DEADLINE REMINDERS: Completed scheduling for all employees');
    } catch (e) {
      print('❌ DEADLINE REMINDERS ERROR: $e');
      print('❌ DEADLINE REMINDERS STACK: ${StackTrace.current}');
      throw e;
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
        'totalTasks': data['totalJobs'] ?? data['totalTasks'] ?? 0,
        'completedTasks': data['completedJobs'] ?? data['completedTasks'] ?? 0,
        'inProgressTasks': data['inProgressJobs'] ?? data['inProgressTasks'] ?? 0,
        'pendingTasks': data['pendingJobs'] ?? data['overdueTasks'] ?? 0,
        'pointsEarned': data['pointsEarned'] ?? 0,
        'totalEarnings': data['totalEarnings'] ?? 0.0,
        'translationsCount': data['translationsCount'] ?? 0,
        'taskDetails': data['taskDetails'] ?? <Map<String, dynamic>>[],
        'pointTransactions': data['pointTransactions'] ?? <Map<String, dynamic>>[],
        'translationDetails': data['translationDetails'] ?? <Map<String, dynamic>>[],
        'tasksByCategory': data['tasksByCategory'] ?? <String, int>{},
        'completionRate': data['completionRate'] ?? 100.0,
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
        'totalTasks': data['totalJobs'] ?? data['totalTasks'] ?? 0,
        'completedTasks': data['completedJobs'] ?? data['completedTasks'] ?? 0,
        'inProgressTasks': 0,
        'pendingTasks': 0,
        'overdueTasks': 0,
        'totalPoints': data['pointsEarned'] ?? 0,
        'totalEarnings': data['totalEarnings'] ?? 0.0,
        'translationsCount': 0,
        'completionRate': data['completionRate'] ?? 0.0,
        'tasksByCategory': data['tasksByCategory'] ?? <String, int>{},
        'averageDailyCompletion': data['averageDailyCompletion'] ?? 0.0,
        'averageDailyEarnings': data['averageDailyEarnings'] ?? 0.0,
        'mostProductiveDay': data['mostProductiveDay'] ?? 'N/A',
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

  // TEST METHODS (PRESERVING ALL ORIGINAL FUNCTION NAMES)
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

  // FIXED: Test methods that don't interfere with automatic system
  Future<void> testDailySummary() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    print('Testing daily summary notification (TEST MODE - will not interfere with automatic system)...');

    await createFirestoreNotification(
      userId: user.uid,
      title: '📊 TEST: Daily Summary - ${_formatDate(DateTime.now())}',
      body: '🧪 TEST: Today: 5/8 tasks completed, 2 in progress, 1 pending • 250 points earned!',
      data: {
        'type': typeDailySummary,
        'date': DateTime.now().toIso8601String(),
        'totalTasks': 8,
        'completedTasks': 5,
        'inProgressTasks': 2,
        'pendingTasks': 1,
        'pointsEarned': 250,
        'totalEarnings': 150.0,
        'completionRate': 62.5,
        'isTest': true, // Mark as test to distinguish from automatic
        'isManualTest': true,
      },
      priority: NotificationPriority.low,
      sendImmediately: true,
    );

    print('Daily summary test notification sent (TEST MODE)');
  }

  Future<void> testWeeklySummary() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    print('Testing weekly summary notification (TEST MODE - will not interfere with automatic system)...');

    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);

    await createFirestoreNotification(
      userId: user.uid,
      title: '📈 TEST: Weekly Summary - Week of ${_formatDate(weekStartDate)}',
      body: '🧪 TEST: This week: 18/25 tasks completed (72.0% completion) • 900 points earned!',
      data: {
        'type': typeWeeklySummary,
        'weekStart': weekStartDate.toIso8601String(),
        'weekEnd': weekStartDate.add(const Duration(days: 7)).toIso8601String(),
        'totalTasks': 25,
        'completedTasks': 18,
        'totalPoints': 900,
        'totalEarnings': 540.0,
        'completionRate': 72.0,
        'isTest': true, // Mark as test to distinguish from automatic
        'isManualTest': true,
      },
      priority: NotificationPriority.low,
      sendImmediately: true,
    );

    print('Weekly summary test notification sent (TEST MODE)');
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

  // Compatibility methods (PRESERVING ALL ORIGINAL FUNCTION NAMES)
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

// FIXED Enhanced Summary Notification Service with proper test/automatic separation
class EnhancedSummaryNotificationService {
  static Timer? _mainTimer;
  static Timer? _backgroundTimer;
  static bool _isInitialized = false;

  // FIXED: Add caching to prevent duplicate notifications
  static String? _lastDailySummaryDate;
  static String? _lastWeeklySummaryWeek;

  static Future<void> initializeEnhancedSummaryNotifications() async {
    if (_isInitialized) {
      print('🔄 Enhanced summary service already initialized, reinitializing...');
      dispose();
    }

    print('🚀 Initializing FIXED enhanced summary notification service...');

    try {
      // FIXED: Main timer - checks every 1 minute for precise timing
      _mainTimer = Timer.periodic(
        const Duration(minutes: 1), // CHANGED from 5 to 1 minute
            (timer) async {
          print('⏰ Main timer tick - checking summaries...');
          await _checkAllSummariesFixed();
        },
      );

      // FIXED: Background timer - checks every 5 minutes for backup
      _backgroundTimer = Timer.periodic(
        const Duration(minutes: 5), // CHANGED from 15 to 5 minutes
            (timer) async {
          print('🌙 Background timer tick - checking summaries...');
          await _checkAllSummariesFixed();
        },
      );

      // Initial check after a short delay
      Timer(const Duration(seconds: 30), () async {
        print('🎯 Initial summary check...');
        await _checkAllSummariesFixed();
      });

      _isInitialized = true;
      print('✅ FIXED Enhanced summary notification service initialized');
    } catch (e) {
      print('❌ Failed to initialize enhanced summary service: $e');
      _isInitialized = false;
    }
  }

  // FIXED: Better error handling and user checking
  static Future<void> _checkAllSummariesFixed() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ No authenticated user for summary checks');
        return;
      }

      // Check both daily and weekly summaries
      await Future.wait([
        _checkDailySummaryWithRetryFixed(user.uid),
        _checkWeeklySummaryWithRetryFixed(user.uid),
      ], eagerError: false);

    } catch (e) {
      print('❌ Error in summary check cycle: $e');
    }
  }

  // FIXED: Improved daily summary checking with caching and test separation
  static Future<void> _checkDailySummaryWithRetryFixed(String userId) async {
    try {
      print('🔍 FIXED Daily summary check for user: $userId');

      // Get preferences with timeout
      final preferencesDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('preferences')
          .doc('notifications')
          .get()
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic> prefs = {};
      if (preferencesDoc.exists) {
        prefs = preferencesDoc.data()!;
      }

      final dailySummaryEnabled = prefs['dailySummaryEnabled'] as bool? ?? false;
      final dailySummaryTime = prefs['dailySummaryTime'] as String? ?? '09:00';

      print('📊 Daily summary - Enabled: $dailySummaryEnabled, Time: $dailySummaryTime');

      if (!dailySummaryEnabled) {
        print('🚫 Daily summary is disabled');
        return;
      }

      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // FIXED: Check cache first to prevent duplicates
      if (_lastDailySummaryDate == today) {
        print('✅ Daily summary already sent today (cached): $today');
        return;
      }

      // Parse the target time
      final timeParts = dailySummaryTime.split(':');
      final targetHour = int.parse(timeParts[0]);
      final targetMinute = int.parse(timeParts[1]);

      // FIXED: Better time checking logic
      final currentHour = now.hour;
      final currentMinute = now.minute;

      print('🕐 Current: ${currentHour.toString().padLeft(2, '0')}:${currentMinute.toString().padLeft(2, '0')}, Target: ${targetHour.toString().padLeft(2, '0')}:${targetMinute.toString().padLeft(2, '0')}');

      // FIXED: More lenient time checking - send if current time is at or after target time
      bool shouldSend = false;
      if (currentHour > targetHour) {
        shouldSend = true;
      } else if (currentHour == targetHour && currentMinute >= targetMinute) {
        shouldSend = true;
      }

      if (!shouldSend) {
        print('⏰ Not time for daily summary yet');
        return;
      }

      // FIXED: Double-check with Firestore to avoid duplicates, but only check for AUTOMATIC summaries
      final todayKey = 'auto_daily_$today'; // Use different key prefix for automatic summaries
      final lastSummaryDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('summaryHistory')
          .doc(todayKey)
          .get()
          .timeout(const Duration(seconds: 10));

      if (lastSummaryDoc.exists) {
        print('✅ Automatic daily summary already exists in Firestore for today');
        _lastDailySummaryDate = today; // Update cache
        return;
      }

      print('🎯 Conditions met - generating FIXED daily summary (AUTOMATIC)');
      await _generateAndSendDailySummaryFixed(userId);
      _lastDailySummaryDate = today; // Update cache

    } catch (e) {
      print('❌ FIXED Daily summary check failed: $e');
    }
  }

  // FIXED: Improved weekly summary checking
  static Future<void> _checkWeeklySummaryWithRetryFixed(String userId) async {
    try {
      print('🔍 FIXED Weekly summary check for user: $userId');

      // Get preferences
      final preferencesDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('preferences')
          .doc('notifications')
          .get()
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic> prefs = {};
      if (preferencesDoc.exists) {
        prefs = preferencesDoc.data()!;
      }

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
      final weekKey = 'auto_weekly_${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}'; // Use different key prefix

      // FIXED: Check cache first
      if (_lastWeeklySummaryWeek == weekKey) {
        print('✅ Weekly summary already sent this week (cached): $weekKey');
        return;
      }

      // Double-check with Firestore
      final lastWeeklySummaryDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('summaryHistory')
          .doc(weekKey)
          .get()
          .timeout(const Duration(seconds: 10));

      if (lastWeeklySummaryDoc.exists) {
        print('✅ Automatic weekly summary already exists in Firestore this week');
        _lastWeeklySummaryWeek = weekKey; // Update cache
        return;
      }

      print('🎯 Conditions met - generating FIXED weekly summary (AUTOMATIC)');
      await _generateAndSendWeeklySummaryFixed(userId);
      _lastWeeklySummaryWeek = weekKey; // Update cache

    } catch (e) {
      print('❌ FIXED Weekly summary check failed: $e');
    }
  }

  // FIXED: Generate daily summary - ALWAYS SENDS regardless of data availability
  static Future<void> _generateAndSendDailySummaryFixed(String userId) async {
    try {
      print('📊 Generating FIXED AUTOMATIC daily summary for user: $userId (ALWAYS SENDS)');

      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      // Initialize default values (will send even if no data)
      int totalTasks = 0;
      int completedTasks = 0;
      int pointsEarned = 0;
      double totalEarnings = 0.0;
      bool hasData = false;

      try {
        // TRY to get real data from pointsHistory, but don't fail if no data
        final pointsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('pointsHistory')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(todayDate))
            .where('timestamp', isLessThan: Timestamp.fromDate(todayDate.add(const Duration(days: 1))))
            .get()
            .timeout(const Duration(seconds: 10));

        if (pointsSnapshot.docs.isNotEmpty) {
          hasData = true;
          for (var doc in pointsSnapshot.docs) {
            final data = doc.data();
            pointsEarned += (data['points'] as int? ?? 0);
            totalEarnings += (data['amount'] as double? ?? 0.0);
            if ((data['points'] as int? ?? 0) > 0 || (data['amount'] as double? ?? 0.0) > 0) {
              totalTasks++;
              completedTasks++;
            }
          }
        }
      } catch (e) {
        print('⚠️ Could not fetch user data, but will still send summary: $e');
        // Continue with default values - we still want to send the notification
      }

      print('📈 AUTOMATIC Daily summary stats (hasData: $hasData): Tasks: $totalTasks, Points: $pointsEarned, Earnings: RM${totalEarnings.toStringAsFixed(2)}');

      String summaryTitle = '📊 Daily Summary - ${_formatDate(today)}';
      String summaryBody;

      if (hasData && totalTasks > 0) {
        // User had activity today
        summaryBody = _buildDailySummaryBody(totalTasks, completedTasks, 0, 0, pointsEarned);
      } else {
        // No activity today - but still send a friendly message
        summaryBody = _buildNoActivitySummaryBody();
      }

      // ALWAYS create notification regardless of data availability
      final notificationService = NotificationService();
      await notificationService.createFirestoreNotification(
        userId: userId,
        title: summaryTitle,
        body: summaryBody,
        data: {
          'type': NotificationService.typeDailySummary,
          'date': today.toIso8601String(),
          'totalTasks': totalTasks,
          'completedTasks': completedTasks,
          'inProgressTasks': 0,
          'pendingTasks': 0,
          'pointsEarned': pointsEarned,
          'totalEarnings': totalEarnings,
          'completionRate': totalTasks > 0 ? (completedTasks / totalTasks) * 100 : 0.0,
          'hasData': hasData,
          'isAutoGenerated': true, // Mark as automatic
          'alwaysSend': true, // Flag to indicate this always sends
        },
        priority: NotificationPriority.low,
        sendImmediately: true,
      );

      // ALWAYS mark as sent in summary history with AUTOMATIC prefix
      final todayKey = 'auto_daily_${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('summaryHistory')
          .doc(todayKey)
          .set({
        'type': 'daily',
        'sentAt': FieldValue.serverTimestamp(),
        'totalTasks': totalTasks,
        'completedTasks': completedTasks,
        'pointsEarned': pointsEarned,
        'totalEarnings': totalEarnings,
        'completionRate': totalTasks > 0 ? (completedTasks / totalTasks) * 100 : 0.0,
        'hasData': hasData,
        'alwaysSend': true,
        'isAutoGenerated': true, // Mark as automatic
      }).timeout(const Duration(seconds: 10));

      print('✅ FIXED AUTOMATIC daily summary sent successfully (hasData: $hasData, alwaysSend: true)');

    } catch (e) {
      print('❌ Error generating FIXED AUTOMATIC daily summary: $e');
      // Even if there's an error, we want to mark as attempted to avoid spam
      try {
        final today = DateTime.now();
        final todayKey = 'auto_daily_${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('summaryHistory')
            .doc(todayKey)
            .set({
          'type': 'daily',
          'sentAt': FieldValue.serverTimestamp(),
          'error': e.toString(),
          'attempted': true,
          'isAutoGenerated': true,
        }).timeout(const Duration(seconds: 5));
      } catch (markError) {
        print('❌ Could not even mark as attempted: $markError');
      }
      throw e;
    }
  }

  // FIXED: Generate weekly summary - ALWAYS SENDS regardless of data availability
  static Future<void> _generateAndSendWeeklySummaryFixed(String userId) async {
    try {
      print('📈 Generating FIXED AUTOMATIC weekly summary for user: $userId (ALWAYS SENDS)');

      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final weekEndDate = weekStartDate.add(const Duration(days: 7));

      // Initialize default values (will send even if no data)
      int totalTasks = 0;
      int completedTasks = 0;
      int totalPoints = 0;
      double totalEarnings = 0.0;
      bool hasData = false;

      try {
        // TRY to get real data from pointsHistory for the week
        final pointsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('pointsHistory')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStartDate))
            .where('timestamp', isLessThan: Timestamp.fromDate(weekEndDate))
            .get()
            .timeout(const Duration(seconds: 15));

        if (pointsSnapshot.docs.isNotEmpty) {
          hasData = true;
          for (var doc in pointsSnapshot.docs) {
            final data = doc.data();
            totalPoints += (data['points'] as int? ?? 0);
            totalEarnings += (data['amount'] as double? ?? 0.0);
            if ((data['points'] as int? ?? 0) > 0 || (data['amount'] as double? ?? 0.0) > 0) {
              totalTasks++;
              completedTasks++;
            }
          }
        }
      } catch (e) {
        print('⚠️ Could not fetch weekly data, but will still send summary: $e');
        // Continue with default values - we still want to send the notification
      }

      final completionRate = totalTasks > 0 ? (completedTasks / totalTasks) * 100 : 0.0;

      print('📊 AUTOMATIC Weekly summary stats (hasData: $hasData): Tasks: $totalTasks, Points: $totalPoints, Rate: ${completionRate.toStringAsFixed(1)}%');

      String summaryTitle = '📈 Weekly Summary - Week of ${_formatDate(weekStartDate)}';
      String summaryBody;

      if (hasData && totalTasks > 0) {
        // User had activity this week
        summaryBody = _buildWeeklySummaryBody(totalTasks, completedTasks, totalPoints, completionRate);
      } else {
        // No activity this week - but still send a friendly message
        summaryBody = _buildNoWeeklyActivitySummaryBody();
      }

      // ALWAYS create notification regardless of data availability
      final notificationService = NotificationService();
      await notificationService.createFirestoreNotification(
        userId: userId,
        title: summaryTitle,
        body: summaryBody,
        data: {
          'type': NotificationService.typeWeeklySummary,
          'weekStart': weekStartDate.toIso8601String(),
          'weekEnd': weekEndDate.toIso8601String(),
          'totalTasks': totalTasks,
          'completedTasks': completedTasks,
          'totalPoints': totalPoints,
          'totalEarnings': totalEarnings,
          'completionRate': completionRate,
          'hasData': hasData,
          'isAutoGenerated': true, // Mark as automatic
          'alwaysSend': true, // Flag to indicate this always sends
        },
        priority: NotificationPriority.low,
        sendImmediately: true,
      );

      // ALWAYS mark as sent with AUTOMATIC prefix
      final weekKey = 'auto_weekly_${weekStartDate.year}-${weekStartDate.month.toString().padLeft(2, '0')}-${weekStartDate.day.toString().padLeft(2, '0')}';
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
        'totalTasks': totalTasks,
        'completedTasks': completedTasks,
        'totalPoints': totalPoints,
        'totalEarnings': totalEarnings,
        'completionRate': completionRate,
        'hasData': hasData,
        'alwaysSend': true,
        'isAutoGenerated': true, // Mark as automatic
      }).timeout(const Duration(seconds: 10));

      print('✅ FIXED AUTOMATIC weekly summary sent successfully (hasData: $hasData, alwaysSend: true)');

    } catch (e) {
      print('❌ Error generating FIXED AUTOMATIC weekly summary: $e');
      // Even if there's an error, we want to mark as attempted to avoid spam
      try {
        final now = DateTime.now();
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
        final weekKey = 'auto_weekly_${weekStartDate.year}-${weekStartDate.month.toString().padLeft(2, '0')}-${weekStartDate.day.toString().padLeft(2, '0')}';
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('summaryHistory')
            .doc(weekKey)
            .set({
          'type': 'weekly',
          'sentAt': FieldValue.serverTimestamp(),
          'error': e.toString(),
          'attempted': true,
          'isAutoGenerated': true,
        }).timeout(const Duration(seconds: 5));
      } catch (markError) {
        print('❌ Could not even mark weekly as attempted: $markError');
      }
      throw e;
    }
  }

  static String _buildDailySummaryBody(int total, int completed, int inProgress, int pending, int points) {
    if (total == 0) {
      return _buildNoActivitySummaryBody();
    }

    String emoji = completed == total ? '🎉' :
    completed > total / 2 ? '👍' :
    completed > 0 ? '💪' : '📝';

    return '$emoji Today: $completed tasks completed'
        '${points > 0 ? ' • $points points earned!' : ''}';
  }

  // NEW: Build encouraging message for days with no activity
  static String _buildNoActivitySummaryBody() {
    final encouragingMessages = [
      '🌟 Rest day! Every break makes you stronger for tomorrow.',
      '🌱 Sometimes the best productivity is taking a well-deserved break.',
      '☕ No tasks today? Perfect time to recharge and plan ahead!',
      '🧘‍♂️ Taking time to rest is also productive. You\'ve earned it!',
      '🌙 Quiet day? That\'s okay - tomorrow brings new opportunities!',
      '💤 Rest is part of the journey. Ready to tackle tomorrow?',
      '🎯 Planning mode: Sometimes the best action is preparation.',
    ];

    final now = DateTime.now();
    final messageIndex = now.day % encouragingMessages.length;
    return encouragingMessages[messageIndex];
  }

  static String _buildWeeklySummaryBody(int total, int completed, int points, double rate) {
    if (total == 0) {
      return _buildNoWeeklyActivitySummaryBody();
    }

    String emoji = rate >= 90 ? '🏆' :
    rate >= 70 ? '🌟' :
    rate >= 50 ? '👍' : '💪';

    return '$emoji This week: $completed tasks completed (${rate.toStringAsFixed(1)}% rate)'
        '${points > 0 ? ' • $points points earned!' : ''}';
  }

  // NEW: Build encouraging message for weeks with no activity
  static String _buildNoWeeklyActivitySummaryBody() {
    final encouragingMessages = [
      '🌿 A quiet week can be the start of something amazing next week!',
      '📅 Fresh start ahead! This week is perfect for planning and preparation.',
      '🔋 Rest week complete! Time to recharge and come back stronger.',
      '🎯 New week, new opportunities! Ready to make it count?',
      '🌟 Every successful journey includes rest stops. You\'re on track!',
      '📝 Planning phase: The calm before the productive storm!',
      '💫 Reset complete! This week is your canvas - what will you create?',
    ];

    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final weekNumber = ((dayOfYear - 1) / 7).floor();
    final messageIndex = weekNumber % encouragingMessages.length;
    return encouragingMessages[messageIndex];
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
    _lastDailySummaryDate = null; // FIXED: Clear cache
    _lastWeeklySummaryWeek = null; // FIXED: Clear cache
    print('🛑 FIXED Enhanced summary notification service disposed');
  }
}

enum NotificationPriority {
  low,
  normal,
  high,
  urgent,
}