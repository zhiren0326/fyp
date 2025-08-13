import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class RedemptionHistoryPage extends StatefulWidget {
  const RedemptionHistoryPage({super.key});

  @override
  State<RedemptionHistoryPage> createState() => _RedemptionHistoryPageState();
}

class _RedemptionHistoryPageState extends State<RedemptionHistoryPage> with TickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allRedemptions = [];
  List<Map<String, dynamic>> _pendingRedemptions = [];
  List<Map<String, dynamic>> _processedRedemptions = [];
  List<Map<String, dynamic>> _deliveredRedemptions = [];
  bool _isLoading = true;
  int _totalRedemptions = 0;
  int _totalPointsSpent = 0;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
        print('RedemptionHistory - Initialized user: ${currentUser.uid}');
        _loadRedemptionHistory();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error initializing user: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRedemptionHistory() async {
    if (_currentUserId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('Loading redemption history for user: $_currentUserId');

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('redemptions')
          .orderBy('timestamp', descending: true)
          .get();

      List<Map<String, dynamic>> allRedemptions = [];
      List<Map<String, dynamic>> pendingRedemptions = [];
      List<Map<String, dynamic>> processedRedemptions = [];
      List<Map<String, dynamic>> deliveredRedemptions = [];

      int totalPointsSpent = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final pointsSpent = (data['pointsSpent'] ?? 0) as int;
        final status = data['status'] as String? ?? 'pending';
        final timestamp = data['timestamp'] as Timestamp?;

        final redemption = {
          'id': doc.id,
          'itemId': data['itemId'] ?? '',
          'itemName': data['itemName'] ?? 'Unknown Item',
          'pointsSpent': pointsSpent,
          'status': status,
          'timestamp': timestamp?.toDate() ?? DateTime.now(),
          'redemptionCode': data['redemptionCode'] ?? '',
          'category': data['category'] ?? 'unknown',
          'description': data['description'] ?? '',
          ...data,
        };

        allRedemptions.add(redemption);
        totalPointsSpent += pointsSpent;

        switch (status.toLowerCase()) {
          case 'pending':
            pendingRedemptions.add(redemption);
            break;
          case 'processed':
            processedRedemptions.add(redemption);
            break;
          case 'delivered':
            deliveredRedemptions.add(redemption);
            break;
        }
      }

      setState(() {
        _allRedemptions = allRedemptions;
        _pendingRedemptions = pendingRedemptions;
        _processedRedemptions = processedRedemptions;
        _deliveredRedemptions = deliveredRedemptions;
        _totalRedemptions = allRedemptions.length;
        _totalPointsSpent = totalPointsSpent;
        _isLoading = false;
      });

      print('Loaded ${allRedemptions.length} redemptions - Total points spent: $totalPointsSpent');

    } catch (e) {
      print('Error loading redemption history: $e');
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
                  'Redemption History',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _loadRedemptionHistory,
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
            // Summary Cards
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Total Redemptions',
                    _totalRedemptions.toString(),
                    Icons.card_giftcard,
                    Colors.amber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Points Spent',
                    _totalPointsSpent.toString(),
                    Icons.stars,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Pending',
                    _pendingRedemptions.length.toString(),
                    Icons.pending,
                    Colors.orange,
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

  Widget _buildRedemptionsList(List<Map<String, dynamic>> redemptions) {
    if (redemptions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(
                Icons.card_giftcard_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No redemptions found',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your redeemed rewards will appear here',
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
      itemCount: redemptions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final redemption = redemptions[index];
        return _buildRedemptionCard(redemption);
      },
    );
  }

  Widget _buildRedemptionCard(Map<String, dynamic> redemption) {
    final itemName = redemption['itemName'] as String;
    final pointsSpent = redemption['pointsSpent'] as int;
    final status = redemption['status'] as String;
    final description = redemption['description'] as String? ?? '';
    final category = redemption['category'] as String? ?? 'unknown';
    final redemptionCode = redemption['redemptionCode'] as String? ?? '';

    // Handle both DateTime and Timestamp types
    DateTime timestamp;
    final timestampData = redemption['timestamp'];
    if (timestampData is DateTime) {
      timestamp = timestampData;
    } else if (timestampData is Timestamp) {
      timestamp = timestampData.toDate();
    } else {
      timestamp = DateTime.now();
    }

    Color statusColor = _getStatusColor(status);
    IconData categoryIcon = _getCategoryIcon(category);
    Color categoryColor = _getCategoryColor(category);

    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(categoryIcon, color: categoryColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getStatusDisplayName(status),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.stars, size: 16, color: Colors.amber[700]),
                    const SizedBox(width: 4),
                    Text(
                      '$pointsSpent points',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                DateFormat('MMM dd, yyyy').format(timestamp),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
          if (redemptionCode.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Redemption Code',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          redemptionCode,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF006D77),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _copyToClipboard(redemptionCode),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF006D77).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.copy,
                        size: 16,
                        color: Color(0xFF006D77),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (status.toLowerCase() == 'pending') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your redemption is being processed. You will receive an email with further instructions.',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'processed':
        return Colors.blue;
      case 'delivered':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStatusDisplayName(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'processed':
        return 'Processed';
      case 'delivered':
        return 'Delivered';
      default:
        return status.toUpperCase();
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'gift_cards':
        return Icons.card_giftcard;
      case 'entertainment':
        return Icons.local_movies;
      case 'vouchers':
        return Icons.local_offer;
      case 'subscriptions':
        return Icons.subscriptions;
      case 'transportation':
        return Icons.local_taxi;
      case 'beverages':
        return Icons.local_cafe;
      case 'food':
        return Icons.restaurant;
      default:
        return Icons.redeem;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'gift_cards':
        return const Color(0xFFFF6B35);
      case 'entertainment':
        return const Color(0xFF8E44AD);
      case 'vouchers':
        return const Color(0xFF27AE60);
      case 'subscriptions':
        return const Color(0xFFE74C3C);
      case 'transportation':
        return const Color(0xFF00D4AA);
      case 'beverages':
        return const Color(0xFF8B4513);
      case 'food':
        return const Color(0xFFFF9500);
      default:
        return const Color(0xFF006D77);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Redemption code copied to clipboard',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: const Color(0xFF006D77),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildStatsCard() {
    final avgPointsPerRedemption = _totalRedemptions > 0
        ? (_totalPointsSpent / _totalRedemptions).round()
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
            'Redemption Statistics',
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
                  'Avg. Points',
                  '$avgPointsPerRedemption pts',
                  Icons.analytics,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  'Delivered',
                  '${_deliveredRedemptions.length}',
                  Icons.check_circle,
                  Colors.green,
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
            Text('Loading redemption history...'),
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
            isScrollable: true,
            tabs: [
              Tab(text: 'All (${_allRedemptions.length})'),
              Tab(text: 'Pending (${_pendingRedemptions.length})'),
              Tab(text: 'Processed (${_processedRedemptions.length})'),
              Tab(text: 'Delivered (${_deliveredRedemptions.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // All redemptions tab
                Column(
                  children: [
                    _buildStatsCard(),
                    Expanded(
                      child: _buildRedemptionsList(_allRedemptions),
                    ),
                  ],
                ),
                // Pending tab
                _buildRedemptionsList(_pendingRedemptions),
                // Processed tab
                _buildRedemptionsList(_processedRedemptions),
                // Delivered tab
                _buildRedemptionsList(_deliveredRedemptions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}