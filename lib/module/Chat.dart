import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp/module/ChatMessage.dart';
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
  String? _currentUserCustomId;
  List<Map<String, dynamic>> _chatList = [];
  List<DocumentSnapshot> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _initializeUserCustomId();
    _loadChatList();
  }

  @override
  void dispose() {
    _searchController.dispose();
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

    try {
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to initialize user ID: $e'),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Load chat list from Firestore
  Future<void> _loadChatList() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _currentUserCustomId == null) return;

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('chats')
          .doc('chat_list')
          .get();

      if (chatDoc.exists) {
        setState(() {
          _chatList = List<Map<String, dynamic>>.from(chatDoc['users'] ?? []);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load chat list: $e'),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Add or update chat in Firestore
  Future<void> _addChat(String customId, String name, String photoURL) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _currentUserCustomId == null) return;

    try {
      final chatDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('chats')
          .doc('chat_list');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(chatDocRef);
        List<Map<String, dynamic>> updatedChatList = List<Map<String, dynamic>>.from(doc.data()?['users'] ?? []);
        final chatIndex = updatedChatList.indexWhere((chat) => chat['customId'] == customId);

        if (chatIndex == -1) {
          updatedChatList.add({'customId': customId, 'name': name, 'photoURL': photoURL});
        } else {
          updatedChatList[chatIndex] = {'customId': customId, 'name': name, 'photoURL': photoURL};
        }

        transaction.set(chatDocRef, {'users': updatedChatList}, SetOptions(merge: true));
      });

      setState(() {
        final chatIndex = _chatList.indexWhere((chat) => chat['customId'] == customId);
        if (chatIndex == -1) {
          _chatList.add({'customId': customId, 'name': name, 'photoURL': photoURL});
        } else {
          _chatList[chatIndex] = {'customId': customId, 'name': name, 'photoURL': photoURL};
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add chat: $e'),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Search users by custom ID and fetch profile details
  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    try {
      final idResult = await FirebaseFirestore.instance
          .collection('custom_ids')
          .where('customId', isEqualTo: query.toUpperCase())
          .get();

      final userDocs = <String, DocumentSnapshot>{};
      for (var customIdDoc in idResult.docs) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(customIdDoc['userId'])
            .collection('profiledetails')
            .doc('profile')
            .get();
        if (userDoc.exists) {
          userDocs[userDoc.reference.parent.parent!.id] = userDoc;
        }
      }

      setState(() {
        _searchResults = userDocs.values.toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Search failed: $e'),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
        child: SafeArea(
          child: Column(
            children: [
              // Custom header
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 16.0),
                child: Column(
                  children: [
                    const Text(
                      'Chat',
                      style: TextStyle(
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
                      final userName = user['name'] ?? 'Unknown';
                      final userPhotoURL = user['photoURL'] ?? 'assets/default_avatar.png';
                      final userGmail = user['email'] ?? '';
                      final userContact = user['phone'] ?? '';
                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('custom_ids').doc(user.reference.parent.parent!.id).get(),
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
                              leading: CircleAvatar(
                                backgroundImage: userPhotoURL.startsWith('assets/')
                                    ? AssetImage(userPhotoURL) as ImageProvider
                                    : NetworkImage(userPhotoURL),
                                radius: 20,
                                onBackgroundImageError: (_, __) => AssetImage('assets/default_avatar.png'),
                              ),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userName,
                                    style: TextStyle(
                                      color: Colors.teal[900],
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Email: $userGmail\nPhone: $userContact',
                                    style: TextStyle(
                                      color: Colors.teal[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'ID: $customId',
                                style: TextStyle(
                                  color: Colors.teal[800],
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () {
                                _addChat(customId, userName, userPhotoURL);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatMessage(
                                      currentUserCustomId: _currentUserCustomId!,
                                      selectedCustomId: customId,
                                      selectedUserName: userName,
                                      selectedUserPhotoURL: userPhotoURL,
                                    ),
                                  ),
                                ).then((_) => _loadChatList()); // Reload chat list on return
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              // Persistent chat list
              Expanded(
                child: ListView.builder(
                  itemCount: _chatList.length,
                  itemBuilder: (context, index) {
                    final chat = _chatList[index];
                    return Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: Colors.white.withOpacity(0.95),
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: chat['photoURL'].startsWith('assets/')
                              ? AssetImage(chat['photoURL']) as ImageProvider
                              : NetworkImage(chat['photoURL']),
                          radius: 20,
                          onBackgroundImageError: (_, __) => AssetImage('assets/default_avatar.png'),
                        ),
                        title: Text(
                          chat['name'],
                          style: TextStyle(
                            color: Colors.teal[900],
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatMessage(
                                currentUserCustomId: _currentUserCustomId!,
                                selectedCustomId: chat['customId'],
                                selectedUserName: chat['name'],
                                selectedUserPhotoURL: chat['photoURL'],
                              ),
                            ),
                          ).then((_) => _loadChatList()); // Reload chat list on return
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}