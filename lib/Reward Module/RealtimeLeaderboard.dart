import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

class RealtimeLeaderboard extends StatefulWidget {
  const RealtimeLeaderboard({super.key});

  @override
  State<RealtimeLeaderboard> createState() => _RealtimeLeaderboardState();
}

class _RealtimeLeaderboardState extends State<RealtimeLeaderboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildLeaderboardStream(String period) {
    DateTime cutoffDate;
    switch (period) {
      case 'weekly':
        cutoffDate = DateTime.now().subtract(const Duration(days: 7));
        break;
      case 'monthly':
        cutoffDate = DateTime.now().subtract(const Duration(days: 30));
        break;
      default: // all-time
        cutoffDate = DateTime(2020); // Far in the past for all-time
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .snapshots(),
      builder: (context, usersSnapshot) {
        if (usersSnapshot.hasError) {
          return Center(
            child: Text(
              'Error loading leaderboard',
              style: GoogleFonts.poppins(color: Colors.red),
            ),
          );
        }

        if (usersSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _buildLeaderboardData(usersSnapshot.data!.docs, period, cutoffDate),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.leaderboard,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No data available',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              );
            }

            final leaderboardData = snapshot.data!;
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: leaderboardData.length,
              itemBuilder: (context, index) {
                return _buildLeaderboardItem(leaderboardData[index], index);
              },
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _buildLeaderboardData(
      List<QueryDocumentSnapshot> userDocs, String period, DateTime cutoffDate) async {
    List<Map<String, dynamic>> leaderboardData = [];

    for (var userDoc in userDocs) {
      try {
        // Get user profile
        final profileDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userDoc.id)
            .collection('profiledetails')
            .doc('profile')
            .get();

        if (!profileDoc.exists) continue;

        final profileData = profileDoc.data()!;

        // Calculate points based on period
        int points = 0;
        int completedJobs = 0;

        if (period == 'all-time') {
          points = (profileData['points'] ?? 0) as int;
        } else {
          // Get points from history within the period
          final pointsHistorySnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(userDoc.id)
              .collection('pointsHistory')
              .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoffDate))
              .where('points', isGreaterThan: 0) // Only positive points (earned, not spent)
              .get();

          for (var doc in pointsHistorySnapshot.docs) {
            points += (doc.data()['points'] ?? 0) as int;
          }
        }

        // Get completed jobs count
        final jobsSnapshot = await FirebaseFirestore.instance
            .collection('jobs')
            .where('acceptedApplicants', arrayContains: userDoc.id)
            .where('isCompleted', isEqualTo: true)
            .get();

        if (period != 'all-time') {
          completedJobs = jobsSnapshot.docs.where((doc) {
            final completedAt = doc.data()['completedAt'] as Timestamp?;
            return completedAt != null && completedAt.toDate().isAfter(cutoffDate);
          }).length;
        } else {
          completedJobs = jobsSnapshot.docs.length;
        }

        if (points > 0 || completedJobs > 0) {
          leaderboardData.add({
            'userId': userDoc.id,
            'name': profileData['name'] ?? 'Unknown User',
            'photoURL': profileData['photoURL'] ?? '',
            'points': points,
            'completedJobs': completedJobs,
            'isCurrentUser': userDoc.id == _currentUserId,
          });
        }
      } catch (e) {
        print('Error processing user ${userDoc.id}: $e');
      }
    }

    // Sort by points (descending)
    leaderboardData.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));

    return leaderboardData;
  }

  Widget _buildLeaderboardItem(Map<String, dynamic> userData, int index) {
    final isCurrentUser = userData['isCurrentUser'] as bool;
    final rank = index + 1;

    Color rankColor = Colors.grey;
    IconData? rankIcon;

    if (rank == 1) {
      rankColor = Colors.amber;
      rankIcon = Icons.emoji_events;
    } else if (rank == 2) {
      rankColor = Colors.grey[400]!;
      rankIcon = Icons.emoji_events;
    } else if (rank == 3) {
      rankColor = Colors.brown;
      rankIcon = Icons.emoji_events;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCurrentUser ? const Color(0xFF006D77).withOpacity(0.1) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: isCurrentUser
            ? Border.all(color: const Color(0xFF006D77), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Rank
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: rankIcon != null
                    ? Icon(rankIcon, color: Colors.white, size: 20)
                    : Text(
                  '$rank',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // User Avatar
            CircleAvatar(
              radius: 25,
              backgroundImage: userData['photoURL'].isNotEmpty
                  ? NetworkImage(userData['photoURL'])
                  : null,
              child: userData['photoURL'].isEmpty
                  ? const Icon(Icons.person, size: 30)
                  : null,
            ),
            const SizedBox(width: 16),

            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        userData['name'],
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isCurrentUser ? const Color(0xFF006D77) : Colors.black,
                        ),
                      ),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF006D77),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'You',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${userData['completedJobs']} jobs completed',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            // Points
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.stars,
                      size: 20,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${userData['points']}',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF006D77),
                      ),
                    ),
                  ],
                ),
                Text(
                  'points',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'All Time'),
              Tab(text: 'This Month'),
              Tab(text: 'This Week'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildLeaderboardStream('all-time'),
            _buildLeaderboardStream('monthly'),
            _buildLeaderboardStream('weekly'),
          ],
        ),
      ),
    );
  }
}