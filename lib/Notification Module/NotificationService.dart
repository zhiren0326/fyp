import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/notification_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Send a notification to a specific user
  Future<void> sendNotification({
    required String userId,
    required String message,
    String title = '',
    required NotificationType type,
    NotificationPriority priority = NotificationPriority.medium,
    Map<String, dynamic> data = const {},
    String? actionUrl,
  }) async {
    try {
      // Check user's notification settings first
      final settings = await _getUserNotificationSettings(userId);
      if (!_shouldSendNotification(type, priority, settings)) {
        return;
      }

      // Check quiet hours
      if (_isQuietHours(settings)) {
        // Schedule for later or skip based on priority
        if (priority == NotificationPriority.critical) {
          // Send anyway for critical notifications
        } else {
          // Skip or schedule for later
          return;
        }
      }

      final notification = AppNotification(
        id: '', // Will be generated by Firestore
        message: message,
        title: title,
        type: type,
        priority: priority,
        timestamp: DateTime.now(),
        data: data,
        actionUrl: actionUrl,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .add(notification.toFirestore());

      print('Notification sent to user $userId: $message');
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  // Send notification to multiple users
  Future<void> sendBulkNotification({
    required List<String> userIds,
    required String message,
    String title = '',
    required NotificationType type,
    NotificationPriority priority = NotificationPriority.medium,
    Map<String, dynamic> data = const {},
  }) async {
    final batch = FirebaseFirestore.instance.batch();

    for (String userId in userIds) {
      final settings = await _getUserNotificationSettings(userId);
      if (!_shouldSendNotification(type, priority, settings)) {
        continue;
      }

      if (_isQuietHours(settings) && priority != NotificationPriority.critical) {
        continue;
      }

      final notification = AppNotification(
        id: '',
        message: message,
        title: title,
        type: type,
        priority: priority,
        timestamp: DateTime.now(),
        data: data,
      );

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc();

      batch.set(docRef, notification.toFirestore());
    }

    try {
      await batch.commit();
      print('Bulk notification sent to ${userIds.length} users');
    } catch (e) {
      print('Error sending bulk notification: $e');
    }
  }

  // Send task reminder notification
  Future<void> sendTaskReminder({
    required String userId,
    required String taskTitle,
    required String taskId,
    required DateTime dueDate,
    int minutesBefore = 60,
  }) async {
    final timeUntilDue = dueDate.difference(DateTime.now()).inMinutes;

    if (timeUntilDue <= minutesBefore && timeUntilDue > 0) {
      String message;
      NotificationPriority priority;

      if (timeUntilDue <= 15) {
        message = 'URGENT: "$taskTitle" is due in ${timeUntilDue} minutes!';
        priority = NotificationPriority.critical;
      } else if (timeUntilDue <= 60) {
        message = 'Reminder: "$taskTitle" is due in ${timeUntilDue} minutes';
        priority = NotificationPriority.high;
      } else {
        message = 'Upcoming: "$taskTitle" is due in ${(timeUntilDue / 60).round()} hours';
        priority = NotificationPriority.medium;
      }

      await sendNotification(
        userId: userId,
        message: message,
        title: 'Task Reminder',
        type: NotificationType.reminder,
        priority: priority,
        data: {
          'taskId': taskId,
          'taskTitle': taskTitle,
          'dueDate': dueDate.toIso8601String(),
        },
      );
    }
  }

  // Send deadline alert notification
  Future<void> sendDeadlineAlert({
    required String userId,
    required String taskTitle,
    required String taskId,
    required DateTime deadline,
  }) async {
    await sendNotification(
      userId: userId,
      message: 'DEADLINE ALERT: "$taskTitle" deadline has passed!',
      title: 'Missed Deadline',
      type: NotificationType.deadline,
      priority: NotificationPriority.critical,
      data: {
        'taskId': taskId,
        'taskTitle': taskTitle,
        'deadline': deadline.toIso8601String(),
      },
    );
  }

  // Send job application status notification
  Future<void> sendJobStatusNotification({
    required String userId,
    required String jobTitle,
    required String jobId,
    required bool accepted,
    String? reason,
  }) async {
    final message = accepted
        ? 'Congratulations! You have been accepted for "$jobTitle"'
        : 'Your application for "$jobTitle" was not accepted${reason != null ? ': $reason' : ''}';

    await sendNotification(
      userId: userId,
      message: message,
      title: accepted ? 'Application Accepted' : 'Application Update',
      type: accepted ? NotificationType.acceptance : NotificationType.rejection,
      priority: NotificationPriority.high,
      data: {
        'jobId': jobId,
        'jobTitle': jobTitle,
        'accepted': accepted,
        'reason': reason,
      },
    );
  }

  // Send progress update notification
  Future<void> sendProgressNotification({
    required String userId,
    required String taskTitle,
    required String taskId,
    required double progressPercentage,
  }) async {
    String message;
    if (progressPercentage >= 100) {
      message = 'Congratulations! You completed "$taskTitle"';
    } else if (progressPercentage >= 75) {
      message = 'Great progress! "$taskTitle" is ${progressPercentage.toInt()}% complete';
    } else if (progressPercentage >= 50) {
      message = 'You\'re halfway there! "$taskTitle" is ${progressPercentage.toInt()}% complete';
    } else {
      message = 'Progress update: "$taskTitle" is ${progressPercentage.toInt()}% complete';
    }

    await sendNotification(
      userId: userId,
      message: message,
      title: 'Progress Update',
      type: NotificationType.progress,
      priority: NotificationPriority.medium,
      data: {
        'taskId': taskId,
        'taskTitle': taskTitle,
        'progressPercentage': progressPercentage,
      },
    );
  }

  // Schedule recurring notifications (for background processing)
  Future<void> scheduleRecurringNotifications() async {
    try {
      // Get all users with active tasks
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .get();

      for (var userDoc in usersQuery.docs) {
        final userId = userDoc.id;

        // Check user's notification settings
        final settings = await _getUserNotificationSettings(userId);
        if (!settings['taskReminders']) continue;

        // Get user's tasks with deadlines
        final tasksQuery = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('tasks')
            .where('date', isGreaterThanOrEqualTo: DateTime.now().toIso8601String().split('T')[0])
            .get();

        for (var taskDoc in tasksQuery.docs) {
          final taskData = taskDoc.data();
          final tasks = taskData['tasks'] as List<dynamic>? ?? [];

          for (var task in tasks) {
            if (task['deadline'] != null) {
              final deadline = DateTime.parse(task['deadline']);
              await sendTaskReminder(
                userId: userId,
                taskTitle: task['title'] ?? 'Unnamed Task',
                taskId: task['id'] ?? taskDoc.id,
                dueDate: deadline,
                minutesBefore: settings['reminderTimeBefore'] ?? 60,
              );
            }
          }
        }

        // Check job deadlines
        final jobsQuery = await FirebaseFirestore.instance
            .collection('jobs')
            .where('acceptedApplicants', arrayContains: userId)
            .where('endDate', isGreaterThanOrEqualTo: DateTime.now().toIso8601String().split('T')[0])
            .get();

        for (var jobDoc in jobsQuery.docs) {
          final jobData = jobDoc.data();
          if (jobData['endDate'] != null) {
            final endDate = DateTime.parse(jobData['endDate']);
            await sendTaskReminder(
              userId: userId,
              taskTitle: jobData['jobPosition'] ?? 'Job Task',
              taskId: jobDoc.id,
              dueDate: endDate,
              minutesBefore: settings['reminderTimeBefore'] ?? 60,
            );
          }
        }
      }
    } catch (e) {
      print('Error in scheduled notifications: $e');
    }
  }

  // Get user's notification settings
  Future<Map<String, dynamic>> _getUserNotificationSettings(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('settings')
          .doc('notifications')
          .get();

      if (doc.exists) {
        return doc.data()!;
      } else {
        // Return default settings
        return {
          'taskReminders': true,
          'deadlineAlerts': true,
          'jobUpdates': true,
          'systemNotifications': true,
          'pushNotifications': true,
          'emailNotifications': false,
          'reminderTimeBefore': 60,
          'quietHours': ["22:00", "08:00"],
          'priority': "all",
        };
      }
    } catch (e) {
      print('Error getting notification settings: $e');
      return {
        'taskReminders': true,
        'deadlineAlerts': true,
        'jobUpdates': true,
        'systemNotifications': true,
        'pushNotifications': true,
        'emailNotifications': false,
        'reminderTimeBefore': 60,
        'quietHours': ["22:00", "08:00"],
        'priority': "all",
      };
    }
  }

  // Check if notification should be sent based on user settings
  bool _shouldSendNotification(NotificationType type, NotificationPriority priority, Map<String, dynamic> settings) {
    // Check priority filter
    final priorityFilter = settings['priority'] ?? 'all';
    if (priorityFilter == 'high' && priority == NotificationPriority.low) {
      return false;
    }
    if (priorityFilter == 'critical' && (priority == NotificationPriority.low || priority == NotificationPriority.medium)) {
      return false;
    }

    // Check type-specific settings
    switch (type) {
      case NotificationType.task:
      case NotificationType.reminder:
        return settings['taskReminders'] ?? true;
      case NotificationType.deadline:
        return settings['deadlineAlerts'] ?? true;
      case NotificationType.job:
      case NotificationType.acceptance:
      case NotificationType.rejection:
        return settings['jobUpdates'] ?? true;
      case NotificationType.system:
        return settings['systemNotifications'] ?? true;
      default:
        return true;
    }
  }

  // Check if current time is within quiet hours
  bool _isQuietHours(Map<String, dynamic> settings) {
    final quietHours = settings['quietHours'] as List<dynamic>? ?? ["22:00", "08:00"];
    if (quietHours.length != 2) return false;

    final now = DateTime.now();
    final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final startTime = quietHours[0] as String;
    final endTime = quietHours[1] as String;

    // Handle overnight quiet hours (e.g., 22:00 to 08:00)
    if (startTime.compareTo(endTime) > 0) {
      return currentTime.compareTo(startTime) >= 0 || currentTime.compareTo(endTime) <= 0;
    } else {
      return currentTime.compareTo(startTime) >= 0 && currentTime.compareTo(endTime) <= 0;
    }
  }

  // Mark notification as read
  Future<void> markAsRead(String userId, String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  // Get unread notification count
  Future<int> getUnreadCount(String userId) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .get();

      return query.docs.length;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  // Clean old notifications (older than 30 days)
  Future<void> cleanOldNotifications() async {
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .get();

      for (var userDoc in usersQuery.docs) {
        final notificationsQuery = await FirebaseFirestore.instance
            .collection('users')
            .doc(userDoc.id)
            .collection('notifications')
            .where('timestamp', isLessThan: Timestamp.fromDate(cutoffDate))
            .get();

        final batch = FirebaseFirestore.instance.batch();
        for (var notificationDoc in notificationsQuery.docs) {
          batch.delete(notificationDoc.reference);
        }

        if (notificationsQuery.docs.isNotEmpty) {
          await batch.commit();
          print('Cleaned ${notificationsQuery.docs.length} old notifications for user ${userDoc.id}');
        }
      }
    } catch (e) {
      print('Error cleaning old notifications: $e');
    }
  }
}