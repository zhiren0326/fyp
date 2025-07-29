import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class CallNotificationService {
  static CallNotificationService? _instance;
  static CallNotificationService get instance => _instance ??= CallNotificationService._();
  CallNotificationService._();

  final Map<String, StreamSubscription> _activeListeners = {};
  final Map<String, OverlayEntry> _activeNotifications = {};

  /// Start listening for incoming calls for a specific user
  void startListeningForCalls(BuildContext context, String userCustomId) {
    // Listen for individual calls
    _activeListeners['individual_$userCustomId'] = FirebaseFirestore.instance
        .collection('calls')
        .where('calleeId', isEqualTo: userCustomId)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final callData = change.doc.data() as Map<String, dynamic>;
          _showIncomingCallNotification(
            context,
            change.doc.id,
            callData,
            false, // isGroup
          );
        }
      }
    });

    // Listen for group calls
    _listenForGroupCalls(context, userCustomId);
  }

  /// Listen for group calls across all user's groups
  void _listenForGroupCalls(BuildContext context, String userCustomId) async {
    try {
      // Get all groups the user is a member of
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc((await _getUserIdFromCustomId(userCustomId)))
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final groups = List<String>.from(userData['groups'] ?? []);

        for (String groupId in groups) {
          _activeListeners['group_${groupId}'] = FirebaseFirestore.instance
              .collection('group_calls')
              .where('groupId', isEqualTo: groupId)
              .where('status', isEqualTo: 'active')
              .snapshots()
              .listen((snapshot) {
            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final callData = change.doc.data() as Map<String, dynamic>;
                final participants = Map<String, dynamic>.from(callData['participants'] ?? {});

                // Show notification if user is not already a participant
                if (!participants.containsKey(userCustomId)) {
                  _showIncomingCallNotification(
                    context,
                    change.doc.id,
                    callData,
                    true, // isGroup
                  );
                }
              }
            }
          });
        }
      }
    } catch (e) {
      print('Error listening for group calls: $e');
    }
  }

  /// Get user ID from custom ID
  Future<String> _getUserIdFromCustomId(String customId) async {
    final customIdDoc = await FirebaseFirestore.instance
        .collection('custom_ids')
        .where('customId', isEqualTo: customId)
        .get();

    if (customIdDoc.docs.isNotEmpty) {
      return customIdDoc.docs.first['userId'];
    }
    throw Exception('User not found');
  }

  /// Show incoming call notification overlay
  void _showIncomingCallNotification(
      BuildContext context,
      String callId,
      Map<String, dynamic> callData,
      bool isGroup,
      ) {
    // Don't show duplicate notifications
    if (_activeNotifications.containsKey(callId)) {
      return;
    }

    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => IncomingCallNotification(
        callId: callId,
        callData: callData,
        isGroup: isGroup,
        onAccept: () {
          _removeNotification(callId);
          _handleAcceptCall(context, callId, callData, isGroup);
        },
        onDecline: () {
          _removeNotification(callId);
          _handleDeclineCall(callId, isGroup);
        },
        onDismiss: () {
          _removeNotification(callId);
        },
      ),
    );

    _activeNotifications[callId] = overlayEntry;
    overlay.insert(overlayEntry);

    // Auto dismiss after 30 seconds
    Timer(const Duration(seconds: 30), () {
      if (_activeNotifications.containsKey(callId)) {
        _removeNotification(callId);
        _handleDeclineCall(callId, isGroup);
      }
    });
  }

  /// Remove notification overlay
  void _removeNotification(String callId) {
    final notification = _activeNotifications.remove(callId);
    notification?.remove();
  }

  /// Handle accept call
  void _handleAcceptCall(
      BuildContext context,
      String callId,
      Map<String, dynamic> callData,
      bool isGroup,
      ) {
    if (isGroup) {
      // Navigate to the group and join the call
      _navigateToGroupAndJoinCall(context, callData, callId);
    } else {
      // Handle individual call acceptance
      _navigateToIndividualCall(context, callData, callId);
    }
  }

  /// Handle decline call
  void _handleDeclineCall(String callId, bool isGroup) async {
    try {
      if (isGroup) {
        // For group calls, just don't join
        print('Declined group call: $callId');
      } else {
        // For individual calls, update status to rejected
        await FirebaseFirestore.instance
            .collection('calls')
            .doc(callId)
            .update({'status': 'rejected'});
      }
    } catch (e) {
      print('Error declining call: $e');
    }
  }

  /// Navigate to group chat and join call
  void _navigateToGroupAndJoinCall(
      BuildContext context,
      Map<String, dynamic> callData,
      String callId,
      ) {
    // This would typically navigate to the group chat screen
    // and automatically trigger the group call join
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Group Call'),
        content: Text('Opening ${callData['groupName']} to join the call...'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Here you would navigate to the ChatMessage screen
              // with the group details and trigger joinGroupCall
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  /// Navigate to individual call
  void _navigateToIndividualCall(
      BuildContext context,
      Map<String, dynamic> callData,
      String callId,
      ) {
    // Similar to group call, navigate to the individual chat
    // and trigger call acceptance
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept Call'),
        content: Text('Opening chat with ${callData['callerName']}...'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to ChatMessage screen and accept call
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  /// Stop listening for calls
  void stopListeningForCalls() {
    for (var listener in _activeListeners.values) {
      listener.cancel();
    }
    _activeListeners.clear();

    // Remove all active notifications
    for (var notification in _activeNotifications.values) {
      notification.remove();
    }
    _activeNotifications.clear();
  }

  /// Clean up resources
  void dispose() {
    stopListeningForCalls();
  }
}

/// Incoming call notification widget
class IncomingCallNotification extends StatefulWidget {
  final String callId;
  final Map<String, dynamic> callData;
  final bool isGroup;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onDismiss;

  const IncomingCallNotification({
    Key? key,
    required this.callId,
    required this.callData,
    required this.isGroup,
    required this.onAccept,
    required this.onDecline,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<IncomingCallNotification> createState() => _IncomingCallNotificationState();
}

class _IncomingCallNotificationState extends State<IncomingCallNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: -1,
      end: 0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _slideAnimation.value * 100),
            child: Opacity(
              opacity: _fadeAnimation.value,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.teal[700]!,
                        Colors.teal[900]!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                widget.isGroup
                                    ? (widget.callData['type'] == 'video'
                                    ? Icons.video_call
                                    : Icons.call)
                                    : (widget.callData['type'] == 'video'
                                    ? Icons.videocam
                                    : Icons.call),
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.isGroup
                                        ? 'Group ${widget.callData['type'] == 'video' ? 'Video' : 'Voice'} Call'
                                        : 'Incoming ${widget.callData['type'] == 'video' ? 'Video' : 'Voice'} Call',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    widget.isGroup
                                        ? widget.callData['groupName'] ?? 'Unknown Group'
                                        : widget.callData['callerName'] ?? 'Unknown',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: widget.onDismiss,
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Call info
                        if (widget.isGroup) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Started by ${widget.callData['creatorName'] ?? 'Unknown'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (widget.callData['participants'] != null)
                            Text(
                              '${(widget.callData['participants'] as Map).length} participant${(widget.callData['participants'] as Map).length != 1 ? 's' : ''}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                        ],

                        const SizedBox(height: 16),

                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: _CallActionButton(
                                onPressed: widget.onDecline,
                                backgroundColor: Colors.red,
                                icon: Icons.call_end,
                                label: 'Decline',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _CallActionButton(
                                onPressed: widget.onAccept,
                                backgroundColor: Colors.green,
                                icon: widget.isGroup
                                    ? Icons.group_add
                                    : (widget.callData['type'] == 'video'
                                    ? Icons.videocam
                                    : Icons.call),
                                label: widget.isGroup ? 'Join' : 'Accept',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Call action button widget
class _CallActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color backgroundColor;
  final IconData icon;
  final String label;

  const _CallActionButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}