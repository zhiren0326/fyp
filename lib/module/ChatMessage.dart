import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

class ChatMessage extends StatefulWidget {
  final String currentUserCustomId;
  final String selectedCustomId;
  final String selectedUserName;
  final String selectedUserPhotoURL;

  const ChatMessage({
    Key? key,
    required this.currentUserCustomId,
    required this.selectedCustomId,
    required this.selectedUserName,
    required this.selectedUserPhotoURL,
  }) : super(key: key);

  @override
  _ChatMessageState createState() => _ChatMessageState();
}

class _ChatMessageState extends State<ChatMessage> {
  final TextEditingController _messageController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final ScrollController _scrollController = ScrollController();
  static const String _geminiApiKey = 'AIzaSyCFdlu9A8pY0FaZEMVaZ7eL-D9XcveMufo';
  static const String _agoraAppId = '<664e8245651b4e39bbcda74d210eb5a0>'; // Replace with your Agora App ID
  String _selectedLanguage = 'en';
  final List<String> _languages = [
    'en', 'es', 'fr', 'de', 'it', 'ja', 'ko', 'zh-cn', 'ru', 'ar'
  ];
  bool _isRecording = false;
  String? _recordedFilePath;
  bool _isGroup = false;
  bool _isGroupOwner = false;
  RtcEngine? _agoraEngine;
  bool _isInCall = false;
  bool _isVideoCall = false;
  int? _remoteUid;
  bool _isAgoraInitialized = false;

  @override
  void initState() {
    super.initState();
    _checkIfGroup();
    _checkIfGroupOwner();
    _initializeAgora();
  }

  Future<void> _initializeAgora() async {
    print('Starting Agora initialization at ${DateTime.now()}');
    bool granted = await _requestPermissions();
    if (granted) {
      print('Permissions granted, initializing Agora engine');
      _initializeAgoraEngine();
      if (_agoraEngine != null) {
        _isAgoraInitialized = true;
        print('Agora engine initialized successfully');
        _joinChannel();
      } else {
        print('Agora engine initialization failed');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initialize Agora engine. Check App ID and permissions.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      print('Permissions not granted, requesting again');
      _showPermissionRequestDialog();
    }
  }

  @override
  void dispose() {
    _cleanupAgoraEngine();
    _messageController.dispose();
    _recorder.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    var statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
    ].request();
    print('Permission statuses: camera=${statuses[Permission.camera]}, microphone=${statuses[Permission.microphone]}, storage=${statuses[Permission.storage]}');
    return statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted &&
        statuses[Permission.storage]!.isGranted;
  }

  void _showPermissionRequestDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text('This app needs camera, microphone, and storage permissions to enable voice and video calls. Please grant them in the settings.'),
        actions: [
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
              _initializeAgora(); // Retry after settings change
            },
            child: const Text('Open Settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _initializeAgoraEngine() {
    try {
      print('Creating Agora engine with App ID: $_agoraAppId');
      _agoraEngine = createAgoraRtcEngine();
      _agoraEngine!.initialize(const RtcEngineContext(
        appId: _agoraAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      print('Agora engine initialized, registering event handler');
      _agoraEngine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          setState(() {
            _isInCall = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Joined channel ${widget.selectedCustomId}'),
              backgroundColor: Colors.teal[700],
              duration: const Duration(seconds: 3),
            ),
          );
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          setState(() {
            _remoteUid = remoteUid;
          });
          _setupRemoteVideo(remoteUid);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('User $remoteUid joined'),
              backgroundColor: Colors.teal[700],
              duration: const Duration(seconds: 3),
            ),
          );
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          setState(() {
            _remoteUid = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('User $remoteUid offline'),
              backgroundColor: Colors.teal[700],
              duration: const Duration(seconds: 3),
            ),
          );
        },
        onError: (ErrorCodeType err, String msg) {
          print('Agora error: $err, $msg');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Agora error: $msg'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        },
      ));

      _agoraEngine!.enableVideo();
      _agoraEngine!.startPreview();
      _setupLocalVideo();
    } catch (e) {
      print('Exception during Agora initialization: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to initialize Agora: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _joinChannel() {
    if (!_isAgoraInitialized || _agoraEngine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agora engine not initialized'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      String token = '<Your token>'; // Replace with temporary token or fetch dynamically
      ChannelMediaOptions options = const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
      );
      print('Joining channel: ${widget.selectedCustomId} with token: $token');
      _agoraEngine!.joinChannel(
        token: token,
        channelId: widget.selectedCustomId,
        uid: 0,
        options: options,
      );
    } catch (e) {
      print('Exception during channel join: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to join channel: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _setupLocalVideo() {
    // Local video setup can be handled in the call dialog for simplicity
  }

  void _setupRemoteVideo(int uid) {
    // Remote video is handled in the call dialog
  }

  void _cleanupAgoraEngine() {
    if (_agoraEngine != null) {
      _agoraEngine!.stopPreview();
      _agoraEngine!.leaveChannel();
      _agoraEngine!.release();
    }
  }

  Future<void> _checkIfGroup() async {
    final groupDoc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.selectedCustomId)
        .get();
    setState(() {
      _isGroup = groupDoc.exists;
    });
  }

  Future<void> _checkIfGroupOwner() async {
    if (!_isGroup) return;
    final groupDoc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.selectedCustomId)
        .get();
    final ownerId = groupDoc['ownerCustomId'];
    setState(() {
      _isGroupOwner = ownerId == widget.currentUserCustomId;
    });
  }

  String _getChatRoomId(String customId1, String customId2) {
    return customId1.compareTo(customId2) < 0
        ? '${customId1}_$customId2'
        : '${customId2}_$customId1';
  }

  Future<void> _sendMessage({PlatformFile? file, String? text, String? voicePath}) async {
    String messageText = text ?? _messageController.text;
    if (messageText.isEmpty && file == null && voicePath == null) return;

    try {
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc((await FirebaseFirestore.instance
          .collection('custom_ids')
          .where('customId', isEqualTo: widget.currentUserCustomId)
          .get())
          .docs[0]['userId'])
          .collection('profiledetails')
          .doc('profile')
          .get();

      String? fileBase64;
      String? fileName;
      String? voiceBase64;
      String? voiceFileName;
      String type = 'text';

      if (file != null) {
        final fileBytes = await File(file.path!).readAsBytes();
        if (fileBytes.length > 500 * 1024) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File size exceeds 500KB limit.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
        fileBase64 = base64Encode(fileBytes);
        fileName = file.name;
        type = 'file';
      }

      if (voicePath != null) {
        final voiceBytes = await File(voicePath).readAsBytes();
        if (voiceBytes.length > 500 * 1024) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Voice file size exceeds 500KB limit.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
        voiceBase64 = base64Encode(voiceBytes);
        voiceFileName = path.basename(voicePath);
        type = 'voice';
      }

      final messageData = {
        'text': messageText,
        'senderCustomId': widget.currentUserCustomId,
        'senderName': currentUserDoc['name'] ?? 'Unknown',
        'timestamp': FieldValue.serverTimestamp(),
        'fileBase64': fileBase64,
        'fileName': fileName,
        'voiceBase64': voiceBase64,
        'voiceFileName': voiceFileName,
        'originalLanguage': 'en',
        'isPinned': false,
        'type': type,
      };

      if (_isGroup) {
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.selectedCustomId)
            .collection('messages')
            .add(messageData);

        final memberDocs = await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.selectedCustomId)
            .collection('members')
            .get();
        for (var member in memberDocs.docs) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(member['userId'])
              .collection('messages')
              .doc(widget.selectedCustomId)
              .set({
            'lastMessage': messageText,
            'timestamp': FieldValue.serverTimestamp(),
            'senderCustomId': widget.currentUserCustomId,
            'groupId': widget.selectedCustomId,
            'type': type,
            if (fileName != null) 'fileName': fileName,
            if (voiceFileName != null) 'voiceFileName': voiceFileName,
          }, SetOptions(merge: true));
        }
      } else {
        final chatRoomId = _getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId);
        final collectionPath = 'chat_rooms/$chatRoomId/messages';
        await FirebaseFirestore.instance.collection(collectionPath).add(messageData);

        final recipientUserId = (await FirebaseFirestore.instance
            .collection('custom_ids')
            .where('customId', isEqualTo: widget.selectedCustomId)
            .get())
            .docs[0]['userId'];
        await FirebaseFirestore.instance
            .collection('users')
            .doc(recipientUserId)
            .collection('messages')
            .doc(widget.currentUserCustomId)
            .set({
          'lastMessage': messageText,
          'timestamp': FieldValue.serverTimestamp(),
          'senderCustomId': widget.currentUserCustomId,
          'type': type,
          if (fileName != null) 'fileName': fileName,
          if (voiceFileName != null) 'voiceFileName': voiceFileName,
        }, SetOptions(merge: true));
      }

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'pdf'],
      );
      if (result != null) {
        final file = result.files.first;
        final translatedText = await _translateFile(file);
        await _sendMessage(file: file, text: translatedText);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload file: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _togglePinMessage(String messageId) async {
    if (!_isGroupOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the group owner can pin/unpin messages.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      final collectionPath = _isGroup
          ? 'groups/${widget.selectedCustomId}/messages'
          : 'chat_rooms/${_getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId)}/messages';
      final messageRef = FirebaseFirestore.instance.collection(collectionPath).doc(messageId);
      final message = await messageRef.get();
      final isPinned = message['isPinned'] ?? false;
      await messageRef.update({'isPinned': !isPinned});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pin/unpin message: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showPinMessageDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Select Messages to Pin',
            style: TextStyle(color: Colors.teal[800], fontWeight: FontWeight.bold),
          ),
          content: Container(
            width: double.maxFinite,
            height: 400,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('groups')
                  .doc(widget.selectedCustomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages available',
                      style: TextStyle(color: Colors.teal[800]),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isPinned = message['isPinned'] ?? false;
                    return FutureBuilder<String>(
                      future: _translateMessage(message['text'] ?? '', _selectedLanguage),
                      builder: (context, snapshot) {
                        final translatedText = snapshot.data ?? message['text'] ?? '';
                        return CheckboxListTile(
                          title: Text(
                            translatedText.isNotEmpty ? translatedText : 'Media Message',
                            style: TextStyle(color: Colors.teal[900]),
                          ),
                          subtitle: Text(
                            message['senderName'] ?? 'Unknown',
                            style: TextStyle(color: Colors.teal[600]),
                          ),
                          value: isPinned,
                          onChanged: (bool? value) {
                            _togglePinMessage(message.id);
                          },
                          activeColor: Colors.teal[800],
                          secondary: Icon(
                            isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                            color: Colors.teal[800],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: TextStyle(color: Colors.teal[800]),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startVoiceCall() async {
    if (!_isAgoraInitialized || _agoraEngine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agora engine not initialized'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_isInCall) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already in a call.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      await _agoraEngine!.enableAudio();
      await _agoraEngine!.disableVideo();
      _joinChannel();
      setState(() {
        _isInCall = true;
        _isVideoCall = false;
      });
      _showCallDialog(false);
    } catch (e) {
      print('Voice call error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start voice call: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _startVideoCall() async {
    if (!_isAgoraInitialized || _agoraEngine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agora engine not initialized'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_isInCall) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already in a call.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      await _agoraEngine!.enableVideo();
      await _agoraEngine!.enableAudio();
      _joinChannel();
      setState(() {
        _isInCall = true;
        _isVideoCall = true;
      });
      _showCallDialog(true);
    } catch (e) {
      print('Video call error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start video call: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _endCall() async {
    if (!_isAgoraInitialized || _agoraEngine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agora engine not initialized'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      await _agoraEngine!.leaveChannel();
      setState(() {
        _isInCall = false;
        _isVideoCall = false;
        _remoteUid = null;
      });
      Navigator.of(context).pop(); // Close the call dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Call ended'),
          backgroundColor: Colors.teal[700],
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('End call error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to end call: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showCallDialog(bool isVideoCall) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(
            isVideoCall ? 'Video Call' : 'Voice Call',
            style: TextStyle(color: Colors.teal[800], fontWeight: FontWeight.bold),
          ),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'In call with ${widget.selectedUserName}',
                  style: TextStyle(color: Colors.teal[800], fontSize: 18),
                ),
                const SizedBox(height: 20),
                if (isVideoCall && _remoteUid != null)
                  Expanded(
                    child: AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _agoraEngine!,
                        canvas: VideoCanvas(uid: _remoteUid),
                      ),
                    ),
                  )
                else if (isVideoCall)
                  Text(
                    'Waiting for remote user...',
                    style: TextStyle(color: Colors.teal[600]),
                  )
                else
                  Icon(
                    Icons.call,
                    size: 100,
                    color: Colors.teal[800],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _endCall,
              child: Text(
                'End Call',
                style: TextStyle(color: Colors.red[700]),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: filePath,
        );
        setState(() {
          _isRecording = true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording permission denied: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
      });
      if (_recordedFilePath != null) {
        final transcribedText = await _transcribeAndTranslateVoice(_recordedFilePath!);
        await _sendMessage(voicePath: _recordedFilePath, text: transcribedText);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to process recording: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<String> _transcribeAndTranslateVoice(String filePath) async {
    try {
      final fileBytes = await File(filePath).readAsBytes();
      final base64Audio = base64Encode(fileBytes);

      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'inlineData': {
                    'mimeType': 'audio/mp4',
                    'data': base64Audio,
                  },
                },
                {'text': 'Transcribe this audio and translate it to $_selectedLanguage.'}
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        throw Exception('Failed to transcribe/translate: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Voice transcription/translation error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return '';
    }
  }

  Future<String> _translateFile(PlatformFile file) async {
    try {
      final fileBytes = await File(file.path!).readAsBytes();
      String content = '';
      if (file.extension == 'txt') {
        content = utf8.decode(fileBytes);
      } else if (file.extension == 'pdf') {
        content = 'PDF content extraction not implemented';
      }

      if (_selectedLanguage == 'en') return content;

      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': 'Translate the following text to $_selectedLanguage: $content'}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        throw Exception('Failed to translate file: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File translation error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return '';
    }
  }

  Future<String> _translateMessage(String text, String targetLanguage) async {
    if (text.isEmpty || targetLanguage == 'en') return text;
    try {
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': 'Translate the following text to $targetLanguage: $text'}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        throw Exception('Failed to translate: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Translation error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return text;
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: widget.selectedUserPhotoURL.startsWith('assets/')
                  ? AssetImage(widget.selectedUserPhotoURL)
                  : (widget.selectedUserPhotoURL.startsWith('data:image')
                  ? MemoryImage(base64Decode(widget.selectedUserPhotoURL.split(',')[1]))
                  : NetworkImage(widget.selectedUserPhotoURL)) as ImageProvider,
              radius: 20,
              onBackgroundImageError: (exception, stackTrace) => AssetImage('assets/default_avatar.png'),
            ),
            const SizedBox(width: 10),
            Text(
              widget.selectedUserName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: Colors.teal[800],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          DropdownButton<String>(
            value: _selectedLanguage,
            icon: const Icon(Icons.translate, color: Colors.white),
            dropdownColor: Colors.teal[800],
            items: _languages.map((String lang) {
              return DropdownMenuItem<String>(
                value: lang,
                child: Text(
                  lang.toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedLanguage = newValue!;
              });
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB2DFDB), Colors.white],
          ),
        ),
        child: Column(
          children: [
            if (_isGroup) // Pinned messages section for groups
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('groups')
                    .doc(widget.selectedCustomId)
                    .collection('messages')
                    .where('isPinned', isEqualTo: true)
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final pinnedMessages = snapshot.data!.docs;
                  return Container(
                    color: Colors.yellow[100]?.withOpacity(0.8),
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pinned Messages',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal[800],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...pinnedMessages.map((message) {
                          return FutureBuilder<String>(
                            future: _translateMessage(message['text'] ?? '', _selectedLanguage),
                            builder: (context, snapshot) {
                              final translatedText = snapshot.data ?? message['text'] ?? '';
                              return Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.yellow[700]!, width: 2),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message['senderName'] ?? 'Unknown',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal[800],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (translatedText.isNotEmpty)
                                      Text(
                                        translatedText,
                                        style: TextStyle(
                                          color: Colors.teal[900],
                                          fontSize: 16,
                                        ),
                                      ),
                                    if (message['fileBase64'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: InkWell(
                                          onTap: () async {
                                            try {
                                              final bytes = base64Decode(message['fileBase64']);
                                              final directory = await getTemporaryDirectory();
                                              final file = File('${directory.path}/${message['fileName']}');
                                              await file.writeAsBytes(bytes);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('File downloaded to ${file.path}'),
                                                  backgroundColor: Colors.teal[700],
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Failed to download file: $e'),
                                                  backgroundColor: Colors.red,
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            }
                                          },
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.attach_file, color: Colors.teal[800]),
                                              const SizedBox(width: 8),
                                              Text(
                                                message['fileName'] ?? 'File',
                                                style: TextStyle(
                                                  color: Colors.teal[800],
                                                  decoration: TextDecoration.underline,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (message['voiceBase64'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: InkWell(
                                          onTap: () async {
                                            try {
                                              final bytes = base64Decode(message['voiceBase64']);
                                              final directory = await getTemporaryDirectory();
                                              final file = File('${directory.path}/${message['voiceFileName']}');
                                              await file.writeAsBytes(bytes);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Voice file downloaded to ${file.path}'),
                                                  backgroundColor: Colors.teal[700],
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Failed to download voice: $e'),
                                                  backgroundColor: Colors.red,
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            }
                                          },
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.mic, color: Colors.teal[800]),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Voice Message',
                                                style: TextStyle(
                                                  color: Colors.teal[800],
                                                  decoration: TextDecoration.underline,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          );
                        }).toList(),
                      ],
                    ),
                  );
                },
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _isGroup
                    ? FirebaseFirestore.instance
                    .collection('groups')
                    .doc(widget.selectedCustomId)
                    .collection('messages')
                    .orderBy('timestamp', descending: true)
                    .snapshots()
                    : FirebaseFirestore.instance
                    .collection('chat_rooms/${_getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId)}/messages')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        'No messages yet',
                        style: TextStyle(
                          color: Colors.teal[800],
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }

                  final messages = snapshot.data!.docs;
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message['senderCustomId'] == widget.currentUserCustomId;
                      final isPinned = message['isPinned'] ?? false;

                      return FutureBuilder<String>(
                        future: _translateMessage(message['text'] ?? '', _selectedLanguage),
                        builder: (context, snapshot) {
                          final translatedText = snapshot.data ?? message['text'] ?? '';
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: widget.selectedUserPhotoURL.startsWith('assets/')
                                  ? AssetImage(widget.selectedUserPhotoURL)
                                  : (widget.selectedUserPhotoURL.startsWith('data:image')
                                  ? MemoryImage(base64Decode(widget.selectedUserPhotoURL.split(',')[1]))
                                  : NetworkImage(widget.selectedUserPhotoURL)) as ImageProvider,
                              radius: 20,
                              onBackgroundImageError: (exception, stackTrace) => AssetImage('assets/default_avatar.png'),
                            ),
                            title: GestureDetector(
                              onLongPress: _isGroup && _isGroupOwner ? () => _togglePinMessage(message.id) : null,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.teal[100]?.withOpacity(0.9)
                                      : Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                  border: isPinned
                                      ? Border.all(color: Colors.yellow[700]!, width: 2)
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message['senderName'] ?? 'Unknown',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal[800],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (translatedText.isNotEmpty)
                                      Text(
                                        translatedText,
                                        style: TextStyle(
                                          color: Colors.teal[900],
                                          fontSize: 18,
                                        ),
                                      ),
                                    if (message['fileBase64'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: InkWell(
                                          onTap: () async {
                                            try {
                                              final bytes = base64Decode(message['fileBase64']);
                                              final directory = await getTemporaryDirectory();
                                              final file = File('${directory.path}/${message['fileName']}');
                                              await file.writeAsBytes(bytes);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('File downloaded to ${file.path}'),
                                                  backgroundColor: Colors.teal[700],
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Failed to download file: $e'),
                                                  backgroundColor: Colors.red,
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            }
                                          },
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.attach_file, color: Colors.teal[800]),
                                              const SizedBox(width: 8),
                                              Text(
                                                message['fileName'] ?? 'File',
                                                style: TextStyle(
                                                  color: Colors.teal[800],
                                                  decoration: TextDecoration.underline,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (message['voiceBase64'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: InkWell(
                                          onTap: () async {
                                            try {
                                              final bytes = base64Decode(message['voiceBase64']);
                                              final directory = await getTemporaryDirectory();
                                              final file = File('${directory.path}/${message['voiceFileName']}');
                                              await file.writeAsBytes(bytes);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Voice file downloaded to ${file.path}'),
                                                  backgroundColor: Colors.teal[700],
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Failed to download voice: $e'),
                                                  backgroundColor: Colors.red,
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            }
                                          },
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.mic, color: Colors.teal[800]),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Voice Message',
                                                style: TextStyle(
                                                  color: Colors.teal[800],
                                                  decoration: TextDecoration.underline,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6, left: 20, right: 20),
                              child: Text(
                                message['timestamp'] != null
                                    ? DateFormat('hh:mm a').format((message['timestamp'] as Timestamp).toDate())
                                    : 'Sending...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.teal[600],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.attach_file, color: Colors.teal[800], size: 28),
                    onPressed: _pickFile,
                    tooltip: 'Attach File',
                  ),
                  IconButton(
                    icon: Icon(Icons.videocam, color: Colors.teal[800], size: 28),
                    onPressed: _isInCall ? _endCall : _startVideoCall,
                    tooltip: _isInCall ? 'End Video Call' : 'Start Video Call',
                  ),
                  IconButton(
                    icon: Icon(Icons.call, color: Colors.teal[800], size: 28),
                    onPressed: _isInCall ? _endCall : _startVoiceCall,
                    tooltip: _isInCall ? 'End Voice Call' : 'Start Voice Call',
                  ),
                  if (_isGroup && _isGroupOwner)
                    IconButton(
                      icon: Icon(Icons.push_pin, color: Colors.teal[800], size: 28),
                      onPressed: _showPinMessageDialog,
                      tooltip: 'Manage Pinned Messages',
                    ),
                  IconButton(
                    icon: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: _isRecording ? Colors.red[700] : Colors.teal[800],
                      size: 28,
                    ),
                    onPressed: _isRecording ? _stopRecording : _startRecording,
                    tooltip: _isRecording ? 'Stop Recording' : 'Record Voice',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Colors.teal[500], fontSize: 18),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: Colors.teal[400]!, width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: Colors.teal[800]!, width: 3),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                      ),
                      style: TextStyle(fontSize: 18, color: Colors.teal[900]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => _sendMessage(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[800],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(16),
                      elevation: 4,
                    ),
                    child: const Icon(Icons.send, color: Colors.white, size: 28),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}