import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp/module/VoiceTranslationScreen.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';

import 'translation_service.dart';
import 'file_service.dart';

class MessageBubble extends StatelessWidget {
  final DocumentSnapshot message;
  final bool isMe;
  final bool isGroup;
  final bool isRealTimeTranslationEnabled;
  final bool showOriginalText;
  final String selectedLanguage;
  final Map<String, String> languageNames;
  final TranslationService translationService;
  final FileService fileService;
  final String selectedUserPhotoURL;
  final String? groupId; // Add groupId parameter
  final bool isGroupOwner; // Add isGroupOwner parameter
  final String currentUserCustomId; // Add current user custom ID

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isMe,
    required this.isGroup,
    required this.isRealTimeTranslationEnabled,
    required this.showOriginalText,
    required this.selectedLanguage,
    required this.languageNames,
    required this.translationService,
    required this.fileService,
    required this.selectedUserPhotoURL,
    this.groupId, // Add groupId parameter
    this.isGroupOwner = false, // Add isGroupOwner parameter
    required this.currentUserCustomId, // Add current user custom ID
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final messageData = message.data() as Map<String, dynamic>;
    final isPinned = messageData['isPinned'] ?? false;

    // Debug print for this specific message
    print('MessageBubble - isPinned: $isPinned, isGroup: $isGroup, isGroupOwner: $isGroupOwner, groupId: $groupId');

    return FutureBuilder<String>(
      future: isRealTimeTranslationEnabled && messageData['text'] != null
          ? translationService.translateText(messageData['text'], selectedLanguage)
          : Future.value(messageData['text'] ?? ''),
      builder: (context, translationSnapshot) {
        final translatedText = translationSnapshot.data ?? messageData['text'] ?? '';

        return GestureDetector(
          onLongPress: () {
            _showMessageOptions(context, message.id, messageData, isMe);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Column(
              children: [
                // Show pinned message indicator at the top
                if (isPinned)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber[300]!, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.push_pin,
                          size: 16,
                          color: Colors.amber[700],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Pinned Message',
                          style: TextStyle(
                            color: Colors.amber[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Message content
                Row(
                  mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!isMe) ...[
                      CircleAvatar(
                        radius: 16,
                        backgroundImage: NetworkImage(selectedUserPhotoURL),
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
                            if (isGroup && !isMe)
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
                            _buildMessageContent(context, messageData, translatedText),

                            // Timestamp and pin indicator
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
                                      : 'Sending...',
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
                        backgroundImage: NetworkImage(selectedUserPhotoURL),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageContent(BuildContext context, Map<String, dynamic> messageData, String translatedText) {
    switch (messageData['type']) {
      case 'text':
        return _buildTextMessage(messageData, translatedText);
      case 'image':
        return _buildImageMessage(context, messageData);
      case 'file':
        return _buildFileMessage(context, messageData);
      case 'voice':
        return _buildVoiceMessage(context, messageData);
      default:
        return _buildTextMessage(messageData, translatedText);
    }
  }

  Widget _buildTextMessage(Map<String, dynamic> messageData, String translatedText) {
    if (translatedText.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showOriginalText &&
            isRealTimeTranslationEnabled &&
            messageData['text'] != translatedText) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Original:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  messageData['text'],
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        SelectableText(
          translatedText,
          style: const TextStyle(fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildImageMessage(BuildContext context, Map<String, dynamic> messageData) {
    return GestureDetector(
      onTap: () => _showFullImage(context, messageData['imageBase64']),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 250,
          maxHeight: 250,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            base64Decode(messageData['imageBase64']),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.grey),
                      Text('Image not available', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFileMessage(BuildContext context, Map<String, dynamic> messageData) {
    final fileName = messageData['fileName'] ?? 'File';
    final fileBase64 = messageData['fileBase64'] ?? '';
    final fileSize = fileBase64.isNotEmpty
        ? fileService.getFileSizeString(base64Decode(fileBase64).length)
        : 'Unknown size';
    final extension = fileName.split('.').last.toLowerCase();
    final fileIcon = fileService.getFileIcon(extension);

    return InkWell(
      onTap: () => _downloadAndOpenFile(context, messageData),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                fileIcon,
                style: const TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fileSize,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.download,
              color: Colors.teal[600],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceMessage(BuildContext context, Map<String, dynamic> messageData) {
    return InkWell(
      onTap: () => _showVoiceMessageDialog(context, messageData),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow,
                color: Colors.blue[700],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Message',
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Tap to play',
                  style: TextStyle(
                    color: Colors.blue[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.volume_up,
              color: Colors.blue[600],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageOptions(BuildContext context, String messageId, Map<String, dynamic> messageData, bool isMe) {
    // Add debug print
    print('ShowMessageOptions - isGroup: $isGroup, isGroupOwner: $isGroupOwner, groupId: $groupId');

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Debug info tile (remove this after fixing)
            if (isGroup)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey[100],
                child: Row(
                  children: [
                    const Icon(Icons.info, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Debug: Group=$isGroup, Owner=$isGroupOwner, GroupId=${groupId ?? "null"}',
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),

            if (messageData['type'] == 'text') ...[
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.blue),
                title: const Text('Copy Text'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: messageData['text']));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Text copied to clipboard'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.translate, color: Colors.teal),
                title: const Text('Translate Message'),
                onTap: () {
                  Navigator.pop(context);
                  _translateMessage(context, messageData['text']);
                },
              ),
              ListTile(
                leading: const Icon(Icons.translate_outlined, color: Colors.blue),
                title: const Text('Translate All Messages'),
                onTap: () {
                  Navigator.pop(context);
                  _translateAllMessages(context);
                },
              ),

            ],
            if (messageData['type'] == 'voice')
              ListTile(
                leading: const Icon(Icons.translate, color: Colors.purple),
                title: const Text('Translate Voice (Manual)'),
                onTap: () {
                  Navigator.pop(context);
                  _showSimpleVoiceTranslation(context);
                },
              ),


            if (messageData['type'] == 'file' && fileService.isTranslationSupported(
                (messageData['fileName'] as String).split('.').last))
              ListTile(
                leading: const Icon(Icons.translate, color: Colors.orange),
                title: const Text('Translate Document'),
                onTap: () {
                  Navigator.pop(context);
                  _translateFileMessage(context, messageData);
                },
              ),

            // Pin message option - Show for all group members but only functional for owners
            if (isGroup && groupId != null)
              ListTile(
                leading: Icon(
                  messageData['isPinned'] ?? false ? Icons.push_pin_outlined : Icons.push_pin,
                  color: isGroupOwner ? Colors.amber : Colors.grey,
                ),
                title: Text(
                  messageData['isPinned'] ?? false ? 'Unpin Message' : 'Pin Message',
                  style: TextStyle(
                    color: isGroupOwner ? Colors.black : Colors.grey,
                  ),
                ),
                subtitle: isGroupOwner ? null : const Text(
                  'Only group owners can pin messages',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: isGroupOwner ? () {
                  Navigator.pop(context);
                  _togglePinMessage(context, messageId, messageData);
                } : () {
                  // Show a message that only owners can pin
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Only group owners can pin messages'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                },
              ),

            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Message', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(context, messageId);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _translateAllMessages(BuildContext context) async {
    try {
      // Show confirmation dialog first
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.translate, color: Colors.blue),
              SizedBox(width: 8),
              Text('Translate All Messages'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This will translate all text messages in this conversation to ${languageNames[selectedLanguage]}.'),
              SizedBox(height: 12),
              Text(
                'Note: Only text messages will be translated. Voice, image, and file messages will be skipped.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Translate All'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _performBulkTranslation(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting translation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _performBulkTranslation(BuildContext context) async {
    List<Map<String, dynamic>> translatedMessages = [];
    int totalMessages = 0;
    int processedMessages = 0;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Translating Messages...'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (totalMessages > 0) ...[
                LinearProgressIndicator(
                  value: processedMessages / totalMessages,
                ),
                SizedBox(height: 8),
                Text('$processedMessages of $totalMessages messages translated'),
              ] else
                Text('Fetching messages...'),
            ],
          ),
        ),
      ),
    );

    try {
      // Fetch all messages from the conversation
      QuerySnapshot messageSnapshot;

      if (isGroup && groupId != null) {
        // For group chats
        messageSnapshot = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId!)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(100) // Limit to last 100 messages
            .get();
      } else {
        // For private chats - you'll need to modify this based on your chat structure
        // This assumes you have a way to identify the chat/conversation
        messageSnapshot = await FirebaseFirestore.instance
            .collection('messages')
            .where('participants', arrayContains: currentUserCustomId)
            .orderBy('timestamp', descending: true)
            .limit(100)
            .get();
      }

      // Filter only text messages
      List<QueryDocumentSnapshot> textMessages = messageSnapshot.docs
          .where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['type'] == 'text' &&
            data['text'] != null &&
            (data['text'] as String).trim().isNotEmpty;
      })
          .toList();

      totalMessages = textMessages.length;

      if (totalMessages == 0) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No text messages found to translate'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Update progress dialog with total count
      // Process messages in batches to avoid overwhelming the translation service
      const batchSize = 5;

      for (int i = 0; i < textMessages.length; i += batchSize) {
        final batch = textMessages.skip(i).take(batchSize).toList();
        final batchTranslations = await Future.wait(
          batch.map((doc) async {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final originalText = data['text'] as String;

              final translation = await translationService.translateText(
                originalText,
                selectedLanguage,
              );

              return {
                'messageId': doc.id,
                'senderName': data['senderName'] ?? 'Unknown',
                'originalText': originalText,
                'translatedText': translation,
                'timestamp': data['timestamp'],
                'isMe': data['senderCustomId'] == currentUserCustomId,
              };
            } catch (e) {
              print('Error translating message ${doc.id}: $e');
              return null;
            }
          }),
        );

        // Add successful translations
        translatedMessages.addAll(
          batchTranslations.where((translation) => translation != null).cast<Map<String, dynamic>>(),
        );

        processedMessages += batch.length;

        // Small delay to prevent rate limiting
        await Future.delayed(Duration(milliseconds: 500));
      }

      // Close progress dialog
      Navigator.pop(context);

      // Show results
      _showTranslationResults(context, translatedMessages);

    } catch (e) {
      Navigator.pop(context); // Close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Translation failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showTranslationResults(BuildContext context, List<Map<String, dynamic>> translatedMessages) {
    if (translatedMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No messages could be translated'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.translate, color: Colors.blue[700]),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'All Messages Translated',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                              ),
                            ),
                            Text(
                              '${translatedMessages.length} messages translated to ${languageNames[selectedLanguage]}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _exportTranslations(context, translatedMessages),
                          icon: Icon(Icons.download, size: 16),
                          label: Text('Export'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _copyAllTranslations(context, translatedMessages),
                          icon: Icon(Icons.copy, size: 16),
                          label: Text('Copy All'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Message list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: EdgeInsets.all(16),
                itemCount: translatedMessages.length,
                itemBuilder: (context, index) {
                  final translation = translatedMessages[index];
                  final isMe = translation['isMe'] as bool;

                  return Card(
                    margin: EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with sender and time
                          Row(
                            children: [
                              Icon(
                                isMe ? Icons.person : Icons.person_outline,
                                size: 16,
                                color: isMe ? Colors.teal : Colors.blue,
                              ),
                              SizedBox(width: 4),
                              Text(
                                translation['senderName'],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isMe ? Colors.teal[800] : Colors.blue[800],
                                  fontSize: 12,
                                ),
                              ),
                              Spacer(),
                              if (translation['timestamp'] != null)
                                Text(
                                  DateFormat('MMM dd, HH:mm').format(
                                    (translation['timestamp'] as Timestamp).toDate(),
                                  ),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              IconButton(
                                onPressed: () => _copyMessage(context, translation),
                                icon: Icon(Icons.copy, size: 16),
                                padding: EdgeInsets.all(4),
                                constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                              ),
                            ],
                          ),

                          Divider(height: 16),

                          // Original text
                          if (showOriginalText) ...[
                            Text(
                              'Original:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: 4),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                translation['originalText'],
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                          ],

                          // Translated text
                          Text(
                            'Translation (${languageNames[selectedLanguage]}):',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                          SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: SelectableText(
                              translation['translatedText'],
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyMessage(BuildContext context, Map<String, dynamic> translation) {
    final text = showOriginalText
        ? 'Original: ${translation['originalText']}\n\nTranslation: ${translation['translatedText']}'
        : translation['translatedText'];

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Message copied to clipboard'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _copyAllTranslations(BuildContext context, List<Map<String, dynamic>> translations) {
    final buffer = StringBuffer();
    buffer.writeln('Translated Messages (${languageNames[selectedLanguage]})');
    buffer.writeln('Generated on ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    buffer.writeln('${'=' * 50}\n');

    for (int i = 0; i < translations.length; i++) {
      final translation = translations[i];
      buffer.writeln('Message ${i + 1}:');
      buffer.writeln('Sender: ${translation['senderName']}');

      if (translation['timestamp'] != null) {
        buffer.writeln('Time: ${DateFormat('yyyy-MM-dd HH:mm').format(
            (translation['timestamp'] as Timestamp).toDate()
        )}');
      }

      if (showOriginalText) {
        buffer.writeln('Original: ${translation['originalText']}');
      }
      buffer.writeln('Translation: ${translation['translatedText']}');
      buffer.writeln('-' * 30);
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('All translations copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _exportTranslations(BuildContext context, List<Map<String, dynamic>> translations) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'translations_$timestamp.txt';
      final file = File('${directory.path}/$fileName');

      final buffer = StringBuffer();
      buffer.writeln('Translated Messages Report');
      buffer.writeln('Target Language: ${languageNames[selectedLanguage]}');
      buffer.writeln('Generated on: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
      buffer.writeln('Total Messages: ${translations.length}');
      buffer.writeln('${'=' * 60}\n');

      for (int i = 0; i < translations.length; i++) {
        final translation = translations[i];
        buffer.writeln('MESSAGE ${i + 1}');
        buffer.writeln('Sender: ${translation['senderName']}');

        if (translation['timestamp'] != null) {
          buffer.writeln('Timestamp: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(
              (translation['timestamp'] as Timestamp).toDate()
          )}');
        }

        buffer.writeln('\nOriginal Text:');
        buffer.writeln(translation['originalText']);

        buffer.writeln('\nTranslated Text (${languageNames[selectedLanguage]}):');
        buffer.writeln(translation['translatedText']);

        buffer.writeln('\n${'─' * 60}\n');
      }

      await file.writeAsString(buffer.toString());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Translations exported to: $fileName'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Open',
            onPressed: () async {
              await OpenFile.open(file.path);
            },
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSimpleVoiceTranslation(BuildContext context) {
    String inputText = '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Voice Message Translation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Please type what you heard in the voice message:'),
            SizedBox(height: 12),
            TextField(
              onChanged: (value) => inputText = value,
              decoration: InputDecoration(
                hintText: 'Enter the voice message text...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (inputText.isNotEmpty) {
                await _translateMessage(context, inputText);
              }
            },
            child: Text('Translate'),
          ),
        ],
      ),
    );
  }

  // Updated pin/unpin message function for groups
  Future<void> _togglePinMessage(BuildContext context, String messageId, Map<String, dynamic> messageData) async {
    if (!isGroup || groupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pin functionality is only available in groups'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!isGroupOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only group owners can pin messages'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final isPinned = messageData['isPinned'] ?? false;
      print('Toggling pin for message $messageId. Currently pinned: $isPinned');

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Update the message in the group's messages collection
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId!)
          .collection('messages')
          .doc(messageId)
          .update({
        'isPinned': !isPinned,
        'pinnedAt': !isPinned ? FieldValue.serverTimestamp() : FieldValue.delete(),
        'pinnedBy': !isPinned ? currentUserCustomId : FieldValue.delete(),
      });

      // If pinning, also add to group's pinned messages collection for quick access
      if (!isPinned) {
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId!)
            .collection('pinned_messages')
            .doc(messageId)
            .set({
          'messageId': messageId,
          'text': messageData['text'] ?? '',
          'senderName': messageData['senderName'] ?? 'Unknown',
          'senderCustomId': messageData['senderCustomId'] ?? '',
          'messageType': messageData['type'] ?? 'text',
          'pinnedAt': FieldValue.serverTimestamp(),
          'pinnedBy': currentUserCustomId,
          'originalTimestamp': messageData['timestamp'],
          if (messageData['type'] == 'image') 'imageBase64': messageData['imageBase64'],
          if (messageData['type'] == 'file') ...{
            'fileName': messageData['fileName'],
            'fileBase64': messageData['fileBase64'],
          },
          if (messageData['type'] == 'voice') ...{
            'voiceFileName': messageData['voiceFileName'],
            'voiceBase64': messageData['voiceBase64'],
          },
        });
      } else {
        // If unpinning, remove from pinned messages collection
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId!)
            .collection('pinned_messages')
            .doc(messageId)
            .delete();
      }

      // Dismiss loading indicator
      Navigator.pop(context);

      print('Pin toggle successful. New state: ${!isPinned}');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isPinned ? 'Message unpinned' : 'Message pinned'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'View Pinned',
            textColor: Colors.white,
            onPressed: () {
              _showPinnedMessages(context);
            },
          ),
        ),
      );
    } catch (e) {
      // Dismiss loading indicator if still showing
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      print('Error toggling pin: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to ${messageData['isPinned'] ?? false ? 'unpin' : 'pin'} message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Show all pinned messages in the group
  void _showPinnedMessages(BuildContext context) {
    if (!isGroup || groupId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.push_pin, color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Pinned Messages',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber[700],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('groups')
                    .doc(groupId!)
                    .collection('pinned_messages')
                    .orderBy('pinnedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.push_pin_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No pinned messages',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final pinnedMessage = snapshot.data!.docs[index];
                      final data = pinnedMessage.data() as Map<String, dynamic>;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    data['senderName'] ?? 'Unknown',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal[800],
                                    ),
                                  ),
                                  const Spacer(),
                                  if (isGroupOwner)
                                    IconButton(
                                      onPressed: () async {
                                        // Unpin this message
                                        try {
                                          await FirebaseFirestore.instance
                                              .collection('groups')
                                              .doc(groupId!)
                                              .collection('messages')
                                              .doc(data['messageId'])
                                              .update({'isPinned': false});

                                          await FirebaseFirestore.instance
                                              .collection('groups')
                                              .doc(groupId!)
                                              .collection('pinned_messages')
                                              .doc(data['messageId'])
                                              .delete();

                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Message unpinned'),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Failed to unpin: $e'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      },
                                      icon: Icon(
                                        Icons.push_pin_outlined,
                                        color: Colors.amber[700],
                                        size: 20,
                                      ),
                                      tooltip: 'Unpin message',
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                data['text'] ?? 'Media message',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Pinned ${data['pinnedAt'] != null
                                    ? DateFormat('MMM dd, yyyy HH:mm').format(
                                    (data['pinnedAt'] as Timestamp).toDate())
                                    : 'recently'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Rest of the existing methods remain the same...
  void _showFullImage(BuildContext context, String base64Image) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: () => _saveImage(context, base64Image),
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                onPressed: () => _shareImage(context, base64Image),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.memory(
                base64Decode(base64Image),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showVoiceMessageDialog(BuildContext context, Map<String, dynamic> messageData) {
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.play_circle_filled,
                size: 60,
                color: Colors.blue[700],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Voice message playback'),
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
              _playVoiceMessage(context, messageData);
            },
            child: const Text('Play'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _translateVoiceMessage(context, messageData);
            },
            child: const Text('Translate'),
          ),
        ],
      ),
    );
  }

  Future<void> _translateMessage(BuildContext context, String text) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final translation = await translationService.translateWithOriginal(text, selectedLanguage);
      Navigator.pop(context);

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
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showOriginalText) ...[
                  Text(
                    'Original:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(translation['original']!),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Translation (${languageNames[selectedLanguage]}):',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.teal[200]!),
                  ),
                  child: SelectableText(translation['translation']!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: translation['translation']!));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Translation copied to clipboard'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Copy'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Translation failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _translateVoiceMessage(BuildContext context, Map<String, dynamic> messageData) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Save voice to temporary file
      final tempDir = await getTemporaryDirectory();
      final voiceFile = File('${tempDir.path}/${messageData['voiceFileName']}');
      await voiceFile.writeAsBytes(base64Decode(messageData['voiceBase64']));

      final result = await fileService.translateVoiceMessage(
        voiceFile.path,
        selectedLanguage,
        languageNames[selectedLanguage] ?? selectedLanguage,
      );

      Navigator.pop(context);

      if (result != null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.mic, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text('Voice Translation'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showOriginalText && result['original'] != null) ...[
                  Text(
                    'Original Transcription:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(result['original']!),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Translation (${languageNames[selectedLanguage]}):',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: SelectableText(result['translation']!),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: result['translation']!));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Translation copied to clipboard'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                child: const Text('Copy'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice translation failed'),
            backgroundColor: Colors.red,
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

  Future<void> _translateFileMessage(BuildContext context, Map<String, dynamic> messageData) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Create temporary file
      final tempDir = await getTemporaryDirectory();
      final fileName = messageData['fileName'] as String;
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(base64Decode(messageData['fileBase64']));

      // Create PlatformFile for translation
      final platformFile = PlatformFile(
        name: fileName,
        size: tempFile.lengthSync(),
        path: tempFile.path,
      );

      final translatedPdf = await fileService.translateDocument(
        platformFile,
        selectedLanguage,
        languageNames[selectedLanguage] ?? selectedLanguage,
      );

      Navigator.pop(context);

      if (translatedPdf != null) {
        // Show options to view or save
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Document Translated'),
            content: const Text('Your document has been translated successfully.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await OpenFile.open(translatedPdf.path);
                },
                child: const Text('View PDF'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final documentsDir = await getApplicationDocumentsDirectory();
                  final savedFile = await translatedPdf.copy(
                    '${documentsDir.path}/translated_${DateTime.now().millisecondsSinceEpoch}.pdf',
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Saved to: ${savedFile.path}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      }
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

  Future<void> _downloadAndOpenFile(BuildContext context, Map<String, dynamic> messageData) async {
    try {
      final fileName = messageData['fileName'] as String;
      final fileBase64 = messageData['fileBase64'] as String;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final documentsDir = await getApplicationDocumentsDirectory();
      final file = await fileService.saveFile(
        fileBase64,
        fileName,
        documentsDir.path,
      );

      Navigator.pop(context);

      final result = await OpenFile.open(file.path);

      if (result.type == ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File saved to: ${file.path}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open file: ${result.message}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _playVoiceMessage(BuildContext context, Map<String, dynamic> messageData) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final voiceFile = File('${tempDir.path}/${messageData['voiceFileName']}');
      await voiceFile.writeAsBytes(base64Decode(messageData['voiceBase64']));

      final result = await OpenFile.open(voiceFile.path);

      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not play voice message: ${result.message}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to play voice message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveImage(BuildContext context, String base64Image) async {
    try {
      final bytes = base64Decode(base64Image);
      final documentsDir = await getApplicationDocumentsDirectory();
      final file = File('${documentsDir.path}/image_${DateTime.now().millisecondsSinceEpoch}.png');
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

  Future<void> _shareImage(BuildContext context, String base64Image) async {
    try {
      final bytes = base64Decode(base64Image);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/shared_image_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      // You would use a share plugin here
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Share functionality would be implemented here'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteMessage(BuildContext context, String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (isGroup && groupId != null) {
          // Delete from group messages
          await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId!)
              .collection('messages')
              .doc(messageId)
              .delete();
        } else {
          // Delete from private messages
          await FirebaseFirestore.instance
              .collection('messages')
              .doc(messageId)
              .delete();
        }

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
  }
}