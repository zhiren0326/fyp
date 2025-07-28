import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RewardPage extends StatefulWidget {
  const RewardPage({super.key});

  @override
  State<RewardPage> createState() => _RewardPageState();
}

class _RewardPageState extends State<RewardPage> with TickerProviderStateMixin {
  late TabController _tabController;
  int _userPoints = 0;
  int _userRank = 0;
  bool _isRedeeming = false;

  final List<Map<String, dynamic>> _redeemableItems = [
    {
      'id': 'gift_card_10',
      'name': 'RM10 Gift Card',
      'points': 50,
      'description': 'Digital gift card for online shopping',
      'category': 'gift_cards',
      'icon': Icons.card_giftcard,
      'color': Colors.purple,
    },
    {
      'id': 'gift_card_25',
      'name': 'RM25 Gift Card',
      'points': 120,
      'description': 'Digital gift card for online shopping',
      'category': 'gift_cards',
      'icon': Icons.card_giftcard,
      'color': Colors.purple,
    },
    {
      'id': 'coffee_voucher',
      'name': 'Coffee Voucher',
      'points': 30,
      'description': 'Free coffee at participating cafes',
      'category': 'vouchers',
      'icon': Icons.local_cafe,
      'color': Colors.brown,
    },
    {
      'id': 'premium_month',
      'name': '1 Month Premium',
      'points': 200,
      'description': 'Premium app features for 1 month',
      'category': 'premium',
      'icon': Icons.star,
      'color': Colors.amber,
    },
    {
      'id': 'premium_year',
      'name': '1 Year Premium',
      'points': 2000,
      'description': 'Premium app features for 1 year',
      'category': 'premium',
      'icon': Icons.stars,
      'color': Colors.amber,
    },
    {
      'id': 'merchandise_tshirt',
      'name': 'Taaz T-Shirt',
      'points': 150,
      'description': 'Official branded t-shirt',
      'category': 'merchandise',
      'icon': Icons.checkroom,
      'color': Colors.teal,
    },
    {
      'id': 'merchandise_mug',
      'name': 'Taaz Mug',
      'points': 80,
      'description': 'Official branded coffee mug',
      'category': 'merchandise',
      'icon': Icons.coffee_maker,
      'color': Colors.teal,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
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
      await _calculateUserRank();
    }
  }

  Future<void> _calculateUserRank() async {
    try {
      final usersWithHigherPoints = await FirebaseFirestore.instance
          .collection('users')
          .where('points', isGreaterThan: _userPoints)
          .get();

      setState(() {
        _userRank = usersWithHigherPoints.docs.length + 1;
      });
    } catch (e) {
      print('Error calculating rank: $e');
    }
  }

  Future<void> _redeemItem(Map<String, dynamic> item) async {
    if (_userPoints < item['points']) {
      _showSnackBar('Insufficient points!', Colors.red);
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Redemption', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to redeem:', style: GoogleFonts.poppins()),
            const SizedBox(height: 8),
            Text(item['name'], style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            Text('${item['points']} points', style: GoogleFonts.poppins(color: Colors.orange)),
            const SizedBox(height: 8),
            Text('Your remaining points: ${_userPoints - item['points']}',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006D77)),
            child: const Text('Redeem', style: TextStyle(color: Colors.white)),
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

      _showSnackBar('Item redeemed successfully!', Colors.green);
      _showRedemptionSuccess(item);

    } catch (e) {
      _showSnackBar('Error redeeming item: $e', Colors.red);
    } finally {
      setState(() => _isRedeeming = false);
    }
  }

  String _generateRedemptionCode() {
    final now = DateTime.now();
    final code = 'FK${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.millisecond}';
    return code;
  }

  void _showRedemptionSuccess(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 24),
            const SizedBox(width: 8),
            Text('Success!', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('You have successfully redeemed:', style: GoogleFonts.poppins()),
            const SizedBox(height: 8),
            Text(item['name'],
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Check your redemption history for the redemption code and instructions.',
                style: GoogleFonts.poppins(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006D77)),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
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
      ),
    );
  }

  Widget _buildTabContent(String tab) {
    switch (tab) {
      case 'Points':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Points',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$_userPoints pts',
                      style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF006D77)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Rank: $_userRank',
                      style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      case 'Redeem':
        return GridView.builder(
          padding: const EdgeInsets.all(8.0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.9,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: _redeemableItems.length,
          itemBuilder: (context, index) {
            final item = _redeemableItems[index];
            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: item['color'],
              child: InkWell(
                onTap: _isRedeeming ? null : () => _redeemItem(item),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item['icon'], size: 40, color: Colors.white),
                      const SizedBox(height: 10),
                      Text(
                        item['name'],
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${item['points']} pts',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      if (_isRedeeming)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      case 'Leaderboard':
        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: 5, // Assuming top 5 for now (dynamic loading can be added)
          itemBuilder: (context, index) {
            return FutureBuilder(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('points', descending: true)
                  .limit(5)
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const ListTile(
                    leading: CircularProgressIndicator(),
                    title: Text('Loading...'),
                  );
                }
                final user = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                return ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(user['name'] ?? 'Anonymous'),
                  trailing: Text('${user['points'] ?? 0} pts'),
                );
              },
            );
          },
        );
      case 'Badges':
        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: 3, // Bronze, Silver, Gold
          itemBuilder: (context, index) {
            final thresholds = [100, 300, 500];
            final names = ['Bronze Badge', 'Silver Badge', 'Gold Badge'];
            final achieved = _userPoints >= thresholds[index];
            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Icon(
                  Icons.star,
                  color: achieved ? Colors.amber : Colors.grey,
                ),
                title: Text(names[index]),
                subtitle: Text('${thresholds[index]}+ points'),
                trailing: achieved
                    ? const Icon(Icons.check, color: Colors.green)
                    : const Text('Not Achieved'),
              ),
            );
          },
        );
      default:
        return const SizedBox.shrink();
    }
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
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Text(
                  'Rewards',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TabBar(
                        controller: _tabController,
                        labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        tabs: const [
                          Tab(text: 'Points'),
                          Tab(text: 'Redeem'),
                          Tab(text: 'Leaderboard'),
                          Tab(text: 'Badges'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildTabContent('Points'),
                            _buildTabContent('Redeem'),
                            _buildTabContent('Leaderboard'),
                            _buildTabContent('Badges'),
                          ],
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
    );
  }
}