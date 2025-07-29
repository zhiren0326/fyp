import 'dart:async';

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

  // Stream subscriptions for cleanup
  StreamSubscription? _leaderboardSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _leaderboardSubscription?.cancel();
    super.dispose();
  }

  Widget _buildLeaderboardStream(String period) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getLeaderboardStream(period),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          print('Leaderboard error: ${snapshot.error}');
          return _buildErrorWidget('Error loading leaderboard: ${snapshot.error}');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingWidget();
        }

        final leaderboardData = snapshot.data ?? [];

        if (leaderboardData.isEmpty) {
          return _buildEmptyWidget();
        }

        return _buildLeaderboardList(leaderboardData);
      },
    );
  }

  Future<Map<String, dynamic>?> _processUserData(String userId, String period) async {
    try {
      print('🔍 Processing user: $userId for period: $period');

      String userName = 'Unknown User';
      String photoURL = '';
      int points = 0;
      Timestamp? lastUpdate;

      // Get user profile data INCLUDING POINTS
      try {
        final profileDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('profiledetails')
            .doc('profile')
            .get();

        if (profileDoc.exists) {
          final profileData = profileDoc.data()!;

          // Print all profile data for debugging
          print('📄 Profile data for $userId: $profileData');

          userName = profileData['name'] ?? 'Unknown User';
          photoURL = profileData['photoURL'] ?? '';
          lastUpdate = profileData['lastPointsUpdate'];

          // Get points directly from profile - check multiple possible field names
          dynamic profilePointsRaw = profileData['points'];
          int points = 0;

          if (profilePointsRaw != null) {
            if (profilePointsRaw is int) {
              points = profilePointsRaw;
            } else if (profilePointsRaw is double) {
              points = profilePointsRaw.toInt();
            } else if (profilePointsRaw is String) {
              points = int.tryParse(profilePointsRaw) ?? 0;
            } else {
              // Handle other types like num
              points = (profilePointsRaw as num?)?.toInt() ?? 0;
            }
            print('💰 Found points in profile: $profilePointsRaw (type: ${profilePointsRaw.runtimeType}) -> parsed to: $points');
          } else {
            // Try alternative field names only if 'points' doesn't exist
            var altPoints = profileData['Points'] ??
                profileData['totalPoints'] ??
                profileData['point'];

            if (altPoints != null) {
              if (altPoints is int) {
                points = altPoints;
              } else if (altPoints is double) {
                points = altPoints.toInt();
              } else if (altPoints is String) {
                points = int.tryParse(altPoints) ?? 0;
              } else {
                points = (altPoints as num?)?.toInt() ?? 0;
              }
              print('💰 Found points in alternative field: $altPoints -> parsed to: $points');
            } else {
              print('❌ No points field found in profile document');
              print('Available fields: ${profileData.keys.toList()}');
            }
          }

          print('👤 Found profile for $userId: $userName with $points points');
        } else {
          print('❌ No profile document found for $userId');
        }
      } catch (e) {
        print('⚠️ Error fetching profile for $userId: $e');
      }

      // If no profile found, try main user document
      if (userName == 'Unknown User') {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data()!;
            print('📄 Main user data for $userId: $userData');

            userName = userData['name'] ?? userData['displayName'] ?? 'Unknown User';
            photoURL = userData['photoURL'] ?? '';

            // Also check for points in main user document as fallback
            if (points == 0) {
              var userPoints = userData['points'] ??
                  userData['Points'] ??
                  userData['totalPoints'] ??
                  userData['point'];

              if (userPoints != null) {
                if (userPoints is int) {
                  points = userPoints;
                } else if (userPoints is double) {
                  points = userPoints.toInt();
                } else if (userPoints is String) {
                  points = int.tryParse(userPoints) ?? 0;
                }
                print('💰 Found points in main user doc: $userPoints');
              }
            }
          }
        } catch (e) {
          print('⚠️ No main user document found for $userId');
        }
      }

      print('💰 Final points for $userId: $points');

      int completedJobs = 0;

      // GET COMPLETED JOBS (simplified for debugging)
      try {
        final jobsQuery = FirebaseFirestore.instance
            .collection('jobs')
            .where('acceptedApplicants', arrayContains: userId)
            .where('isCompleted', isEqualTo: true);

        final jobsSnapshot = await jobsQuery.get();
        completedJobs = jobsSnapshot.docs.length;
        print('💼 Total completed jobs for $userId: $completedJobs');
      } catch (e) {
        print('❗ Error fetching jobs for $userId: $e');
      }

      final result = {
        'userId': userId,
        'name': userName,
        'photoURL': photoURL,
        'points': points,
        'completedJobs': completedJobs,
        'isCurrentUser': userId == _currentUserId,
        'lastUpdate': lastUpdate ?? Timestamp.now(),
      };

      print('✅ Final result for $userId: $result');

      return result;

    } catch (e) {
      print('❗ Error processing user data for $userId: $e');
      return null;
    }
  }

  Stream<List<Map<String, dynamic>>> _getLeaderboardStream(String period) {
    return FirebaseFirestore.instance
        .collection('users')
        .snapshots()
        .asyncMap((usersSnapshot) async {
      print('📊 Found ${usersSnapshot.docs.length} users in collection');

      // Print all user IDs for debugging
      print('📝 User IDs found: ${usersSnapshot.docs.map((doc) => doc.id).toList()}');

      List<Map<String, dynamic>> leaderboardData = [];

      // Process each user
      for (var userDoc in usersSnapshot.docs) {
        try {
          print('🔍 Processing user: ${userDoc.id}');
          final userData = await _processUserData(userDoc.id, period);

          if (userData != null) {
            leaderboardData.add(userData);
            print('✅ Added user ${userDoc.id} to leaderboard');
          } else {
            print('❌ Skipped user ${userDoc.id} - userData is null');
          }
        } catch (e) {
          print('❗ Error processing user ${userDoc.id}: $e');
        }
      }

      print('📋 Final leaderboard data count: ${leaderboardData.length}');

      // Sort by points (descending), then by completed jobs as tiebreaker
      leaderboardData.sort((a, b) {
        int pointsComparison = (b['points'] as int).compareTo(a['points'] as int);
        if (pointsComparison != 0) return pointsComparison;

        // If points are equal, sort by completed jobs
        return (b['completedJobs'] as int).compareTo(a['completedJobs'] as int);
      });

      return leaderboardData;
    });
  }

  Widget _buildLeaderboardList(List<Map<String, dynamic>> leaderboardData) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: leaderboardData.length,
      itemBuilder: (context, index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          child: _buildLeaderboardItem(leaderboardData[index], index),
        );
      },
    );
  }

  Widget _buildLeaderboardItem(Map<String, dynamic> userData, int index) {
    final isCurrentUser = userData['isCurrentUser'] as bool;
    final rank = index + 1;
    final lastUpdate = userData['lastUpdate'] as Timestamp?;

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

            // User Avatar with live indicator
            Stack(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage: userData['photoURL'].isNotEmpty
                      ? _getImageProvider(userData['photoURL'])
                      : null,
                  backgroundColor: Colors.grey[200],
                  child: userData['photoURL'].isEmpty
                      ? const Icon(Icons.person, size: 30, color: Colors.grey)
                      : null,
                ),
                if (_isRecentlyUpdated(lastUpdate))
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),

            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          userData['name'],
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isCurrentUser ? const Color(0xFF006D77) : Colors.black,
                          ),
                          overflow: TextOverflow.ellipsis,
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

  bool _isRecentlyUpdated(Timestamp? lastUpdate) {
    if (lastUpdate == null) return false;
    final now = DateTime.now();
    final updateTime = lastUpdate.toDate();
    return now.difference(updateTime).inMinutes < 5;
  }

  Widget _buildLoadingWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF006D77)),
          ),
          SizedBox(height: 16),
          Text('Loading leaderboard...'),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading leaderboard',
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: Colors.red[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => setState(() {}),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006D77),
            ),
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
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
          const SizedBox(height: 8),
          Text(
            'Complete some jobs to appear on the leaderboard!',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
          title: Row(
            children: [
              Text(
                'Leaderboard',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF006D77),
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
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
ImageProvider _getImageProvider(String photoURL) {
  if (photoURL.startsWith('assets/')) {
    // It's a local asset
    return AssetImage(photoURL);
  } else if (photoURL.startsWith('http')) {
    // It's a network image
    return NetworkImage(photoURL);
  } else {
    // Default to AssetImage for other cases
    return AssetImage(photoURL);
  }
}