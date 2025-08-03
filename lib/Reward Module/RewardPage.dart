import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp/Reward%20Module/RealtimeLeaderboard.dart';
import 'package:google_fonts/google_fonts.dart';

import 'BadgesPage.dart';
import 'MoneyPage.dart';

class RewardsPage extends StatefulWidget {
  const RewardsPage({super.key});

  @override
  State<RewardsPage> createState() => _RewardsPageState();
}

class _RewardsPageState extends State<RewardsPage> {
  int _userPoints = 0;
  List<Map<String, dynamic>> _topPerformers = [];
  bool _isLoading = true;
  bool _isRedeeming = false;

  final List<Map<String, dynamic>> _redeemableItems = [
    {
      'id': 'rm10_shopee',
      'name': 'RM10 Shopee Gift Card',
      'points': 1000,
      'description': 'Digital gift card for Shopee online shopping',
      'category': 'gift_cards',
      'icon': Icons.card_giftcard,
      'color': const Color(0xFFFF6B35),
    },
    {
      'id': 'movie_ticket',
      'name': 'Movie Ticket',
      'points': 1500,
      'description': 'Cinema ticket for latest movies',
      'category': 'entertainment',
      'icon': Icons.local_movies,
      'color': const Color(0xFF8E44AD),
    },
    {
      'id': 'food_voucher',
      'name': 'Food Voucher',
      'points': 800,
      'description': 'RM20 food voucher at participating restaurants',
      'category': 'vouchers',
      'icon': Icons.restaurant,
      'color': const Color(0xFF27AE60),
    },
    {
      'id': 'spotify_premium',
      'name': 'Spotify Premium',
      'points': 2000,
      'description': '1 month Spotify Premium subscription',
      'category': 'subscriptions',
      'icon': Icons.headphones,
      'color': const Color(0xFFE74C3C),
    },
    {
      'id': 'grab_voucher',
      'name': 'Grab Voucher',
      'points': 600,
      'description': 'RM15 Grab ride voucher',
      'category': 'transportation',
      'icon': Icons.local_taxi,
      'color': const Color(0xFF00D4AA),
    },
    {
      'id': 'coffee_voucher',
      'name': 'Coffee Voucher',
      'points': 400,
      'description': 'Free coffee at Starbucks or local cafes',
      'category': 'beverages',
      'icon': Icons.local_cafe,
      'color': const Color(0xFF8B4513),
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadUserPoints(),
      _loadTopPerformers(),
    ]);
    setState(() => _isLoading = false);
  }

  Future<void> _loadUserPoints() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('profiledetails')
          .doc('profile')
          .get();

      if (doc.exists) {
        setState(() {
          _userPoints = (doc.data()?['points'] ?? 0) as int;
        });
      }
    } catch (e) {
      print('Error loading user points: $e');
    }
  }

  Future<void> _loadTopPerformers() async {
    try {
      // Get all users and their profile data
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .limit(20) // Limit to prevent excessive reads
          .get();

      List<Map<String, dynamic>> performers = [];

      for (var userDoc in usersSnapshot.docs) {
        try {
          final profileDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userDoc.id)
              .collection('profiledetails')
              .doc('profile')
              .get();

          if (profileDoc.exists) {
            final profileData = profileDoc.data()!;
            final points = (profileData['points'] ?? 0) as int;

            if (points > 0) {
              performers.add({
                'userId': userDoc.id,
                'name': profileData['name'] ?? 'Unknown User',
                'photoURL': profileData['photoURL'] ?? '',
                'points': points,
              });
            }
          }
        } catch (e) {
          print('Error processing user ${userDoc.id}: $e');
        }
      }

      // Sort by points and take top 3
      performers.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));

      setState(() {
        _topPerformers = performers.take(3).toList();
      });
    } catch (e) {
      print('Error loading top performers: $e');
    }
  }

  Future<void> _redeemItem(Map<String, dynamic> item) async {
    if (_userPoints < item['points']) {
      _showSnackBar('Insufficient points! You need ${item['points']} points.', Colors.red);
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          'Confirm Redemption',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to redeem:', style: GoogleFonts.poppins()),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: item['color'].withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: item['color'].withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(item['icon'], color: item['color'], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name'],
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${item['points']} points',
                          style: GoogleFonts.poppins(
                            color: item['color'],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Remaining points: ${_userPoints - item['points']}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.orange[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006D77),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Redeem',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRedeeming = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Deduct points from user
        final profileRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('profiledetails')
            .doc('profile');

        final profileDoc = await transaction.get(profileRef);
        final currentPoints = (profileDoc.data()?['points'] ?? 0) as int;

        if (currentPoints < item['points']) {
          throw Exception('Insufficient points');
        }

        transaction.update(profileRef, {
          'points': currentPoints - item['points'],
          'lastPointsUpdate': Timestamp.now(),
        });

        // Add redemption record
        final redemptionRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('redemptions')
            .doc();

        transaction.set(redemptionRef, {
          'itemId': item['id'],
          'itemName': item['name'],
          'pointsSpent': item['points'],
          'timestamp': Timestamp.now(),
          'status': 'pending', // pending, processed, delivered
          'redemptionCode': _generateRedemptionCode(),
          'category': item['category'],
          'description': item['description'],
        });

        // Add to points history
        final pointsHistoryRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('pointsHistory')
            .doc();

        transaction.set(pointsHistoryRef, {
          'points': -item['points'],
          'source': 'redemption',
          'itemName': item['name'],
          'timestamp': Timestamp.now(),
          'description': 'Redeemed ${item['name']}',
        });
      });

      setState(() {
        _userPoints -= item['points'] as int;
      });

      _showRedemptionSuccess(item);

    } catch (e) {
      _showSnackBar('Error redeeming item: $e', Colors.red);
    } finally {
      setState(() => _isRedeeming = false);
    }
  }

  String _generateRedemptionCode() {
    final now = DateTime.now();
    final code = 'RWD${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.millisecond}';
    return code;
  }

  void _showRedemptionSuccess(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[100],
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.green, size: 24),
            ),
            const SizedBox(width: 12),
            Text('Success!', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You have successfully redeemed:',
              style: GoogleFonts.poppins(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: item['color'].withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: item['color'].withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Icon(item['icon'], color: item['color'], size: 32),
                  const SizedBox(height: 8),
                  Text(
                    item['name'],
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Check your redemption history for the redemption code and instructions. You will receive further details via email.',
                style: GoogleFonts.poppins(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006D77),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'OK',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      margin: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF006D77),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  'My Earnings',
                  'Track your income',
                  Icons.account_balance_wallet,
                  Colors.green,
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MoneyPage()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  'Achievements',
                  'View your badges',
                  Icons.emoji_events,
                  Colors.amber,
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const BadgesPage()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF006D77),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(
                  'Rewards',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 48), // Balance the back button
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.stars, color: Colors.amber, size: 32),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      Text(
                        '$_userPoints pts',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Your Points',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPerformers() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Top Performers',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF006D77),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => RealtimeLeaderboard()));
                },
                child: Text(
                  'View All',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF006D77),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_topPerformers.isEmpty)
            Center(
              child: Text(
                'No performers data available',
                style: GoogleFonts.poppins(color: Colors.grey),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _topPerformers.asMap().entries.map((entry) {
                int index = entry.key;
                Map<String, dynamic> performer = entry.value;
                return _buildPerformerCard(performer, index);
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildPerformerCard(Map<String, dynamic> performer, int index) {
    Color rankColor = Colors.grey;
    IconData rankIcon = Icons.emoji_events;

    if (index == 0) {
      rankColor = Colors.amber;
    } else if (index == 1) {
      rankColor = Colors.grey[400]!;
    } else if (index == 2) {
      rankColor = Colors.brown;
    }

    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundImage: performer['photoURL'].isNotEmpty
                  ? _getImageProvider(performer['photoURL'])
                  : null,
              backgroundColor: Colors.grey[200],
              child: performer['photoURL'].isEmpty
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
        const SizedBox(height: 8),
        Text(
          performer['name'].length > 8
              ? '${performer['name'].substring(0, 8)}...'
              : performer['name'],
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          '${performer['points']} pts',
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  // Replace your reward item builder in the GridView with this fixed version:

  Widget _buildRewardItem(Map<String, dynamic> item, bool canAfford) {
    return GestureDetector(
      onTap: _isRedeeming || !canAfford ? null : () => _redeemItem(item),
      child: Container(
        decoration: BoxDecoration(
          color: canAfford ? Colors.white : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Add this
          children: [
            // Icon and points section
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: item['color'].withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min, // Add this
                  children: [
                    Icon(
                      item['icon'],
                      size: 36, // Reduced from 40
                      color: canAfford ? item['color'] : Colors.grey,
                    ),
                    const SizedBox(height: 6), // Reduced from 8
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.stars,
                          size: 14, // Reduced from 16
                          color: canAfford ? Colors.amber : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item['points']} pts', // Shortened text
                          style: GoogleFonts.poppins(
                            fontSize: 11, // Reduced from 12
                            fontWeight: FontWeight.w600,
                            color: canAfford ? item['color'] : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Title and button section
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8), // Reduced from 12
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // Add this
                  children: [
                    // Title
                    Flexible( // Wrap with Flexible
                      child: Text(
                        item['name'],
                        style: GoogleFonts.poppins(
                          fontSize: 13, // Reduced from 14
                          fontWeight: FontWeight.bold,
                          color: canAfford ? Colors.black : Colors.grey,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                    // Button/Loading indicator
                    if (_isRedeeming)
                      const Center(
                        child: SizedBox(
                          height: 18, // Reduced from 20
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6), // Reduced from 8
                        decoration: BoxDecoration(
                          color: canAfford ? item['color'] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          canAfford ? 'Redeem' : 'Need ${item['points'] - _userPoints}',
                          style: GoogleFonts.poppins(
                            fontSize: 10, // Reduced from 11
                            fontWeight: FontWeight.w600,
                            color: canAfford ? Colors.white : Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

// Updated GridView builder method
  Widget _buildRedeemRewards() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Redeem Rewards',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF006D77),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  '$_userPoints pts',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.9, // Increased from 0.85 to give more height
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _redeemableItems.length,
            itemBuilder: (context, index) {
              final item = _redeemableItems[index];
              final canAfford = _userPoints >= item['points'];
              return _buildRewardItem(item, canAfford);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            _buildQuickActions(),
            _buildTopPerformers(),
            _buildRedeemRewards(),
            const SizedBox(height: 20),
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