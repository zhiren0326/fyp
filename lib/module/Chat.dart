import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String? _selectedCustomId;
  String? _selectedUserName;
  List<DocumentSnapshot> _searchResults = [];
  String? _currentUserCustomId;

  @override
  void initState() {
    super.initState();
    _initializeUserCustomId();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // Generate a 3-letter + 3-number custom ID (e.g., ABC123)
  String _generateCustomId() {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final random = Random();
    String letterPart = List.generate(3, (_) => letters[random.nextInt(26)]).join();
    String numberPart = List.generate(3, (_) => random.nextInt(10).toString()).join();
    return '$letterPart$numberPart';
  }

  // Initialize or fetch user's custom ID
  Future<void> _initializeUserCustomId() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('custom_ids')
        .doc(currentUser.uid)
        .get();

    if (!userDoc.exists) {
      String customId;
      bool isUnique;
      do {
        customId = _generateCustomId();
        isUnique = (await FirebaseFirestore.instance
            .collection('custom_ids')
            .where('customId', isEqualTo: customId)
            .get())
            .docs
            .isEmpty;
      } while (!isUnique);

      await FirebaseFirestore.instance
          .collection('custom_ids')
          .doc(currentUser.uid)
          .set({
        'customId': customId,
        'userId': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _currentUserCustomId = customId;
      });
    } else {
      setState(() {
        _currentUserCustomId = userDoc['customId'];
      });
    }
  }

  // Search users by custom ID only
  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final idResult = await FirebaseFirestore.instance
        .collection('custom_ids')
        .where('customId', isEqualTo: query.toUpperCase())
        .get();

    final userDocs = <String, DocumentSnapshot>{};
    for (var customIdDoc in idResult.docs) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(customIdDoc['userId'])
          .get();
      if (userDoc.exists) {
        userDocs[userDoc.id] = userDoc;
      }
    }

    setState(() {
      _searchResults = userDocs.values.toList();
    });
  }

  // Create or get chat room ID for one-on-one chat
  String _getChatRoomId(String customId1, String customId2) {
    return customId1.compareTo(customId2) < 0
        ? '${customId1}_$customId2'
        : '${customId2}_$customId1';
  }

  // Send message
  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty || _selectedCustomId == null) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _currentUserCustomId == null) return;

    final collectionPath =
        'chat_rooms/${_getChatRoomId(_currentUserCustomId!, _selectedCustomId!)}/messages';

    await FirebaseFirestore.instance.collection(collectionPath).add({
      'text': _messageController.text,
      'senderCustomId': _currentUserCustomId,
      'senderName': (await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get())['profiledetails']['profile']['name'] ?? 'Unknown',
      'timestamp': FieldValue.serverTimestamp(),
    });

    _messageController.clear();
  }

  // Copy custom ID to clipboard
  void _copyCustomId() {
    if (_currentUserCustomId != null) {
      Clipboard.setData(ClipboardData(text: _currentUserCustomId!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ID $_currentUserCustomId copied to clipboard'),
          backgroundColor: Colors.teal[700],
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Share custom ID with error handling
  void _shareCustomId() async {
    if (_currentUserCustomId != null) {
      try {
        await Share.share('My Chat ID: $_currentUserCustomId');
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share ID: $e'),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            // Custom header
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 40.0, 16.0, 16.0),
              child: Column(
                children: [
                  Text(
                    _selectedUserName ?? 'Chat',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_currentUserCustomId != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Your ID: $_currentUserCustomId',
                          style: TextStyle(
                            color: Colors.teal[900],
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: Icon(Icons.copy, color: Colors.teal[700], size: 28),
                          onPressed: _copyCustomId,
                          tooltip: 'Copy ID',
                        ),
                        IconButton(
                          icon: Icon(Icons.share, color: Colors.teal[700], size: 28),
                          onPressed: _shareCustomId,
                          tooltip: 'Share ID',
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // Search bar for custom IDs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Enter user ID (e.g., ABC123)',
                  hintStyle: TextStyle(color: Colors.teal[500], fontSize: 18),
                  prefixIcon: Icon(Icons.search, color: Colors.teal[800], size: 30),
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
                onChanged: (query) {
                  _searchUsers(query);
                },
              ),
            ),
            // Search results for users
            if (_searchResults.isNotEmpty)
              Container(
                height: 140,
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final user = _searchResults[index];
                    final userName = user['profiledetails']['profile']['name'] ?? 'Unknown';
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('custom_ids').doc(user.id).get(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox.shrink();
                        final customId = snapshot.data?['customId'] ?? 'Unknown';
                        return Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          color: Colors.white.withOpacity(0.95),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            title: Text(
                              '$userName (ID: $customId)',
                              style: TextStyle(
                                color: Colors.teal[900],
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () {
                              setState(() {
                                _selectedCustomId = customId;
                                _selectedUserName = userName;
                                _searchResults = [];
                                _searchController.clear();
                              });
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            // Chat messages
            Expanded(
              child: _selectedCustomId != null
                  ? StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(
                    'chat_rooms/${_getChatRoomId(_currentUserCustomId!, _selectedCustomId!)}/messages')
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
                      final isMe = message['senderCustomId'] == _currentUserCustomId;
                      return ListTile(
                        title: BobbleHeadAnimation(
                          isMe: isMe,
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
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2, left: 20, right: 20),
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
              )
                  : Center(
                child: Text(
                  'Enter a user ID to start chatting',
                  style: TextStyle(
                    color: Colors.teal[800],
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            // Message input
            if (_selectedCustomId != null)
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

// Bobble head animation widget
class BobbleHeadAnimation extends StatefulWidget {
  final bool isMe;
  final Widget child;

  const BobbleHeadAnimation({Key? key, required this.isMe, required this.child}) : super(key: key);

  @override
  BobbleHeadAnimationState createState() => BobbleHeadAnimationState();
}

class BobbleHeadAnimationState extends State<BobbleHeadAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..forward();

    _animation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(widget.isMe ? -_animation.value : _animation.value, 0),
          child: widget.child,
        );
      },
    );
  }
}