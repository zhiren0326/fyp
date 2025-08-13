import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class PointsHistoryPage extends StatefulWidget {
  const PointsHistoryPage({super.key});

  @override
  State<PointsHistoryPage> createState() => _PointsHistoryPageState();
}

class _PointsHistoryPageState extends State<PointsHistoryPage> with TickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allTransactions = [];
  List<Map<String, dynamic>> _earnedTransactions = [];
  List<Map<String, dynamic>> _spentTransactions = [];
  bool _isLoading = true;
  int _totalPoints = 0;
  int _totalEarned = 0;
  int _totalSpent = 0;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initializeUser() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
        currentUser = userCredential.user;
      }

      if (currentUser != null) {
        setState(() {
          _currentUserId = currentUser!.uid;
        });
        print('PointsHistory - Initialized user: ${currentUser.uid}');
        _loadPointsHistory();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error initializing user: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPointsHistory() async {
    if (_currentUserId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('Loading points history for user: $_currentUserId');

      // Load current points from profile
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('profiledetails')
          .doc('profile')
          .get();

      if (profileDoc.exists) {
        final profileData = profileDoc.data()!;
        // Try both 'totalPoints' and 'points' field names for compatibility
        _totalPoints = (profileData['totalPoints'] ?? profileData['points'] ?? 0) as int;
      }

      // Load points history
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('pointsHistory')
          .orderBy('timestamp', descending: true)
          .get();

      List<Map<String, dynamic>> allTransactions = [];
      List<Map<String, dynamic>> earnedTransactions = [];
      List<Map<String, dynamic>> spentTransactions = [];

      int totalEarned = 0;
      int totalSpent = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final points = (data['points'] ?? 0) as int;
        final timestamp = data['timestamp'] as Timestamp?;

        final transaction = {
          'id': doc.id,
          'points': points,
          'description': data['description'] ?? 'Points transaction',
          'source': data['source'] ?? 'unknown',
          'taskTitle': data['taskTitle'] ?? '',
          'itemName': data['itemName'] ?? '',
          'timestamp': timestamp?.toDate() ?? DateTime.now(),
          'type': points >= 0 ? 'earned' : 'spent',
          ...data,
        };

        allTransactions.add(transaction);

        if (points >= 0) {
          earnedTransactions.add(transaction);
          totalEarned += points;
        } else {
          spentTransactions.add(transaction);
          totalSpent += points.abs();
        }
      }

      setState(() {
        _allTransactions = allTransactions;
        _earnedTransactions = earnedTransactions;
        _spentTransactions = spentTransactions;
        _totalEarned = totalEarned;
        _totalSpent = totalSpent;
        _isLoading = false;
      });

      print('Loaded ${allTransactions.length} transactions - Earned: ${earnedTransactions.length}, Spent: ${spentTransactions.length}');

    } catch (e) {
      print('Error loading points history: $e');
      setState(() => _isLoading = false);
    }
  }

  Widget _buildHeader() {
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
                  'Points History',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _loadPointsHistory,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_currentUserId != null)
              Text(
                'User: ${_currentUserId!.substring(0, 8)}...',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            const SizedBox(height: 16),
            // Points Summary Cards
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Current Points',
                    _totalPoints.toString(),
                    Icons.stars,
                    Colors.amber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Total Earned',
                    _totalEarned.toString(),
                    Icons.trending_up,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Total Spent',
                    _totalSpent.toString(),
                    Icons.trending_down,
                    Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: Colors.white.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList(List<Map<String, dynamic>> transactions) {
    if (transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(
                Icons.history,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No transactions found',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your points transactions will appear here',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: transactions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final transaction = transactions[index];
        return _buildTransactionCard(transaction);
      },
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final points = transaction['points'] as int;
    final isEarning = points >= 0;
    final description = transaction['description'] as String? ?? 'Points transaction';
    final source = transaction['source'] as String? ?? 'unknown';
    final taskTitle = transaction['taskTitle'] as String? ?? '';
    final itemName = transaction['itemName'] as String? ?? '';

    // Handle both DateTime and Timestamp types
    DateTime timestamp;
    final timestampData = transaction['timestamp'];
    if (timestampData is DateTime) {
      timestamp = timestampData;
    } else if (timestampData is Timestamp) {
      timestamp = timestampData.toDate();
    } else {
      timestamp = DateTime.now();
    }

    Color cardColor = isEarning ? Colors.green[50]! : Colors.red[50]!;
    Color iconColor = isEarning ? Colors.green : Colors.red;
    IconData icon = isEarning ? Icons.add_circle : Icons.remove_circle;

    // Determine the display title and subtitle
    String displayTitle = description;
    String displaySubtitle = '';

    if (taskTitle.isNotEmpty) {
      displayTitle = taskTitle;
      displaySubtitle = description;
    } else if (itemName.isNotEmpty) {
      displayTitle = itemName;
      displaySubtitle = description;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: iconColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (displaySubtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    displaySubtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getSourceDisplayName(source),
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: iconColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMM dd, yyyy • HH:mm').format(timestamp),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isEarning ? '+' : '-',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                  Icon(Icons.stars, size: 16, color: Colors.amber[700]),
                  const SizedBox(width: 4),
                  Text(
                    '${points.abs()}',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
              Text(
                'pts',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getSourceDisplayName(String source) {
    switch (source) {
      case 'task_completion':
        return 'Task Completed';
      case 'redemption':
        return 'Redemption';
      case 'bonus':
        return 'Bonus';
      case 'referral':
        return 'Referral';
      case 'achievement':
        return 'Achievement';
      default:
        return source.toUpperCase();
    }
  }

  Widget _buildStatsCard() {
    final avgEarningPerTransaction = _earnedTransactions.isNotEmpty
        ? (_totalEarned / _earnedTransactions.length).round()
        : 0;

    final avgSpentPerTransaction = _spentTransactions.isNotEmpty
        ? (_totalSpent / _spentTransactions.length).round()
        : 0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Statistics',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF006D77),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Avg. Earned',
                  '$avgEarningPerTransaction pts',
                  Icons.trending_up,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  'Avg. Spent',
                  '$avgSpentPerTransaction pts',
                  Icons.trending_down,
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Earning Transactions',
                  '${_earnedTransactions.length}',
                  Icons.add_circle_outline,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  'Spending Transactions',
                  '${_spentTransactions.length}',
                  Icons.remove_circle_outline,
                  Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
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
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF006D77)),
            ),
            SizedBox(height: 16),
            Text('Loading points history...'),
          ],
        ),
      )
          : Column(
        children: [
          _buildHeader(),
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF006D77),
            labelColor: const Color(0xFF006D77),
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Earned'),
              Tab(text: 'Spent'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // All transactions tab
                Column(
                  children: [
                    _buildStatsCard(),
                    Expanded(
                      child: _buildTransactionsList(_allTransactions),
                    ),
                  ],
                ),
                // Earned tab
                _buildTransactionsList(_earnedTransactions),
                // Spent tab
                _buildTransactionsList(_spentTransactions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}