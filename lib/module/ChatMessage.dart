import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  // Create or get chat room ID for one-on-one chat
  String _getChatRoomId(String customId1, String customId2) {
    return customId1.compareTo(customId2) < 0
        ? '${customId1}_$customId2'
        : '${customId2}_$customId1';
  }

  // Send message and save for both users
  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty) return;

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

      final messageData = {
        'text': _messageController.text,
        'senderCustomId': widget.currentUserCustomId,
        'senderName': currentUserDoc['name'] ?? 'Unknown',
        'timestamp': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection(collectionPath).add(messageData);
      _messageController.clear();
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

  @override
  void dispose() {
    _messageController.dispose();
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
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: widget.selectedUserPhotoURL.startsWith('assets/')
                              ? AssetImage(widget.selectedUserPhotoURL) as ImageProvider
                              : NetworkImage(widget.selectedUserPhotoURL),
                          radius: 20,
                          onBackgroundImageError: (_, __) => AssetImage('assets/default_avatar.png'),
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
                              Text(
                                message['text'],
                                style: TextStyle(
                                  color: Colors.teal[900],
                                  fontSize: 18,
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Row(
                children: [
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