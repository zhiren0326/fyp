// Create this as a separate file: lib/models/time_block.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TimeBlock {
  final String id;
  final String title;
  final DateTime date;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final Color color;
  final List<String> taskIds;

  TimeBlock({
    required this.id,
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.color,
    this.taskIds = const [],
  });

  factory TimeBlock.fromMap(Map<String, dynamic> map) {
    final startParts = (map['startTime'] as String).split(':');
    final endParts = (map['endTime'] as String).split(':');

    return TimeBlock(
      id: map['id'] as String,
      title: map['title'] as String,
      date: DateTime.parse(map['date']),
      startTime: TimeOfDay(
        hour: int.parse(startParts[0]),
        minute: int.parse(startParts[1]),
      ),
      endTime: TimeOfDay(
        hour: int.parse(endParts[0]),
        minute: int.parse(endParts[1]),
      ),
      color: Color(map['color'] as int),
      taskIds: List<String>.from(map['taskIds'] ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'date': DateFormat('yyyy-MM-dd').format(date),
    'startTime': '${startTime.hour}:${startTime.minute}',
    'endTime': '${endTime.hour}:${endTime.minute}',
    'color': color.value,
    'taskIds': taskIds,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimeBlock && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}