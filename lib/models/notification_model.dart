import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  task,
  deadline,
  job,
  system,
  acceptance,
  rejection,
  reminder,
  progress,
}

enum NotificationPriority {
  low,
  medium,
  high,
  critical,
}

class AppNotification {
  final String id;
  final String message;
  final String title;
  final NotificationType type;
  final NotificationPriority priority;
  final DateTime timestamp;
  final bool read;
  final Map<String, dynamic> data;
  final String? actionUrl;
  final String? imageUrl;

  AppNotification({
    required this.id,
    required this.message,
    this.title = '',
    required this.type,
    this.priority = NotificationPriority.medium,
    required this.timestamp,
    this.read = false,
    this.data = const {},
    this.actionUrl,
    this.imageUrl,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return AppNotification(
      id: doc.id,
      message: data['message'] ?? '',
      title: data['title'] ?? '',
      type: _parseNotificationType(data['type']),
      priority: _parseNotificationPriority(data['priority']),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      read: data['read'] ?? false,
      data: Map<String, dynamic>.from(data['data'] ?? {}),
      actionUrl: data['actionUrl'],
      imageUrl: data['imageUrl'],
    );
  }

  static NotificationType _parseNotificationType(dynamic type) {
    if (type is String) {
      switch (type.toLowerCase()) {
        case 'task':
          return NotificationType.task;
        case 'deadline':
          return NotificationType.deadline;
        case 'job':
          return NotificationType.job;
        case 'system':
          return NotificationType.system;
        case 'acceptance':
          return NotificationType.acceptance;
        case 'rejection':
          return NotificationType.rejection;
        case 'reminder':
          return NotificationType.reminder;
        case 'progress':
          return NotificationType.progress;
        default:
          return NotificationType.system;
      }
    }
    return NotificationType.system;
  }

  static NotificationPriority _parseNotificationPriority(dynamic priority) {
    if (priority is String) {
      switch (priority.toLowerCase()) {
        case 'low':
          return NotificationPriority.low;
        case 'medium':
          return NotificationPriority.medium;
        case 'high':
          return NotificationPriority.high;
        case 'critical':
          return NotificationPriority.critical;
        default:
          return NotificationPriority.medium;
      }
    }
    return NotificationPriority.medium;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'message': message,
      'title': title,
      'type': type.toString().split('.').last,
      'priority': priority.toString().split('.').last,
      'timestamp': Timestamp.fromDate(timestamp),
      'read': read,
      'data': data,
      'actionUrl': actionUrl,
      'imageUrl': imageUrl,
    };
  }

  AppNotification copyWith({
    String? id,
    String? message,
    String? title,
    NotificationType? type,
    NotificationPriority? priority,
    DateTime? timestamp,
    bool? read,
    Map<String, dynamic>? data,
    String? actionUrl,
    String? imageUrl,
  }) {
    return AppNotification(
      id: id ?? this.id,
      message: message ?? this.message,
      title: title ?? this.title,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      timestamp: timestamp ?? this.timestamp,
      read: read ?? this.read,
      data: data ?? this.data,
      actionUrl: actionUrl ?? this.actionUrl,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}