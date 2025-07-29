import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class GroupCallService {
  final BuildContext context;
  final String currentUserCustomId;
  final String currentUserName;
  final String currentUserPhotoURL;
  final String groupId;
  final String groupName;
  final VoidCallback? onCallEnded;

  // WebRTC related
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  MediaStream? _localStream;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  // Call state
  bool _isInCall = false;
  bool _isVideoCall = false;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerOn = false;
  String? _currentCallId;

  // Participants management
  final Map<String, Map<String, dynamic>> _participants = {};
  final List<String> _participantOrder = [];

  // UI state management
  Function? _dialogSetState;

  // Listeners
  StreamSubscription? _callListener;
  StreamSubscription? _participantsListener;
  StreamSubscription? _candidatesListener;
  Timer? _callTimeoutTimer;

  // ICE servers configuration
  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
        ]
      }
    ]
  };

  GroupCallService({
    required this.context,
    required this.currentUserCustomId,
    required this.currentUserName,
    required this.currentUserPhotoURL,
    required this.groupId,
    required this.groupName,
    this.onCallEnded,
  });

  // Public getters for external access (using different names to avoid conflicts)
  bool get isCurrentlyInCall => _isInCall;
  int get participantCount => _participants.length;
  String get currentCallType => _isVideoCall ? 'video' : 'voice';
  Map<String, Map<String, dynamic>> get participants => Map.unmodifiable(_participants);
  bool canStartCall() => !_isInCall;

  // Getter to check if currently in a call
  bool get isInCall => _isInCall;

  /// Initialize the group call service
  Future<void> initialize() async {
    await _localRenderer.initialize();
    _listenToGroupCalls();
  }

  /// Start a group video call
  Future<void> startGroupVideoCall() async {
    if (_isInCall) {
      _showError('Already in a call');
      return;
    }

    if (!canStartCall()) {
      _showError('Cannot start call at this time');
      return;
    }

    try {
      print('Starting group video call...');

      // Request permissions
      final permissions = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      if (!permissions.values.every((status) => status.isGranted)) {
        _showError('Camera and microphone permissions required');
        return;
      }

      await _getUserMedia(true);
      _currentCallId = '${groupId}_${DateTime.now().millisecondsSinceEpoch}';

      await _createGroupCall(_currentCallId!, 'video');

      _isInCall = true;
      _isVideoCall = true;

      _listenToGroupCallUpdates(_currentCallId!);
      _startCallTimeout(); // Add timeout for group calls
      _showGroupCallDialog();

      print('Group video call started successfully');

    } catch (e) {
      print('Error starting group video call: $e');
      _showError('Failed to start group video call: $e');
      _cleanup();
    }
  }

  /// Start a group voice call
  Future<void> startGroupVoiceCall() async {
    if (_isInCall) {
      _showError('Already in a call');
      return;
    }

    if (!canStartCall()) {
      _showError('Cannot start call at this time');
      return;
    }

    try {
      print('Starting group voice call...');

      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        _showError('Microphone permission required');
        return;
      }

      await _getUserMedia(false);
      _currentCallId = '${groupId}_${DateTime.now().millisecondsSinceEpoch}';

      await _createGroupCall(_currentCallId!, 'voice');

      _isInCall = true;
      _isVideoCall = false;

      _listenToGroupCallUpdates(_currentCallId!);
      _startCallTimeout(); // Add timeout for group calls
      _showGroupCallDialog();

      print('Group voice call started successfully');

    } catch (e) {
      print('Error starting group voice call: $e');
      _showError('Failed to start group voice call: $e');
      _cleanup();
    }
  }

  /// Start call timeout timer
  void _startCallTimeout() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(minutes: 2), () {
      // If only one participant after 2 minutes, show message and end call
      if (_participants.length <= 1) {
        _showError('No other participants joined the call');
        endGroupCall();
      }
    });
  }

  /// Join an existing group call
  Future<void> joinGroupCall(String callId, Map<String, dynamic> callData) async {
    if (_isInCall) {
      _showError('Already in a call');
      return;
    }

    try {
      print('Joining group call: $callId');

      _isVideoCall = callData['type'] == 'video';

      // Request permissions
      if (_isVideoCall) {
        final permissions = await [
          Permission.camera,
          Permission.microphone,
        ].request();

        if (!permissions.values.every((status) => status.isGranted)) {
          _showError('Camera and microphone permissions required');
          return;
        }
      } else {
        final status = await Permission.microphone.request();
        if (!status.isGranted) {
          _showError('Microphone permission required');
          return;
        }
      }

      await _getUserMedia(_isVideoCall);
      _currentCallId = callId;

      // Add self to participants
      await _addParticipantToCall(callId);

      _isInCall = true;

      _listenToGroupCallUpdates(callId);
      _showGroupCallDialog();

      print('Joined group call successfully');

    } catch (e) {
      print('Error joining group call: $e');
      _showError('Failed to join group call: $e');
      _cleanup();
    }
  }

  /// Create a new group call
  Future<void> _createGroupCall(String callId, String type) async {
    final callData = {
      'groupId': groupId,
      'groupName': groupName,
      'creatorId': currentUserCustomId,
      'creatorName': currentUserName,
      'type': type,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'participants': {
        currentUserCustomId: {
          'userId': currentUserCustomId,
          'userName': currentUserName,
          'userPhotoURL': currentUserPhotoURL,
          'joinedAt': FieldValue.serverTimestamp(),
          'isVideoEnabled': _isVideoCall,
          'isMuted': false,
        }
      }
    };

    await FirebaseFirestore.instance
        .collection('group_calls')
        .doc(callId)
        .set(callData);

    // Add to participants locally
    _participants[currentUserCustomId] = {
      'userId': currentUserCustomId,
      'userName': currentUserName,
      'userPhotoURL': currentUserPhotoURL,
      'isVideoEnabled': _isVideoCall,
      'isMuted': false,
    };

    if (!_participantOrder.contains(currentUserCustomId)) {
      _participantOrder.add(currentUserCustomId);
    }

    // Notify all group members about the new call
    await _notifyGroupMembers(callId, type);
  }

  /// Notify all group members about the call
  Future<void> _notifyGroupMembers(String callId, String type) async {
    try {
      // Get all group members
      final membersSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .get();

      // Send notification to each member (except the creator)
      for (var memberDoc in membersSnapshot.docs) {
        final memberData = memberDoc.data();
        final memberCustomId = memberData['userCustomId'] ?? memberDoc.id;

        if (memberCustomId != currentUserCustomId) {
          // Create a notification document
          await FirebaseFirestore.instance
              .collection('call_notifications')
              .doc('${callId}_$memberCustomId')
              .set({
            'callId': callId,
            'recipientId': memberCustomId,
            'callType': type,
            'groupId': groupId,
            'groupName': groupName,
            'creatorId': currentUserCustomId,
            'creatorName': currentUserName,
            'timestamp': FieldValue.serverTimestamp(),
            'status': 'pending',
          });
        }
      }

      print('Notified ${membersSnapshot.docs.length - 1} group members about the call');
    } catch (e) {
      print('Error notifying group members: $e');
    }
  }

  /// Add participant to existing call
  Future<void> _addParticipantToCall(String callId) async {
    await FirebaseFirestore.instance
        .collection('group_calls')
        .doc(callId)
        .update({
      'participants.${currentUserCustomId}': {
        'userId': currentUserCustomId,
        'userName': currentUserName,
        'userPhotoURL': currentUserPhotoURL,
        'joinedAt': FieldValue.serverTimestamp(),
        'isVideoEnabled': _isVideoCall,
        'isMuted': false,
      }
    });
  }

  /// Listen to group call updates
  void _listenToGroupCallUpdates(String callId) {
    _participantsListener = FirebaseFirestore.instance
        .collection('group_calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) async {
      if (!context.mounted) return;

      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;

        if (data['status'] == 'ended') {
          endGroupCall(isRemoteDisconnection: true);
          return;
        }

        final participants = Map<String, dynamic>.from(data['participants'] ?? {});
        await _handleParticipantChanges(participants);
      }
    });

    // Listen for ICE candidates
    _candidatesListener = FirebaseFirestore.instance
        .collection('group_calls')
        .doc(callId)
        .collection('candidates')
        .snapshots()
        .listen((snapshot) {
      if (!context.mounted) return;

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          if (data['fromUserId'] != currentUserCustomId) {
            _handleRemoteCandidate(data);
          }
        }
      }
    });

    // Listen for offers and answers
    _callListener = FirebaseFirestore.instance
        .collection('group_calls')
        .doc(callId)
        .collection('signaling')
        .snapshots()
        .listen((snapshot) {
      if (!context.mounted) return;

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          if (data['toUserId'] == currentUserCustomId) {
            _handleSignalingMessage(data);
          }
        }
      }
    });
  }

  /// Handle participant changes
  Future<void> _handleParticipantChanges(Map<String, dynamic> participants) async {
    final currentParticipants = Set<String>.from(_participants.keys);
    final newParticipants = Set<String>.from(participants.keys);

    // Handle new participants
    for (final participantId in newParticipants.difference(currentParticipants)) {
      if (participantId != currentUserCustomId) {
        await _handleNewParticipant(participantId, participants[participantId]);
      }
    }

    // Handle removed participants
    for (final participantId in currentParticipants.difference(newParticipants)) {
      await _handleRemovedParticipant(participantId);
    }

    // Update participant info
    _participants.clear();
    _participantOrder.clear();

    participants.forEach((id, data) {
      _participants[id] = Map<String, dynamic>.from(data);
      if (!_participantOrder.contains(id)) {
        _participantOrder.add(id);
      }
    });

    _updateDialogUI();
  }

  /// Handle new participant joining
  Future<void> _handleNewParticipant(String participantId, Map<String, dynamic> participantData) async {
    print('New participant joined: $participantId');

    // Create peer connection for new participant
    await _createPeerConnectionForParticipant(participantId);

    // Create and send offer to new participant
    final offer = await _peerConnections[participantId]!.createOffer();
    await _peerConnections[participantId]!.setLocalDescription(offer);

    await _sendSignalingMessage(participantId, 'offer', {
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  /// Handle participant leaving
  Future<void> _handleRemovedParticipant(String participantId) async {
    print('Participant left: $participantId');

    // Close peer connection
    await _peerConnections[participantId]?.close();
    _peerConnections.remove(participantId);

    // Clean up streams and renderers
    _remoteStreams[participantId]?.dispose();
    _remoteStreams.remove(participantId);

    await _remoteRenderers[participantId]?.dispose();
    _remoteRenderers.remove(participantId);

    _updateDialogUI();
  }

  /// Create peer connection for a participant
  Future<void> _createPeerConnectionForParticipant(String participantId) async {
    final peerConnection = await createPeerConnection(_configuration);

    // Add local stream tracks
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        peerConnection.addTrack(track, _localStream!);
      });
    }

    peerConnection.onIceCandidate = (candidate) {
      _sendIceCandidate(participantId, candidate);
    };

    peerConnection.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStreams[participantId] = event.streams[0];
        _setupRemoteRenderer(participantId, event.streams[0]);
      }
    };

    _peerConnections[participantId] = peerConnection;
  }

  /// Setup remote renderer for participant
  Future<void> _setupRemoteRenderer(String participantId, MediaStream stream) async {
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    renderer.srcObject = stream;
    _remoteRenderers[participantId] = renderer;
    _updateDialogUI();
  }

  /// Handle signaling messages (offers/answers)
  Future<void> _handleSignalingMessage(Map<String, dynamic> data) async {
    final fromUserId = data['fromUserId'];
    final type = data['type'];
    final sdpData = data['data'];

    if (type == 'offer') {
      await _handleOffer(fromUserId, sdpData);
    } else if (type == 'answer') {
      await _handleAnswer(fromUserId, sdpData);
    }
  }

  /// Handle incoming offer
  Future<void> _handleOffer(String fromUserId, Map<String, dynamic> offerData) async {
    if (!_peerConnections.containsKey(fromUserId)) {
      await _createPeerConnectionForParticipant(fromUserId);
    }

    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _peerConnections[fromUserId]!.setRemoteDescription(offer);

    final answer = await _peerConnections[fromUserId]!.createAnswer();
    await _peerConnections[fromUserId]!.setLocalDescription(answer);

    await _sendSignalingMessage(fromUserId, 'answer', {
      'sdp': answer.sdp,
      'type': answer.type,
    });
  }

  /// Handle incoming answer
  Future<void> _handleAnswer(String fromUserId, Map<String, dynamic> answerData) async {
    if (_peerConnections.containsKey(fromUserId)) {
      final answer = RTCSessionDescription(answerData['sdp'], answerData['type']);
      await _peerConnections[fromUserId]!.setRemoteDescription(answer);
    }
  }

  /// Handle remote ICE candidate
  void _handleRemoteCandidate(Map<String, dynamic> data) async {
    final fromUserId = data['fromUserId'];
    final toUserId = data['toUserId'];

    if (toUserId == currentUserCustomId && _peerConnections.containsKey(fromUserId)) {
      final candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );
      await _peerConnections[fromUserId]!.addCandidate(candidate);
    }
  }

  /// Send signaling message
  Future<void> _sendSignalingMessage(String toUserId, String type, Map<String, dynamic> data) async {
    if (_currentCallId != null) {
      await FirebaseFirestore.instance
          .collection('group_calls')
          .doc(_currentCallId!)
          .collection('signaling')
          .add({
        'fromUserId': currentUserCustomId,
        'toUserId': toUserId,
        'type': type,
        'data': data,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Send ICE candidate
  Future<void> _sendIceCandidate(String toUserId, RTCIceCandidate candidate) async {
    if (_currentCallId != null) {
      await FirebaseFirestore.instance
          .collection('group_calls')
          .doc(_currentCallId!)
          .collection('candidates')
          .add({
        'fromUserId': currentUserCustomId,
        'toUserId': toUserId,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Get user media
  Future<void> _getUserMedia(bool video) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': {
        'echoCancellation': true,
        'autoGainControl': true,
        'noiseSuppression': true,
      },
      'video': video ? {
        'width': {'ideal': 640},
        'height': {'ideal': 480},
        'frameRate': {'ideal': 30},
        'facingMode': 'user',
      } : false
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      if (video && _localStream != null) {
        _localRenderer.srcObject = _localStream;
      }
    } catch (e) {
      throw Exception('Failed to access camera/microphone: $e');
    }
  }

  /// Listen to incoming group calls
  void _listenToGroupCalls() {
    FirebaseFirestore.instance
        .collection('group_calls')
        .where('groupId', isEqualTo: groupId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final callData = change.doc.data() as Map<String, dynamic>;
          final participants = Map<String, dynamic>.from(callData['participants'] ?? {});

          // Show incoming call dialog if user is not already a participant
          if (!participants.containsKey(currentUserCustomId) && !_isInCall) {
            _showIncomingGroupCallDialog(change.doc.id, callData);
          }
        }
      }
    });
  }

  /// Show incoming group call dialog
  void _showIncomingGroupCallDialog(String callId, Map<String, dynamic> callData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          'Incoming Group ${callData['type'] == 'video' ? 'Video' : 'Voice'} Call',
          style: TextStyle(color: Colors.teal[800]),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              callData['type'] == 'video' ? Icons.video_call : Icons.call,
              size: 60,
              color: Colors.teal[800],
            ),
            const SizedBox(height: 16),
            Text(
              '${callData['creatorName']} started a group ${callData['type']} call in ${callData['groupName']}',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Participants: ${(callData['participants'] as Map).length}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Close incoming call dialog
                    // Don't need additional navigation for decline
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Close incoming call dialog
                    // Join the call - navigation will be handled by the call end callback
                    joinGroupCall(callId, callData);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Join'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Show group call dialog
  void _showGroupCallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (!didPop) {
            final shouldEnd = await _showEndCallConfirmation(dialogContext);
            if (shouldEnd == true) {
              await endGroupCall();
            }
          }
        },
        child: StatefulBuilder(
          builder: (context, setState) {
            _dialogSetState = setState;

            return Dialog(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.95,
                height: MediaQuery.of(context).size.height * 0.85,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildGroupCallHeader(),
                    Expanded(
                      child: _isVideoCall ? _buildGroupVideoCallArea() : _buildGroupVoiceCallArea(),
                    ),
                    _buildGroupCallControls(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ).then((_) {
      // Handle dialog dismissal
      _dialogSetState = null;
      // If the dialog was dismissed without properly ending the call, end it now
      if (_isInCall) {
        print('Dialog dismissed without ending call, cleaning up...');
        endGroupCall();
      }
    });
  }

  /// Build group call header
  Widget _buildGroupCallHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal[800],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isVideoCall ? Icons.video_call : Icons.call,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  groupName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Icon(
                      Icons.people,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_participants.length} participant${_participants.length != 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _isVideoCall ? Icons.videocam : Icons.mic,
                      color: Colors.white70,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isVideoCall ? 'Video' : 'Voice',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Call duration
          StreamBuilder<int>(
            stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
            builder: (context, snapshot) {
              final duration = snapshot.data ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(duration ~/ 60).toString().padLeft(2, '0')}:${(duration % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Build group video call area
  Widget _buildGroupVideoCallArea() {
    final participantIds = _participantOrder.where((id) => _participants.containsKey(id)).toList();
    final participantCount = participantIds.length;

    if (participantCount == 0) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.teal),
      );
    }

    return Container(
      color: Colors.black,
      child: _buildVideoGrid(participantIds),
    );
  }

  /// Build video grid layout
  Widget _buildVideoGrid(List<String> participantIds) {
    final count = participantIds.length;

    if (count == 1) {
      return _buildSingleVideoView(participantIds[0]);
    } else if (count == 2) {
      return _buildTwoVideoView(participantIds);
    } else if (count <= 4) {
      return _buildFourVideoGrid(participantIds);
    } else {
      return _buildMultiVideoGrid(participantIds);
    }
  }

  /// Build single video view (self only)
  Widget _buildSingleVideoView(String participantId) {
    return Stack(
      children: [
        // Main video (self)
        Container(
          width: double.infinity,
          height: double.infinity,
          child: participantId == currentUserCustomId
              ? (_isVideoEnabled
              ? RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : _buildNoVideoPlaceholder(_participants[participantId]))
              : (_remoteRenderers[participantId] != null
              ? RTCVideoView(_remoteRenderers[participantId]!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : _buildNoVideoPlaceholder(_participants[participantId])),
        ),
        // Participant info overlay
        Positioned(
          bottom: 16,
          left: 16,
          child: _buildParticipantInfo(_participants[participantId]),
        ),
      ],
    );
  }

  /// Build two video view
  Widget _buildTwoVideoView(List<String> participantIds) {
    return Column(
      children: participantIds.map((id) => Expanded(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(1),
          child: Stack(
            children: [
              id == currentUserCustomId
                  ? (_isVideoEnabled
                  ? RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : _buildNoVideoPlaceholder(_participants[id]))
                  : (_remoteRenderers[id] != null
                  ? RTCVideoView(_remoteRenderers[id]!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : _buildNoVideoPlaceholder(_participants[id])),
              Positioned(
                bottom: 8,
                left: 8,
                child: _buildParticipantInfo(_participants[id]),
              ),
            ],
          ),
        ),
      )).toList(),
    );
  }

  /// Build four video grid
  Widget _buildFourVideoGrid(List<String> participantIds) {
    final rows = (participantIds.length / 2).ceil();

    return Column(
      children: List.generate(rows, (rowIndex) {
        final startIndex = rowIndex * 2;
        final endIndex = (startIndex + 2).clamp(0, participantIds.length);
        final rowParticipants = participantIds.sublist(startIndex, endIndex);

        return Expanded(
          child: Row(
            children: rowParticipants.map((id) => Expanded(
              child: Container(
                margin: const EdgeInsets.all(1),
                child: Stack(
                  children: [
                    id == currentUserCustomId
                        ? (_isVideoEnabled
                        ? RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                        : _buildNoVideoPlaceholder(_participants[id]))
                        : (_remoteRenderers[id] != null
                        ? RTCVideoView(_remoteRenderers[id]!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                        : _buildNoVideoPlaceholder(_participants[id])),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: _buildParticipantInfo(_participants[id], isSmall: true),
                    ),
                  ],
                ),
              ),
            )).toList(),
          ),
        );
      }),
    );
  }

  /// Build multi video grid (for more than 4 participants)
  Widget _buildMultiVideoGrid(List<String> participantIds) {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.75,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: participantIds.length,
      itemBuilder: (context, index) {
        final id = participantIds[index];
        return Stack(
          children: [
            id == currentUserCustomId
                ? (_isVideoEnabled
                ? RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : _buildNoVideoPlaceholder(_participants[id]))
                : (_remoteRenderers[id] != null
                ? RTCVideoView(_remoteRenderers[id]!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : _buildNoVideoPlaceholder(_participants[id])),
            Positioned(
              bottom: 2,
              left: 2,
              child: _buildParticipantInfo(_participants[id], isSmall: true),
            ),
          ],
        );
      },
    );
  }

  /// Build group voice call area
  Widget _buildGroupVoiceCallArea() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey[900]!, Colors.grey[800]!],
        ),
      ),
      child: Column(
        children: [
          // Participants grid
          Expanded(
            child: _buildVoiceParticipantsGrid(),
          ),
          // Call status
          Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Group Voice Call Active',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build voice participants grid
  Widget _buildVoiceParticipantsGrid() {
    final participantIds = _participantOrder.where((id) => _participants.containsKey(id)).toList();

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.8,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: participantIds.length,
      itemBuilder: (context, index) {
        final participant = _participants[participantIds[index]];
        return _buildVoiceParticipantCard(participant);
      },
    );
  }

  /// Build voice participant card
  Widget _buildVoiceParticipantCard(Map<String, dynamic>? participant) {
    if (participant == null) return const SizedBox();

    final isMuted = participant['isMuted'] ?? false;
    final isCurrentUser = participant['userId'] == currentUserCustomId;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
        border: isCurrentUser ? Border.all(color: Colors.teal, width: 2) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            children: [
              CircleAvatar(
                backgroundImage: NetworkImage(participant['userPhotoURL'] ?? ''),
                radius: 30,
                backgroundColor: Colors.grey[700],
              ),
              if (isMuted)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.mic_off,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            participant['userName'] ?? 'Unknown',
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

  /// Build no video placeholder
  Widget _buildNoVideoPlaceholder(Map<String, dynamic>? participant) {
    if (participant == null) return Container(color: Colors.grey[800]);

    return Container(
      color: Colors.grey[800],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundImage: NetworkImage(participant['userPhotoURL'] ?? ''),
              radius: 40,
              backgroundColor: Colors.grey[700],
            ),
            const SizedBox(height: 12),
            Text(
              participant['userName'] ?? 'Unknown',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Icon(
              Icons.videocam_off,
              color: Colors.white54,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  /// Build participant info overlay
  Widget _buildParticipantInfo(Map<String, dynamic>? participant, {bool isSmall = false}) {
    if (participant == null) return const SizedBox();

    final isMuted = participant['isMuted'] ?? false;
    final name = participant['userName'] ?? 'Unknown';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 4 : 8,
        vertical: isSmall ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(isSmall ? 4 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMuted)
            Icon(
              Icons.mic_off,
              color: Colors.red,
              size: isSmall ? 12 : 16,
            ),
          if (isMuted) SizedBox(width: isSmall ? 2 : 4),
          Text(
            name,
            style: TextStyle(
              color: Colors.white,
              fontSize: isSmall ? 10 : 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Build group call controls
  Widget _buildGroupCallControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey[800]!, Colors.grey[900]!],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _buildGroupControlButtons(),
        ),
      ),
    );
  }

  /// Build group control buttons
  List<Widget> _buildGroupControlButtons() {
    List<Widget> buttons = [];

    // Mute button
    buttons.add(
      _GroupCallControlButton(
        icon: _isMuted ? Icons.mic_off : Icons.mic,
        onPressed: _toggleMute,
        backgroundColor: _isMuted ? Colors.red : Colors.grey[700]!,
        tooltip: _isMuted ? 'Unmute' : 'Mute',
      ),
    );

    // Video toggle (only for video calls)
    if (_isVideoCall) {
      buttons.add(
        _GroupCallControlButton(
          icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
          onPressed: _toggleVideo,
          backgroundColor: _isVideoEnabled ? Colors.grey[700]! : Colors.red,
          tooltip: _isVideoEnabled ? 'Turn off camera' : 'Turn on camera',
        ),
      );
    }

    // End call button
    buttons.add(
      _GroupCallControlButton(
        icon: Icons.call_end,
        onPressed: () => endGroupCall(),
        backgroundColor: Colors.red,
        iconSize: 32,
        tooltip: 'Leave call',
      ),
    );

    // Speaker button
    buttons.add(
      _GroupCallControlButton(
        icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
        onPressed: _toggleSpeaker,
        backgroundColor: _isSpeakerOn ? Colors.teal[600]! : Colors.grey[700]!,
        tooltip: _isSpeakerOn ? 'Turn off speaker' : 'Turn on speaker',
      ),
    );

    // Switch camera (only for video calls)
    if (_isVideoCall) {
      buttons.add(
        _GroupCallControlButton(
          icon: Icons.switch_camera,
          onPressed: _switchCamera,
          backgroundColor: Colors.grey[700]!,
          tooltip: 'Switch camera',
        ),
      );
    }

    return buttons;
  }

  /// Toggle mute
  void _toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final newMutedState = !_isMuted;
        audioTracks[0].enabled = !newMutedState;
        _isMuted = newMutedState;

        // Update in Firebase
        _updateParticipantStatus();
        _updateDialogUI();
        _showMuteStatus();
      }
    }
  }

  /// Toggle video
  void _toggleVideo() {
    if (_localStream != null && _isVideoCall) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        final newVideoState = !_isVideoEnabled;
        videoTracks[0].enabled = newVideoState;
        _isVideoEnabled = newVideoState;

        // Update in Firebase
        _updateParticipantStatus();
        _updateDialogUI();
        _showVideoStatus();
      }
    }
  }

  /// Toggle speaker
  void _toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    _updateDialogUI();
    _showSpeakerStatus();
  }

  /// Switch camera
  void _switchCamera() {
    if (_localStream != null && _isVideoCall) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        try {
          Helper.switchCamera(videoTracks[0]);
          _showCameraSwitchStatus();
        } catch (e) {
          _showError('Failed to switch camera');
        }
      }
    }
  }

  /// Update participant status in Firebase
  Future<void> _updateParticipantStatus() async {
    if (_currentCallId != null) {
      await FirebaseFirestore.instance
          .collection('group_calls')
          .doc(_currentCallId!)
          .update({
        'participants.${currentUserCustomId}.isMuted': _isMuted,
        'participants.${currentUserCustomId}.isVideoEnabled': _isVideoEnabled,
      });
    }
  }

  /// Update dialog UI
  void _updateDialogUI() {
    _dialogSetState?.call(() {});
  }

  /// Show end call confirmation
  Future<bool?> _showEndCallConfirmation(BuildContext dialogContext) {
    return showDialog<bool>(
      context: dialogContext,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Leave Call?'),
          content: Text('Are you sure you want to leave this group call?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Leave'),
            ),
          ],
        );
      },
    );
  }

  /// End group call
  Future<void> endGroupCall({bool isRemoteDisconnection = false}) async {
    try {
      print('Ending group call...');

      // Clean up local stream
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) => track.stop());
        _localStream!.dispose();
        _localStream = null;
      }

      // Clean up peer connections
      for (final connection in _peerConnections.values) {
        await connection.close();
      }
      _peerConnections.clear();

      // Clean up remote streams and renderers
      for (final stream in _remoteStreams.values) {
        stream.dispose();
      }
      _remoteStreams.clear();

      for (final renderer in _remoteRenderers.values) {
        await renderer.dispose();
      }
      _remoteRenderers.clear();

      // Clean up local renderer
      _localRenderer.srcObject = null;

      // Remove self from call in Firebase (only if this user initiated the end)
      if (_currentCallId != null && !isRemoteDisconnection) {
        await FirebaseFirestore.instance
            .collection('group_calls')
            .doc(_currentCallId!)
            .update({
          'participants.${currentUserCustomId}': FieldValue.delete(),
        });

        // If no participants left, end the call
        final callDoc = await FirebaseFirestore.instance
            .collection('group_calls')
            .doc(_currentCallId!)
            .get();

        if (callDoc.exists) {
          final participants = callDoc.data()?['participants'] as Map<String, dynamic>?;
          if (participants == null || participants.isEmpty) {
            await FirebaseFirestore.instance
                .collection('group_calls')
                .doc(_currentCallId!)
                .update({'status': 'ended'});
          }
        }
      }

      // Cancel listeners
      _participantsListener?.cancel();
      _candidatesListener?.cancel();
      _callListener?.cancel();
      _callTimeoutTimer?.cancel();

      // Reset state
      _isInCall = false;
      _isVideoCall = false;
      _isMuted = false;
      _isVideoEnabled = true;
      _isSpeakerOn = false;
      _currentCallId = null;
      _dialogSetState = null;
      _participants.clear();
      _participantOrder.clear();

      print('Group call ended successfully');

      // Close the call dialog first
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Close the call dialog
      }

      // Then call the callback to handle navigation back to previous screen
      Future.delayed(const Duration(milliseconds: 200), () {
        onCallEnded?.call();
      });

    } catch (e) {
      print('Error ending group call: $e');
      // Even if there's an error, try to navigate back
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      Future.delayed(const Duration(milliseconds: 200), () {
        onCallEnded?.call();
      });
    }
  }

  /// Cleanup resources
  void _cleanup() {
    _isInCall = false;
    _isVideoCall = false;
    _participants.clear();
    _participantOrder.clear();
    _localStream?.dispose();
    _localStream = null;
  }

  /// Show error message
  void _showError(String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Show status messages
  void _showMuteStatus() {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isMuted ? 'Microphone muted' : 'Microphone unmuted'),
          backgroundColor: _isMuted ? Colors.red : Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showVideoStatus() {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isVideoEnabled ? 'Camera enabled' : 'Camera disabled'),
          backgroundColor: _isVideoEnabled ? Colors.green : Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showSpeakerStatus() {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isSpeakerOn ? 'Speaker enabled' : 'Speaker disabled'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showCameraSwitchStatus() {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera switched'),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  /// Dispose resources
  void dispose() {
    print('Disposing GroupCallService...');
    _callTimeoutTimer?.cancel();
    endGroupCall();
    _localRenderer.dispose();
  }

  /// Force cleanup in case of errors
  Future<void> forceCleanup() async {
    try {
      print('Force cleaning up GroupCallService...');

      // Cancel all timers and listeners
      _callTimeoutTimer?.cancel();
      _participantsListener?.cancel();
      _candidatesListener?.cancel();
      _callListener?.cancel();

      // Dispose local stream
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) => track.stop());
        _localStream!.dispose();
        _localStream = null;
      }

      // Close all peer connections
      for (final connection in _peerConnections.values) {
        await connection.close();
      }
      _peerConnections.clear();

      // Dispose remote streams
      for (final stream in _remoteStreams.values) {
        stream.dispose();
      }
      _remoteStreams.clear();

      // Dispose remote renderers
      for (final renderer in _remoteRenderers.values) {
        await renderer.dispose();
      }
      _remoteRenderers.clear();

      // Clean up local renderer
      _localRenderer.srcObject = null;

      // Reset all state
      _isInCall = false;
      _isVideoCall = false;
      _isMuted = false;
      _isVideoEnabled = true;
      _isSpeakerOn = false;
      _currentCallId = null;
      _dialogSetState = null;
      _participants.clear();
      _participantOrder.clear();

      print('Force cleanup completed');
    } catch (e) {
      print('Error during force cleanup: $e');
    }
  }

  /// Get call statistics
  Map<String, dynamic> getCallStats() {
    return {
      'isInCall': _isInCall,
      'callType': _isVideoCall ? 'video' : 'voice',
      'participantCount': _participants.length,
      'isMuted': _isMuted,
      'isVideoEnabled': _isVideoEnabled,
      'isSpeakerOn': _isSpeakerOn,
      'currentCallId': _currentCallId,
      'groupId': groupId,
      'groupName': groupName,
    };
  }
}

/// Group call control button widget
class _GroupCallControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final double iconSize;
  final String? tooltip;

  const _GroupCallControlButton({
    required this.icon,
    required this.onPressed,
    required this.backgroundColor,
    this.iconSize = 24,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: backgroundColor,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.3),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        splashColor: Colors.white.withOpacity(0.2),
        highlightColor: Colors.white.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Icon(
            icon,
            color: Colors.white,
            size: iconSize,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}