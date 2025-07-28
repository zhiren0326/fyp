import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:open_file/open_file.dart';
import 'dart:async';

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
  final ImagePicker _imagePicker = ImagePicker();

  // API Keys - Replace with your actual keys
  static const String _geminiApiKey = 'YOUR_GEMINI_API_KEY';
  static const String _googleTranslateApiKey = 'YOUR_GOOGLE_TRANSLATE_API_KEY';

  // Language settings
  String _selectedLanguage = 'en';
  final Map<String, String> _languageNames = {
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'it': 'Italian',
    'pt': 'Portuguese',
    'ru': 'Russian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'zh': 'Chinese',
    'ar': 'Arabic',
    'hi': 'Hindi',
    'th': 'Thai',
    'vi': 'Vietnamese',
    'id': 'Indonesian',
  };

  bool _isRecording = false;
  String? _recordedFilePath;
  bool _isGroup = false;
  bool _isGroupOwner = false;

  // Feature flags
  bool _isRealTimeTranslationEnabled = false;
  bool _showOriginalText = false;
  Map<String, String> _translationCache = {};
  Map<String, dynamic> _userPreferences = {};
  List<Map<String, dynamic>> _pinnedMessages = [];
  bool _isTyping = false;
  Timer? _typingTimer;
  String _currentTypingUser = '';

  // WebRTC Simple Implementation
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _isInCall = false;
  bool _isVideoCall = false;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  // Localized Interface
  Map<String, Map<String, String>> _localizedStrings = {
    'en': {
      'type_message': 'Type a message...',
      'no_messages': 'No messages yet',
      'pinned_messages': 'Pinned Messages',
      'voice_message': 'Voice Message',
      'file': 'File',
      'image': 'Image',
      'sending': 'Sending...',
      'today': 'Today',
      'yesterday': 'Yesterday',
      'typing': 'is typing...',
      'online': 'Online',
      'offline': 'Offline',
      'last_seen': 'Last seen',
    },
    'es': {
      'type_message': 'Escribe un mensaje...',
      'no_messages': 'No hay mensajes aún',
      'pinned_messages': 'Mensajes Fijados',
      'voice_message': 'Mensaje de Voz',
      'file': 'Archivo',
      'image': 'Imagen',
      'sending': 'Enviando...',
      'today': 'Hoy',
      'yesterday': 'Ayer',
      'typing': 'está escribiendo...',
      'online': 'En línea',
      'offline': 'Desconectado',
      'last_seen': 'Última vez',
    },
    'fr': {
      'type_message': 'Tapez un message...',
      'no_messages': 'Pas encore de messages',
      'pinned_messages': 'Messages Épinglés',
      'voice_message': 'Message Vocal',
      'file': 'Fichier',
      'image': 'Image',
      'sending': 'Envoi...',
      'today': 'Aujourd\'hui',
      'yesterday': 'Hier',
      'typing': 'est en train d\'écrire...',
      'online': 'En ligne',
      'offline': 'Hors ligne',
      'last_seen': 'Vu dernièrement',
    },
    // Add more languages as needed
  };

  @override
  void initState() {
    super.initState();
    _checkIfGroup();
    _checkIfGroupOwner();
    _loadUserPreferences();
    _setupTypingIndicator();
    _initializeWebRTC();
    _listenToIncomingCalls();
    _resetUnreadMessages();
  }

  // Reset unread messages when opening chat
  Future<void> _resetUnreadMessages() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('unread_counts')
          .doc('counts')
          .update({widget.selectedCustomId: FieldValue.delete()});
    } catch (e) {
      print('Error resetting unread count: $e');
    }
  }

  // Initialize WebRTC
  Future<void> _initializeWebRTC() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  // Get localized string
  String _getLocalizedString(String key) {
    return _localizedStrings[_selectedLanguage]?[key] ??
        _localizedStrings['en']?[key] ??
        key;
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isRealTimeTranslationEnabled = prefs.getBool('realTimeTranslation_${widget.currentUserCustomId}') ?? false;
      _selectedLanguage = prefs.getString('preferredLanguage_${widget.currentUserCustomId}') ?? 'en';
      _showOriginalText = prefs.getBool('showOriginalText_${widget.currentUserCustomId}') ?? false;
    });
  }

  Future<void> _saveUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('realTimeTranslation_${widget.currentUserCustomId}', _isRealTimeTranslationEnabled);
    await prefs.setString('preferredLanguage_${widget.currentUserCustomId}', _selectedLanguage);
    await prefs.setBool('showOriginalText_${widget.currentUserCustomId}', _showOriginalText);
  }

  void _setupTypingIndicator() {
    _messageController.addListener(() {
      if (_messageController.text.isNotEmpty && !_isTyping) {
        _sendTypingIndicator(true);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          _sendTypingIndicator(false);
        });
      } else if (_messageController.text.isEmpty && _isTyping) {
        _sendTypingIndicator(false);
        _typingTimer?.cancel();
      }
    });
  }

  Future<void> _sendTypingIndicator(bool isTyping) async {
    setState(() {
      _isTyping = isTyping;
    });

    try {
      final typingData = {
        'userCustomId': widget.currentUserCustomId,
        'userName': widget.selectedUserName,
        'isTyping': isTyping,
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (_isGroup) {
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.selectedCustomId)
            .collection('typing')
            .doc(widget.currentUserCustomId)
            .set(typingData);
      } else {
        final chatRoomId = _getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId);
        await FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(chatRoomId)
            .collection('typing')
            .doc(widget.currentUserCustomId)
            .set(typingData);
      }

      // Auto-remove typing indicator after 5 seconds
      if (isTyping) {
        Future.delayed(const Duration(seconds: 5), () {
          _sendTypingIndicator(false);
        });
      }
    } catch (e) {
      print('Error sending typing indicator: $e');
    }
  }

  // Enhanced Translation with Google Translate API
  Future<String> _translateText(String text, String targetLanguage) async {
    if (text.isEmpty || targetLanguage == 'en') return text;

    // Check cache first
    final cacheKey = '${text}_$targetLanguage';
    if (_translationCache.containsKey(cacheKey)) {
      return _translationCache[cacheKey]!;
    }

    try {
      // Using Google Translate API
      final response = await http.post(
        Uri.parse('https://translation.googleapis.com/language/translate/v2?key=$_googleTranslateApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'q': text,
          'target': targetLanguage,
          'source': 'auto',
          'format': 'text'
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translatedText = data['data']['translations'][0]['translatedText'];

        // Cache the translation
        _translationCache[cacheKey] = translatedText;

        return translatedText;
      } else {
        // Fallback to Gemini API
        return await _translateWithGemini(text, targetLanguage);
      }
    } catch (e) {
      print('Translation error: $e');
      return text;
    }
  }

  // Fallback translation with Gemini
  Future<String> _translateWithGemini(String text, String targetLanguage) async {
    try {
      final languageName = _languageNames[targetLanguage] ?? targetLanguage;
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [{
              'text': 'Translate the following text to $languageName. Only provide the translation, nothing else: $text'
            }]
          }]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'].trim();
      }
    } catch (e) {
      print('Gemini translation error: $e');
    }
    return text;
  }

  // Document Translation
  Future<void> _translateDocument(PlatformFile file) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final fileBytes = await File(file.path!).readAsBytes();
      String content = '';

      // Extract text based on file type
      if (file.extension == 'txt') {
        content = utf8.decode(fileBytes);
      } else if (file.extension == 'pdf') {
        // For PDF, you would need to use a PDF parsing library
        content = 'PDF content (implement PDF parsing)';
      } else if (file.extension == 'docx' || file.extension == 'doc') {
        // For Word docs, you would need appropriate parsing
        content = 'Word document content (implement parsing)';
      }

      if (content.isEmpty) {
        Navigator.pop(context);
        throw Exception('Could not extract text from file');
      }

      // Translate content
      final translatedContent = await _translateText(content, _selectedLanguage);

      Navigator.pop(context);

      // Show translated content
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.translate, color: Colors.teal[800]),
              const SizedBox(width: 8),
              const Text('Translated Document'),
            ],
          ),
          content: Container(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_showOriginalText) ...[
                    Text(
                      'Original (${file.name}):',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(content),
                    const Divider(height: 20),
                  ],
                  Text(
                    'Translated to ${_languageNames[_selectedLanguage]}:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(translatedContent),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _sendMessage(text: translatedContent);
              },
              child: const Text('Send Translation'),
            ),
            TextButton(
              onPressed: () async {
                // Save translated document
                final directory = await getApplicationDocumentsDirectory();
                final translatedFile = File('${directory.path}/translated_${file.name}');
                await translatedFile.writeAsString(translatedContent);

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Saved to: ${translatedFile.path}'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Document translation error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Voice Translation
  Future<void> _translateVoiceMessage(String voicePath) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final fileBytes = await File(voicePath).readAsBytes();
      final base64Audio = base64Encode(fileBytes);

      // Transcribe and translate using Gemini
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-pro-vision:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [
              {
                'inline_data': {
                  'mime_type': 'audio/mp4',
                  'data': base64Audio,
                }
              },
              {
                'text': 'Transcribe this audio and translate it to ${_languageNames[_selectedLanguage]}. Format: Original: [transcription] | Translation: [translation]'
              }
            ]
          }]
        }),
      );

      Navigator.pop(context);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['candidates'][0]['content']['parts'][0]['text'];

        // Parse the result
        final parts = result.split('|');
        final original = parts[0].replaceAll('Original:', '').trim();
        final translation = parts.length > 1 ? parts[1].replaceAll('Translation:', '').trim() : original;

        // Show translation dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.mic, color: Colors.teal[800]),
                const SizedBox(width: 8),
                const Text('Voice Translation'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_showOriginalText) ...[
                  const Text(
                    'Original:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(original),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Translation (${_languageNames[_selectedLanguage]}):',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(translation),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _sendMessage(text: translation);
                },
                child: const Text('Send as Text'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Voice translation error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Language Settings Dialog
  void _showLanguageSettings() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.language, color: Colors.teal[800]),
              const SizedBox(width: 8),
              const Text('Language Settings'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Real-time translation toggle
                SwitchListTile(
                  title: const Text('Real-time Translation'),
                  subtitle: const Text('Automatically translate incoming messages'),
                  value: _isRealTimeTranslationEnabled,
                  onChanged: (bool value) {
                    setDialogState(() {
                      _isRealTimeTranslationEnabled = value;
                    });
                    setState(() {
                      _isRealTimeTranslationEnabled = value;
                    });
                    _saveUserPreferences();
                  },
                  activeColor: Colors.teal[800],
                ),
                const Divider(),

                // Show original text toggle
                SwitchListTile(
                  title: const Text('Show Original Text'),
                  subtitle: const Text('Display original text along with translation'),
                  value: _showOriginalText,
                  onChanged: (bool value) {
                    setDialogState(() {
                      _showOriginalText = value;
                    });
                    setState(() {
                      _showOriginalText = value;
                    });
                    _saveUserPreferences();
                  },
                  activeColor: Colors.teal[800],
                ),
                const Divider(),

                // Language selection
                const Text(
                  'Preferred Language',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.teal),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedLanguage,
                      isExpanded: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      items: _languageNames.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Row(
                            children: [
                              Text(
                                _getLanguageFlag(entry.key),
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              Text(entry.value),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setDialogState(() {
                            _selectedLanguage = newValue;
                          });
                          setState(() {
                            _selectedLanguage = newValue;
                          });
                          _saveUserPreferences();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Quick translate button
                ElevatedButton.icon(
                  onPressed: () async {
                    final text = _messageController.text;
                    if (text.isNotEmpty) {
                      final translated = await _translateText(text, _selectedLanguage);
                      _messageController.text = translated;
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.translate),
                  label: const Text('Translate Current Message'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[700],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  String _getLanguageFlag(String langCode) {
    final flags = {
      'en': '🇬🇧',
      'es': '🇪🇸',
      'fr': '🇫🇷',
      'de': '🇩🇪',
      'it': '🇮🇹',
      'pt': '🇵🇹',
      'ru': '🇷🇺',
      'ja': '🇯🇵',
      'ko': '🇰🇷',
      'zh': '🇨🇳',
      'ar': '🇸🇦',
      'hi': '🇮🇳',
      'th': '🇹🇭',
      'vi': '🇻🇳',
      'id': '🇮🇩',
    };
    return flags[langCode] ?? '🌐';
  }

  // Video Call Implementation (Simple WebRTC)
  Future<void> _startVideoCall() async {
    try {
      // Request permissions
      final permissions = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      if (!permissions.values.every((status) => status.isGranted)) {
        throw Exception('Camera and microphone permissions required');
      }

      // Create peer connection
      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ]
      };

      _peerConnection = await createPeerConnection(configuration);

      // Get user media
      final mediaConstraints = {
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        }
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;

      // Add tracks to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Set up peer connection event handlers
      _peerConnection!.onIceCandidate = (candidate) {
        _sendIceCandidate(candidate);
      };

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          setState(() {
            _remoteStream = event.streams[0];
            _remoteRenderer.srcObject = _remoteStream;
          });
        }
      };

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send call invitation via Firebase
      final callData = {
        'callerId': widget.currentUserCustomId,
        'callerName': widget.selectedUserName,
        'calleeId': widget.selectedCustomId,
        'type': 'video',
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        },
        'status': 'calling',
        'timestamp': FieldValue.serverTimestamp(),
      };

      final callId = '${widget.currentUserCustomId}_${DateTime.now().millisecondsSinceEpoch}';
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .set(callData);

      setState(() {
        _isInCall = true;
        _isVideoCall = true;
      });

      _showCallDialog(true, callId);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start video call: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startVoiceCall() async {
    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        throw Exception('Microphone permission required');
      }

      // Create peer connection
      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ]
      };

      _peerConnection = await createPeerConnection(configuration);

      // Get audio only
      final mediaConstraints = {
        'audio': true,
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      // Add audio track to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Set up event handlers
      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          setState(() {
            _remoteStream = event.streams[0];
          });
        }
      };

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send call invitation
      final callData = {
        'callerId': widget.currentUserCustomId,
        'callerName': widget.selectedUserName,
        'calleeId': widget.selectedCustomId,
        'type': 'voice',
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        },
        'status': 'calling',
        'timestamp': FieldValue.serverTimestamp(),
      };

      final callId = '${widget.currentUserCustomId}_${DateTime.now().millisecondsSinceEpoch}';
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .set(callData);

      setState(() {
        _isInCall = true;
        _isVideoCall = false;
      });

      _showCallDialog(false, callId);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start voice call: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _listenToIncomingCalls() {
    FirebaseFirestore.instance
        .collection('calls')
        .where('calleeId', isEqualTo: widget.currentUserCustomId)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final callData = change.doc.data();
          _showIncomingCallDialog(change.doc.id, callData!);
        }
      }
    });
  }

  void _showIncomingCallDialog(String callId, Map<String, dynamic> callData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          'Incoming ${callData['type'] == 'video' ? 'Video' : 'Voice'} Call',
          style: TextStyle(color: Colors.teal[800]),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              callData['type'] == 'video' ? Icons.videocam : Icons.call,
              size: 60,
              color: Colors.teal[800],
            ),
            const SizedBox(height: 16),
            Text(
              '${callData['callerName']} is calling...',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _rejectCall(callId);
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Decline'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _acceptCall(callId, callData);
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptCall(String callId, Map<String, dynamic> callData) async {
    try {
      // Set up peer connection
      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ]
      };

      _peerConnection = await createPeerConnection(configuration);

      // Get media based on call type
      final mediaConstraints = {
        'audio': true,
        'video': callData['type'] == 'video',
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      if (callData['type'] == 'video') {
        _localRenderer.srcObject = _localStream;
      }

      // Add tracks
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Set remote description
      final offer = RTCSessionDescription(
        callData['offer']['sdp'],
        callData['offer']['type'],
      );
      await _peerConnection!.setRemoteDescription(offer);

      // Create answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Update call status
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({
        'status': 'connected',
        'answer': {
          'sdp': answer.sdp,
          'type': answer.type,
        }
      });

      setState(() {
        _isInCall = true;
        _isVideoCall = callData['type'] == 'video';
      });

      _showCallDialog(callData['type'] == 'video', callId);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept call: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectCall(String callId) async {
    await FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .update({'status': 'rejected'});
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    // Implementation for sending ICE candidates through Firebase
    // This would be part of the WebRTC signaling process
  }

  void _showCallDialog(bool isVideo, String callId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: isVideo ? MediaQuery.of(context).size.height * 0.8 : 300,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Call header
                Container(
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
                        backgroundImage: NetworkImage(widget.selectedUserPhotoURL),
                        radius: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.selectedUserName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              isVideo ? 'Video Call' : 'Voice Call',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                      ),
                    ],
                  ),
                ),

                // Video/Audio area
                Expanded(
                  child: isVideo ? Stack(
                    children: [
                      // Remote video
                      Container(
                        color: Colors.black,
                        child: _remoteStream != null
                            ? RTCVideoView(_remoteRenderer)
                            : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                backgroundImage: NetworkImage(widget.selectedUserPhotoURL),
                                radius: 60,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Connecting...',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Local video (picture-in-picture)
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
                            child: _localStream != null
                                ? RTCVideoView(_localRenderer, mirror: true)
                                : Container(color: Colors.grey[800]),
                          ),
                        ),
                      ),
                    ],
                  ) : Container(
                    color: Colors.grey[850],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            backgroundImage: NetworkImage(widget.selectedUserPhotoURL),
                            radius: 60,
                          ),
                          const SizedBox(height: 24),
                          Icon(
                            Icons.call,
                            size: 40,
                            color: Colors.teal[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _remoteStream != null ? 'Connected' : 'Connecting...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Call controls
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Mute button
                      _CallControlButton(
                        icon: _localStream?.getAudioTracks().first.enabled ?? true
                            ? Icons.mic
                            : Icons.mic_off,
                        onPressed: () {
                          final audioTrack = _localStream?.getAudioTracks().first;
                          if (audioTrack != null) {
                            audioTrack.enabled = !audioTrack.enabled;
                            setState(() {});
                          }
                        },
                        backgroundColor: Colors.grey[700]!,
                      ),

                      // Video toggle (only for video calls)
                      if (isVideo)
                        _CallControlButton(
                          icon: _localStream?.getVideoTracks().first.enabled ?? true
                              ? Icons.videocam
                              : Icons.videocam_off,
                          onPressed: () {
                            final videoTrack = _localStream?.getVideoTracks().first;
                            if (videoTrack != null) {
                              videoTrack.enabled = !videoTrack.enabled;
                              setState(() {});
                            }
                          },
                          backgroundColor: Colors.grey[700]!,
                        ),

                      // End call button
                      _CallControlButton(
                        icon: Icons.call_end,
                        onPressed: () => _endCall(callId),
                        backgroundColor: Colors.red,
                        iconSize: 32,
                      ),

                      // Speaker button
                      _CallControlButton(
                        icon: Icons.volume_up,
                        onPressed: () {
                          // Toggle speaker
                        },
                        backgroundColor: Colors.grey[700]!,
                      ),

                      // Switch camera (only for video calls)
                      if (isVideo)
                        _CallControlButton(
                          icon: Icons.switch_camera,
                          onPressed: () {
                            _localStream?.getVideoTracks().forEach((track) {
                              Helper.switchCamera(track);
                            });
                          },
                          backgroundColor: Colors.grey[700]!,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _endCall(String callId) async {
    try {
      // Clean up local stream
      _localStream?.getTracks().forEach((track) => track.stop());
      _localStream?.dispose();
      _localStream = null;

      // Clean up remote stream
      _remoteStream?.getTracks().forEach((track) => track.stop());
      _remoteStream?.dispose();
      _remoteStream = null;

      // Close peer connection
      await _peerConnection?.close();
      _peerConnection = null;

      // Clean up renderers
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;

      // Update call status
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({
        'status': 'ended',
        'endTime': FieldValue.serverTimestamp(),
      });

      setState(() {
        _isInCall = false;
        _isVideoCall = false;
      });

      Navigator.of(context).pop();
    } catch (e) {
      print('Error ending call: $e');
    }
  }

  // Image picker with compression
  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImageFromSource(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImageFromSource(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        final file = File(image.path);
        final fileBytes = await file.readAsBytes();

        // Check file size
        if (fileBytes.length > 5 * 1024 * 1024) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image size exceeds 5MB limit'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        final base64Image = base64Encode(fileBytes);
        await _sendMessage(
          imageBase64: base64Image,
          imageName: path.basename(image.path),
          messageType: 'image',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // File picker with document translation option
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'],
      );

      if (result != null) {
        final file = result.files.first;

        // Check if it's a document that can be translated
        if (['txt', 'pdf', 'doc', 'docx'].contains(file.extension)) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Document Options'),
              content: const Text('Would you like to translate this document?'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _sendFileMessage(file);
                  },
                  child: const Text('Send Original'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _translateDocument(file);
                  },
                  child: const Text('Translate'),
                ),
              ],
            ),
          );
        } else {
          _sendFileMessage(file);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendFileMessage(PlatformFile file) async {
    try {
      final fileBytes = await File(file.path!).readAsBytes();

      // Check file size
      if (fileBytes.length > 10 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File size exceeds 10MB limit'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final base64File = base64Encode(fileBytes);
      await _sendMessage(
        fileBase64: base64File,
        fileName: file.name,
        messageType: 'file',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Voice recording with translation
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
          content: Text('Recording failed: $e'),
          backgroundColor: Colors.red,
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
        // Show voice message options
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.mic, color: Colors.teal[800]),
                const SizedBox(width: 8),
                const Text('Voice Message'),
              ],
            ),
            content: const Text('Choose how to send your voice message:'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _sendVoiceMessage(_recordedFilePath!);
                },
                child: const Text('Send Voice'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _translateVoiceMessage(_recordedFilePath!);
                },
                child: const Text('Translate First'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _recordedFilePath = null;
                  });
                },
                child: const Text('Cancel', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to stop recording: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendVoiceMessage(String voicePath) async {
    try {
      final voiceBytes = await File(voicePath).readAsBytes();

      if (voiceBytes.length > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice message too large'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final base64Voice = base64Encode(voiceBytes);
      await _sendMessage(
        voiceBase64: base64Voice,
        voiceFileName: path.basename(voicePath),
        messageType: 'voice',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send voice message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Main send message function
  Future<void> _sendMessage({
    String? text,
    String? fileBase64,
    String? fileName,
    String? voiceBase64,
    String? voiceFileName,
    String? imageBase64,
    String? imageName,
    String messageType = 'text',
  }) async {
    String messageText = text ?? _messageController.text.trim();

    if (messageText.isEmpty &&
        fileBase64 == null &&
        voiceBase64 == null &&
        imageBase64 == null) return;

    try {
      // Get current user details
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

      final messageData = {
        'text': messageText,
        'senderCustomId': widget.currentUserCustomId,
        'senderName': currentUserDoc['name'] ?? 'Unknown',
        'timestamp': FieldValue.serverTimestamp(),
        'type': messageType,
        'originalLanguage': _selectedLanguage,
        'isPinned': false,
        if (fileBase64 != null) 'fileBase64': fileBase64,
        if (fileName != null) 'fileName': fileName,
        if (voiceBase64 != null) 'voiceBase64': voiceBase64,
        if (voiceFileName != null) 'voiceFileName': voiceFileName,
        if (imageBase64 != null) 'imageBase64': imageBase64,
        if (imageName != null) 'imageName': imageName,
      };

      if (_isGroup) {
        // Send to group
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.selectedCustomId)
            .collection('messages')
            .add(messageData);

        // Update last message for all group members
        final memberDocs = await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.selectedCustomId)
            .collection('members')
            .get();

        for (var member in memberDocs.docs) {
          if (member['userId'] != widget.currentUserCustomId) {
            // Update unread count for other members
            await FirebaseFirestore.instance
                .collection('users')
                .doc(member['userId'])
                .collection('unread_counts')
                .doc('counts')
                .set({
              widget.selectedCustomId: FieldValue.increment(1)
            }, SetOptions(merge: true));
          }

          // Update last message
          await FirebaseFirestore.instance
              .collection('users')
              .doc(member['userId'])
              .collection('messages')
              .doc(widget.selectedCustomId)
              .set({
            'lastMessage': messageText.isNotEmpty ? messageText : '$messageType message',
            'timestamp': FieldValue.serverTimestamp(),
            'senderCustomId': widget.currentUserCustomId,
            'senderName': currentUserDoc['name'] ?? 'Unknown',
            'groupId': widget.selectedCustomId,
            'groupName': widget.selectedUserName,
            'type': messageType,
          }, SetOptions(merge: true));
        }
      } else {
        // Send to individual
        final chatRoomId = _getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId);
        await FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(chatRoomId)
            .collection('messages')
            .add(messageData);

        // Get recipient user ID
        final recipientUserId = (await FirebaseFirestore.instance
            .collection('custom_ids')
            .where('customId', isEqualTo: widget.selectedCustomId)
            .get())
            .docs[0]['userId'];

        // Update unread count for recipient
        await FirebaseFirestore.instance
            .collection('users')
            .doc(recipientUserId)
            .collection('unread_counts')
            .doc('counts')
            .set({
          widget.currentUserCustomId: FieldValue.increment(1)
        }, SetOptions(merge: true));

        // Update last message for recipient
        await FirebaseFirestore.instance
            .collection('users')
            .doc(recipientUserId)
            .collection('messages')
            .doc(widget.currentUserCustomId)
            .set({
          'lastMessage': messageText.isNotEmpty ? messageText : '$messageType message',
          'timestamp': FieldValue.serverTimestamp(),
          'senderCustomId': widget.currentUserCustomId,
          'senderName': currentUserDoc['name'] ?? 'Unknown',
          'type': messageType,
        }, SetOptions(merge: true));
      }

      _messageController.clear();
      _sendTypingIndicator(false);
      _scrollToBottom();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Message pinning (for groups)
  Future<void> _togglePinMessage(String messageId) async {
    if (!_isGroup || !_isGroupOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only group admins can pin messages'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final messageRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.selectedCustomId)
          .collection('messages')
          .doc(messageId);

      final message = await messageRef.get();
      final isPinned = message['isPinned'] ?? false;

      // Check pinned message limit
      if (!isPinned) {
        final pinnedCount = await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.selectedCustomId)
            .collection('messages')
            .where('isPinned', isEqualTo: true)
            .get();

        if (pinnedCount.docs.length >= 5) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Maximum 5 pinned messages allowed'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }

      await messageRef.update({'isPinned': !isPinned});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isPinned ? 'Message unpinned' : 'Message pinned'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pin/unpin message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _sendTypingIndicator(false);
    _endCall('');
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _messageController.dispose();
    _recorder.dispose();
    _scrollController.dispose();
    super.dispose();
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

    if (groupDoc.exists) {
      final creatorId = groupDoc['creatorId'];
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null) {
        final customIdDoc = await FirebaseFirestore.instance
            .collection('custom_ids')
            .doc(currentUser.uid)
            .get();

        setState(() {
          _isGroupOwner = customIdDoc['customId'] == widget.currentUserCustomId &&
              creatorId == currentUser.uid;
        });
      }
    }
  }

  String _getChatRoomId(String customId1, String customId2) {
    return customId1.compareTo(customId2) < 0
        ? '${customId1}_$customId2'
        : '${customId2}_$customId1';
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
                  : NetworkImage(widget.selectedUserPhotoURL) as ImageProvider,
              radius: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.selectedUserName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (_isRealTimeTranslationEnabled)
                    Text(
                      'Auto-translate: ${_languageNames[_selectedLanguage]}',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.teal[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: _isInCall ? null : _startVideoCall,
            tooltip: 'Video Call',
          ),
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: _isInCall ? null : _startVoiceCall,
            tooltip: 'Voice Call',
          ),
          IconButton(
            icon: const Icon(Icons.translate),
            onPressed: _showLanguageSettings,
            tooltip: 'Language Settings',
          ),
          if (_isGroup)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'pin') {
                  _showPinnedMessages();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'pin',
                  child: Row(
                    children: [
                      Icon(Icons.push_pin, color: Colors.black54),
                      SizedBox(width: 8),
                      Text('Pinned Messages'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.teal[50]!, Colors.white],
          ),
        ),
        child: Column(
          children: [
            // Pinned messages bar (for groups)
            if (_isGroup)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('groups')
                    .doc(widget.selectedCustomId)
                    .collection('messages')
                    .where('isPinned', isEqualTo: true)
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final pinnedMessages = snapshot.data!.docs;
                  return Container(
                    color: Colors.amber[100],
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.push_pin, size: 16, color: Colors.amber[800]),
                            const SizedBox(width: 4),
                            Text(
                              _getLocalizedString('pinned_messages'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber[900],
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _showPinnedMessages,
                              child: const Text('View All'),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 60,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: pinnedMessages.length.clamp(0, 3),
                            itemBuilder: (context, index) {
                              final message = pinnedMessages[index];
                              return Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.amber),
                                ),
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message['senderName'] ?? 'Unknown',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      message['text'] ?? 'Media message',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            // Typing indicator
            _buildTypingIndicator(),

            // Messages list
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
                    .collection('chat_rooms')
                    .doc(_getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId))
                    .collection('messages')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        _getLocalizedString('no_messages'),
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final message = snapshot.data!.docs[index];
                      return _buildMessage(message);
                    },
                  );
                },
              ),
            ),

            // Input area
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Attachment options
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _pickFile,
                    color: Colors.teal[700],
                  ),
                  IconButton(
                    icon: const Icon(Icons.image),
                    onPressed: _pickImage,
                    color: Colors.teal[700],
                  ),

                  // Message input
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _getLocalizedString('type_message'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),

                  // Voice or send button
                  if (_messageController.text.isEmpty)
                    IconButton(
                      icon: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        color: _isRecording ? Colors.red : Colors.teal[700],
                      ),
                      onPressed: _isRecording ? _stopRecording : _startRecording,
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.send, color: Colors.teal[700]),
                      onPressed: () => _sendMessage(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return StreamBuilder<QuerySnapshot>(
      stream: _isGroup
          ? FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.selectedCustomId)
          .collection('typing')
          .where('isTyping', isEqualTo: true)
          .where('userCustomId', isNotEqualTo: widget.currentUserCustomId)
          .snapshots()
          : FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(_getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId))
          .collection('typing')
          .where('isTyping', isEqualTo: true)
          .where('userCustomId', isNotEqualTo: widget.currentUserCustomId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final typingUsers = snapshot.data!.docs
            .map((doc) => doc['userName'] as String)
            .toList();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 20,
                child: Stack(
                  children: List.generate(3, (index) {
                    return AnimatedPositioned(
                      duration: Duration(milliseconds: 300 + (index * 100)),
                      left: index * 10.0,
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 300 + (index * 100)),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.teal[600],
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                typingUsers.length == 1
                    ? '${typingUsers.first} ${_getLocalizedString('typing')}'
                    : '${typingUsers.length} people ${_getLocalizedString('typing')}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessage(DocumentSnapshot message) {
    final isMe = message['senderCustomId'] == widget.currentUserCustomId;
    final messageData = message.data() as Map<String, dynamic>;
    final isPinned = messageData['isPinned'] ?? false;

    return FutureBuilder<String>(
      future: _isRealTimeTranslationEnabled && messageData['text'] != null
          ? _translateText(messageData['text'], _selectedLanguage)
          : Future.value(messageData['text'] ?? ''),
      builder: (context, translationSnapshot) {
        final translatedText = translationSnapshot.data ?? messageData['text'] ?? '';

        return GestureDetector(
          onLongPress: () {
            _showMessageOptions(message.id, messageData, isMe);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe) ...[
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: NetworkImage(widget.selectedUserPhotoURL),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.teal[100] : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                        bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 1,
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                      border: isPinned
                          ? Border.all(color: Colors.amber, width: 2)
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sender name (for groups)
                        if (_isGroup && !isMe)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              messageData['senderName'] ?? 'Unknown',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal[800],
                                fontSize: 12,
                              ),
                            ),
                          ),

                        // Message content
                        if (messageData['type'] == 'text' && translatedText.isNotEmpty) ...[
                          if (_showOriginalText &&
                              _isRealTimeTranslationEnabled &&
                              messageData['text'] != translatedText) ...[
                            Text(
                              messageData['text'],
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            translatedText,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ] else if (messageData['type'] == 'image') ...[
                          _buildImageMessage(messageData),
                        ] else if (messageData['type'] == 'file') ...[
                          _buildFileMessage(messageData),
                        ] else if (messageData['type'] == 'voice') ...[
                          _buildVoiceMessage(messageData),
                        ],

                        // Timestamp
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isPinned)
                              Icon(
                                Icons.push_pin,
                                size: 12,
                                color: Colors.amber[700],
                              ),
                            if (isPinned) const SizedBox(width: 4),
                            Text(
                              messageData['timestamp'] != null
                                  ? DateFormat('HH:mm').format(
                                  (messageData['timestamp'] as Timestamp).toDate())
                                  : _getLocalizedString('sending'),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: NetworkImage(widget.selectedUserPhotoURL),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageMessage(Map<String, dynamic> message) {
    return GestureDetector(
      onTap: () => _showFullImage(message['imageBase64']),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          base64Decode(message['imageBase64']),
          width: 200,
          height: 200,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildFileMessage(Map<String, dynamic> message) {
    return InkWell(
      onTap: () => _downloadFile(message),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, color: Colors.teal[700]),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message['fileName'] ?? _getLocalizedString('file'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _formatFileSize(base64Decode(message['fileBase64']).length),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceMessage(Map<String, dynamic> message) {
    return InkWell(
      onTap: () => _playVoiceMessage(message),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic, color: Colors.blue[700]),
            const SizedBox(width: 8),
            Text(
              _getLocalizedString('voice_message'),
              style: TextStyle(color: Colors.blue[700]),
            ),
            const SizedBox(width: 8),
            Text(
              '0:${message['voiceFileName']?.split('_').last?.split('.').first?.substring(10, 12) ?? '00'}',
              style: TextStyle(
                color: Colors.blue[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageOptions(String messageId, Map<String, dynamic> message, bool isMe) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message['type'] == 'text')
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message['text']));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
            if (message['type'] == 'text')
              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text('Translate'),
                onTap: () async {
                  Navigator.pop(context);
                  final translated = await _translateText(
                    message['text'],
                    _selectedLanguage,
                  );
                  _showTranslationDialog(message['text'], translated);
                },
              ),
            if (_isGroup && _isGroupOwner)
              ListTile(
                leading: Icon(
                  message['isPinned'] ?? false ? Icons.push_pin_outlined : Icons.push_pin,
                ),
                title: Text(
                  message['isPinned'] ?? false ? 'Unpin Message' : 'Pin Message',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _togglePinMessage(messageId);
                },
              ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(messageId);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showTranslationDialog(String original, String translated) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.translate, color: Colors.teal[800]),
            const SizedBox(width: 8),
            const Text('Translation'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Original:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(original),
            const SizedBox(height: 12),
            Text(
              'Translation (${_languageNames[_selectedLanguage]}):',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(translated),
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
  }

  void _showPinnedMessages() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 500),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber[100],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.push_pin, color: Colors.amber[800]),
                    const SizedBox(width: 8),
                    Text(
                      _getLocalizedString('pinned_messages'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('groups')
                      .doc(widget.selectedCustomId)
                      .collection('messages')
                      .where('isPinned', isEqualTo: true)
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text('No pinned messages'),
                      );
                    }

                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final message = snapshot.data!.docs[index];
                        return _buildPinnedMessageItem(message);
                      },
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedMessageItem(DocumentSnapshot message) {
    final messageData = message.data() as Map<String, dynamic>;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.teal[100],
        child: Text(
          (messageData['senderName'] ?? 'U')[0].toUpperCase(),
          style: TextStyle(color: Colors.teal[800]),
        ),
      ),
      title: Text(messageData['senderName'] ?? 'Unknown'),
      subtitle: Text(
        messageData['text'] ?? 'Media message',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _isGroupOwner
          ? IconButton(
        icon: const Icon(Icons.push_pin_outlined),
        onPressed: () => _togglePinMessage(message.id),
      )
          : null,
    );
  }

  void _showFullImage(String base64Image) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.black,
            actions: [
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: () => _saveImage(base64Image),
              ),
            ],
          ),
          body: Container(
            color: Colors.black,
            child: Center(
              child: InteractiveViewer(
                child: Image.memory(base64Decode(base64Image)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveImage(String base64Image) async {
    try {
      final bytes = base64Decode(base64Image);
      final directory = await getExternalStorageDirectory();
      final file = File('${directory!.path}/image_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image saved to: ${file.path}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadFile(Map<String, dynamic> message) async {
    try {
      final bytes = base64Decode(message['fileBase64']);
      final directory = await getExternalStorageDirectory();
      final file = File('${directory!.path}/${message['fileName']}');
      await file.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File saved to: ${file.path}'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Open',
            onPressed: () async {
              final result = await OpenFile.open(file.path);
              if (result.type != ResultType.done) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not open file: ${result.message}'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _playVoiceMessage(Map<String, dynamic> message) async {
    // Show dialog with play controls and translation option
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.mic, color: Colors.blue[700]),
            const SizedBox(width: 8),
            const Text('Voice Message'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_filled, size: 60, color: Colors.blue[700]),
            const SizedBox(height: 16),
            const Text('Voice message playback'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Save voice file and play
              _saveAndPlayVoice(message);
            },
            child: const Text('Play'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Save and translate
              final tempDir = await getTemporaryDirectory();
              final file = File('${tempDir.path}/${message['voiceFileName']}');
              await file.writeAsBytes(base64Decode(message['voiceBase64']));
              _translateVoiceMessage(file.path);
            },
            child: const Text('Translate'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndPlayVoice(Map<String, dynamic> message) async {
    try {
      final bytes = base64Decode(message['voiceBase64']);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${message['voiceFileName']}');
      await file.writeAsBytes(bytes);

      // Open the file with default audio player
      await OpenFile.open(file.path);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to play voice message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      final collection = _isGroup
          ? FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.selectedCustomId)
          .collection('messages')
          : FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(_getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId))
          .collection('messages');

      await collection.doc(messageId).delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// Call control button widget
class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final double iconSize;

  const _CallControlButton({
    required this.icon,
    required this.onPressed,
    required this.backgroundColor,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            color: Colors.white,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}

