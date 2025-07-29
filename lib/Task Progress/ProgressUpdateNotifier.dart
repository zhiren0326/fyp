import 'package:flutter/foundation.dart';

/// A notifier class that handles progress updates across the application
/// Used to notify listeners when task progress changes
class ProgressUpdateNotifier extends ChangeNotifier {
  bool _hasUpdates = false;
  String? _lastUpdatedTaskId;
  DateTime? _lastUpdateTime;

  /// Gets whether there are pending updates
  bool get hasUpdates => _hasUpdates;

  /// Gets the ID of the last updated task
  String? get lastUpdatedTaskId => _lastUpdatedTaskId;

  /// Gets the timestamp of the last update
  DateTime? get lastUpdateTime => _lastUpdateTime;

  /// Notifies all listeners that progress has changed
  /// This will trigger UI updates in listening widgets
  void notifyProgressChanged([String? taskId]) {
    _hasUpdates = true;
    _lastUpdatedTaskId = taskId;
    _lastUpdateTime = DateTime.now();
    notifyListeners();
  }

  /// Marks updates as acknowledged/processed
  void markUpdatesProcessed() {
    _hasUpdates = false;
    notifyListeners();
  }

  /// Clears all update states
  void clearUpdates() {
    _hasUpdates = false;
    _lastUpdatedTaskId = null;
    _lastUpdateTime = null;
    notifyListeners();
  }

  /// Notifies about task status changes
  void notifyStatusChanged(String taskId, String newStatus) {
    _lastUpdatedTaskId = taskId;
    _lastUpdateTime = DateTime.now();
    _hasUpdates = true;
    notifyListeners();
  }

  /// Notifies about milestone completion
  void notifyMilestoneChanged(String taskId) {
    _lastUpdatedTaskId = taskId;
    _lastUpdateTime = DateTime.now();
    _hasUpdates = true;
    notifyListeners();
  }

  /// Notifies about subtask completion
  void notifySubTaskChanged(String taskId) {
    _lastUpdatedTaskId = taskId;
    _lastUpdateTime = DateTime.now();
    _hasUpdates = true;
    notifyListeners();
  }
}