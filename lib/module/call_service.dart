import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class CallService {
  final BuildContext context;
  final String currentUserCustomId;
  final String selectedCustomId;
  final String selectedUserName;
  final String selectedUserPhotoURL;

  // Add a callback for navigation
  final VoidCallback? onCallEnded;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isInCall = false;
  bool _isVideoCall = false;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerOn = false;
  bool _remoteVideoReceived = false;
  bool _isCallConnected = false;

  // Add setState function for dialog updates
  Function? _dialogSetState;

  StreamSubscription? _callListener;
  StreamSubscription? _candidateListener;
  StreamSubscription? _callUpdateListener;
  String? _currentCallId;

  // Timer for call timeout
  Timer? _callTimeoutTimer;

  // Track who ended the call
  bool _callEndedByRemoteUser = false;

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

  CallService({
    required this.context,
    required this.currentUserCustomId,
    required this.selectedCustomId,
    required this.selectedUserName,
    required this.selectedUserPhotoURL,
    this.onCallEnded,
  });

  /// Initialize the call service
  Future<void> initialize() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _listenToIncomingCalls();
  }

  /// Start a video call
  Future<void> startVideoCall() async {
    if (_isInCall) {
      _showError('Already in a call');
      return;
    }

    try {
      print('Starting video call...');

      // Request permissions
      final permissions = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      if (!permissions.values.every((status) => status.isGranted)) {
        _showError('Camera and microphone permissions required');
        return;
      }

      await _createPeerConnection();
      await _getUserMedia(true); // true for video

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      print('Offer created and local description set');

      // Send call invitation
      _currentCallId = '${currentUserCustomId}_${DateTime.now().millisecondsSinceEpoch}';
      await _sendCallInvitation(_currentCallId!, 'video', offer);

      _isInCall = true;
      _isVideoCall = true;

      // Listen to call updates immediately after sending invitation
      _listenToCallUpdates(_currentCallId!);

      // Start timeout timer
      _startCallTimeout();

      _showCallDialog();
      print('Video call started successfully');

    } catch (e) {
      print('Error starting video call: $e');
      _showError('Failed to start video call: $e');
      // Clean up on error
      _isInCall = false;
      _isVideoCall = false;
    }
  }

  /// Start a voice call
  Future<void> startVoiceCall() async {
    if (_isInCall) {
      _showError('Already in a call');
      return;
    }

    try {
      print('Starting voice call...');

      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        _showError('Microphone permission required');
        return;
      }

      await _createPeerConnection();
      await _getUserMedia(false); // false for audio only

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      print('Offer created and local description set');

      // Send call invitation
      _currentCallId = '${currentUserCustomId}_${DateTime.now().millisecondsSinceEpoch}';
      await _sendCallInvitation(_currentCallId!, 'voice', offer);

      _isInCall = true;
      _isVideoCall = false;

      // Listen to call updates immediately after sending invitation
      _listenToCallUpdates(_currentCallId!);

      // Start timeout timer
      _startCallTimeout();

      _showCallDialog();
      print('Voice call started successfully');

    } catch (e) {
      print('Error starting voice call: $e');
      _showError('Failed to start voice call: $e');
      // Clean up on error
      _isInCall = false;
      _isVideoCall = false;
    }
  }

  /// Start call timeout timer
  void _startCallTimeout() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!_isCallConnected) {
        _showError('No answer from ${selectedUserName}');
        _cancelCall();
      }
    });
  }

  /// Create peer connection
  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_configuration);

    _peerConnection!.onIceCandidate = (candidate) {
      if (_currentCallId != null) {
        _sendIceCandidate(_currentCallId!, candidate);
      }
    };

    _peerConnection!.onTrack = (event) {
      print('Received remote track: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteRenderer.srcObject = _remoteStream;
        _remoteVideoReceived = true;
        _isCallConnected = true;
        print('Remote stream set successfully');

        // Cancel timeout timer
        _callTimeoutTimer?.cancel();

        // Update dialog UI
        _updateDialogUI();
      }
    };

    _peerConnection!.onConnectionState = (state) {
      print('Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        print('Call connected successfully');
        _isCallConnected = true;
        _callTimeoutTimer?.cancel();
        _updateDialogUI();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        print('Call disconnected or failed');
        endCall(isRemoteDisconnection: true);
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      print('ICE Connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        _isCallConnected = true;
        _callTimeoutTimer?.cancel();
        _updateDialogUI();
      }
    };
  }

  /// Update dialog UI
  void _updateDialogUI() {
    if (_dialogSetState != null) {
      _dialogSetState!(() {});
    }
  }

  /// Listen to call updates
  void _listenToCallUpdates(String callId) {
    _callUpdateListener = FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) async {
      if (!context.mounted) {
        print('Context not mounted, cancelling call update listener');
        _callUpdateListener?.cancel();
        return;
      }

      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;

        if (data['status'] == 'answered' && data['answer'] != null) {
          try {
            final answer = RTCSessionDescription(
              data['answer']['sdp'],
              data['answer']['type'],
            );
            await _peerConnection!.setRemoteDescription(answer);
            print('Remote description set successfully');

            // Update UI to show connection is being established
            _updateDialogUI();
          } catch (e) {
            print('Error setting remote description: $e');
          }
        } else if (data['status'] == 'rejected') {
          _callTimeoutTimer?.cancel();
          if (context.mounted) {
            _showError('Call was rejected');
          }
          endCall(isRemoteDisconnection: true);
        } else if (data['status'] == 'ended') {
          print('Call ended by other user');
          _callEndedByRemoteUser = true;
          endCall(isRemoteDisconnection: true);
        } else if (data['status'] == 'cancelled') {
          print('Call was cancelled');
          endCall(isRemoteDisconnection: true);
        }
      }
    });

    // Listen for ICE candidates
    _candidateListener = FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .collection('candidates')
        .snapshots()
        .listen((snapshot) {
      if (!context.mounted) {
        print('Context not mounted, cancelling candidate listener');
        _candidateListener?.cancel();
        return;
      }

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          if (data['userId'] != currentUserCustomId) { // Only add candidates from the other user
            try {
              final candidate = RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              );
              _peerConnection?.addCandidate(candidate);
              print('ICE candidate added from user: ${data['userId']}');
            } catch (e) {
              print('Error adding ICE candidate: $e');
            }
          }
        }
      }
    });
  }

  /// Show navigation prompt dialog
  Future<void> _showNavigationPrompt({bool wasEndedByRemoteUser = false}) async {
    if (!context.mounted) return;

    // Determine the message based on how the call ended
    String title;
    String message;

    if (wasEndedByRemoteUser) {
      title = 'Call Ended';
      message = '$selectedUserName has ended the call. Would you like to return to the chat?';
    } else {
      title = 'Call Ended';
      message = 'The call has ended. Would you like to return to the chat?';
    }

    final shouldNavigate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.call_end,
                color: Colors.red,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundImage: NetworkImage(selectedUserPhotoURL),
                radius: 30,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay Here'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat, size: 18),
                  SizedBox(width: 4),
                  Text('Back to Chat'),
                ],
              ),
            ),
          ],
        );
      },
    );

    // Navigate back to chat if user confirmed
    if (shouldNavigate == true) {
      _performNavigation();
    }
  }

  /// Perform the actual navigation
  void _performNavigation() {
    // Close call dialog if open
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // Call the callback to handle navigation
    onCallEnded?.call();
  }

  /// Navigate back to chat screen (modified to show prompt)
  void _navigateBackToChat({bool wasEndedByRemoteUser = false}) {
    // Show prompt dialog instead of immediately navigating
    _showNavigationPrompt(wasEndedByRemoteUser: wasEndedByRemoteUser);
  }

  /// Cancel outgoing call
  Future<void> _cancelCall() async {
    if (_currentCallId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('calls')
            .doc(_currentCallId!)
            .update({
          'status': 'cancelled',
          'endTime': FieldValue.serverTimestamp(),
        });
        print('Call cancelled');
      } catch (e) {
        print('Error cancelling call: $e');
      }
    }
    endCall();
  }

  /// Show call dialog
  void _showCallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (!didPop) {
            // Show confirmation dialog before ending call
            final shouldEnd = await _showEndCallConfirmation(dialogContext);
            if (shouldEnd == true) {
              await _cancelCall();
            }
          }
        },
        child: StatefulBuilder(
          builder: (context, setState) {
            // Store setState function for updates
            _dialogSetState = setState;

            return Dialog(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: _isVideoCall ? MediaQuery.of(context).size.height * 0.8 : 400,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    // Call header
                    _buildCallHeader(),

                    // Video/Audio area
                    Expanded(
                      child: _isVideoCall ? _buildVideoCallArea() : _buildVoiceCallArea(),
                    ),

                    // Call controls
                    _buildCallControls(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ).then((_) {
      // Dialog was closed
      _dialogSetState = null;
    });
  }

  /// Show end call confirmation dialog
  Future<bool?> _showEndCallConfirmation(BuildContext dialogContext) {
    return showDialog<bool>(
      context: dialogContext,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('End Call?'),
          content: Text('Are you sure you want to end this call with $selectedUserName?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Yes, End Call'),
            ),
          ],
        );
      },
    );
  }

  /// Build video call area
  Widget _buildVideoCallArea() {
    return Stack(
      children: [
        // Remote video or connecting state
        Container(
          color: Colors.black,
          child: (_remoteStream != null && _isCallConnected)
              ? RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
              : Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  backgroundImage: NetworkImage(selectedUserPhotoURL),
                  radius: 60,
                ),
                const SizedBox(height: 16),
                Text(
                  _isCallConnected ? 'Connected' : 'Calling...',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                if (!_isCallConnected)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Local video (picture-in-picture)
        if (_localStream != null)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              width: 120,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _isVideoEnabled
                    ? RTCVideoView(
                  _localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
                    : Container(
                  color: Colors.grey[800],
                  child: const Center(
                    child: Icon(Icons.videocam_off, color: Colors.white, size: 40),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Build voice call area
  Widget _buildVoiceCallArea() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey[900]!,
            Colors.grey[850]!,
            Colors.grey[800]!,
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // User avatar with glow effect
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _isCallConnected
                        ? Colors.teal.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundImage: NetworkImage(selectedUserPhotoURL),
                radius: 80,
                backgroundColor: Colors.grey[700],
              ),
            ),

            const SizedBox(height: 32),

            // User name
            Text(
              selectedUserName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 16),

            // Call status with icon
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isMuted ? Icons.mic_off : Icons.call,
                    size: 24,
                    color: _isMuted ? Colors.red : Colors.teal[300],
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _getCallStatusText(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Audio visualization or progress indicator
            if (_isCallConnected && _remoteStream != null)
              SizedBox(
                height: 60,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) =>
                      AnimatedContainer(
                        duration: Duration(milliseconds: 300 + (index * 100)),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: 4,
                        height: _isMuted ? 20 : (20 + (index * 8.0)),
                        decoration: BoxDecoration(
                          color: Colors.teal[300]?.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ),
                ),
              )
            else if (!_isCallConnected)
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
              ),
          ],
        ),
      ),
    );
  }

  /// Get call status text for voice calls
  String _getCallStatusText() {
    if (!_isCallConnected) {
      return 'Calling...';
    } else if (_isMuted && _remoteStream != null) {
      return 'Muted • Connected';
    } else if (_remoteStream != null) {
      return 'Connected';
    } else {
      return 'Connecting...';
    }
  }

  /// Build call header
  Widget _buildCallHeader() {
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
          CircleAvatar(
            backgroundImage: NetworkImage(selectedUserPhotoURL),
            radius: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedUserName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _isVideoCall ? 'Video Call' : 'Voice Call',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (_isCallConnected)
            StreamBuilder<int>(
              stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
              builder: (context, snapshot) {
                final duration = snapshot.data ?? 0;
                return Text(
                  '${(duration ~/ 60).toString().padLeft(2, '0')}:${(duration % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                );
              },
            )
          else
            const Text(
              'Calling...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
        ],
      ),
    );
  }

  /// Build call controls
  Widget _buildCallControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey[800]!,
            Colors.grey[850]!,
            Colors.grey[900]!,
          ],
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
          children: _buildControlButtons(),
        ),
      ),
    );
  }

  /// Build control buttons based on call type
  List<Widget> _buildControlButtons() {
    List<Widget> buttons = [];

    // Only show controls if call is connected
    if (_isCallConnected) {
      // Mute button
      buttons.add(
        _CallControlButton(
          icon: _isMuted ? Icons.mic_off : Icons.mic,
          onPressed: _toggleMute,
          backgroundColor: _isMuted ? Colors.red : Colors.grey[700]!,
          tooltip: _isMuted ? 'Unmute' : 'Mute',
        ),
      );

      // Video toggle (only for video calls)
      if (_isVideoCall) {
        buttons.add(
          _CallControlButton(
            icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
            onPressed: _toggleVideo,
            backgroundColor: _isVideoEnabled ? Colors.grey[700]! : Colors.red,
            tooltip: _isVideoEnabled ? 'Turn off camera' : 'Turn on camera',
          ),
        );
      }
    }

    // End call button (always present)
    buttons.add(
      _CallControlButton(
        icon: Icons.call_end,
        onPressed: () async {
          if (_isCallConnected) {
            endCall();
          } else {
            // If not connected yet, cancel the call
            await _cancelCall();
          }
        },
        backgroundColor: Colors.red,
        iconSize: 32,
        tooltip: 'End call',
      ),
    );

    // Only show additional controls if connected
    if (_isCallConnected) {
      // Speaker button
      buttons.add(
        _CallControlButton(
          icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
          onPressed: _toggleSpeaker,
          backgroundColor: _isSpeakerOn ? Colors.teal[600]! : Colors.grey[700]!,
          tooltip: _isSpeakerOn ? 'Turn off speaker' : 'Turn on speaker',
        ),
      );

      // Switch camera (only for video calls)
      if (_isVideoCall) {
        buttons.add(
          _CallControlButton(
            icon: Icons.switch_camera,
            onPressed: _switchCamera,
            backgroundColor: Colors.grey[700]!,
            tooltip: 'Switch camera',
          ),
        );
      }
    }

    return buttons;
  }

  /// End call (modified to track who ended the call)
  Future<void> endCall({bool isRemoteDisconnection = false}) async {
    try {
      print('Ending call...');

      // Cancel timeout timer
      _callTimeoutTimer?.cancel();

      // Clean up local stream
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          track.stop();
          print('Stopped local track: ${track.kind}');
        });
        _localStream!.dispose();
        _localStream = null;
      }

      // Clean up remote stream
      if (_remoteStream != null) {
        _remoteStream!.getTracks().forEach((track) {
          track.stop();
          print('Stopped remote track: ${track.kind}');
        });
        _remoteStream!.dispose();
        _remoteStream = null;
      }

      // Close peer connection
      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
        print('Peer connection closed');
      }

      // Clean up renderers
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;

      // Update call status in Firebase (only if this user initiated the end)
      if (_currentCallId != null && !isRemoteDisconnection) {
        try {
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(_currentCallId!)
              .update({
            'status': 'ended',
            'endTime': FieldValue.serverTimestamp(),
          });
          print('Call status updated to ended');
        } catch (e) {
          print('Error updating call status: $e');
        }
      }

      // Cancel all listeners
      _candidateListener?.cancel();
      _callUpdateListener?.cancel();

      // Store the call ended state before resetting
      final wasEndedByRemote = _callEndedByRemoteUser || isRemoteDisconnection;

      // Reset state
      _isInCall = false;
      _isVideoCall = false;
      _isMuted = false;
      _isVideoEnabled = true;
      _isSpeakerOn = false;
      _remoteVideoReceived = false;
      _isCallConnected = false;
      _currentCallId = null;
      _dialogSetState = null;
      _callEndedByRemoteUser = false;

      print('Call ended successfully');

      // Navigate back to chat with prompt
      _navigateBackToChat(wasEndedByRemoteUser: wasEndedByRemote);

    } catch (e) {
      print('Error ending call: $e');
      // Still try to navigate back even if cleanup fails
      _navigateBackToChat(wasEndedByRemoteUser: isRemoteDisconnection);
    }
  }

  /// Toggle mute
  void _toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final newMutedState = !_isMuted;
        audioTracks[0].enabled = !newMutedState;
        _isMuted = newMutedState;
        print('Audio ${_isMuted ? 'muted' : 'unmuted'}');

        // Update UI
        _updateDialogUI();
        // Show feedback to user
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
        print('Video ${_isVideoEnabled ? 'enabled' : 'disabled'}');

        // Update UI
        _updateDialogUI();
        _showVideoStatus();
      }
    }
  }

  /// Toggle speaker
  void _toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;

    // Enable/disable speaker phone
    if (_localStream != null) {
      print('Speaker ${_isSpeakerOn ? 'enabled' : 'disabled'}');
      _updateDialogUI();
      _showSpeakerStatus();
    }
  }

  /// Switch camera
  void _switchCamera() {
    if (_localStream != null && _isVideoCall) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        try {
          Helper.switchCamera(videoTracks[0]);
          print('Camera switched successfully');
          _showCameraSwitchStatus();
        } catch (e) {
          print('Error switching camera: $e');
          _showError('Failed to switch camera');
        }
      }
    }
  }

  /// Show incoming call dialog
  void _showIncomingCallDialog(String callId, Map<String, dynamic> callData) {
    if (_isInCall) {
      // Already in a call, reject this one
      _rejectCall(callId);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) {
            // Handle back button - reject call
            _rejectCall(callId);
            Navigator.of(context).pop();
          }
        },
        child: AlertDialog(
          title: Text(
            'Incoming ${callData['type'] == 'video' ? 'Video' : 'Voice'} Call',
            style: TextStyle(color: Colors.teal[800]),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundImage: NetworkImage(selectedUserPhotoURL),
                radius: 40,
              ),
              const SizedBox(height: 16),
              Icon(
                callData['type'] == 'video' ? Icons.videocam : Icons.call,
                size: 60,
                color: Colors.teal[800],
              ),
              const SizedBox(height: 16),
              Text(
                '${callData['callerName']} is calling...',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
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
                      Navigator.pop(context);
                      _rejectCall(callId);
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.call_end, size: 20),
                        SizedBox(width: 4),
                        Text('Decline'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _acceptCall(callId, callData);
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          callData['type'] == 'video' ? Icons.videocam : Icons.call,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        const Text('Accept'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Accept incoming call
  Future<void> _acceptCall(String callId, Map<String, dynamic> callData) async {
    try {
      print('Accepting call: $callId');
      _currentCallId = callId;
      _isVideoCall = callData['type'] == 'video';

      // Request permissions first
      if (_isVideoCall) {
        final permissions = await [
          Permission.camera,
          Permission.microphone,
        ].request();

        if (!permissions.values.every((status) => status.isGranted)) {
          _showError('Camera and microphone permissions required');
          _rejectCall(callId);
          return;
        }
      } else {
        final status = await Permission.microphone.request();
        if (!status.isGranted) {
          _showError('Microphone permission required');
          _rejectCall(callId);
          return;
        }
      }

      await _createPeerConnection();
      await _getUserMedia(_isVideoCall);

      // Set remote description from the offer
      final offer = RTCSessionDescription(
        callData['offer']['sdp'],
        callData['offer']['type'],
      );
      await _peerConnection!.setRemoteDescription(offer);
      print('Remote description set from offer');

      // Create and set local description (answer)
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      print('Local description set');

      // Send answer to Firebase
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({
        'status': 'answered',
        'answer': {
          'sdp': answer.sdp,
          'type': answer.type,
        }
      });

      _isInCall = true;
      _listenToCallUpdates(callId);
      _showCallDialog();

      print('Call accepted successfully');

    } catch (e) {
      print('Error accepting call: $e');
      _showError('Failed to accept call: $e');
      _rejectCall(callId);
    }
  }

  /// Reject incoming call
  Future<void> _rejectCall(String callId) async {
    await FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .update({'status': 'rejected'});
  }

  /// Get user media (camera/microphone)
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
        print('Local video stream set');
      }

      // Add tracks to peer connection
      if (_localStream != null && _peerConnection != null) {
        _localStream!.getTracks().forEach((track) {
          print('Adding track: ${track.kind}');
          _peerConnection!.addTrack(track, _localStream!);
        });
      }
    } catch (e) {
      print('Error getting user media: $e');
      throw Exception('Failed to access camera/microphone: $e');
    }
  }

  /// Send call invitation via Firebase
  Future<void> _sendCallInvitation(String callId, String type, RTCSessionDescription offer) async {
    final callData = {
      'callerId': currentUserCustomId,
      'callerName': selectedUserName,
      'calleeId': selectedCustomId,
      'type': type,
      'offer': {
        'sdp': offer.sdp,
        'type': offer.type,
      },
      'status': 'calling',
      'timestamp': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .set(callData);
  }

  /// Send ICE candidate
  Future<void> _sendIceCandidate(String callId, RTCIceCandidate candidate) async {
    await FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .collection('candidates')
        .add({
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
      'userId': currentUserCustomId, // Add user ID to identify who sent the candidate
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Listen to incoming calls
  void _listenToIncomingCalls() {
    _callListener = FirebaseFirestore.instance
        .collection('calls')
        .where('calleeId', isEqualTo: currentUserCustomId)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final callData = change.doc.data() as Map<String, dynamic>;
          _showIncomingCallDialog(change.doc.id, callData);
        }
      }
    });
  }

  /// Show mute status feedback
  void _showMuteStatus() {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isMuted ? Icons.mic_off : Icons.mic,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(_isMuted ? 'Microphone muted' : 'Microphone unmuted'),
            ],
          ),
          backgroundColor: _isMuted ? Colors.red : Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// Show video status feedback
  void _showVideoStatus() {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(_isVideoEnabled ? 'Camera enabled' : 'Camera disabled'),
            ],
          ),
          backgroundColor: _isVideoEnabled ? Colors.green : Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// Show speaker status feedback
  void _showSpeakerStatus() {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(_isSpeakerOn ? 'Speaker enabled' : 'Speaker disabled'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// Show camera switch status feedback
  void _showCameraSwitchStatus() {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.switch_camera, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Camera switched'),
            ],
          ),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  /// Show error message
  void _showError(String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      print('Error (context unmounted): $message');
    }
  }

  /// Dispose resources
  void dispose() {
    print('Disposing CallService...');
    _callTimeoutTimer?.cancel();
    endCall();
    _callListener?.cancel();
    _candidateListener?.cancel();
    _callUpdateListener?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }
}

/// Call control button widget
class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final double iconSize;
  final String? tooltip;

  const _CallControlButton({
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
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}