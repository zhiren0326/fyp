// lib/Notification Module/PopupNotificationManager.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/notification_model.dart';
import 'PopupNotificationService.dart';
import 'NotificationService.dart';

// Integration class to listen for new notifications and show pop-ups
class PopupNotificationManager {
  static final PopupNotificationManager _instance = PopupNotificationManager._internal();
  factory PopupNotificationManager() => _instance;
  PopupNotificationManager._internal();

  StreamSubscription<QuerySnapshot>? _notificationSubscription;
  BuildContext? _context;
  Set<String> _shownNotifications = {};
  bool _isInitialized = false;

  // Initialize the popup notification listener
  void initialize(BuildContext context) {
    if (_isInitialized) return;

    _context = context;
    _startListening();
    _isInitialized = true;
    print('PopupNotificationManager initialized');
  }

  void _startListening() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _context == null) {
      print('Cannot start listening: user or context is null');
      return;
    }

    print('Starting to listen for notifications for user: ${user.uid}');

    _notificationSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen(
      _handleNewNotifications,
      onError: (error) {
        print('Error listening to notifications: $error');
      },
    );
  }

  void _handleNewNotifications(QuerySnapshot snapshot) {
    if (_context == null) {
      print('Context is null, cannot show notifications');
      return;
    }

    print('Received ${snapshot.docChanges.length} notification changes');

    for (var change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.added) {
        try {
          final notification = AppNotification.fromFirestore(change.doc);
          print('Processing notification: ${notification.id} - ${notification.message}');

          // Check if we've already shown this notification
          if (!_shownNotifications.contains(notification.id)) {
            _shownNotifications.add(notification.id);
            _showPopupNotification(notification);
          } else {
            print('Notification ${notification.id} already shown, skipping');
          }
        } catch (e) {
          print('Error processing notification: $e');
        }
      }
    }
  }

  void _showPopupNotification(AppNotification notification) {
    if (_context == null) {
      print('Context is null, cannot show popup notification');
      return;
    }

    print('Showing popup notification: ${notification.message}');

    // Determine duration based on priority
    Duration duration;
    switch (notification.priority) {
      case NotificationPriority.critical:
        duration = const Duration(seconds: 8);
        break;
      case NotificationPriority.high:
        duration = const Duration(seconds: 6);
        break;
      case NotificationPriority.medium:
        duration = const Duration(seconds: 4);
        break;
      case NotificationPriority.low:
        duration = const Duration(seconds: 3);
        break;
    }

    PopupNotificationService().showNotificationFromModel(
      context: _context!,
      notification: notification,
      duration: duration,
      onTap: () => _handleNotificationTap(notification),
      onDismiss: () => _handleNotificationDismiss(notification),
    );
  }

  void _handleNotificationTap(AppNotification notification) {
    print('Notification tapped: ${notification.id}');

    // Mark as read when tapped
    _markAsRead(notification.id);

    // Handle navigation based on notification data
    _navigateBasedOnNotification(notification);
  }

  void _handleNotificationDismiss(AppNotification notification) {
    print('Notification dismissed: ${notification.id}');
    // Optionally mark as read when dismissed
    // _markAsRead(notification.id);
  }

  void _navigateBasedOnNotification(AppNotification notification) {
    if (_context == null) return;

    try {
      // Handle different navigation scenarios based on notification data
      if (notification.data.containsKey('jobId')) {
        final jobId = notification.data['jobId'];
        print('Navigate to job details: $jobId');
        // Example navigation:
        // Navigator.push(_context!, MaterialPageRoute(
        //   builder: (context) => JobDetailsScreen(jobId: jobId),
        // ));

        // Show a snackbar for demo purposes
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text('Would navigate to job: $jobId'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (notification.data.containsKey('taskId')) {
        final taskId = notification.data['taskId'];
        print('Navigate to task details: $taskId');
        // Example navigation:
        // Navigator.push(_context!, MaterialPageRoute(
        //   builder: (context) => TaskDetailsScreen(taskId: taskId),
        // ));

        // Show a snackbar for demo purposes
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text('Would navigate to task: $taskId'),
            backgroundColor: Colors.blue,
          ),
        );
      } else if (notification.actionUrl != null) {
        print('Navigate to URL: ${notification.actionUrl}');
        // Handle URL navigation
        // You can use url_launcher package for external URLs

        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text('Would open URL: ${notification.actionUrl}'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        // Default action - just show the notification was tapped
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text('Notification tapped: ${notification.title}'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      print('Error handling notification navigation: $e');
    }
  }

  void _markAsRead(String notificationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});

      print('Marked notification as read: $notificationId');
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  // Restart listening (useful when user logs in/out)
  void restart(BuildContext context) {
    dispose();
    _isInitialized = false;
    initialize(context);
  }

  // Update context (useful when navigating between screens)
  void updateContext(BuildContext context) {
    _context = context;
  }

  // Clean up
  void dispose() {
    print('Disposing PopupNotificationManager');
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _shownNotifications.clear();
    _context = null;
    _isInitialized = false;
  }

  // Clear shown notifications cache (useful for testing)
  void clearCache() {
    _shownNotifications.clear();
    print('Cleared notification cache');
  }

  // Check if manager is initialized
  bool get isInitialized => _isInitialized;

  // Get number of shown notifications (for debugging)
  int get shownNotificationsCount => _shownNotifications.length;

  // Manually show a test notification (for debugging)
  void showTestNotification() {
    if (_context == null) return;

    final testNotification = AppNotification(
      id: 'test_${DateTime.now().millisecondsSinceEpoch}',
      message: 'This is a test notification to verify the popup system is working.',
      title: 'Test Notification',
      type: NotificationType.system,
      priority: NotificationPriority.medium,
      timestamp: DateTime.now(),
      data: {'isTest': true},
    );

    _showPopupNotification(testNotification);
  }

  // Force refresh notifications (manually trigger a check)
  void refreshNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _context == null) return;

    try {
      print('Manually refreshing notifications');
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      _handleNewNotifications(snapshot);
    } catch (e) {
      print('Error refreshing notifications: $e');
    }
  }
}

// Helper widget to easily integrate popup notifications into any screen
class PopupNotificationWrapper extends StatefulWidget {
  final Widget child;
  final bool autoInit;

  const PopupNotificationWrapper({
    super.key,
    required this.child,
    this.autoInit = true,
  });

  @override
  State<PopupNotificationWrapper> createState() => _PopupNotificationWrapperState();
}

class _PopupNotificationWrapperState extends State<PopupNotificationWrapper> {
  @override
  void initState() {
    super.initState();
    if (widget.autoInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PopupNotificationManager().initialize(context);
      });
    }
  }

  @override
  void dispose() {
    if (widget.autoInit) {
      PopupNotificationManager().dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Update context when widget rebuilds
    if (widget.autoInit) {
      PopupNotificationManager().updateContext(context);
    }
    return widget.child;
  }
}

// Debug widget to help test notifications
class NotificationDebugPanel extends StatelessWidget {
  const NotificationDebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Notification Debug Panel',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      PopupNotificationManager().showTestNotification();
                    },
                    child: const Text('Show Test Popup'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      PopupNotificationManager().refreshNotifications();
                    },
                    child: const Text('Refresh'),
                  ),
                ),
              ],
            ),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      PopupNotificationManager().clearCache();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cache cleared')),
                      );
                    },
                    child: const Text('Clear Cache'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final manager = PopupNotificationManager();
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Debug Info'),
                          content: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Initialized: ${manager.isInitialized}'),
                              Text('Shown Notifications: ${manager.shownNotificationsCount}'),
                              Text('User: ${FirebaseAuth.instance.currentUser?.uid ?? 'Not logged in'}'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Debug Info'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}