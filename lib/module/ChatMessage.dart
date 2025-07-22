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
  String _selectedLanguage = 'en'; // Default language
  final List<String> _languages = [
    'en', 'es', 'fr', 'de', 'it', 'ja', 'ko', 'zh-cn', 'ru', 'ar'
  ]; // Supported languages
  bool _isRecording = false;
  String? _recordedFilePath;
  bool _isGroup = false;

  @override
  void initState() {
    super.initState();
    _checkIfGroup();
  }

  @override
  void dispose() {
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
          // Limit to 500KB
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('File size exceeds 500KB limit.'),
              backgroundColor: Colors.red[700],
              duration: const Duration(seconds: 3),
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
          // Limit to 500KB
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Voice file size exceeds 500KB limit.'),
              backgroundColor: Colors.red[700],
              duration: const Duration(seconds: 3),
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
        // Store message in group messages collection
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
        // Store message for one-to-one chat
        final chatRoomId = _getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId);
        final collectionPath = 'chat_rooms/$chatRoomId/messages';
        await FirebaseFirestore.instance.collection(collectionPath).add(messageData);

        // Update last message for both users
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
          backgroundColor: Colors.red[700],
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
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _togglePinMessage(String messageId) async {
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
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
          backgroundColor: Colors.red[700],
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
          backgroundColor: Colors.red[700],
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
          backgroundColor: Colors.red[700],
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
        // Note: PDF parsing requires additional packages like `pdf_text`
        content = 'PDF content extraction not implemented'; // Placeholder
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
          backgroundColor: Colors.red[700],
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
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
      return text; // Fallback to original text
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, // Reverse list, so scroll to 0 for newest messages
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
              onBackgroundImageError: (_, __) => AssetImage('assets/default_avatar.png'),
            ),
            const SizedBox(width: 10),
            Text(
              widget.selectedUserName,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: Colors.teal[800],
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          DropdownButton<String>(
            value: _selectedLanguage,
            icon: Icon(Icons.translate, color: Colors.white),
            dropdownColor: Colors.teal[800],
            items: _languages.map((String lang) {
              return DropdownMenuItem<String>(
                value: lang,
                child: Text(
                  lang.toUpperCase(),
                  style: TextStyle(color: Colors.white),
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedLanguage = newValue!;
              });
            },
          ),
          SizedBox(width: 10),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFFB2DFDB), Colors.white],
          ),
        ),
        child: Column(
          children: [
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
                    .collection(
                    'chat_rooms/${_getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId)}/messages')
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
                                  ? MemoryImage(
                                  base64Decode(widget.selectedUserPhotoURL.split(',')[1]))
                                  : NetworkImage(widget.selectedUserPhotoURL)) as ImageProvider,
                              radius: 20,
                              onBackgroundImageError: (_, __) =>
                                  AssetImage('assets/default_avatar.png'),
                            ),
                            title: GestureDetector(
                              onLongPress: () => _togglePinMessage(message.id),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.teal[100]!.withOpacity(0.9)
                                      : Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  border: isPinned
                                      ? Border.all(color: Colors.yellow[700]!, width: 2)
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                                              final file =
                                              File('${directory.path}/${message['fileName']}');
                                              await file.writeAsBytes(bytes);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content:
                                                  Text('File downloaded to ${file.path}'),
                                                  backgroundColor: Colors.teal[700],
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Failed to download file: $e'),
                                                  backgroundColor: Colors.red[700],
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            }
                                          },
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.attach_file, color: Colors.teal[800]),
                                              SizedBox(width: 8),
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
                                              final file = File(
                                                  '${directory.path}/${message['voiceFileName']}');
                                              await file.writeAsBytes(bytes);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content:
                                                  Text('Voice file downloaded to ${file.path}'),
                                                  backgroundColor: Colors.teal[700],
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Failed to download voice: $e'),
                                                  backgroundColor: Colors.red[700],
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                            }
                                          },
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.mic, color: Colors.teal[800]),
                                              SizedBox(width: 8),
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
                                    ? DateFormat('hh:mm a')
                                    .format((message['timestamp'] as Timestamp).toDate())
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
                  ),
                  IconButton(
                    icon: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: _isRecording ? Colors.red[700] : Colors.teal[800],
                      size: 28,
                    ),
                    onPressed: _isRecording ? _stopRecording : _startRecording,
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
                    child: Icon(Icons.send, color: Colors.white, size: 28),
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