import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

class MoneyPage extends StatefulWidget {
  const MoneyPage({super.key});

  @override
  State<MoneyPage> createState() => _MoneyPageState();
}

class _MoneyPageState extends State<MoneyPage> with TickerProviderStateMixin {
  late TabController _tabController;
  double _totalEarnings = 0.0;
  double _thisMonthEarnings = 0.0;
  double _pendingPayments = 0.0;
  List<Map<String, dynamic>> _recentTransactions = [];
  List<Map<String, dynamic>> _monthlyData = [];
  bool _isLoading = true;
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
        print('MoneyPage - Initialized user: ${currentUser.uid}');
        _loadData();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error initializing user: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadData() async {
    if (_currentUserId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    await Future.wait([
      _loadEarningsData(),
      _loadTransactionHistory(),
      _loadMonthlyEarnings(),
    ]);
    setState(() => _isLoading = false);
  }

  Future<void> _loadEarningsData() async {
    try {
      if (_currentUserId == null) return;

      print('Loading earnings data for user: $_currentUserId');

      // Get total earnings from profile
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('profiledetails')
          .doc('profile')
          .get();

      if (profileDoc.exists) {
        final data = profileDoc.data()!;
        setState(() {
          _totalEarnings = (data['totalEarnings'] ?? 0.0).toDouble();
        });
        print('Total earnings from profile: $_totalEarnings');
      }

      // Calculate this month earnings from moneyHistory
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);

      print('Fetching monthly earnings from: $startOfMonth to: $now');

      final monthlySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('moneyHistory')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('type', isEqualTo: 'earning')
          .get();

      double thisMonth = 0.0;
      print('Found ${monthlySnapshot.docs.length} money transactions this month');

      for (var doc in monthlySnapshot.docs) {
        final docData = doc.data();
        final amount = (docData['amount'] ?? 0.0).toDouble();
        thisMonth += amount;
        print('Money transaction: ${doc.id} - Amount: $amount - Description: ${docData['description']}');
      }

      setState(() {
        _thisMonthEarnings = thisMonth;
      });

      print('This month earnings: $_thisMonthEarnings');

      // Calculate pending payments from taskProgress (if that collection exists)
      try {
        final pendingSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .collection('taskProgress')
            .where('completionApproved', isEqualTo: true)
            .where('paymentStatus', isEqualTo: 'pending')
            .get();

        double pending = 0.0;
        for (var doc in pendingSnapshot.docs) {
          pending += (doc.data()['moneyEarned'] ?? 0.0).toDouble();
        }

        setState(() {
          _pendingPayments = pending;
        });

        print('Pending payments: $_pendingPayments');
      } catch (e) {
        print('No taskProgress collection or error calculating pending: $e');
        setState(() {
          _pendingPayments = 0.0;
        });
      }

    } catch (e) {
      print('Error loading earnings data: $e');
    }
  }

  Future<void> _loadTransactionHistory() async {
    try {
      if (_currentUserId == null) return;

      print('Loading transaction history for user: $_currentUserId');

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('moneyHistory')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      final transactions = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'amount': (data['amount'] ?? 0.0).toDouble(),
          'description': data['description'] ?? 'Transaction',
          'taskTitle': data['taskTitle'] ?? 'Unknown Task',
          'type': data['type'] ?? 'earning',
          'source': data['source'] ?? 'unknown',
          'timestamp': data['timestamp'] as Timestamp?,
          ...data,
        };
      }).toList();

      setState(() {
        _recentTransactions = transactions;
      });

      print('Loaded ${transactions.length} recent transactions');

    } catch (e) {
      print('Error loading transaction history: $e');
    }
  }

  Future<void> _loadMonthlyEarnings() async {
    try {
      if (_currentUserId == null) return;

      print('Loading monthly earnings data for user: $_currentUserId');

      final now = DateTime.now();
      List<Map<String, dynamic>> monthlyData = [];

      // Get last 6 months data
      for (int i = 5; i >= 0; i--) {
        final month = DateTime(now.year, now.month - i, 1);
        final nextMonth = DateTime(now.year, now.month - i + 1, 1);

        print('Fetching data for month: ${month.month}/${month.year}');

        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .collection('moneyHistory')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(month))
            .where('timestamp', isLessThan: Timestamp.fromDate(nextMonth))
            .where('type', isEqualTo: 'earning')
            .get();

        double total = 0.0;
        print('Found ${snapshot.docs.length} transactions for ${month.month}/${month.year}');

        for (var doc in snapshot.docs) {
          final amount = (doc.data()['amount'] ?? 0.0).toDouble();
          total += amount;
          print('  Transaction: ${doc.id} - Amount: $amount');
        }

        monthlyData.add({
          'month': _getMonthName(month.month),
          'amount': total,
          'year': month.year,
          'monthNumber': month.month,
        });

        print('Month ${_getMonthName(month.month)}: RM$total');
      }

      setState(() {
        _monthlyData = monthlyData;
      });

      print('Loaded monthly data for ${monthlyData.length} months');

    } catch (e) {
      print('Error loading monthly earnings: $e');
    }
  }

  String _getMonthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month];
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
                  'My Earnings',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _loadData,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // User ID display
            if (_currentUserId != null)
              Text(
                'User: ${_currentUserId!.substring(0, 8)}...',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    'Total Earnings',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.account_balance_wallet,
                          color: Colors.amber, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'RM ${_totalEarnings.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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

  Widget _buildEarningsCards() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: _buildEarningCard(
              'This Month',
              _thisMonthEarnings,
              Icons.calendar_today,
              Colors.green,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildEarningCard(
              'Pending',
              _pendingPayments,
              Icons.pending,
              Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningCard(String title, double amount, IconData icon, Color color) {
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
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'RM ${amount.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsChart() {
    if (_monthlyData.isEmpty) {
      return Container(
        height: 200,
        margin: const EdgeInsets.symmetric(horizontal: 20),
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
        child: const Center(
          child: Text('No earnings data available'),
        ),
      );
    }

    final maxAmount = _monthlyData.map((e) => e['amount'] as double).reduce((a, b) => a > b ? a : b);

    return Container(
      height: 250,
      margin: const EdgeInsets.symmetric(horizontal: 20),
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
          Text(
            'Monthly Earnings (Last 6 Months)',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxAmount > 0 ? maxAmount * 1.2 : 100,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: const Color(0xFF006D77),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final monthData = _monthlyData[group.x.toInt()];
                      return BarTooltipItem(
                        '${monthData['month']}\nRM ${rod.toY.toStringAsFixed(2)}',
                        GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < _monthlyData.length) {
                          return Text(
                            _monthlyData[value.toInt()]['month'],
                            style: GoogleFonts.poppins(fontSize: 10),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          'RM${value.toInt()}',
                          style: GoogleFonts.poppins(fontSize: 8),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: _monthlyData.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value['amount'],
                        color: const Color(0xFF006D77),
                        width: 20,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionHistory() {
    return Container(
      margin: const EdgeInsets.all(20),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Transactions',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_recentTransactions.length} transactions',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (_recentTransactions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt_long, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      'No transactions found',
                      style: GoogleFonts.poppins(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Data source: /users/${_currentUserId?.substring(0, 8)}../moneyHistory/',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentTransactions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final transaction = _recentTransactions[index];
                return _buildTransactionItem(transaction);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] ?? 0.0).toDouble();
    final type = transaction['type'] ?? 'earning';
    final description = transaction['description'] ?? 'Transaction';
    final taskTitle = transaction['taskTitle'] ?? '';
    final timestamp = transaction['timestamp'] as Timestamp?;
    final isEarning = type == 'earning';

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isEarning ? Colors.green[100] : Colors.red[100],
          shape: BoxShape.circle,
        ),
        child: Icon(
          isEarning ? Icons.add : Icons.remove,
          color: isEarning ? Colors.green : Colors.red,
          size: 20,
        ),
      ),
      title: Text(
        taskTitle.isNotEmpty ? taskTitle : description,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (taskTitle.isNotEmpty && taskTitle != description)
            Text(
              description,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          Text(
            timestamp != null
                ? _formatDate(timestamp.toDate())
                : 'Unknown date',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
      trailing: Text(
        '${isEarning ? '+' : '-'}RM ${amount.toStringAsFixed(2)}',
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isEarning ? Colors.green : Colors.red,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildEarningsCards(),
          _buildEarningsChart(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildTransactionHistory(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStatsTab() {
    // Calculate stats from actual data
    final totalTransactions = _recentTransactions.length;
    final averagePerTransaction = totalTransactions > 0 ? _totalEarnings / totalTransactions : 0.0;
    final bestMonth = _monthlyData.isNotEmpty
        ? _monthlyData.reduce((a, b) => (a['amount'] as double) > (b['amount'] as double) ? a : b)
        : null;
    final bestMonthAmount = bestMonth != null ? bestMonth['amount'] as double : 0.0;
    final bestMonthName = bestMonth != null ? bestMonth['month'] as String : 'N/A';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildStatCard(
                'Average per Transaction',
                'RM ${averagePerTransaction.toStringAsFixed(2)}',
                Icons.analytics,
                Colors.blue
            ),
            const SizedBox(height: 16),
            _buildStatCard(
                'Best Month',
                '$bestMonthName: RM ${bestMonthAmount.toStringAsFixed(2)}',
                Icons.trending_up,
                Colors.green
            ),
            const SizedBox(height: 16),
            _buildStatCard(
                'Total Transactions',
                '$totalTransactions transactions',
                Icons.receipt_long,
                Colors.purple
            ),
            const SizedBox(height: 16),
            _buildStatCard(
                'This Month Progress',
                'RM ${_thisMonthEarnings.toStringAsFixed(2)}',
                Icons.calendar_month,
                Colors.orange
            ),
            const SizedBox(height: 16),
            _buildStatCard(
                'Available Balance',
                'RM ${_totalEarnings.toStringAsFixed(2)}',
                Icons.account_balance,
                const Color(0xFF006D77)
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: double.infinity,
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
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
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF006D77)),
            ),
            SizedBox(height: 16),
            Text('Loading money data...'),
          ],
        ),
      )
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
                    Tab(text: 'Overview'),
                    Tab(text: 'History'),
                    Tab(text: 'Stats'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(),
                      _buildTransactionsTab(),
                      _buildStatsTab(),
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