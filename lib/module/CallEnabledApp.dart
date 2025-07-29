import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp/module/CallNotificationService.dart';
import 'package:fyp/module/ChatMessage.dart';
import 'package:fyp/module/GroupCallService.dart';

// Import your services and widgets
import 'call_service.dart';


/// Main application wrapper that initializes call services
class CallEnabledApp extends StatefulWidget {
  final Widget child;

  const CallEnabledApp({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<CallEnabledApp> createState() => _CallEnabledAppState();
}

class _CallEnabledAppState extends State<CallEnabledApp> {
  String? _currentUserCustomId;

  @override
  void initState() {
    super.initState();
    _initializeCallServices();
  }

  Future<void> _initializeCallServices() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        // Get the current user's custom ID
        final customIdDoc = await FirebaseFirestore.instance
            .collection('custom_ids')
            .doc(currentUser.uid)
            .get();

        if (customIdDoc.exists) {
          _currentUserCustomId = customIdDoc['customId'];

          // Start listening for incoming calls
          if (mounted && _currentUserCustomId != null) {
            CallNotificationService.instance.startListeningForCalls(
              context,
              _currentUserCustomId!,
            );
          }
        }
      } catch (e) {
        print('Error initializing call services: $e');
      }
    }
  }

  @override
  void dispose() {
    CallNotificationService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Example of how to integrate the ChatMessage widget with calling
class ChatMessageWrapper extends StatefulWidget {
  final String currentUserCustomId;
  final String selectedCustomId;
  final String selectedUserName;
  final String selectedUserPhotoURL;

  const ChatMessageWrapper({
    Key? key,
    required this.currentUserCustomId,
    required this.selectedCustomId,
    required this.selectedUserName,
    required this.selectedUserPhotoURL,
  }) : super(key: key);

  @override
  State<ChatMessageWrapper> createState() => _ChatMessageWrapperState();
}

class _ChatMessageWrapperState extends State<ChatMessageWrapper> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ChatMessage(
        currentUserCustomId: widget.currentUserCustomId,
        selectedCustomId: widget.selectedCustomId,
        selectedUserName: widget.selectedUserName,
        selectedUserPhotoURL: widget.selectedUserPhotoURL,
      ),
    );
  }
}

/// Firebase Firestore database structure guide
/// This shows the required database structure for group calls
class DatabaseStructureGuide {
  /*

  REQUIRED FIRESTORE COLLECTIONS:

  1. group_calls/
     - {callId}/
       - groupId: string (the group's custom ID)
       - groupName: string
       - creatorId: string (custom ID of call creator)
       - creatorName: string
       - type: string ('video' or 'voice')
       - status: string ('active', 'ended')
       - createdAt: timestamp
       - participants: map {
           {userId}: {
             userId: string,
             userName: string,
             userPhotoURL: string,
             joinedAt: timestamp,
             isVideoEnabled: boolean,
             isMuted: boolean
           }
         }

       - candidates/ (subcollection)
         - {candidateId}/
           - fromUserId: string
           - toUserId: string
           - candidate: string
           - sdpMid: string
           - sdpMLineIndex: number
           - timestamp: timestamp

       - signaling/ (subcollection)
         - {signalingId}/
           - fromUserId: string
           - toUserId: string
           - type: string ('offer' or 'answer')
           - data: map {
               sdp: string,
               type: string
             }
           - timestamp: timestamp

  2. calls/ (for individual calls - existing structure)
     - {callId}/
       - callerId: string
       - callerName: string
       - calleeId: string
       - type: string ('video' or 'voice')
       - offer: map
       - status: string
       - timestamp: timestamp

       - candidates/ (subcollection)
         - similar to group_calls structure

  3. users/ (existing structure with additions)
     - {userId}/
       - groups: array of group IDs the user belongs to
       - profiledetails/
         - profile/
           - name: string
           - photoURL: string

  4. groups/ (existing structure)
     - {groupId}/
       - name: string
       - creatorId: string
       - members/ (subcollection)
         - {memberId}/
           - userId: string
           - joinedAt: timestamp

  5. custom_ids/ (existing structure)
     - {userId}/
       - customId: string
       - userId: string

  */
}

/// Usage examples and best practices
class UsageExamples {

  /// Example 1: Starting a group video call
  static Future<void> startGroupVideoCallExample(
      BuildContext context,
      String currentUserCustomId,
      String currentUserName,
      String currentUserPhotoURL,
      String groupId,
      String groupName,
      ) async {
    final groupCallService = GroupCallService(
      context: context,
      currentUserCustomId: currentUserCustomId,
      currentUserName: currentUserName,
      currentUserPhotoURL: currentUserPhotoURL,
      groupId: groupId,
      groupName: groupName,
      onCallEnded: () {
        // Handle call ended - maybe navigate back to chat
        Navigator.of(context).pop();
      },
    );

    await groupCallService.initialize();
    await groupCallService.startGroupVideoCall();
  }

  /// Example 2: Joining an existing group call
  static Future<void> joinGroupCallExample(
      BuildContext context,
      String callId,
      Map<String, dynamic> callData,
      String currentUserCustomId,
      String currentUserName,
      String currentUserPhotoURL,
      ) async {
    final groupCallService = GroupCallService(
      context: context,
      currentUserCustomId: currentUserCustomId,
      currentUserName: currentUserName,
      currentUserPhotoURL: currentUserPhotoURL,
      groupId: callData['groupId'],
      groupName: callData['groupName'],
      onCallEnded: () {
        Navigator.of(context).pop();
      },
    );

    await groupCallService.initialize();
    await groupCallService.joinGroupCall(callId, callData);
  }

  /// Example 3: Setting up call notifications in main app
  static void setupCallNotificationsExample(BuildContext context, String userCustomId) {
    CallNotificationService.instance.startListeningForCalls(context, userCustomId);
  }

  /// Example 4: Individual call setup (existing functionality)
  static Future<void> startIndividualVideoCallExample(
      BuildContext context,
      String currentUserCustomId,
      String selectedCustomId,
      String selectedUserName,
      String selectedUserPhotoURL,
      ) async {
    final callService = CallService(
      context: context,
      currentUserCustomId: currentUserCustomId,
      selectedCustomId: selectedCustomId,
      selectedUserName: selectedUserName,
      selectedUserPhotoURL: selectedUserPhotoURL,
      onCallEnded: () {
        Navigator.of(context).pop();
      },
    );

    await callService.initialize();
    await callService.startVideoCall();
  }
}

/// Security rules guide for Firestore
class SecurityRulesGuide {
  /*

  FIRESTORE SECURITY RULES:

  rules_version = '2';
  service cloud.firestore {
    match /databases/{database}/documents {

      // Group calls - only group members can read/write
      match /group_calls/{callId} {
        allow read, write: if request.auth != null &&
          isGroupMember(resource.data.groupId, request.auth.uid) ||
          isGroupMember(request.resource.data.groupId, request.auth.uid);

        match /candidates/{candidateId} {
          allow read, write: if request.auth != null &&
            isGroupMember(get(/databases/$(database)/documents/group_calls/$(callId)).data.groupId, request.auth.uid);
        }

        match /signaling/{signalingId} {
          allow read, write: if request.auth != null &&
            isGroupMember(get(/databases/$(database)/documents/group_calls/$(callId)).data.groupId, request.auth.uid);
        }
      }

      // Individual calls - participants only
      match /calls/{callId} {
        allow read, write: if request.auth != null &&
          isCallParticipant(resource, request.auth.uid) ||
          isCallParticipant(request.resource, request.auth.uid);

        match /candidates/{candidateId} {
          allow read, write: if request.auth != null &&
            isCallParticipant(get(/databases/$(database)/documents/calls/$(callId)), request.auth.uid);
        }
      }

      // Helper function to check if user is group member
      function isGroupMember(groupId, userId) {
        return exists(/databases/$(database)/documents/groups/$(groupId)/members/$(userId));
      }

      // Helper function to check if user is call participant
      function isCallParticipant(callData, userId) {
        let customId = getCustomId(userId);
        return callData.data.callerId == customId || callData.data.calleeId == customId;
      }

      // Helper function to get custom ID from user ID
      function getCustomId(userId) {
        return get(/databases/$(database)/documents/custom_ids/$(userId)).data.customId;
      }
    }
  }

  */
}

/// Performance optimization tips
class PerformanceOptimizationGuide {
  /*

  PERFORMANCE OPTIMIZATION TIPS:

  1. Limit participant count:
     - Maximum 12 participants for group video calls
     - Maximum 20 participants for group voice calls
     - Use CallUtils.isParticipantLimitReached() to check

  2. Video quality optimization:
     - Reduce video resolution for participants > 4
     - Use adaptive bitrate based on network conditions
     - Implement video codec selection (VP8, VP9, H.264)

  3. Memory management:
     - Dispose WebRTC streams properly
     - Clean up peer connections when participants leave
     - Use object pooling for frequently created objects

  4. Network optimization:
     - Use STUN/TURN servers for better connectivity
     - Implement connection quality monitoring
     - Fallback to audio-only when video quality is poor

  5. UI optimization:
     - Use efficient grid layouts for multiple participants
     - Implement virtual scrolling for large participant lists
     - Cache participant avatars and user data

  6. Battery optimization:
     - Reduce frame rate when app is in background
     - Disable video processing when not visible
     - Use hardware acceleration when available

  */
}

/// Troubleshooting guide
class TroubleshootingGuide {
  /*

  COMMON ISSUES AND SOLUTIONS:

  1. "No audio/video permissions"
     - Check Permission.camera and Permission.microphone
     - Request permissions before starting calls
     - Guide users to app settings if permissions denied

  2. "Call connection failed"
     - Verify STUN/TURN server configuration
     - Check network connectivity
     - Implement retry mechanism with exponential backoff

  3. "Participant not visible in group call"
     - Ensure proper Firebase listener cleanup
     - Check participant data structure in Firestore
     - Verify peer connection state

  4. "Video not displaying"
     - Check RTCVideoRenderer initialization
     - Verify video track is enabled
     - Ensure proper WebRTC constraints

  5. "Call notifications not working"
     - Verify CallNotificationService is initialized
     - Check Firestore security rules
     - Ensure proper listener setup

  6. "High memory usage"
     - Check for memory leaks in WebRTC streams
     - Dispose unused peer connections
     - Monitor participant cleanup

  DEBUGGING STEPS:

  1. Enable debug logging in WebRTC
  2. Monitor Firestore listeners
  3. Check peer connection statistics
  4. Verify media stream states
  5. Test on different devices and networks

  */
}

/// Feature extension ideas
class FeatureExtensionIdeas {
  /*

  FUTURE ENHANCEMENT IDEAS:

  1. Advanced Features:
     - Screen sharing in group calls
     - Recording group calls
     - Background blur/virtual backgrounds
     - Noise cancellation
     - Real-time captions/transcription

  2. UI/UX Improvements:
     - Picture-in-picture mode
     - Call preview before joining
     - Participant hand raising
     - Chat during calls
     - Breakout rooms

  3. Integration Features:
     - Calendar integration for scheduled calls
     - Contact integration
     - Call history and analytics
     - Call quality ratings
     - Integration with other apps

  4. Administrative Features:
     - Call moderation (mute participants)
     - Waiting room functionality
     - Call time limits
     - Participant management
     - Call recording permissions

  5. Accessibility Features:
     - Voice commands
     - Keyboard navigation
     - High contrast mode
     - Text-to-speech
     - Sign language support

  */
}

/// Main entry point example
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CallEnabledApp(
      child: MaterialApp(
        title: 'Chat App with Group Calls',
        theme: ThemeData(
          primarySwatch: Colors.teal,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const ChatListScreen(), // Your main chat list screen
        routes: {
          '/chat': (context) => const ChatRouteHandler(), // Handles chat navigation
        },
      ),
    );
  }
}

/// Route handler for chat navigation
class ChatRouteHandler extends StatelessWidget {
  const ChatRouteHandler({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Extract arguments passed from navigation
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    return ChatMessageWrapper(
      currentUserCustomId: args['currentUserCustomId'],
      selectedCustomId: args['selectedCustomId'],
      selectedUserName: args['selectedUserName'],
      selectedUserPhotoURL: args['selectedUserPhotoURL'],
    );
  }
}

/// Placeholder for your chat list screen
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: Colors.teal[800],
      ),
      body: const Center(
        child: Text(
          'Your chat list goes here\n\nIntegrate with your existing chat list\nand navigation logic',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}