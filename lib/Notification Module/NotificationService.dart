// Enhanced NotificationService that stores in Firestore and sends from there

import 'dart:io';

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
import 'dart:convert';
import 'dart:async';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Stream subscription for listening to new notifications
  StreamSubscription<QuerySnapshot>? _notificationSubscription;

  // Notification channels
  static const String highPriorityChannel = 'high_priority_channel';
  static const String defaultChannel = 'default_channel';
  static const String summaryChannel = 'summary_channel';

  // Notification types
  static const String typeDeadlineWarning = 'deadline_warning';
  static const String typeTaskAssigned = 'task_assigned';
  static const String typeStatusChanged = 'status_changed';
  static const String typePriorityAlert = 'priority_alert';
  static const String typeDailySummary = 'daily_summary';
  static const String typeWeeklySummary = 'weekly_summary';
  static const String typeJobCreated = 'job_created';

  Future<void> initialize() async {
    try {
      print('Initializing NotificationService...');

      // Initialize timezone first
      tz.initializeTimeZones();
      print('Timezone initialized');

      // Request notification permissions FIRST
      final permissionGranted = await _requestNotificationPermissions();
      if (!permissionGranted) {
        print('Notification permissions denied');
        // Continue initialization even if permissions denied for now
      }

      // Initialize local notifications
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
        print('Failed to initialize flutter_local_notifications');
        return;
      }
      print('Flutter local notifications initialized');

      // Create notification channels
      await _createNotificationChannels();
      print('Notification channels created');

      // Initialize Firebase Messaging
      await _initializeFirebaseMessaging();
      print('Firebase messaging initialized');

      // Start listening to Firestore notifications
      await _startListeningToFirestoreNotifications();
      print('Firestore notification listener started');

      _isInitialized = true;
      print('NotificationService initialization completed successfully');

    } catch (e) {
      print('Error initializing NotificationService: $e');
      _isInitialized = false;
    }
  }

  // Listen to new notifications in Firestore and send them locally
  Future<void> _startListeningToFirestoreNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('No user authenticated - cannot listen to notifications');
      return;
    }

    print('Starting to listen for notifications for user: ${user.uid}');

    // Simplified query that doesn't require a composite index
    _notificationSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('sent', isEqualTo: false)
    // Removed orderBy to avoid index requirement
        .snapshots()
        .listen((snapshot) {
      print('Firestore notification snapshot received with ${snapshot.docs.length} documents');

      // Sort documents by timestamp in memory if needed
      final sortedDocs = snapshot.docs.toList()
        ..sort((a, b) {
          final aTimestamp = a.data()['timestamp'] as Timestamp?;
          final bTimestamp = b.data()['timestamp'] as Timestamp?;
          if (aTimestamp == null || bTimestamp == null) return 0;
          return bTimestamp.compareTo(aTimestamp); // Descending order
        });

      for (var doc in sortedDocs) {
        // Only process newly added documents
        if (snapshot.docChanges.any((change) =>
        change.type == DocumentChangeType.added &&
            change.doc.id == doc.id)) {

          final notification = doc.data() as Map<String, dynamic>;
          final docId = doc.id;

          print('New notification found in Firestore: ${notification['title']}');
          _processFirestoreNotification(docId, notification);
        }
      }
    }, onError: (error) {
      print('Error listening to Firestore notifications: $error');
    });
  }

  // Process and send notification from Firestore
  Future<void> _processFirestoreNotification(String docId, Map<String, dynamic> notificationData) async {
    try {
      print('Processing Firestore notification: ${notificationData['title']}');

      final title = notificationData['title'] as String? ?? 'Notification';
      final body = notificationData['body'] as String? ?? '';
      final data = notificationData['data'] as Map<String, dynamic>? ?? {};
      final priorityString = notificationData['priority'] as String? ?? 'normal';

      // Convert priority string to enum
      final priority = _stringToNotificationPriority(priorityString);

      // Send the local notification
      await _showLocalNotification(
        title: title,
        body: body,
        payload: jsonEncode(data),
        priority: priority,
      );

      // Mark as sent in Firestore
      await _markNotificationAsSent(docId);

      print('Notification processed and sent: $title');
    } catch (e) {
      print('Error processing Firestore notification: $e');
    }
  }

  // Mark notification as sent in Firestore
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
    }
  }

  // Create notification in Firestore (this is what gets called from your app)
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

      final notificationData = {
        'title': title,
        'body': body,
        'data': data,
        'priority': priority.toString().split('.').last, // Convert enum to string
        'timestamp': FieldValue.serverTimestamp(),
        'sent': false,
        'read': false,
        'scheduledFor': scheduledFor?.toIso8601String(),
        'sendImmediately': sendImmediately,
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .add(notificationData);

      print('Notification created in Firestore successfully');

      // If it's for the current user and should be sent immediately,
      // it will be picked up by the listener automatically

    } catch (e) {
      print('Error creating Firestore notification: $e');
    }
  }

  // Job creation notification using Firestore
  Future<void> showJobCreatedNotification({
    required String jobId,
    required String jobTitle,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No authenticated user for job notification');
        return;
      }

      print('Creating job creation notification in Firestore');

      await createFirestoreNotification(
        userId: user.uid,
        title: '✅ Job Created Successfully!',
        body: 'Your job "$jobTitle" has been posted successfully.',
        data: {
          'type': typeJobCreated,
          'jobId': jobId,
          'timestamp': DateTime.now().toIso8601String(),
        },
        priority: NotificationPriority.normal,
        sendImmediately: true,
      );

      print('Job creation notification created in Firestore for: $jobTitle');
    } catch (e) {
      print('Error creating job notification: $e');
    }
  }

  // Real-time notification using Firestore
  Future<void> sendRealTimeNotification({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    try {
      print('Sending real-time notification via Firestore to user: $userId');

      await createFirestoreNotification(
        userId: userId,
        title: title,
        body: body,
        data: data,
        priority: priority,
        sendImmediately: true,
      );

      print('Real-time notification created in Firestore');
    } catch (e) {
      print('Error sending real-time notification: $e');
    }
  }

  // UPDATED: Get user's notification preferences from Firestore
  Future<Map<String, dynamic>> _getUserNotificationPreferences(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('preferences')
          .doc('notifications')
          .get();

      if (doc.exists) {
        return doc.data() ?? {};
      } else {
        // Return default preferences if no custom preferences exist
        return {
          'deadlineWarningHours': 24,
          'secondWarningHours': 2,
          'deadlineNotificationsEnabled': true,
          'soundEnabled': true,
          'vibrationEnabled': true,
          'highPriorityOnly': false,
        };
      }
    } catch (e) {
      print('Error getting user notification preferences: $e');
      // Return defaults on error
      return {
        'deadlineWarningHours': 24,
        'secondWarningHours': 2,
        'deadlineNotificationsEnabled': true,
        'soundEnabled': true,
        'vibrationEnabled': true,
        'highPriorityOnly': false,
      };
    }
  }

  // UPDATED: Schedule deadline reminders for employees only with user preferences
  Future<void> scheduleDeadlineRemindersForEmployees({
    required String taskId,
    required String taskTitle,
    required DateTime deadline,
    required List<String> employeeIds, // Only employees get deadline reminders
    String? employerUserId, // Employer doesn't get deadline reminders
  }) async {
    try {
      print('Scheduling deadline reminders for employees: $employeeIds');

      // Schedule reminders for each employee
      for (String employeeId in employeeIds) {
        // Get employee's notification preferences
        final preferences = await _getUserNotificationPreferences(employeeId);

        // Check if deadline notifications are enabled for this user
        final deadlineNotificationsEnabled = preferences['deadlineNotificationsEnabled'] as bool? ?? true;
        if (!deadlineNotificationsEnabled) {
          print('Deadline notifications disabled for user: $employeeId');
          continue;
        }

        final deadlineWarningHours = preferences['deadlineWarningHours'] as int? ?? 24;
        final secondWarningHours = preferences['secondWarningHours'] as int? ?? 2;

        print('User $employeeId preferences: ${deadlineWarningHours}h and ${secondWarningHours}h warnings');

        // Primary deadline warning (user-configurable, default 24 hours)
        final warningTime = deadline.subtract(Duration(hours: deadlineWarningHours));
        if (warningTime.isAfter(DateTime.now())) {
          await createFirestoreNotification(
            userId: employeeId,
            title: '⏰ Deadline Warning',
            body: 'Task "$taskTitle" deadline in $deadlineWarningHours hours!',
            data: {
              'type': typeDeadlineWarning,
              'taskId': taskId,
              'deadline': deadline.toIso8601String(),
              'warningType': 'primary',
            },
            priority: NotificationPriority.high,
            sendImmediately: false,
            scheduledFor: warningTime,
          );
          print('Primary deadline warning scheduled for $employeeId at $warningTime');
        }

        // Secondary deadline warning (user-configurable, default 2 hours)
        final urgentWarningTime = deadline.subtract(Duration(hours: secondWarningHours));
        if (urgentWarningTime.isAfter(DateTime.now()) && urgentWarningTime.isAfter(warningTime)) {
          await createFirestoreNotification(
            userId: employeeId,
            title: '🚨 URGENT: Deadline in $secondWarningHours Hours!',
            body: 'Complete "$taskTitle" immediately!',
            data: {
              'type': typePriorityAlert,
              'taskId': taskId,
              'deadline': deadline.toIso8601String(),
              'warningType': 'urgent',
            },
            priority: NotificationPriority.urgent,
            sendImmediately: false,
            scheduledFor: urgentWarningTime,
          );
          print('Urgent deadline warning scheduled for $employeeId at $urgentWarningTime');
        }

        // Final deadline notification (30 minutes before)
        final finalWarningTime = deadline.subtract(const Duration(minutes: 30));
        if (finalWarningTime.isAfter(DateTime.now()) && finalWarningTime.isAfter(urgentWarningTime)) {
          await createFirestoreNotification(
            userId: employeeId,
            title: '🔴 FINAL WARNING: 30 Minutes Left!',
            body: 'Task "$taskTitle" deadline is in 30 minutes!',
            data: {
              'type': typePriorityAlert,
              'taskId': taskId,
              'deadline': deadline.toIso8601String(),
              'warningType': 'final',
            },
            priority: NotificationPriority.urgent,
            sendImmediately: false,
            scheduledFor: finalWarningTime,
          );
          print('Final deadline warning scheduled for $employeeId at $finalWarningTime');
        }
      }

      print('Deadline reminders scheduled for ${employeeIds.length} employees');
    } catch (e) {
      print('Error scheduling deadline reminders: $e');
    }
  }

  // UPDATED: Save user notification preferences to Firestore
  Future<void> saveNotificationPreferences({
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
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No authenticated user to save preferences');
        return;
      }

      final preferences = <String, dynamic>{};

      if (deadlineWarningHours != null) preferences['deadlineWarningHours'] = deadlineWarningHours;
      if (secondWarningHours != null) preferences['secondWarningHours'] = secondWarningHours;
      if (deadlineNotificationsEnabled != null) preferences['deadlineNotificationsEnabled'] = deadlineNotificationsEnabled;
      if (dailySummaryEnabled != null) preferences['dailySummaryEnabled'] = dailySummaryEnabled;
      if (weeklySummaryEnabled != null) preferences['weeklySummaryEnabled'] = weeklySummaryEnabled;
      if (dailySummaryTime != null) preferences['dailySummaryTime'] = dailySummaryTime;
      if (soundEnabled != null) preferences['soundEnabled'] = soundEnabled;
      if (vibrationEnabled != null) preferences['vibrationEnabled'] = vibrationEnabled;
      if (highPriorityOnly != null) preferences['highPriorityOnly'] = highPriorityOnly;
      if (taskAssignedNotifications != null) preferences['taskAssignedNotifications'] = taskAssignedNotifications;
      if (statusChangeNotifications != null) preferences['statusChangeNotifications'] = statusChangeNotifications;
      if (completionReviewNotifications != null) preferences['completionReviewNotifications'] = completionReviewNotifications;
      if (milestoneNotifications != null) preferences['milestoneNotifications'] = milestoneNotifications;

      // Add timestamp
      preferences['lastUpdated'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('preferences')
          .doc('notifications')
          .set(preferences, SetOptions(merge: true));

      print('Notification preferences saved to Firestore');
    } catch (e) {
      print('Error saving notification preferences: $e');
    }
  }

  // DEPRECATED: Keep old method for backward compatibility but mark as deprecated
  @deprecated
  Future<void> scheduleDeadlineReminders({
    required String taskId,
    required String taskTitle,
    required DateTime deadline,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Use the new method with current user as the only employee
    await scheduleDeadlineRemindersForEmployees(
      taskId: taskId,
      taskTitle: taskTitle,
      deadline: deadline,
      employeeIds: [user.uid],
    );
  }

  Future<void> _createNotificationChannels() async {
    final androidPlugin = _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // High priority channel with heads-up notifications
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          highPriorityChannel,
          'High Priority Notifications',
          description: 'Urgent alerts and deadline warnings',
          importance: Importance.max, // Changed to max for heads-up
          playSound: true,
          enableVibration: true,
          enableLights: true,
          showBadge: true,
          sound: RawResourceAndroidNotificationSound('notification'), // Add custom sound if available
        ),
      );

      // Default channel with high importance for pop-ups
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          defaultChannel,
          'Default Notifications',
          description: 'Regular task updates and reminders',
          importance: Importance.high, // Changed from defaultImportance to high
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          summaryChannel,
          'Summary Notifications',
          description: 'Daily and weekly task summaries',
          importance: Importance.low,
          showBadge: true,
        ),
      );
    }
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

  // Actually show the local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String payload,
    NotificationPriority priority = NotificationPriority.normal,
    bool showBigText = false,
  }) async {
    try {
      print('Showing local notification: $title');

      if (!_isInitialized) {
        print('Cannot show notification - service not initialized');
        return;
      }

      // Check for Android 13+ permissions
      final hasPermission = await _requestExactNotificationPermissions();
      if (!hasPermission) {
        print('Cannot show notification - no permissions');
        return;
      }

      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);

      // For testing, force high priority to ensure pop-up
      final testPriority = priority == NotificationPriority.normal
          ? NotificationPriority.high
          : priority;

      await _flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        _getNotificationDetails(testPriority, showBigText: showBigText),
        payload: payload,
      );

      print('Local notification shown with ID: $id, Priority: $testPriority');
    } catch (e) {
      print('Error showing local notification: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  // Test notification
  Future<void> testNotificationStyles() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Test 1: High priority notification
      await createFirestoreNotification(
        userId: user.uid,
        title: '🚨 High Priority Test',
        body: 'This should appear as a heads-up notification',
        data: {'type': 'test_high'},
        priority: NotificationPriority.high,
        sendImmediately: true,
      );

      // Wait a bit
      await Future.delayed(const Duration(seconds: 2));

      // Test 2: Urgent notification
      await createFirestoreNotification(
        userId: user.uid,
        title: '🔴 Urgent Test',
        body: 'This should definitely pop up!',
        data: {'type': 'test_urgent'},
        priority: NotificationPriority.urgent,
        sendImmediately: true,
      );

      print('Test notifications created with different priorities');
    } catch (e) {
      print('Error in testNotificationStyles: $e');
    }
  }

  // Other existing methods remain the same...
  Future<bool> _requestNotificationPermissions() async {
    try {
      final PermissionStatus status = await Permission.notification.request();

      if (status.isGranted) {
        print('Notification permission granted');
        return true;
      } else if (status.isDenied) {
        print('Notification permission denied');
        return false;
      } else if (status.isPermanentlyDenied) {
        print('Notification permission permanently denied');
        return false;
      }

      return false;
    } catch (e) {
      print('Error requesting notification permissions: $e');
      return false;
    }
  }

  Future<bool> checkNotificationPermissions() async {
    try {
      final PermissionStatus status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      print('Error checking notification permissions: $e');
      return false;
    }
  }

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

  Future<bool> _requestExactNotificationPermissions() async {
    try {
      // Check Android version
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;

        // Android 13 (API 33) and above require POST_NOTIFICATIONS permission
        if (androidInfo.version.sdkInt >= 33) {
          final status = await Permission.notification.status;

          if (!status.isGranted) {
            final result = await Permission.notification.request();

            if (!result.isGranted) {
              // Open app settings if permission is permanently denied
              if (result.isPermanentlyDenied) {
                await openAppSettings();
              }
              return false;
            }
          }
        }

        // Check if notifications are enabled at the system level
        final bool? areNotificationsEnabled = await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled();

        if (areNotificationsEnabled == false) {
          // Prompt user to enable notifications in settings
          print('Notifications are disabled at system level');
          return false;
        }
      }

      return true;
    } catch (e) {
      print('Error checking notification permissions: $e');
      return false;
    }
  }

  NotificationDetails _getNotificationDetails(NotificationPriority priority, {bool showBigText = false}) {
    final androidDetails = AndroidNotificationDetails(
      _getChannelForPriority(priority),
      _getChannelNameForPriority(priority),
      channelDescription: 'Task management notifications',
      importance: _getImportanceForPriority(priority),
      priority: _getPriorityForNotificationPriority(priority),
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF006D77),
      enableLights: true, // Always enable lights
      enableVibration: true, // Always enable vibration
      playSound: true,
      styleInformation: showBigText
          ? const BigTextStyleInformation('')
          : const DefaultStyleInformation(true, true), // Show as pop-up
      // Add these for better visibility
      fullScreenIntent: priority == NotificationPriority.urgent, // For urgent notifications
      visibility: NotificationVisibility.public,
      autoCancel: true,
      ongoing: false,
      ticker: 'New notification', // Shows in status bar
      // For Android 12+
      channelShowBadge: true,
      category: AndroidNotificationCategory.message,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive, // For iOS 15+
    );

    return NotificationDetails(android: androidDetails, iOS: iosDetails);
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

  void _onNotificationResponse(NotificationResponse response) {
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      final type = data['type'] as String?;
      print('Notification tapped: $type');
    }
  }

  // Placeholder methods for compatibility
  Future<void> generateDailySummary() async {
    print('generateDailySummary called');
  }

  Future<void> updateNotificationPreferences({
    int? deadlineWarningHours,
    bool? dailySummaryEnabled,
    bool? weeklySummaryEnabled,
    String? dailySummaryTime,
    bool? soundEnabled,
    bool? vibrationEnabled,
  }) async {
    print('updateNotificationPreferences called - redirecting to saveNotificationPreferences');
    await saveNotificationPreferences(
      deadlineWarningHours: deadlineWarningHours,
      dailySummaryEnabled: dailySummaryEnabled,
      weeklySummaryEnabled: weeklySummaryEnabled,
      dailySummaryTime: dailySummaryTime,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
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

  void dispose() {
    _notificationSubscription?.cancel();
  }
}

enum NotificationPriority {
  low,
  normal,
  high,
  urgent,
}