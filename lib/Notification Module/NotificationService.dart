// lib/services/NotificationService.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
    InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );

    // Request permissions
    await _requestPermissions();

    _isInitialized = true;
    print('Notification service initialized');
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      // Request notification permission
      await androidImplementation?.requestNotificationsPermission();

      // Request exact alarm permission for Android 12+
      try {
        await androidImplementation?.requestExactAlarmsPermission();
      } catch (e) {
        print('Exact alarm permission not available or already granted: $e');
      }
    }

    if (Platform.isIOS) {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      print('Notification tapped: $payload');
    }
  }

  // Show immediate notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String channelId = 'default_channel',
    String channelName = 'Default Notifications',
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Default notification channel',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF006D77),
      styleInformation: BigTextStyleInformation(body),
      ticker: title,
      showWhen: true,
      autoCancel: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  // Schedule notification with fallback for permission issues
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String channelId = 'scheduled_channel',
    String channelName = 'Scheduled Notifications',
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    // Check if the scheduled time is in the past
    if (scheduledTime.isBefore(DateTime.now())) {
      print('Cannot schedule notification for past time: $scheduledTime');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Scheduled notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF006D77),
      styleInformation: BigTextStyleInformation(body),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        notificationDetails,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
      );
      print('Notification scheduled successfully for: $scheduledTime');
    } catch (e) {
      print('Error scheduling notification, trying alternative method: $e');
      // Fallback: try with inexact timing
      try {
        await _flutterLocalNotificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          tz.TZDateTime.from(scheduledTime, tz.local),
          notificationDetails,
          payload: payload,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
        );
        print('Notification scheduled with inexact timing for: $scheduledTime');
      } catch (e2) {
        print('Failed to schedule notification: $e2');
        // If scheduling fails, show immediate notification as fallback
        await showNotification(
          id: id,
          title: 'Reminder Set',
          body: 'We\'ll remind you about: $title',
          channelId: channelId,
          channelName: channelName,
          payload: payload,
        );
      }
    }
  }

  // New task posted notification
  Future<void> notifyNewTaskPosted({
    required String taskTitle,
    required String employerName,
    required String taskId,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch,
      title: 'New Task Available',
      body: '$employerName posted a new task: $taskTitle',
      channelId: 'new_tasks',
      channelName: 'New Tasks',
      payload: 'task_$taskId',
    );
  }

  // Task status changed notification
  Future<void> notifyTaskStatusChanged({
    required String taskTitle,
    required String newStatus,
    required String taskId,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch,
      title: 'Task Status Updated',
      body: '$taskTitle status changed to: $newStatus',
      channelId: 'task_status',
      channelName: 'Task Status Updates',
      payload: 'task_$taskId',
    );
  }

  // Deadline up notification
  Future<void> notifyDeadlineUp({
    required String taskTitle,
    required String taskId,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch,
      title: 'DEADLINE ALERT!',
      body: 'The deadline for "$taskTitle" has passed!',
      channelId: 'deadlines',
      channelName: 'Deadline Alerts',
      payload: 'task_$taskId',
    );
  }

  // Schedule deadline reminders with better error handling
  Future<void> scheduleDeadlineReminders({
    required String taskId,
    required String taskTitle,
    required DateTime deadline,
  }) async {
    final now = DateTime.now();

    // Schedule reminders only if they're in the future
    final reminders = [
      {'duration': const Duration(days: 1), 'title': 'Task Due Tomorrow', 'urgent': false},
      {'duration': const Duration(hours: 2), 'title': 'Task Due in 2 Hours', 'urgent': true},
      {'duration': const Duration(minutes: 30), 'title': 'Task Due in 30 Minutes', 'urgent': true},
    ];

    for (int i = 0; i < reminders.length; i++) {
      final reminder = reminders[i];
      final reminderTime = deadline.subtract(reminder['duration'] as Duration);

      if (reminderTime.isAfter(now)) {
        final isUrgent = reminder['urgent'] as bool;
        await scheduleNotification(
          id: '${taskId}_reminder_$i'.hashCode,
          title: reminder['title'] as String,
          body: isUrgent
              ? 'URGENT: "$taskTitle" deadline approaching!'
              : 'Reminder: "$taskTitle" is due tomorrow',
          scheduledTime: reminderTime,
          channelId: isUrgent ? 'urgent_reminders' : 'reminders',
          channelName: isUrgent ? 'Urgent Reminders' : 'Task Reminders',
          payload: 'reminder_$taskId',
        );
      }
    }

    // Schedule deadline passed notification
    final afterDeadline = deadline.add(const Duration(minutes: 5));
    if (afterDeadline.isAfter(now)) {
      await scheduleNotification(
        id: '${taskId}_deadline'.hashCode,
        title: 'DEADLINE PASSED!',
        body: 'The deadline for "$taskTitle" has passed!',
        scheduledTime: afterDeadline,
        channelId: 'deadlines',
        channelName: 'Deadline Alerts',
        payload: 'deadline_$taskId',
      );
    }
  }

  // Daily summary notification (fallback to periodic if exact scheduling fails)
  Future<void> scheduleDailySummary() async {
    try {
      final now = DateTime.now();
      final tomorrow9AM = DateTime(now.year, now.month, now.day + 1, 9, 0);

      await scheduleNotification(
        id: 'daily_summary'.hashCode,
        title: 'Daily Task Summary',
        body: 'Check your tasks and deadlines for today',
        scheduledTime: tomorrow9AM,
        channelId: 'summaries',
        channelName: 'Task Summaries',
        payload: 'daily_summary',
      );
    } catch (e) {
      print('Failed to schedule daily summary: $e');
      // Show immediate notification as fallback
      await showNotification(
        id: 'daily_summary_fallback'.hashCode,
        title: 'Daily Summary Enabled',
        body: 'Daily task summaries have been enabled',
        channelId: 'summaries',
        channelName: 'Task Summaries',
      );
    }
  }

  // Weekly summary notification
  Future<void> scheduleWeeklySummary() async {
    try {
      final now = DateTime.now();
      final daysUntilMonday = (8 - now.weekday) % 7;
      final nextMonday9AM = DateTime(
          now.year,
          now.month,
          now.day + daysUntilMonday,
          9,
          0
      );

      await scheduleNotification(
        id: 'weekly_summary'.hashCode,
        title: 'Weekly Task Summary',
        body: 'Review your task progress and upcoming deadlines for this week',
        scheduledTime: nextMonday9AM,
        channelId: 'summaries',
        channelName: 'Task Summaries',
        payload: 'weekly_summary',
      );
    } catch (e) {
      print('Failed to schedule weekly summary: $e');
      // Show immediate notification as fallback
      await showNotification(
        id: 'weekly_summary_fallback'.hashCode,
        title: 'Weekly Summary Enabled',
        body: 'Weekly task summaries have been enabled',
        channelId: 'summaries',
        channelName: 'Task Summaries',
      );
    }
  }

  // Progress update notification
  Future<void> notifyProgressUpdate({
    required String taskTitle,
    required double progressPercentage,
    required String taskId,
  }) async {
    String message;
    if (progressPercentage >= 100) {
      message = 'Congratulations! You completed "$taskTitle"';
    } else if (progressPercentage >= 75) {
      message = 'Great progress! "$taskTitle" is ${progressPercentage.toInt()}% complete';
    } else if (progressPercentage >= 50) {
      message = 'Halfway there! "$taskTitle" is ${progressPercentage.toInt()}% complete';
    } else {
      message = 'Progress update: "$taskTitle" is ${progressPercentage.toInt()}% complete';
    }

    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch,
      title: 'Progress Update',
      body: message,
      channelId: 'progress',
      channelName: 'Progress Updates',
      payload: 'progress_$taskId',
    );
  }

  // Monitor new tasks from Firestore
  void startTaskMonitoring() {
    FirebaseFirestore.instance
        .collection('jobs')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          notifyNewTaskPosted(
            taskTitle: data['jobPosition'] ?? 'New Task',
            employerName: data['employerName'] ?? 'Unknown Employer',
            taskId: change.doc.id,
          );
        }
      }
    });
  }

  // Monitor task status changes for accepted applicants
  void startStatusMonitoring(String userId) {
    // Monitor jobs where user is accepted
    FirebaseFirestore.instance
        .collection('jobs')
        .where('acceptedApplicants', arrayContains: userId)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data()!;
          final taskTitle = data['jobPosition'] ?? 'Task';
          final isCompleted = data['isCompleted'] ?? false;

          if (isCompleted) {
            notifyTaskStatusChanged(
              taskTitle: taskTitle,
              newStatus: 'Completed',
              taskId: change.doc.id,
            );
          }
        }
      }
    });

    // Monitor task progress
    FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('taskProgress')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data()!;
          final progress = (data['currentProgress'] ?? 0.0).toDouble();
          final taskTitle = data['taskTitle'] ?? 'Task';

          // Notify on milestone achievements (25%, 50%, 75%, 100%)
          if (progress % 25 == 0 && progress > 0) {
            notifyProgressUpdate(
              taskTitle: taskTitle,
              progressPercentage: progress,
              taskId: change.doc.id,
            );
          }
        }
      }
    });
  }

  // Cancel specific notification
  Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
  }

  // Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  // Cancel task-specific notifications
  Future<void> cancelTaskNotifications(String taskId) async {
    for (int i = 0; i < 3; i++) {
      await cancelNotification('${taskId}_reminder_$i'.hashCode);
    }
    await cancelNotification('${taskId}_deadline'.hashCode);
  }

  // Check if exact alarms are supported
  Future<bool> canScheduleExactNotifications() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      try {
        return await androidImplementation?.canScheduleExactNotifications() ?? false;
      } catch (e) {
        print('Cannot check exact notification permissions: $e');
        return false;
      }
    }
    return true; // iOS doesn't have this restriction
  }
}