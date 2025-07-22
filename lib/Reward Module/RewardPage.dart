import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RewardPage extends StatefulWidget {
  const RewardPage({super.key});

  @override
  State<RewardPage> createState() => _RewardPageState();
}

class _RewardPageState extends State<RewardPage> {
  int _userPoints = 0;
  List<Map<String, dynamic>> _leaderboard = [];
  List<Map<String, String>> _redeemableItems = [
    {'name': 'Gift Card', 'points': '50'},
    {'name': 'Merchandise', 'points': '100'},
    {'name': 'Premium Subscription', 'points': '200'},
  ];
  List<Map<String, dynamic>> _badges = [];

  @override
  void initState() {
    super.initState();
    _loadUserPoints();
    _loadLeaderboard();
    _loadBadges();
  }

  Future<void> _loadUserPoints() async {
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
  }

  Future<void> _loadLeaderboard() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .orderBy('points', descending: true)
        .limit(5)
        .get();
    setState(() {
      _leaderboard = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'name': data['name'] ?? 'Anonymous',
          'points': data['points'] ?? 0,
        };
      }).toList();
    });
  }

  Future<void> _loadBadges() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_userPoints >= 100) {
      _badges.add({'name': 'Bronze Badge', 'description': '100+ points'});
    }
    if (_userPoints >= 300) {
      _badges.add({'name': 'Silver Badge', 'description': '300+ points'});
    }
    if (_userPoints >= 500) {
      _badges.add({'name': 'Gold Badge', 'description': '500+ points'});
    }
    setState(() {});
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
            'Rewards',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 20,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.teal,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
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
                        style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Leaderboard',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _leaderboard.length,
                    itemBuilder: (context, index) {
                      final user = _leaderboard[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text('${index + 1}'),
                        ),
                        title: Text(user['name']),
                        trailing: Text('${user['points']} pts'),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Redeemable Items',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _redeemableItems.length,
                    itemBuilder: (context, index) {
                      final item = _redeemableItems[index];
                      return ListTile(
                        title: Text(item['name']!),
                        trailing: Text('${item['points']} pts'),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Badges',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _badges.length,
                    itemBuilder: (context, index) {
                      final badge = _badges[index];
                      return ListTile(
                        leading: Icon(Icons.star, color: Colors.amber),
                        title: Text(badge['name']),
                        subtitle: Text(badge['description']),
                      );
                    },
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