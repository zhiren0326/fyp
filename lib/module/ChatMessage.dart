import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:translator/translator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

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
  final GoogleTranslator _translator = GoogleTranslator();
  final stt.SpeechToText _speech = stt.SpeechToText();
  static const String _geminiApiKey = 'AIzaSyCFdlu9A8pY0FaZEMVaZ7eL-D9XcveMufo';
  String _selectedLanguage = 'en'; // Default language
  final List<String> _languages = [
    'en', 'es', 'fr', 'de', 'it', 'ja', 'ko', 'zh-cn', 'ru', 'ar'
  ]; // Supported languages
  bool _isListening = false;
  String _recognizedText = '';

  @override
  void initState() {
    super.initState();
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          setState(() => _isListening = status == 'listening');
          if (status == 'done') {
            _speech.stop();
          }
        },
        onError: (error) {
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Speech recognition error: ${error.errorMsg}'),
              backgroundColor: Colors.red[700],
              duration: const Duration(seconds: 3),
            ),
          );
        },
      );
      if (!available) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Speech recognition not available. Please check microphone permissions.'),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to initialize speech recognition: $e'),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _getChatRoomId(String customId1, String customId2) {
    return customId1.compareTo(customId2) < 0
        ? '${customId1}_$customId2'
        : '${customId2}_$customId1';
  }

  Future<void> _sendMessage({PlatformFile? file, String? text}) async {
    String messageText = text ?? _messageController.text;
    if (messageText.isEmpty && file == null) return;

    try {
      final chatRoomId = _getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId);
      final collectionPath = 'chat_rooms/$chatRoomId/messages';

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
      if (file != null) {
        final fileBytes = await File(file.path!).readAsBytes();
        fileBase64 = base64Encode(fileBytes);
        fileName = file.name;
      }

      final messageData = {
        'text': messageText,
        'senderCustomId': widget.currentUserCustomId,
        'senderName': currentUserDoc['name'] ?? 'Unknown',
        'timestamp': FieldValue.serverTimestamp(),
        'fileBase64': fileBase64,
        'fileName': fileName,
        'originalLanguage': 'en',
      };

      await FirebaseFirestore.instance.collection(collectionPath).add(messageData);
      _messageController.clear();
      setState(() => _recognizedText = '');
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
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        await _sendMessage(file: result.files.first);
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

  Future<void> _startListening() async {
    if (!_isListening) {
      try {
        bool available = await _speech.isAvailable;
        if (!available) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Microphone not available. Please check permissions.'),
              backgroundColor: Colors.red[700],
              duration: const Duration(seconds: 3),
            ),
          );
          return;
        }

        await _speech.listen(
          onResult: (result) async {
            setState(() {
              _recognizedText = result.recognizedWords;
              _messageController.text = _recognizedText;
            });
            if (result.finalResult && _recognizedText.isNotEmpty) {
              await Future.delayed(Duration(milliseconds: 500)); // Ensure stability
              final translatedText = await _translateMessage(_recognizedText, _selectedLanguage);
              await _sendMessage(text: translatedText);
              await _speech.stop();
            }
          },
          localeId: _selectedLanguage, // Use selected language for speech recognition
          cancelOnError: true,
          partialResults: true,
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start speech recognition: $e'),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() => _isListening = false);
      }
    } else {
      await _speech.stop();
      setState(() => _isListening = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectedUserName),
        backgroundColor: Colors.teal[800],
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
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
                stream: FirebaseFirestore.instance
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

                  return ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message['senderCustomId'] == widget.currentUserCustomId;

                      return FutureBuilder<String>(
                        future: _translateMessage(message['text'] ?? '', _selectedLanguage),
                        builder: (context, snapshot) {
                          final translatedText = snapshot.data ?? message['text'] ?? '';
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: widget.selectedUserPhotoURL.startsWith('assets/')
                                  ? AssetImage(widget.selectedUserPhotoURL) as ImageProvider
                                  : NetworkImage(widget.selectedUserPhotoURL),
                              radius: 20,
                              onBackgroundImageError: (_, __) =>
                                  AssetImage('assets/default_avatar.png'),
                            ),
                            title: Container(
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
                                          // Decode and save the file locally for viewing
                                          try {
                                            final bytes = base64Decode(message['fileBase64']);
                                            final directory = await getTemporaryDirectory();
                                            final file = File('${directory.path}/${message['fileName']}');
                                            await file.writeAsBytes(bytes);
                                            // Use a package like open_file to open the file
                                            // For now, show a snackbar
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
                                ],
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6, left: 20, right: 20),
                              child: Text(
                                message['timestamp'] != null
                                    ? DateFormat('hh:mm a')
                                    .format((message['timestamp'] as Timestamp).toDate())
                                    : '',
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
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: Colors.teal[800],
                      size: 28,
                    ),
                    onPressed: _startListening,
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
                    onPressed: _sendMessage,
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