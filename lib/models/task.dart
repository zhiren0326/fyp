import 'package:flutter/material.dart';

enum TaskPriority { low, medium, high }

class Task {
  final String id;
  final String title;
  final String description;
  final String category;
  final TaskPriority priority;
  final int estimatedDuration; // in minutes
  final bool isCompleted;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final bool isTimeBlocked;
  final String? jobId;

  Task({
    required this.id,
    required this.title,
    this.description = '',
    this.category = 'General',
    this.priority = TaskPriority.medium,
    this.estimatedDuration = 30,
    this.isCompleted = false,
    required this.startTime,
    required this.endTime,
    this.isTimeBlocked = false,
    this.jobId,
  });

  Task copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    TaskPriority? priority,
    int? estimatedDuration,
    bool? isCompleted,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    bool? isTimeBlocked,
    String? jobId,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      isCompleted: isCompleted ?? this.isCompleted,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isTimeBlocked: isTimeBlocked ?? this.isTimeBlocked,
      jobId: jobId ?? this.jobId,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category,
    'priority': priority.name,
    'estimatedDuration': estimatedDuration,
    'isCompleted': isCompleted,
    'startTime': '${startTime.hour}:${startTime.minute}',
    'endTime': '${endTime.hour}:${endTime.minute}',
    'isTimeBlocked': isTimeBlocked,
    'jobId': jobId,
  };

  factory Task.fromMap(Map<String, dynamic> map) {
    final startParts = (map['startTime'] as String).split(':');
    final endParts = (map['endTime'] as String).split(':');

    TaskPriority priority = TaskPriority.medium;
    if (map['priority'] != null) {
      switch (map['priority'].toString().toLowerCase()) {
        case 'high':
          priority = TaskPriority.high;
          break;
        case 'low':
          priority = TaskPriority.low;
          break;
        default:
          priority = TaskPriority.medium;
      }
    }

    return Task(
      id: map['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: map['title'] as String,
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? 'General',
      priority: priority,
      estimatedDuration: map['estimatedDuration'] as int? ?? 30,
      isCompleted: map['isCompleted'] as bool? ?? false,
      startTime: TimeOfDay(
        hour: int.parse(startParts[0]),
        minute: int.parse(startParts[1]),
      ),
      endTime: TimeOfDay(
        hour: int.parse(endParts[0]),
        minute: int.parse(endParts[1]),
      ),
      isTimeBlocked: map['isTimeBlocked'] as bool? ?? false,
      jobId: map['jobId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Task && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}