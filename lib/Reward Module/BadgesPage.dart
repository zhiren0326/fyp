import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BadgesPage extends StatefulWidget {
  const BadgesPage({super.key});

  @override
  State<BadgesPage> createState() => _BadgesPageState();
}

class _BadgesPageState extends State<BadgesPage> with TickerProviderStateMixin {
  late TabController _tabController;
  List<String> _earnedBadges = [];
  Map<String, dynamic> _userStats = {};
  bool _isLoading = true;

  // All available badges with their requirements
  final Map<String, Map<String, dynamic>> allBadges = {
    // Task Completion Badges
    'first_task': {
      'name': 'First Steps',
      'description': 'Complete your first task',
      'icon': Icons.star,
      'color': Colors.blue,
      'category': 'Tasks',
      'requirement': 'Complete 1 task',
      'points': 50,
    },
    'task_warrior': {
      'name': 'Task Warrior',
      'description': 'Complete 5 tasks successfully',
      'icon': Icons.military_tech,
      'color': Colors.orange,
      'category': 'Tasks',
      'requirement': 'Complete 5 tasks',
      'points': 100,
    },
    'dedicated_worker': {
      'name': 'Dedicated Worker',
      'description': 'Complete 10 tasks',
      'icon': Icons.work,
      'color': Colors.green,
      'category': 'Tasks',
      'requirement': 'Complete 10 tasks',
      'points': 200,
    },
    'task_master': {
      'name': 'Task Master',
      'description': 'Complete 25 tasks',
      'icon': Icons.emoji_events,
      'color': Colors.purple,
      'category': 'Tasks',
      'requirement': 'Complete 25 tasks',
      'points': 500,
    },
    'legend': {
      'name': 'Legend',
      'description': 'Complete 50 tasks - You are legendary!',
      'icon': Icons.diamond,
      'color': Colors.red,
      'category': 'Tasks',
      'requirement': 'Complete 50 tasks',
      'points': 1000,
    },

    // Earnings Badges
    'first_earnings': {
      'name': 'First Paycheck',
      'description': 'Earn your first RM100',
      'icon': Icons.attach_money,
      'color': Colors.green,
      'category': 'Earnings',
      'requirement': 'Earn RM100',
      'points': 25,
    },
    'money_maker': {
      'name': 'Money Maker',
      'description': 'Earn RM1,000 in total',
      'icon': Icons.monetization_on,
      'color': Colors.amber,
      'category': 'Earnings',
      'requirement': 'Earn RM1,000',
      'points': 150,
    },
    'high_earner': {
      'name': 'High Earner',
      'description': 'Earn RM5,000 in total',
      'icon': Icons.account_balance,
      'color': Colors.deepPurple,
      'category': 'Earnings',
      'requirement': 'Earn RM5,000',
      'points': 500,
    },

    // Points Badges
    'point_collector': {
      'name': 'Point Collector',
      'description': 'Accumulate 500 points',
      'icon': Icons.stars,
      'color': Colors.indigo,
      'category': 'Points',
      'requirement': 'Collect 500 points',
      'points': 100,
    },
    'point_master': {
      'name': 'Point Master',
      'description': 'Accumulate 2,000 points',
      'icon': Icons.auto_awesome,
      'color': Colors.pink,
      'category': 'Points',
      'requirement': 'Collect 2,000 points',
      'points': 300,
    },

    // Duration & Efficiency Badges
    'quick_finisher': {
      'name': 'Quick Finisher',
      'description': 'Complete a 1-hour task',
      'icon': Icons.timer,
      'color': Colors.cyan,
      'category': 'Duration',
      'requirement': 'Complete 1-hour task',
      'points': 50,
    },
    'marathon_runner': {
      'name': 'Marathon Runner',
      'description': 'Complete a task lasting 8+ hours',
      'icon': Icons.fitness_center,
      'color': Colors.deepOrange,
      'category': 'Duration',
      'requirement': 'Complete 8+ hour task',
      'points': 200,
    },
    'efficiency_expert': {
      'name': 'Efficiency Expert',
      'description': 'Complete tasks worth 1000+ points in a week',
      'icon': Icons.trending_up,
      'color': Colors.teal,
      'category': 'Duration',
      'requirement': '1000+ points in a week',
      'points': 250,
    },
    'early_bird': {
      'name': 'Early Bird',
      'description': 'Complete a task before 8 AM',
      'icon': Icons.wb_sunny,
      'color': Colors.orange,
      'category': 'Special',
      'requirement': 'Complete task before 8 AM',
      'points': 75,
    },
    'night_owl': {
      'name': 'Night Owl',
      'description': 'Complete a task after 10 PM',
      'icon': Icons.nightlight,
      'color': Colors.deepPurple,
      'category': 'Special',
      'requirement': 'Complete task after 10 PM',
      'points': 75,
    },
    'speed_demon': {
      'name': 'Speed Demon',
      'description': 'Complete a task in under 1 hour',
      'icon': Icons.flash_on,
      'color': Colors.red,
      'category': 'Special',
      'requirement': 'Complete task quickly',
      'points': 150,
    },
    'perfectionist': {
      'name': 'Perfectionist',
      'description': 'Complete 5 tasks with 100% rating',
      'icon': Icons.grade,
      'color': Colors.amber,
      'category': 'Special',
      'requirement': '5 perfect ratings',
      'points': 250,
    },
    'team_player': {
      'name': 'Team Player',
      'description': 'Work on a collaborative task',
      'icon': Icons.group,
      'color': Colors.blue,
      'category': 'Special',
      'requirement': 'Join team task',
      'points': 100,
    },
    'consistent': {
      'name': 'Consistent',
      'description': 'Complete tasks for 7 consecutive days',
      'icon': Icons.calendar_today,
      'color': Colors.green,
      'category': 'Special',
      'requirement': '7 day streak',
      'points': 300,
    },
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBadgesData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBadgesData() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Load earned badges
      final badgesDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('badges')
          .doc('achievements')
          .get();

      if (badgesDoc.exists) {
        _earnedBadges = List<String>.from(badgesDoc.data()?['earnedBadges'] ?? []);
      }

      // Load user stats
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('profiledetails')
          .doc('profile')
          .get();

      if (profileDoc.exists) {
        _userStats = profileDoc.data() ?? {};
      }

    } catch (e) {
      print('Error loading badges data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildHeader() {
    final earnedCount = _earnedBadges.length;
    final totalCount = allBadges.length;
    final progress = totalCount > 0 ? earnedCount / totalCount : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF006D77), Color(0xFF83C5BE)],
        ),
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
                  'Achievements',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 48),
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
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.emoji_events, color: Colors.amber, size: 32),
                      const SizedBox(width: 12),
                      Text(
                        '$earnedCount / $totalCount',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Badges Earned',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}% Complete',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
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

  Widget _buildEarnedBadgesTab() {
    if (_earnedBadges.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No badges earned yet',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete tasks to earn your first badge!',
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

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _earnedBadges.length,
      itemBuilder: (context, index) {
        final badgeId = _earnedBadges[index];
        final badge = allBadges[badgeId];
        if (badge == null) return const SizedBox.shrink();
        return _buildBadgeCard(badgeId, badge, true);
      },
    );
  }

  Widget _buildAllBadgesTab() {
    // Group badges by category
    Map<String, List<MapEntry<String, Map<String, dynamic>>>> groupedBadges = {};

    for (var entry in allBadges.entries) {
      final category = entry.value['category'] as String;
      if (!groupedBadges.containsKey(category)) {
        groupedBadges[category] = [];
      }
      groupedBadges[category]!.add(entry);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: groupedBadges.entries.map((categoryEntry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 16),
                child: Text(
                  categoryEntry.key,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF006D77),
                  ),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: categoryEntry.value.length,
                itemBuilder: (context, index) {
                  final badgeEntry = categoryEntry.value[index];
                  final badgeId = badgeEntry.key;
                  final badge = badgeEntry.value;
                  final isEarned = _earnedBadges.contains(badgeId);
                  return _buildBadgeCard(badgeId, badge, isEarned);
                },
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBadgeCard(String badgeId, Map<String, dynamic> badge, bool isEarned) {
    final progress = _calculateBadgeProgress(badgeId);

    return GestureDetector(
      onTap: () => _showBadgeDetails(badgeId, badge, isEarned),
      child: Container(
        decoration: BoxDecoration(
          color: isEarned ? Colors.white : Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isEarned
                  ? (badge['color'] as Color).withOpacity(0.3)
                  : Colors.grey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: isEarned
              ? Border.all(color: (badge['color'] as Color).withOpacity(0.3), width: 2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isEarned
                    ? (badge['color'] as Color).withOpacity(0.1)
                    : Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(
                badge['icon'] as IconData,
                size: 40,
                color: isEarned ? badge['color'] as Color : Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                badge['name'] as String,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isEarned ? badge['color'] as Color : Colors.grey,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            if (!isEarned && progress != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(badge['color'] as Color),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(progress * 100).toInt()}%',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
            ] else if (isEarned) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'EARNED',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double? _calculateBadgeProgress(String badgeId) {
    final tasksCompleted = (_userStats['tasksCompleted'] ?? 0) as int;
    final totalEarnings = (_userStats['totalEarnings'] ?? 0.0) as double;
    final points = (_userStats['points'] ?? 0) as int;

    switch (badgeId) {
      case 'first_task':
        return tasksCompleted >= 1 ? 1.0 : tasksCompleted / 1;
      case 'task_warrior':
        return tasksCompleted >= 5 ? 1.0 : tasksCompleted / 5;
      case 'dedicated_worker':
        return tasksCompleted >= 10 ? 1.0 : tasksCompleted / 10;
      case 'task_master':
        return tasksCompleted >= 25 ? 1.0 : tasksCompleted / 25;
      case 'legend':
        return tasksCompleted >= 50 ? 1.0 : tasksCompleted / 50;
      case 'first_earnings':
        return totalEarnings >= 100 ? 1.0 : totalEarnings / 100;
      case 'money_maker':
        return totalEarnings >= 1000 ? 1.0 : totalEarnings / 1000;
      case 'high_earner':
        return totalEarnings >= 5000 ? 1.0 : totalEarnings / 5000;
      case 'point_collector':
        return points >= 500 ? 1.0 : points / 500;
      case 'point_master':
        return points >= 2000 ? 1.0 : points / 2000;
      default:
        return null;
    }
  }

  void _showBadgeDetails(String badgeId, Map<String, dynamic> badge, bool isEarned) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (badge['color'] as Color).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                badge['icon'] as IconData,
                size: 60,
                color: badge['color'] as Color,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              badge['name'] as String,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: badge['color'] as Color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              badge['description'] as String,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flag, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Requirement: ${badge['requirement']}',
                        style: GoogleFonts.poppins(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.stars, size: 16, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text(
                        'Reward: ${badge['points']} points',
                        style: GoogleFonts.poppins(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isEarned) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'EARNED',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: GoogleFonts.poppins(color: const Color(0xFF006D77)),
            ),
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
          : Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  indicatorColor: const Color(0xFF006D77),
                  labelColor: const Color(0xFF006D77),
                  unselectedLabelColor: Colors.grey,
                  tabs: const [
                    Tab(text: 'Earned'),
                    Tab(text: 'All Badges'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildEarnedBadgesTab(),
                      _buildAllBadgesTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}