// lib/Notification Module/HybridNotificationService.dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'LocalNotificationService.dart';
import 'PopupNotificationService.dart';
import 'NotificationService.dart';
import '../models/notification_model.dart';

class HybridNotificationService {
  static final HybridNotificationService _instance = HybridNotificationService._internal();
  factory HybridNotificationService() => _instance;
  HybridNotificationService._internal();

  final LocalNotificationService _localService = LocalNotificationService();
  final PopupNotificationService _popupService = PopupNotificationService();
  final NotificationService _dbService = NotificationService();

  bool _isAppInForeground = true;

  // Initialize all notification services
  Future<void> initialize() async {
    await _localService.initialize();
    print('Hybrid notification service initialized');
  }

  // Set app state (call this from your app lifecycle)
  void setAppState({required bool isInForeground}) {
    _isAppInForeground = isInForeground;
  }

  // Send notification with automatic popup/local decision
  Future<void> sendHybridNotification({
    required BuildContext? context,
    required String userId,
    required String message,
    String title = '',
    required NotificationType type,
    NotificationPriority priority = NotificationPriority.medium,
    Map<String, dynamic> data = const {},
    String? actionUrl,
    bool forceLocal = false,
    bool saveToDatabase = true,
  }) async {
    try {
      // Always save to database if requested
      if (saveToDatabase) {
        await _dbService.sendNotification(
          userId: userId,
          message: message,
          title: title,
          type: type,
          priority: priority,
          data: data,
          actionUrl: actionUrl,
        );
      }

      // Generate unique notification ID
      final notificationId = DateTime.now().millisecondsSinceEpoch;

      // Decide whether to show popup or local notification
      if (_isAppInForeground && context != null && !forceLocal) {
        // Show popup notification when app is in foreground
        _popupService.showPopupNotification(
          context: context,
          message: message,
          title: title,
          type: type,
          priority: priority,
          onTap: () => _handleNotificationAction(data, actionUrl),
        );
      } else {
        // Show local notification when app is in background or forceLocal is true
        await _localService.showNotification(
          id: notificationId,
          title: title.isNotEmpty ? title : _getDefaultTitle(type),
          body: message,
          type: type,
          priority: priority,
          payload: _createPayload(data, actionUrl),
        );
      }

      print('Hybrid notification sent: $message');
    } catch (e) {
      print('Error sending hybrid notification: $e');
    }
  }

  // Schedule task reminder with hybrid approach
  Future<void> scheduleTaskReminderHybrid({
    required String userId,
    required String taskId,
    required String taskTitle,
    required DateTime dueDate,
    List<int> reminderMinutes = const [1440, 60, 30, 15], // 1 day, 1hr, 30min, 15min
    Map<String, dynamic> additionalData = const {},
  }) async {
    try {
      // Schedule local notifications for all reminders
      await _localService.scheduleTaskReminder(
        taskId: taskId,
        taskTitle: taskTitle,
        dueDate: dueDate,
        reminderMinutes: reminderMinutes,
      );

      // Also save reminder settings to database for popup notifications
      for (int minutes in reminderMinutes) {
        final reminderTime = dueDate.subtract(Duration(minutes: minutes));
        if (reminderTime.isBefore(DateTime.now())) continue;

        // Create a scheduled notification record in Firestore
        await _dbService.sendNotification(
          userId: userId,
          message: _getTaskReminderMessage(taskTitle, minutes),
          title: _getTaskReminderTitle(minutes),
          type: NotificationType.reminder,
          priority: _getTaskReminderPriority(minutes),
          data: {
            'taskId': taskId,
            'taskTitle': taskTitle,
            'dueDate': dueDate.toIso8601String(),
            'scheduledFor': reminderTime.toIso8601String(),
            'isScheduled': true,
            ...additionalData,
          },
        );
      }

      print('Task reminders scheduled for: $taskTitle');
    } catch (e) {
      print('Error scheduling task reminder: $e');
    }
  }

  // Schedule job interview reminder
  Future<void> scheduleJobInterviewHybrid({
    required String userId,
    required String jobId,
    required String jobTitle,
    required String companyName,
    required DateTime interviewDate,
    String? interviewLocation,
    String? interviewType,
  }) async {
    try {
      // Schedule local notifications
      await _localService.scheduleJobInterviewReminder(
        jobId: jobId,
        jobTitle: jobTitle,
        companyName: companyName,
        interviewDate: interviewDate,
      );

      // Schedule database notifications for popup display
      final reminderTimes = [
        const Duration(days: 1),
        const Duration(hours: 2),
        const Duration(minutes: 30),
      ];

      for (var duration in reminderTimes) {
        final reminderTime = interviewDate.subtract(duration);
        if (reminderTime.isBefore(DateTime.now())) continue;

        String message;
        String title;
        if (duration.inDays > 0) {
          message = 'Interview tomorrow with $companyName for $jobTitle position';
          title = 'Interview Reminder';
        } else if (duration.inHours > 0) {
          message = 'Interview in ${duration.inHours} hours with $companyName';
          title = 'Interview Soon';
        } else {
          message = 'Interview starting in ${duration.inMinutes} minutes!';
          title = 'Interview Now';
        }

        await _dbService.sendNotification(
          userId: userId,
          message: message,
          title: title,
          type: NotificationType.job,
          priority: duration.inMinutes <= 30
              ? NotificationPriority.critical
              : NotificationPriority.high,
          data: {
            'jobId': jobId,
            'jobTitle': jobTitle,
            'companyName': companyName,
            'interviewDate': interviewDate.toIso8601String(),
            'interviewLocation': interviewLocation,
            'interviewType': interviewType,
            'scheduledFor': reminderTime.toIso8601String(),
            'isScheduled': true,
          },
        );
      }

      print('Interview reminders scheduled for: $jobTitle at $companyName');
    } catch (e) {
      print('Error scheduling interview reminder: $e');
    }
  }

  // Send immediate critical notification (both popup and local)
  Future<void> sendCriticalNotification({
    required BuildContext? context,
    required String userId,
    required String message,
    String title = 'Critical Alert',
    Map<String, dynamic> data = const {},
  }) async {
    final notificationId = DateTime.now().millisecondsSinceEpoch;

    // Always send both popup and local for critical notifications
    if (context != null) {
      _popupService.showPopupNotification(
        context: context,
        message: message,
        title: title,
        type: NotificationType.system,
        priority: NotificationPriority.critical,
        duration: const Duration(seconds: 10),
        onTap: () => _handleNotificationAction(data, null),
      );
    }

    await _localService.showNotification(
      id: notificationId,
      title: title,
      body: message,
      type: NotificationType.system,
      priority: NotificationPriority.critical,
      payload: _createPayload(data, null),
    );

    // Also save to database
    await _dbService.sendNotification(
      userId: userId,
      message: message,
      title: title,
      type: NotificationType.system,
      priority: NotificationPriority.critical,
      data: data,
    );
  }

  // Cancel task notifications
  Future<void> cancelTaskNotifications(String taskId) async {
    await _localService.cancelTaskNotifications(taskId);
    print('Cancelled notifications for task: $taskId');
  }

  // Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _localService.cancelAllNotifications();
    _popupService.clearAll();
    print('Cancelled all notifications');
  }

  // Get pending local notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _localService.getPendingNotifications();
  }

  // Helper methods
  String _getDefaultTitle(NotificationType type) {
    switch (type) {
      case NotificationType.task:
        return 'Task Update';
      case NotificationType.deadline:
        return 'Deadline Alert';
      case NotificationType.job:
        return 'Job Update';
      case NotificationType.acceptance:
        return 'Application Accepted';
      case NotificationType.rejection:
        return 'Application Update';
      case NotificationType.reminder:
        return 'Reminder';
      case NotificationType.progress:
        return 'Progress Update';
      case NotificationType.system:
        return 'Notification';
    }
  }

  String _createPayload(Map<String, dynamic> data, String? actionUrl) {
    final payload = {
      'data': data,
      'actionUrl': actionUrl,
      'timestamp': DateTime.now().toIso8601String(),
    };
    return payload.toString();
  }

  void _handleNotificationAction(Map<String, dynamic> data, String? actionUrl) {
    // Handle notification tap actions
    if (data.containsKey('taskId')) {
      print('Navigate to task: ${data['taskId']}');
    } else if (data.containsKey('jobId')) {
      print('Navigate to job: ${data['jobId']}');
    }

    if (actionUrl != null) {
      print('Navigate to URL: $actionUrl');
    }
  }

  String _getTaskReminderMessage(String taskTitle, int minutes) {
    if (minutes >= 1440) {
      return '"$taskTitle" is due tomorrow';
    } else if (minutes >= 60) {
      return '"$taskTitle" is due in ${(minutes / 60).round()} hour(s)';
    } else {
      return '"$taskTitle" is due in $minutes minutes';
    }
  }

  String _getTaskReminderTitle(int minutes) {
    if (minutes >= 1440) {
      return 'Task Due Tomorrow';
    } else if (minutes <= 15) {
      return 'URGENT: Task Due Soon!';
    } else if (minutes <= 60) {
      return 'Task Reminder';
    } else {
      return 'Upcoming Task';
    }
  }

  NotificationPriority _getTaskReminderPriority(int minutes) {
    if (minutes <= 15) {
      return NotificationPriority.critical;
    } else if (minutes <= 60) {
      return NotificationPriority.high;
    } else {
      return NotificationPriority.medium;
    }
  }
}

// App lifecycle manager to track foreground/background state
class NotificationAppLifecycleManager extends WidgetsBindingObserver {
  final HybridNotificationService _hybridService = HybridNotificationService();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _hybridService.setAppState(isInForeground: true);
        print('App resumed - popup notifications active');
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _hybridService.setAppState(isInForeground: false);
        print('App backgrounded - local notifications active');
        break;
      case AppLifecycleState.hidden:
        _hybridService.setAppState(isInForeground: false);
        break;
    }
  }

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}