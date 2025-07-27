import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/notification_model.dart';

class PopupNotificationService {
  static final PopupNotificationService _instance = PopupNotificationService._internal();
  factory PopupNotificationService() => _instance;
  PopupNotificationService._internal();

  OverlayEntry? _currentOverlay;
  final List<_QueuedNotification> _notificationQueue = [];
  bool _isShowingNotification = false;

  // Show popup notification
  void showPopupNotification({
    required BuildContext context,
    required String message,
    String title = '',
    NotificationType type = NotificationType.system,
    NotificationPriority priority = NotificationPriority.medium,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
    VoidCallback? onDismiss,
  }) {
    if (!context.mounted) {
      debugPrint('PopupNotificationService: Context is not mounted, skipping notification');
      return;
    }

    final overlay = _createNotificationOverlay(
      message: message,
      title: title,
      type: type,
      priority: priority,
      duration: duration,
      onTap: onTap,
      onDismiss: onDismiss,
    );

    if (_isShowingNotification) {
      // Add to queue if another notification is showing
      _notificationQueue.add(_QueuedNotification(context: context, overlay: overlay));
    } else {
      _showOverlay(context, overlay);
    }
  }

  // Show notification from AppNotification model
  void showNotificationFromModel({
    required BuildContext context,
    required AppNotification notification,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
    VoidCallback? onDismiss,
  }) {
    if (!context.mounted) {
      debugPrint('PopupNotificationService: Context is not mounted, skipping model notification');
      return;
    }

    showPopupNotification(
      context: context,
      message: notification.message,
      title: notification.title,
      type: notification.type,
      priority: notification.priority,
      duration: duration,
      onTap: onTap,
      onDismiss: onDismiss,
    );
  }

  void _showOverlay(BuildContext context, OverlayEntry overlay) {
    if (!context.mounted) {
      debugPrint('PopupNotificationService: Context is not mounted for overlay, skipping');
      _isShowingNotification = false;
      _processNextInQueue();
      return;
    }

    try {
      _isShowingNotification = true;
      _currentOverlay = overlay;
      Overlay.of(context).insert(overlay);
    } catch (e) {
      debugPrint('PopupNotificationService: Error inserting overlay: $e');
      _isShowingNotification = false;
      _currentOverlay = null;
      _processNextInQueue();
    }
  }

  void _hideCurrentNotification() {
    if (_currentOverlay != null) {
      try {
        _currentOverlay!.remove();
      } catch (e) {
        debugPrint('PopupNotificationService: Error removing overlay: $e');
      }
      _currentOverlay = null;
      _isShowingNotification = false;
      _processNextInQueue();
    }
  }

  void _processNextInQueue() {
    if (_notificationQueue.isNotEmpty) {
      // Remove invalid contexts from queue
      while (_notificationQueue.isNotEmpty && !_notificationQueue.first.context.mounted) {
        debugPrint('PopupNotificationService: Removing stale context from queue');
        _notificationQueue.removeAt(0);
      }

      if (_notificationQueue.isNotEmpty) {
        final nextNotification = _notificationQueue.removeAt(0);
        Future.delayed(const Duration(milliseconds: 100), () {
          _showOverlay(nextNotification.context, nextNotification.overlay);
        });
      }
    }
  }

  OverlayEntry _createNotificationOverlay({
    required String message,
    String title = '',
    required NotificationType type,
    required NotificationPriority priority,
    required Duration duration,
    VoidCallback? onTap,
    VoidCallback? onDismiss,
  }) {
    return OverlayEntry(
      builder: (context) => ProgressPopupNotificationWidget(
        message: message,
        title: title,
        type: type,
        priority: priority,
        duration: duration,
        onTap: () {
          _hideCurrentNotification();
          onTap?.call();
        },
        onDismiss: () {
          _hideCurrentNotification();
          onDismiss?.call();
        },
        showProgress: true,
      ),
    );
  }

  // Clear all notifications
  void clearAll() {
    _hideCurrentNotification();
    _notificationQueue.clear();
  }

  // Check if notifications are showing
  bool get isShowingNotification => _isShowingNotification;
  int get queueLength => _notificationQueue.length;
}

// Helper class to store context with overlay
class _QueuedNotification {
  final BuildContext context;
  final OverlayEntry overlay;

  _QueuedNotification({required this.context, required this.overlay});
}

class PopupNotificationWidget extends StatefulWidget {
  final String message;
  final String title;
  final NotificationType type;
  final NotificationPriority priority;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const PopupNotificationWidget({
    super.key,
    required this.message,
    this.title = '',
    required this.type,
    required this.priority,
    required this.duration,
    this.onTap,
    this.onDismiss,
  });

  @override
  State<PopupNotificationWidget> createState() => _PopupNotificationWidgetState();
}

class _PopupNotificationWidgetState extends State<PopupNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    // Start animation
    if (mounted) {
      _animationController.forward();
    }

    // Auto dismiss
    Future.delayed(widget.duration, () {
      if (mounted) {
        _dismissNotification();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismissNotification() async {
    if (mounted) {
      await _animationController.reverse();
      if (mounted) {
        widget.onDismiss?.call();
      }
    }
  }

  Color _getNotificationColor() {
    switch (widget.priority) {
      case NotificationPriority.critical:
        return Colors.red;
      case NotificationPriority.high:
        return Colors.orange;
      case NotificationPriority.medium:
        return Colors.teal;
      case NotificationPriority.low:
        return Colors.blue;
    }
  }

  IconData _getNotificationIcon() {
    switch (widget.type) {
      case NotificationType.task:
        return Icons.task_alt;
      case NotificationType.deadline:
        return Icons.alarm;
      case NotificationType.job:
        return Icons.work;
      case NotificationType.system:
        return Icons.info;
      case NotificationType.acceptance:
        return Icons.check_circle;
      case NotificationType.rejection:
        return Icons.cancel;
      case NotificationType.reminder:
        return Icons.schedule;
      case NotificationType.progress:
        return Icons.trending_up;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getNotificationColor();
    final icon = _getNotificationIcon();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        color.withOpacity(0.1),
                        Colors.white,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: color.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              icon,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.title.isNotEmpty)
                                  Text(
                                    widget.title,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                Text(
                                  widget.message,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _dismissNotification,
                            icon: Icon(
                              Icons.close,
                              color: Colors.grey[600],
                              size: 18,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
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

class ProgressPopupNotificationWidget extends StatefulWidget {
  final String message;
  final String title;
  final NotificationType type;
  final NotificationPriority priority;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final bool showProgress;

  const ProgressPopupNotificationWidget({
    super.key,
    required this.message,
    this.title = '',
    required this.type,
    required this.priority,
    required this.duration,
    this.onTap,
    this.onDismiss,
    this.showProgress = true,
  });

  @override
  State<ProgressPopupNotificationWidget> createState() => _ProgressPopupNotificationWidgetState();
}

class _ProgressPopupNotificationWidgetState extends State<ProgressPopupNotificationWidget>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _progressController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _progressController = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));

    // Start animations
    if (mounted) {
      _slideController.forward();
      if (widget.showProgress) {
        _progressController.forward();
      }
    }

    // Auto dismiss
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _dismissNotification();
      }
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _dismissNotification() async {
    if (mounted) {
      await _slideController.reverse();
      if (mounted) {
        widget.onDismiss?.call();
      }
    }
  }

  Color _getNotificationColor() {
    switch (widget.priority) {
      case NotificationPriority.critical:
        return Colors.red;
      case NotificationPriority.high:
        return Colors.orange;
      case NotificationPriority.medium:
        return Colors.teal;
      case NotificationPriority.low:
        return Colors.blue;
    }
  }

  IconData _getNotificationIcon() {
    switch (widget.type) {
      case NotificationType.task:
        return Icons.task_alt;
      case NotificationType.deadline:
        return Icons.alarm;
      case NotificationType.job:
        return Icons.work;
      case NotificationType.system:
        return Icons.info;
      case NotificationType.acceptance:
        return Icons.check_circle;
      case NotificationType.rejection:
        return Icons.cancel;
      case NotificationType.reminder:
        return Icons.schedule;
      case NotificationType.progress:
        return Icons.trending_up;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getNotificationColor();
    final icon = _getNotificationIcon();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _slideController,
        builder: (context, child) {
          return SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        color.withOpacity(0.1),
                        Colors.white,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: color.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: widget.onTap,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  icon,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.title.isNotEmpty)
                                      Text(
                                        widget.title,
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                    Text(
                                      widget.message,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _dismissNotification,
                                icon: Icon(
                                  Icons.close,
                                  color: Colors.grey[600],
                                  size: 18,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.showProgress)
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                            color: Colors.grey[200],
                          ),
                          child: AnimatedBuilder(
                            animation: _progressController,
                            builder: (context, child) {
                              return LinearProgressIndicator(
                                value: widget.showProgress ? 1.0 - _progressController.value : 0.0,
                                backgroundColor: Colors.transparent,
                                valueColor: AlwaysStoppedAnimation<Color>(color),
                              );
                            },
                          ),
                        ),
                    ],
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