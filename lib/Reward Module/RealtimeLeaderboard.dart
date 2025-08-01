import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RealtimeLeaderboard extends StatefulWidget {
  const RealtimeLeaderboard({super.key});

  @override
  State<RealtimeLeaderboard> createState() => _RealtimeLeaderboardState();
}

class _RealtimeLeaderboardState extends State<RealtimeLeaderboard> {
  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    print('Current user: ${user?.uid}, Email: ${user?.email}');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB2DFDB), Colors.white],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            'Leaderboard',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collectionGroup('profiledetails')
              .where('points', isGreaterThan: 0)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              print('StreamBuilder error: ${snapshot.error}');
              return Center(
                child: Text(
                  'Error loading leaderboard: ${snapshot.error}',
                  style: GoogleFonts.poppins(color: Colors.red),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              print('No profiles with points found');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.leaderboard_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No users with points yet.',
                      style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              );
            }

            final leaderboard = _processProfiles(snapshot.data!.docs);
            print('Leaderboard processed: ${leaderboard.length} users with points');

            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: leaderboard.length,
              itemBuilder: (context, index) {
                final user = leaderboard[index];
                final isCurrentUser = user['userId'] == FirebaseAuth.instance.currentUser?.uid;
                return _buildLeaderboardCard(user, index, isCurrentUser);
              },
            );
          },
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _processProfiles(List<QueryDocumentSnapshot> profileDocs) {
    List<Map<String, dynamic>> leaderboard = [];
    print('Processing ${profileDocs.length} profile documents');

    for (var profileDoc in profileDocs) {
      try {
        final profileData = profileDoc.data() as Map<String, dynamic>;
        final userId = profileDoc.reference.parent.parent!.id;
        print('Checking profile for user: $userId, Data: $profileData');

        final pointsRaw = profileData['points'];
        int points = 0;
        if (pointsRaw is num) {
          points = pointsRaw.toInt();
        } else if (pointsRaw is String) {
          points = int.tryParse(pointsRaw) ?? 0;
        } else {
          print('Invalid points format for user $userId: $pointsRaw');
          continue;
        }

        if (points > 0) {
          leaderboard.add({
            'userId': userId,
            'name': profileData['name']?.toString() ?? 'Unknown User',
            'photoURL': profileData['photoURL']?.toString() ?? '',
            'points': points,
          });
          print('Added user to leaderboard: $userId, Points: $points, Name: ${profileData['name']}');
        } else {
          print('User $userId has no points or points <= 0: $pointsRaw');
        }
      } catch (e, stackTrace) {
        print('Error processing profile for user: ${profileDoc.reference.parent.parent!.id}, Error: $e');
        print('Stack trace: $stackTrace');
      }
    }

    leaderboard.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
    return leaderboard;
  }

  Widget _buildLeaderboardCard(Map<String, dynamic> user, int index, bool isCurrentUser) {
    Color rankColor = Colors.grey;
    IconData rankIcon = Icons.emoji_events;

    if (index == 0) {
      rankColor = Colors.amber;
    } else if (index == 1) {
      rankColor = Colors.grey[400]!;
    } else if (index == 2) {
      rankColor = Colors.brown;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: isCurrentUser ? const Color(0xFF006D77).withOpacity(0.1) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Stack(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: user['photoURL'].isNotEmpty
                      ? _getImageProvider(user['photoURL'])
                      : null,
                  backgroundColor: Colors.grey[200],
                  child: user['photoURL'].isEmpty
                      ? const Icon(Icons.person, size: 30, color: Colors.grey)
                      : null,
                ),
                if (index < 3)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: rankColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        rankIcon,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['name'].length > 15
                        ? '${user['name'].substring(0, 15)}...'
                        : user['name'],
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isCurrentUser ? const Color(0xFF006D77) : Colors.black,
                    ),
                  ),
                  Text(
                    '${user['points']} points',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
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

  ImageProvider _getImageProvider(String photoURL) {
    if (photoURL.startsWith('assets/')) {
      return AssetImage(photoURL);
    } else if (photoURL.startsWith('http')) {
      return NetworkImage(photoURL);
    }
    return const AssetImage('assets/default_avatar.png');
  }
}