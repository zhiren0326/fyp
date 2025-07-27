import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/notification_model.dart';

class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // Initialize the local notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize timezone
    tz.initializeTimeZones();

    // Android initialization settings
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
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

    // Request permissions for Android 13+
    if (Platform.isAndroid) {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    // Request permissions for iOS
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

    _isInitialized = true;
    print('Local notifications initialized successfully');
  }

  // Handle notification tap
  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      print('Notification tapped with payload: $payload');
      // Handle navigation based on payload
      _handleNotificationTap(payload);
    }
  }

  void _handleNotificationTap(String payload) {
    // Parse the payload and handle navigation
    // You can pass JSON data as payload and parse it here
    try {
      // Example: {"type":"job","id":"job123","action":"view"}
      // Handle navigation to specific screens based on payload
      print('Handling notification tap: $payload');
    } catch (e) {
      print('Error handling notification tap: $e');
    }
  }

  // Show immediate notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    NotificationType type = NotificationType.system,
    NotificationPriority priority = NotificationPriority.medium,
    String? payload,
    String? largeIcon,
    String? bigPicture,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final androidDetails = AndroidNotificationDetails(
      _getChannelId(type),
      _getChannelName(type),
      channelDescription: _getChannelDescription(type),
      importance: _getImportance(priority),
      priority: _getPriority(priority),
      icon: _getNotificationIcon(type),
      color: _getNotificationColor(type),
      largeIcon: largeIcon != null ? DrawableResourceAndroidBitmap(largeIcon) : null,
      styleInformation: bigPicture != null
          ? BigPictureStyleInformation(
        DrawableResourceAndroidBitmap(bigPicture),
        largeIcon: largeIcon != null ? DrawableResourceAndroidBitmap(largeIcon) : null,
      )
          : BigTextStyleInformation(body),
      ticker: title,
      showWhen: true,
      autoCancel: true,
      fullScreenIntent: priority == NotificationPriority.critical,
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

    await _flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );

    print('Local notification shown: $title');
  }

  // Schedule notification for specific time
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    NotificationType type = NotificationType.system,
    NotificationPriority priority = NotificationPriority.medium,
    String? payload,
    bool matchDateTimeComponents = false,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final androidDetails = AndroidNotificationDetails(
      _getChannelId(type),
      _getChannelName(type),
      channelDescription: _getChannelDescription(type),
      importance: _getImportance(priority),
      priority: _getPriority(priority),
      icon: _getNotificationIcon(type),
      color: _getNotificationColor(type),
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
      matchDateTimeComponents: matchDateTimeComponents
          ? DateTimeComponents.dateAndTime
          : null,
    );

    print('Notification scheduled for: $scheduledTime');
  }

  // Schedule periodic notifications
  Future<void> schedulePeriodicNotification({
    required int id,
    required String title,
    required String body,
    required RepeatInterval repeatInterval,
    NotificationType type = NotificationType.system,
    NotificationPriority priority = NotificationPriority.medium,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final androidDetails = AndroidNotificationDetails(
      _getChannelId(type),
      _getChannelName(type),
      channelDescription: _getChannelDescription(type),
      importance: _getImportance(priority),
      priority: _getPriority(priority),
      icon: _getNotificationIcon(type),
      color: _getNotificationColor(type),
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

    await _flutterLocalNotificationsPlugin.periodicallyShow(
      id,
      title,
      body,
      repeatInterval,
      notificationDetails,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    print('Periodic notification scheduled: $repeatInterval');
  }

  // Schedule task reminder notifications
  Future<void> scheduleTaskReminder({
    required String taskId,
    required String taskTitle,
    required DateTime dueDate,
    List<int> reminderMinutes = const [60, 30, 15], // Remind 1hr, 30min, 15min before
  }) async {
    for (int i = 0; i < reminderMinutes.length; i++) {
      final reminderTime = dueDate.subtract(Duration(minutes: reminderMinutes[i]));

      // Don't schedule past reminders
      if (reminderTime.isBefore(DateTime.now())) continue;

      final id = taskId.hashCode + i; // Unique ID for each reminder
      String title;
      String body;
      NotificationPriority priority;

      if (reminderMinutes[i] <= 15) {
        title = 'URGENT: Task Due Soon!';
        body = '"$taskTitle" is due in ${reminderMinutes[i]} minutes';
        priority = NotificationPriority.critical;
      } else if (reminderMinutes[i] <= 30) {
        title = 'Task Reminder';
        body = '"$taskTitle" is due in ${reminderMinutes[i]} minutes';
        priority = NotificationPriority.high;
      } else {
        title = 'Upcoming Task';
        body = '"$taskTitle" is due in ${(reminderMinutes[i] / 60).round()} hour(s)';
        priority = NotificationPriority.medium;
      }

      await scheduleNotification(
        id: id,
        title: title,
        body: body,
        scheduledTime: reminderTime,
        type: NotificationType.reminder,
        priority: priority,
        payload: '{"type":"task","id":"$taskId","action":"view"}',
      );
    }
  }

  // Schedule job interview reminder
  Future<void> scheduleJobInterviewReminder({
    required String jobId,
    required String jobTitle,
    required String companyName,
    required DateTime interviewDate,
  }) async {
    // Remind 1 day before
    final oneDayBefore = interviewDate.subtract(const Duration(days: 1));
    if (oneDayBefore.isAfter(DateTime.now())) {
      await scheduleNotification(
        id: '${jobId}_1day'.hashCode,
        title: 'Interview Tomorrow',
        body: 'Don\'t forget your interview with $companyName for $jobTitle position',
        scheduledTime: oneDayBefore,
        type: NotificationType.job,
        priority: NotificationPriority.high,
        payload: '{"type":"job","id":"$jobId","action":"interview"}',
      );
    }

    // Remind 2 hours before
    final twoHoursBefore = interviewDate.subtract(const Duration(hours: 2));
    if (twoHoursBefore.isAfter(DateTime.now())) {
      await scheduleNotification(
        id: '${jobId}_2hrs'.hashCode,
        title: 'Interview in 2 Hours',
        body: 'Get ready for your interview with $companyName',
        scheduledTime: twoHoursBefore,
        type: NotificationType.job,
        priority: NotificationPriority.critical,
        payload: '{"type":"job","id":"$jobId","action":"interview"}',
      );
    }

    // Remind 30 minutes before
    final thirtyMinsBefore = interviewDate.subtract(const Duration(minutes: 30));
    if (thirtyMinsBefore.isAfter(DateTime.now())) {
      await scheduleNotification(
        id: '${jobId}_30min'.hashCode,
        title: 'Interview Starting Soon!',
        body: 'Your interview with $companyName starts in 30 minutes',
        scheduledTime: thirtyMinsBefore,
        type: NotificationType.job,
        priority: NotificationPriority.critical,
        payload: '{"type":"job","id":"$jobId","action":"interview"}',
      );
    }
  }

  // Cancel specific notification
  Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
    print('Cancelled notification: $id');
  }

  // Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
    print('Cancelled all notifications');
  }

  // Cancel notifications by tag/group
  Future<void> cancelTaskNotifications(String taskId) async {
    // Cancel all reminders for a specific task
    final reminderMinutes = [60, 30, 15];
    for (int i = 0; i < reminderMinutes.length; i++) {
      final id = taskId.hashCode + i;
      await cancelNotification(id);
    }
  }

  // Get pending notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _flutterLocalNotificationsPlugin.pendingNotificationRequests();
  }

  // Helper methods for notification configuration
  String _getChannelId(NotificationType type) {
    switch (type) {
      case NotificationType.task:
      case NotificationType.reminder:
        return 'tasks_channel';
      case NotificationType.deadline:
        return 'deadlines_channel';
      case NotificationType.job:
      case NotificationType.acceptance:
      case NotificationType.rejection:
        return 'jobs_channel';
      case NotificationType.system:
      case NotificationType.progress:
        return 'system_channel';
    }
  }

  String _getChannelName(NotificationType type) {
    switch (type) {
      case NotificationType.task:
      case NotificationType.reminder:
        return 'Task Reminders';
      case NotificationType.deadline:
        return 'Deadline Alerts';
      case NotificationType.job:
      case NotificationType.acceptance:
      case NotificationType.rejection:
        return 'Job Updates';
      case NotificationType.system:
      case NotificationType.progress:
        return 'System Notifications';
    }
  }

  String _getChannelDescription(NotificationType type) {
    switch (type) {
      case NotificationType.task:
      case NotificationType.reminder:
        return 'Notifications for task reminders and deadlines';
      case NotificationType.deadline:
        return 'Critical alerts for approaching deadlines';
      case NotificationType.job:
      case NotificationType.acceptance:
      case NotificationType.rejection:
        return 'Updates about job applications and interviews';
      case NotificationType.system:
      case NotificationType.progress:
        return 'General app notifications and updates';
    }
  }

  Importance _getImportance(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.critical:
        return Importance.max;
      case NotificationPriority.high:
        return Importance.high;
      case NotificationPriority.medium:
        return Importance.defaultImportance;
      case NotificationPriority.low:
        return Importance.low;
    }
  }

  Priority _getPriority(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.critical:
        return Priority.max;
      case NotificationPriority.high:
        return Priority.high;
      case NotificationPriority.medium:
        return Priority.defaultPriority;
      case NotificationPriority.low:
        return Priority.low;
    }
  }

  String _getNotificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.task:
      case NotificationType.reminder:
        return 'ic_task';
      case NotificationType.deadline:
        return 'ic_alarm';
      case NotificationType.job:
      case NotificationType.acceptance:
      case NotificationType.rejection:
        return 'ic_work';
      case NotificationType.system:
      case NotificationType.progress:
        return 'ic_notification';
    }
  }

  Color _getNotificationColor(NotificationType type) {
    switch (type) {
      case NotificationType.task:
      case NotificationType.reminder:
        return Colors.blue;
      case NotificationType.deadline:
        return Colors.red;
      case NotificationType.job:
      case NotificationType.acceptance:
        return Colors.green;
      case NotificationType.rejection:
        return Colors.orange;
      case NotificationType.system:
      case NotificationType.progress:
        return Colors.teal;
    }
  }
}