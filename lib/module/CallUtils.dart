import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;

/// Utility class for call-related operations
class CallUtils {
  /// Calculate optimal grid layout for participants
  static GridLayoutInfo calculateGridLayout(int participantCount) {
    if (participantCount <= 1) {
      return GridLayoutInfo(crossAxisCount: 1, aspectRatio: 16 / 9);
    } else if (participantCount == 2) {
      return GridLayoutInfo(crossAxisCount: 1, aspectRatio: 16 / 9);
    } else if (participantCount <= 4) {
      return GridLayoutInfo(crossAxisCount: 2, aspectRatio: 4 / 3);
    } else if (participantCount <= 9) {
      return GridLayoutInfo(crossAxisCount: 3, aspectRatio: 4 / 3);
    } else if (participantCount <= 16) {
      return GridLayoutInfo(crossAxisCount: 4, aspectRatio: 1);
    } else {
      return GridLayoutInfo(crossAxisCount: 5, aspectRatio: 1);
    }
  }

  /// Format call duration
  static String formatCallDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Get participant display name
  static String getParticipantDisplayName(Map<String, dynamic>? participant, String currentUserId) {
    if (participant == null) return 'Unknown';

    final userId = participant['userId'] ?? '';
    final userName = participant['userName'] ?? 'Unknown';

    return userId == currentUserId ? 'You' : userName;
  }

  /// Generate unique call ID
  static String generateCallId(String groupIdOrUserId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${groupIdOrUserId}_$timestamp';
  }

  /// Check if user has call permissions
  static Future<bool> checkCallPermissions({required bool needsVideo}) async {
    if (needsVideo) {
      // Check both camera and microphone permissions
      return true; // Implement actual permission check
    } else {
      // Check only microphone permission
      return true; // Implement actual permission check
    }
  }

  /// Calculate participant position for circular layout
  static Offset calculateParticipantPosition(
      int index,
      int totalParticipants,
      double radius,
      Size containerSize,
      ) {
    if (totalParticipants == 1) {
      return Offset(containerSize.width / 2, containerSize.height / 2);
    }

    final angle = (2 * math.pi * index) / totalParticipants - math.pi / 2;
    final centerX = containerSize.width / 2;
    final centerY = containerSize.height / 2;

    return Offset(
      centerX + radius * math.cos(angle),
      centerY + radius * math.sin(angle),
    );
  }

  /// Get call status text
  static String getCallStatusText(String status, bool isGroup) {
    switch (status) {
      case 'calling':
        return isGroup ? 'Starting call...' : 'Calling...';
      case 'connecting':
        return 'Connecting...';
      case 'connected':
        return 'Connected';
      case 'ended':
        return 'Call ended';
      case 'rejected':
        return 'Call declined';
      default:
        return 'Unknown';
    }
  }

  /// Validate participant limits
  static bool isParticipantLimitReached(int currentCount, {int maxParticipants = 12}) {
    return currentCount >= maxParticipants;
  }
}

/// Grid layout information
class GridLayoutInfo {
  final int crossAxisCount;
  final double aspectRatio;

  GridLayoutInfo({
    required this.crossAxisCount,
    required this.aspectRatio,
  });
}

/// Call statistics widget
class CallStatsWidget extends StatelessWidget {
  final int participantCount;
  final Duration callDuration;
  final String callType;
  final bool isGroup;

  const CallStatsWidget({
    Key? key,
    required this.participantCount,
    required this.callDuration,
    required this.callType,
    required this.isGroup,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            callType == 'video' ? Icons.videocam : Icons.call,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            CallUtils.formatCallDuration(callDuration),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isGroup) ...[
            const SizedBox(width: 8),
            const Text(
              '•',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.people,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              '$participantCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Connection quality indicator with custom signal bars
class ConnectionQualityIndicator extends StatelessWidget {
  final String quality; // 'excellent', 'good', 'fair', 'poor'
  final bool isVisible;

  const ConnectionQualityIndicator({
    Key? key,
    required this.quality,
    this.isVisible = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    Color color;
    int bars;

    switch (quality) {
      case 'excellent':
        color = Colors.green;
        bars = 4;
        break;
      case 'good':
        color = Colors.yellow;
        bars = 3;
        break;
      case 'fair':
        color = Colors.orange;
        bars = 2;
        break;
      case 'poor':
        color = Colors.red;
        bars = 1;
        break;
      default:
        color = Colors.grey;
        bars = 0;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Custom signal bars
          Row(
            children: List.generate(4, (index) {
              return Container(
                width: 3,
                height: 6 + (index * 3),
                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                decoration: BoxDecoration(
                  color: index < bars ? color : Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          ),
          const SizedBox(width: 6),
          // Quality indicator icon
          Icon(
            bars > 2 ? Icons.wifi : bars > 0 ? Icons.wifi_2_bar : Icons.wifi_off,
            color: color,
            size: 12,
          ),
        ],
      ),
    );
  }
}

/// Participant avatar with status indicators
class ParticipantAvatar extends StatelessWidget {
  final Map<String, dynamic>? participant;
  final bool isMuted;
  final bool isVideoEnabled;
  final bool isSpeaking;
  final double size;
  final bool showStatusIndicators;
  final String currentUserId;

  const ParticipantAvatar({
    Key? key,
    required this.participant,
    this.isMuted = false,
    this.isVideoEnabled = true,
    this.isSpeaking = false,
    this.size = 60,
    this.showStatusIndicators = true,
    required this.currentUserId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final photoURL = participant?['userPhotoURL'] ?? '';
    final isCurrentUser = participant?['userId'] == currentUserId;

    return Stack(
      children: [
        // Avatar with speaking indicator
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isSpeaking
                ? Border.all(
              color: Colors.green,
              width: 3,
            )
                : isCurrentUser
                ? Border.all(
              color: Colors.teal,
              width: 2,
            )
                : null,
          ),
          child: CircleAvatar(
            radius: size / 2,
            backgroundImage: photoURL.isNotEmpty
                ? NetworkImage(photoURL)
                : null,
            backgroundColor: Colors.grey[700],
            child: photoURL.isEmpty
                ? Icon(
              Icons.person,
              size: size * 0.6,
              color: Colors.white,
            )
                : null,
          ),
        ),

        // Status indicators
        if (showStatusIndicators) ...[
          // Mute indicator
          if (isMuted)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mic_off,
                  color: Colors.white,
                  size: size * 0.2,
                ),
              ),
            ),

          // Video disabled indicator
          if (!isVideoEnabled)
            Positioned(
              bottom: 0,
              left: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.videocam_off,
                  color: Colors.white,
                  size: size * 0.2,
                ),
              ),
            ),

          // Current user indicator
          if (isCurrentUser)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.teal,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person,
                  color: Colors.white,
                  size: size * 0.15,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Call controls overlay
class CallControlsOverlay extends StatelessWidget {
  final bool isMuted;
  final bool isVideoEnabled;
  final bool isSpeakerOn;
  final bool isVideoCall;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleVideo;
  final VoidCallback onToggleSpeaker;
  final VoidCallback? onSwitchCamera;
  final VoidCallback onEndCall;
  final bool isVisible;

  const CallControlsOverlay({
    Key? key,
    required this.isMuted,
    required this.isVideoEnabled,
    required this.isSpeakerOn,
    required this.isVideoCall,
    required this.onToggleMute,
    this.onToggleVideo,
    required this.onToggleSpeaker,
    this.onSwitchCamera,
    required this.onEndCall,
    this.isVisible = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Positioned(
      bottom: 50,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Mute button
            _ControlButton(
              icon: isMuted ? Icons.mic_off : Icons.mic,
              isActive: !isMuted,
              onPressed: onToggleMute,
              tooltip: isMuted ? 'Unmute' : 'Mute',
            ),

            // Video toggle (only for video calls)
            if (isVideoCall && onToggleVideo != null)
              _ControlButton(
                icon: isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                isActive: isVideoEnabled,
                onPressed: onToggleVideo!,
                tooltip: isVideoEnabled ? 'Turn off camera' : 'Turn on camera',
              ),

            // End call button
            _ControlButton(
              icon: Icons.call_end,
              isActive: false,
              backgroundColor: Colors.red,
              onPressed: onEndCall,
              tooltip: 'End call',
              size: 56,
            ),

            // Speaker button
            _ControlButton(
              icon: isSpeakerOn ? Icons.volume_up : Icons.volume_down,
              isActive: isSpeakerOn,
              onPressed: onToggleSpeaker,
              tooltip: isSpeakerOn ? 'Turn off speaker' : 'Turn on speaker',
            ),

            // Switch camera (only for video calls)
            if (isVideoCall && onSwitchCamera != null)
              _ControlButton(
                icon: Icons.switch_camera,
                isActive: true,
                onPressed: onSwitchCamera!,
                tooltip: 'Switch camera',
              ),
          ],
        ),
      ),
    );
  }
}

/// Individual control button
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color? backgroundColor;
  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  const _ControlButton({
    required this.icon,
    required this.isActive,
    this.backgroundColor,
    required this.onPressed,
    required this.tooltip,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ??
        (isActive ? Colors.white.withOpacity(0.2) : Colors.red.withOpacity(0.8));

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bgColor,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: Icon(
              icon,
              color: Colors.white,
              size: size * 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

/// Participant list widget for voice calls
class VoiceCallParticipantsList extends StatelessWidget {
  final List<Map<String, dynamic>> participants;
  final String currentUserId;
  final ScrollController? scrollController;

  const VoiceCallParticipantsList({
    Key? key,
    required this.participants,
    required this.currentUserId,
    this.scrollController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.8,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final participant = participants[index];
        return _buildVoiceParticipantCard(participant);
      },
    );
  }

  Widget _buildVoiceParticipantCard(Map<String, dynamic> participant) {
    final isMuted = participant['isMuted'] ?? false;
    final isCurrentUser = participant['userId'] == currentUserId;
    final userName = CallUtils.getParticipantDisplayName(participant, currentUserId);

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
        border: isCurrentUser ? Border.all(color: Colors.teal, width: 2) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ParticipantAvatar(
            participant: participant,
            isMuted: isMuted,
            currentUserId: currentUserId,
            size: 50,
          ),
          const SizedBox(height: 8),
          Text(
            userName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Call error widget
class CallErrorWidget extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const CallErrorWidget({
    Key? key,
    required this.error,
    this.onRetry,
    this.onDismiss,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.white,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Call Error',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (onDismiss != null)
                TextButton(
                  onPressed: onDismiss,
                  child: const Text(
                    'Dismiss',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              if (onRetry != null)
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                  ),
                  child: const Text('Retry'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}