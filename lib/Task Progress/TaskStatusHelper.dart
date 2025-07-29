import 'package:flutter/material.dart';

/// Helper class for task status operations
class TaskStatusHelper {
  /// Available task status options
  static const List<String> statusOptions = [
    'Not Started',
    'In Progress',
    'On Hold',
    'Pending Review',
    'Completed',
    'Cancelled',
    'Rejected'
  ];

  /// Gets color based on task status
  static Color getStatusColor(String status) {
    switch (status) {
      case 'Not Started':
        return Colors.grey;
      case 'In Progress':
        return Colors.blue;
      case 'On Hold':
        return Colors.orange;
      case 'Pending Review':
        return Colors.yellow[700] ?? Colors.yellow;
      case 'Completed':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      case 'Cancelled':
        return Colors.red[800] ?? Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Gets icon based on task status
  static IconData getStatusIcon(String status) {
    switch (status) {
      case 'Not Started':
        return Icons.play_circle_outline;
      case 'In Progress':
        return Icons.timelapse;
      case 'On Hold':
        return Icons.pause_circle_outline;
      case 'Pending Review':
        return Icons.pending;
      case 'Completed':
        return Icons.check_circle;
      case 'Rejected':
        return Icons.cancel;
      case 'Cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  /// Checks if status allows progress editing
  static bool canEditProgress(String status) {
    return status == 'Not Started' ||
        status == 'In Progress' ||
        status == 'On Hold';
  }

  /// Checks if status indicates task completion
  static bool isCompleted(String status) {
    return status == 'Completed';
  }

  /// Checks if status indicates task is pending review
  static bool isPendingReview(String status) {
    return status == 'Pending Review';
  }

  /// Checks if status indicates task is active (can be worked on)
  static bool isActive(String status) {
    return status == 'Not Started' ||
        status == 'In Progress' ||
        status == 'On Hold';
  }

  /// Gets next logical status based on current status
  static String? getNextStatus(String currentStatus) {
    switch (currentStatus) {
      case 'Not Started':
        return 'In Progress';
      case 'In Progress':
        return 'Pending Review';
      case 'On Hold':
        return 'In Progress';
      case 'Pending Review':
        return 'Completed'; // This would typically be set by employer
      default:
        return null;
    }
  }

  /// Gets status description
  static String getStatusDescription(String status) {
    switch (status) {
      case 'Not Started':
        return 'Task has not been started yet';
      case 'In Progress':
        return 'Task is currently being worked on';
      case 'On Hold':
        return 'Task is temporarily paused';
      case 'Pending Review':
        return 'Task is completed and awaiting review';
      case 'Completed':
        return 'Task has been completed and approved';
      case 'Rejected':
        return 'Task submission was rejected';
      case 'Cancelled':
        return 'Task has been cancelled';
      default:
        return 'Unknown status';
    }
  }
}