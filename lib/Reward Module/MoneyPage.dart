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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('profiledetails')
          .doc('profile')
          .get();

      if (profileDoc.exists) {
        final data = profileDoc.data()!;
        setState(() {
          _totalEarnings = (data['totalEarnings'] ?? 0.0).toDouble();
        });
      }

      // Calculate this month earnings
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);

      final monthlySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('moneyHistory')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('type', isEqualTo: 'earning')
          .get();

      double thisMonth = 0.0;
      for (var doc in monthlySnapshot.docs) {
        thisMonth += (doc.data()['amount'] ?? 0.0).toDouble();
      }

      setState(() {
        _thisMonthEarnings = thisMonth;
      });

      // Calculate pending payments (completed tasks not yet paid)
      final pendingSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
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

    } catch (e) {
      print('Error loading earnings data: $e');
    }
  }

  Future<void> _loadTransactionHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('moneyHistory')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      final transactions = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();

      setState(() {
        _recentTransactions = transactions;
      });

    } catch (e) {
      print('Error loading transaction history: $e');
    }
  }

  Future<void> _loadMonthlyEarnings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      List<Map<String, dynamic>> monthlyData = [];

      // Get last 6 months data
      for (int i = 5; i >= 0; i--) {
        final month = DateTime(now.year, now.month - i, 1);
        final nextMonth = DateTime(now.year, now.month - i + 1, 1);

        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('moneyHistory')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(month))
            .where('timestamp', isLessThan: Timestamp.fromDate(nextMonth))
            .where('type', isEqualTo: 'earning')
            .get();

        double total = 0.0;
        for (var doc in snapshot.docs) {
          total += (doc.data()['amount'] ?? 0.0).toDouble();
        }

        monthlyData.add({
          'month': _getMonthName(month.month),
          'amount': total,
        });
      }

      setState(() {
        _monthlyData = monthlyData;
      });

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
        ),
        child: const Center(
          child: Text('No earnings data available'),
        ),
      );
    }

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
            'Monthly Earnings',
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
                maxY: _monthlyData.map((e) => e['amount'] as double).reduce((a, b) => a > b ? a : b) * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: const Color(0xFF006D77),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        'RM ${rod.toY.toStringAsFixed(2)}',
                        GoogleFonts.poppins(color: Colors.white),
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
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
            child: Text(
              'Recent Transactions',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_recentTransactions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('No transactions found')),
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
        description,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        timestamp != null
            ? _formatDate(timestamp.toDate())
            : 'Unknown date',
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: Colors.grey[600],
        ),
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
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildStatCard('Average per Task', 'RM ${(_totalEarnings / 5).toStringAsFixed(2)}', Icons.assignment, Colors.blue),
            const SizedBox(height: 16),
            _buildStatCard('Best Month', 'RM ${_monthlyData.isNotEmpty ? _monthlyData.map((e) => e['amount'] as double).reduce((a, b) => a > b ? a : b).toStringAsFixed(2) : '0.00'}', Icons.trending_up, Colors.green),
            const SizedBox(height: 16),
            _buildStatCard('Total Withdrawals', 'RM 0.00', Icons.money_off, Colors.red),
            const SizedBox(height: 16),
            _buildStatCard('Available Balance', 'RM ${_totalEarnings.toStringAsFixed(2)}', Icons.account_balance, Colors.purple),
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
                    fontSize: 18,
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