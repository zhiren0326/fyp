import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

class RewardsStorePage extends StatefulWidget {
  const RewardsStorePage({super.key});

  @override
  State<RewardsStorePage> createState() => _RewardsStorePageState();
}

class _RewardsStorePageState extends State<RewardsStorePage> {
  int _userPoints = 0;
  List<Map<String, dynamic>> _rewards = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserPoints();
    _loadRewards();
  }

  Future<void> _loadUserPoints() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('profiledetails')
          .doc('profile')
          .get();

      if (profileDoc.exists) {
        setState(() {
          _userPoints = (profileDoc.data()?['points'] ?? 0) as int;
        });
      }
    } catch (e) {
      print('Error loading user points: $e');
    }
  }

  Future<void> _loadRewards() async {
    try {
      final rewardsSnapshot = await FirebaseFirestore.instance
          .collection('rewards')
          .orderBy('pointsCost', descending: false)
          .get();

      setState(() {
        _rewards = rewardsSnapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading rewards: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _redeemReward(Map<String, dynamic> reward) async {
    if (_userPoints < reward['pointsCost']) {
      _showSnackBar('Insufficient points!', Colors.red);
      return;
    }

    try {
      final currentUser = FirebaseAuth.instance.currentUser!;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Deduct points from user
        final profileRef = FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('profiledetails')
            .doc('profile');

        final profileDoc = await transaction.get(profileRef);
        final currentPoints = (profileDoc.data()?['points'] ?? 0) as int;

        transaction.update(profileRef, {
          'points': currentPoints - reward['pointsCost'],
          'lastPointsUpdate': Timestamp.now(),
        });

        // Add to redemption history
        final redemptionRef = FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('redemptions')
            .doc();

        transaction.set(redemptionRef, {
          'rewardId': reward['id'],
          'rewardName': reward['name'],
          'pointsCost': reward['pointsCost'],
          'redeemedAt': Timestamp.now(),
          'status': 'pending', // pending, approved, delivered
          'rewardType': reward['type'],
          'description': reward['description'],
        });

        // Add to points history
        final pointsHistoryRef = FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('pointsHistory')
            .doc();

        transaction.set(pointsHistoryRef, {
          'points': -reward['pointsCost'],
          'source': 'reward_redemption',
          'rewardName': reward['name'],
          'timestamp': Timestamp.now(),
          'description': 'Redeemed: ${reward['name']}',
        });
      });

      setState(() {
        _userPoints -= reward['pointsCost'] as int;
      });

      _showSnackBar('Reward redeemed successfully!', Colors.green);

    } catch (e) {
      _showSnackBar('Error redeeming reward: $e', Colors.red);
    }
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

  Color _getRewardTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'voucher':
        return Colors.blue;
      case 'gift_card':
        return Colors.purple;
      case 'merchandise':
        return Colors.green;
      case 'experience':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _buildPointsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF006D77), Color(0xFF83C5BE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Points',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
              Text(
                '$_userPoints',
                style: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.stars,
              size: 32,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardCard(Map<String, dynamic> reward) {
    final canAfford = _userPoints >= reward['pointsCost'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: canAfford ? Colors.white : Colors.grey[100],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getRewardTypeColor(reward['type']).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _getRewardTypeColor(reward['type'])),
                    ),
                    child: Text(
                      reward['type'].toString().toUpperCase(),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _getRewardTypeColor(reward['type']),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.stars,
                        size: 20,
                        color: canAfford ? Colors.amber : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${reward['pointsCost']}',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: canAfford ? const Color(0xFF006D77) : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                reward['name'],
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: canAfford ? Colors.black : Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                reward['description'],
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: canAfford ? Colors.grey[600] : Colors.grey,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canAfford ? () => _redeemReward(reward) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAfford ? const Color(0xFF006D77) : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    canAfford ? 'Redeem Now' : 'Insufficient Points',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
            'Rewards Store',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: () {
                // Navigate to redemption history
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            _buildPointsCard(),
            Expanded(
              child: _rewards.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.card_giftcard,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No rewards available',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: _rewards.length,
                itemBuilder: (context, index) {
                  return _buildRewardCard(_rewards[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}