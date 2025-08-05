// Updated WeeklySummaryPage.dart - Using UserDataService for user-specific data
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'UserDataService.dart'; // Import the new service

class WeeklySummaryPage extends StatefulWidget {
  final Map<String, dynamic>? summaryData;
  final String? weekStart;

  const WeeklySummaryPage({
    super.key,
    this.summaryData,
    this.weekStart,
  });

  @override
  State<WeeklySummaryPage> createState() => _WeeklySummaryPageState();
}

class _WeeklySummaryPageState extends State<WeeklySummaryPage> {
  Map<String, dynamic>? _summaryData;
  bool _isLoading = true;
  DateTime _selectedWeekStart = DateTime.now();
  List<Map<String, dynamic>> _dailyBreakdown = [];
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    if (widget.weekStart != null) {
      _selectedWeekStart = DateTime.parse(widget.weekStart!);
    } else {
      _selectedWeekStart = _getWeekStart(DateTime.now());
    }
    _initializeUser();
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

        print('Initialized user: ${currentUser.uid}');

        if (widget.summaryData != null) {
          _summaryData = widget.summaryData;
          _dailyBreakdown = widget.summaryData?['dailyBreakdown'] ?? [];
          setState(() => _isLoading = false);
        } else {
          _loadWeeklySummary();
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error initializing user: $e');
      setState(() => _isLoading = false);
    }
  }

  DateTime _getWeekStart(DateTime date) {
    final daysFromMonday = (date.weekday - 1) % 7;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: daysFromMonday));
  }

  Future<void> _loadWeeklySummary() async {
    if (_currentUserId == null) {
      print('No current user ID available');
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('Loading weekly summary for user: $_currentUserId starting $_selectedWeekStart');

      // Check if user has any data
      final hasData = await UserDataService.userHasData(_currentUserId!);
      if (!hasData) {
        print('User has no data available');
        setState(() {
          _summaryData = null;
          _dailyBreakdown = [];
          _isLoading = false;
        });
        return;
      }

      // Use the new service to generate user-specific summary
      final summaryData = await UserDataService.generateWeeklySummaryForUser(
        userId: _currentUserId!,
        weekStart: _selectedWeekStart,
      );

      setState(() {
        _summaryData = summaryData;
        _dailyBreakdown = summaryData['dailyBreakdown'] as List<Map<String, dynamic>>? ?? [];
        _isLoading = false;
      });

      print('Weekly summary loaded successfully: ${summaryData['totalTasks']} tasks, ${summaryData['totalPoints']} points');

    } catch (e) {
      print('Error loading weekly summary: $e');
      setState(() {
        _summaryData = null;
        _dailyBreakdown = [];
        _isLoading = false;
      });

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading weekly summary: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectWeek() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedWeekStart,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      helpText: 'Select any day in the week',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF006D77),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedWeekStart = _getWeekStart(picked);
      });
      _loadWeeklySummary();
    }
  }

  String _formatWeekRange(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    if (weekStart.month == weekEnd.month) {
      return '${months[weekStart.month - 1]} ${weekStart.day} - ${weekEnd.day}, ${weekStart.year}';
    } else {
      return '${months[weekStart.month - 1]} ${weekStart.day} - ${months[weekEnd.month - 1]} ${weekEnd.day}, ${weekStart.year}';
    }
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    double? progress,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDailyChart() {
    if (_dailyBreakdown.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Progress',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}%',
                            style: GoogleFonts.poppins(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < _dailyBreakdown.length) {
                            final dayName = _dailyBreakdown[value.toInt()]['dayName'] as String? ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                dayName.length >= 3 ? dayName.substring(0, 3) : dayName,
                                style: GoogleFonts.poppins(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: 6,
                  minY: 0,
                  maxY: 100,
                  lineBarsData: [
                    LineChartBarData(
                      spots: _dailyBreakdown.asMap().entries.map((entry) {
                        final completionRate = entry.value['completionRate'] as double? ?? 0.0;
                        return FlSpot(entry.key.toDouble(), completionRate);
                      }).toList(),
                      isCurved: true,
                      color: const Color(0xFF006D77),
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF006D77).withOpacity(0.1),
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

  Widget _buildPointsChart() {
    if (_dailyBreakdown.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Points Earned',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: GoogleFonts.poppins(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < _dailyBreakdown.length) {
                            final dayName = _dailyBreakdown[value.toInt()]['dayName'] as String? ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                dayName.length >= 3 ? dayName.substring(0, 3) : dayName,
                                style: GoogleFonts.poppins(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _dailyBreakdown.asMap().entries.map((entry) {
                    final points = entry.value['points'] as int? ?? 0;
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: points.toDouble(),
                          color: Colors.amber[700],
                          width: 20,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
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
      ),
    );
  }

  Widget _buildEarningsChart() {
    if (_dailyBreakdown.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Earnings',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            'RM${value.toInt()}',
                            style: GoogleFonts.poppins(fontSize: 9),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < _dailyBreakdown.length) {
                            final dayName = _dailyBreakdown[value.toInt()]['dayName'] as String? ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                dayName.length >= 3 ? dayName.substring(0, 3) : dayName,
                                style: GoogleFonts.poppins(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _dailyBreakdown.asMap().entries.map((entry) {
                    final earnings = entry.value['earnings'] as double? ?? 0.0;
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: earnings,
                          color: Colors.green[600],
                          width: 20,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
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
      ),
    );
  }

  Widget _buildDailyBreakdown() {
    if (_dailyBreakdown.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Breakdown',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 16),
            ..._dailyBreakdown.map((day) => _buildDayItem(day)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDayItem(Map<String, dynamic> day) {
    final date = day['date'] as DateTime? ?? DateTime.now();
    final isToday = date.day == DateTime.now().day &&
        date.month == DateTime.now().month &&
        date.year == DateTime.now().year;

    final completedTasks = day['completedTasks'] as int? ?? 0;
    final totalTasks = day['totalTasks'] as int? ?? 0;
    final points = day['points'] as int? ?? 0;
    final earnings = day['earnings'] as double? ?? 0.0;
    final translations = day['translations'] as int? ?? 0;
    final completionRate = day['completionRate'] as double? ?? 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isToday ? const Color(0xFF006D77).withOpacity(0.1) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: isToday ? Border.all(color: const Color(0xFF006D77), width: 1) : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day['dayName'] as String? ?? 'Unknown',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isToday ? const Color(0xFF006D77) : Colors.black87,
                  ),
                ),
                Text(
                  '${date.day}/${date.month}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$completedTasks tasks',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (earnings > 0) ...[
                  Text(
                    'RM${earnings.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.green[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (translations > 0) ...[
                  Text(
                    '$translations translations',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: Colors.blue[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.stars, size: 14, color: Colors.amber[700]),
                    const SizedBox(width: 4),
                    Text(
                      points.toString(),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber[700],
                      ),
                    ),
                  ],
                ),
                Text(
                  '${completionRate.toStringAsFixed(0)}%',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsCard() {
    if (_summaryData == null) return const SizedBox.shrink();

    final completionRate = _summaryData!['completionRate'] as double? ?? 0.0;
    final averageDailyCompletion = _summaryData!['averageDailyCompletion'] as double? ?? 0.0;
    final averageDailyEarnings = _summaryData!['averageDailyEarnings'] as double? ?? 0.0;
    final mostProductiveDay = _summaryData!['mostProductiveDay'] as String? ?? 'N/A';
    final totalPoints = _summaryData!['totalPoints'] as int? ?? 0;
    final totalEarnings = _summaryData!['totalEarnings'] as double? ?? 0.0;
    final translationsCount = _summaryData!['translationsCount'] as int? ?? 0;

    String performanceEmoji = completionRate >= 90 ? '🏆' :
    completionRate >= 70 ? '🌟' :
    completionRate >= 50 ? '👍' : '💪';

    String motivationalMessage = completionRate >= 90 ? 'Excellent work this week!' :
    completionRate >= 70 ? 'Great progress this week!' :
    completionRate >= 50 ? 'Good effort, keep it up!' :
    'Every step counts, keep going!';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF006D77).withOpacity(0.1),
              const Color(0xFF006D77).withOpacity(0.05),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  performanceEmoji,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  'Weekly Insights',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF006D77),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              motivationalMessage,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            _buildInsightRow('Average daily completion', '${averageDailyCompletion.toStringAsFixed(1)}%'),
            _buildInsightRow('Most productive day', mostProductiveDay),
            _buildInsightRow('Total points earned', '$totalPoints points'),
            _buildInsightRow('Total earnings', 'RM${totalEarnings.toStringAsFixed(2)}'),
            _buildInsightRow('Average daily earnings', 'RM${averageDailyEarnings.toStringAsFixed(2)}'),
            if (translationsCount > 0)
              _buildInsightRow('Translations completed', '$translationsCount translations'),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightRow(String label, String value, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isWarning ? Colors.red : const Color(0xFF006D77),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown() {
    if (_summaryData == null) return const SizedBox.shrink();

    final tasksByCategory = _summaryData!['tasksByCategory'] as Map<String, int>? ?? <String, int>{};

    if (tasksByCategory.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Task Categories This Week',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 16),
            ...tasksByCategory.entries.map((entry) => _buildCategoryItem(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryItem(String category, int count) {
    final colors = {
      'Translation': Colors.blue,
      'Development': Colors.green,
      'Design': Colors.purple,
      'Research': Colors.orange,
      'Writing': Colors.teal,
      'General': Colors.grey,
    };

    final color = colors[category] ?? Colors.grey;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            category,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              count.toString(),
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
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
          title: Text(
            'Weekly Summary',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: _selectWeek,
              tooltip: 'Select Week',
            ),
            if (_currentUserId != null)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadWeeklySummary,
                tooltip: 'Refresh Data',
              ),
          ],
        ),
        body: _isLoading
            ? const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF006D77)),
          ),
        )
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Info Card
              if (_currentUserId != null)
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.person, color: Colors.grey[600], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'User: ${_currentUserId!.substring(0, 8)}...',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Week Header
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF006D77), Color(0xFF00838F)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatWeekRange(_selectedWeekStart),
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_summaryData != null) ...[
                        Text(
                          'Overall Completion: ${(_summaryData!['completionRate'] as double? ?? 0.0).toStringAsFixed(1)}%',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: (_summaryData!['completionRate'] as double? ?? 0.0) / 100,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Statistics Grid
              if (_summaryData != null) ...[
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildStatCard(
                      title: 'Total Tasks',
                      value: (_summaryData!['totalTasks'] as int? ?? 0).toString(),
                      icon: Icons.assignment,
                      color: const Color(0xFF006D77),
                    ),
                    _buildStatCard(
                      title: 'Completed',
                      value: (_summaryData!['completedTasks'] as int? ?? 0).toString(),
                      icon: Icons.check_circle,
                      color: Colors.green,
                      progress: (_summaryData!['completionRate'] as double? ?? 0.0),
                    ),
                    _buildStatCard(
                      title: 'Total Points',
                      value: (_summaryData!['totalPoints'] as int? ?? 0).toString(),
                      icon: Icons.stars,
                      color: Colors.amber[700]!,
                    ),
                    _buildStatCard(
                      title: 'Total Earnings',
                      value: 'RM${(_summaryData!['totalEarnings'] as double? ?? 0.0).toStringAsFixed(0)}',
                      icon: Icons.attach_money,
                      color: Colors.green[600]!,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Insights Card
                _buildInsightsCard(),

                const SizedBox(height: 20),

                // Daily Progress Chart
                _buildDailyChart(),

                const SizedBox(height: 20),

                // Points Chart
                _buildPointsChart(),

                const SizedBox(height: 20),

                // Earnings Chart
                _buildEarningsChart(),

                const SizedBox(height: 20),

                // Task Categories
                _buildCategoryBreakdown(),

                const SizedBox(height: 20),

                // Daily Breakdown
                _buildDailyBreakdown(),
              ] else ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No data available for this week',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _currentUserId != null
                              ? 'User: ${_currentUserId!.substring(0, 8)}...'
                              : 'No user logged in',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _selectWeek,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF006D77),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Select Different Week',
                            style: GoogleFonts.poppins(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}