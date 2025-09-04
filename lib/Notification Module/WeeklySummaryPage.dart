// Fixed WeeklySummaryPage.dart - Corrected user authentication and data fetching
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'UserDataService.dart';

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
  String? _errorMessage;

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

  // FIXED: Proper user authentication without creating new anonymous users
  Future<void> _initializeUser() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;

      // Don't create anonymous users - use existing authenticated user
      if (currentUser == null) {
        print('ERROR: No authenticated user found');
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please log in first to view weekly summary';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please log in first to view weekly summary'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _currentUserId = currentUser.uid;
      });

      print('=== WEEKLY SUMMARY DEBUG INFO ===');
      print('Current User ID: ${currentUser.uid}');
      print('Expected User ID (from Firebase): N84HVhnPOQeSmozIVDuckPfMfua2');
      print('User IDs match: ${currentUser.uid ==
          "N84HVhnPOQeSmozIVDuckPfMfua2"}');
      print('Selected week start: $_selectedWeekStart');
      print('Week end: ${_selectedWeekStart.add(const Duration(days: 7))}');

      // IMPORTANT: If they don't match, this is the problem!
      if (currentUser.uid != "N84HVhnPOQeSmozIVDuckPfMfua2") {
        print(
            'WARNING: Current user is different from the user with data in Firebase!');
        print('You need to authenticate as user N84HVhnPOQeSmozIVDuckPfMfua2');
      }
      print('===================================');

      // Check if user has data before proceeding
      final userDataSummary = await UserDataService.getUserDataSummary(
          currentUser.uid);
      print('User data summary: $userDataSummary');

      final hasData = userDataSummary['dataAvailable'] as bool? ?? false;
      print('User has data: $hasData');

      if (!hasData) {
        print('User ${currentUser.uid} has no data available');
        setState(() {
          _summaryData = null;
          _dailyBreakdown = [];
          _isLoading = false;
          _errorMessage =
          'No data found for current user. Make sure you are logged in as the correct user.';
        });
        return;
      }

      if (widget.summaryData != null) {
        _summaryData = widget.summaryData;
        _dailyBreakdown = widget.summaryData?['dailyBreakdown'] ?? [];
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        await _loadWeeklySummary();
      }
    } catch (e) {
      print('Error initializing user: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error initializing user: ${e.toString()}';
      });
    }
  }

  DateTime _getWeekStart(DateTime date) {
    final daysFromMonday = (date.weekday - 1) % 7;
    return DateTime(date.year, date.month, date.day).subtract(
        Duration(days: daysFromMonday));
  }

  // _loadWeeklySummary with better error handling and debugging
  Future<void> _loadWeeklySummary() async {
    if (_currentUserId == null) {
      print('No current user ID available');
      setState(() {
        _isLoading = false;
        _errorMessage = 'No user ID available';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('=== LOADING WEEKLY SUMMARY ===');
      print('User ID: $_currentUserId');
      print('Week start: $_selectedWeekStart');
      print('Week end: ${_selectedWeekStart.add(const Duration(days: 7))}');

      // First, let's debug what data is actually available
      await _debugDataFetching();

      // Check if user has any data first
      final userDataSummary = await UserDataService.getUserDataSummary(
          _currentUserId!);
      print('User data summary: $userDataSummary');

      if (!(userDataSummary['dataAvailable'] as bool? ?? false)) {
        print('User has no data available');
        setState(() {
          _summaryData = null;
          _dailyBreakdown = [];
          _isLoading = false;
          _errorMessage = 'No data found for this user';
        });
        return;
      }

      // Generate weekly summary
      print('Generating weekly summary...');
      final summaryData = await UserDataService.generateWeeklySummaryForUser(
        userId: _currentUserId!,
        weekStart: _selectedWeekStart,
      );

      print('=== WEEKLY SUMMARY RESULTS ===');
      print('Summary data received: ${summaryData.isNotEmpty}');
      print('Total tasks: ${summaryData['totalTasks']}');
      print('Total points: ${summaryData['totalPoints']}');
      print('Total earnings: ${summaryData['totalEarnings']}');
      print('Daily breakdown length: ${(summaryData['dailyBreakdown'] as List?)
          ?.length ?? 0}');
      print('User name: ${summaryData['userName']}');

      if (summaryData.containsKey('error')) {
        print('Error in summary data: ${summaryData['error']}');
      }
      print('================================');

      setState(() {
        _summaryData = summaryData;
        _dailyBreakdown =
            summaryData['dailyBreakdown'] as List<Map<String, dynamic>>? ?? [];
        _isLoading = false;
        _errorMessage = summaryData.containsKey('error')
            ? summaryData['error'] as String?
            : null;
      });

      // logging
      final totalTasks = summaryData['totalTasks'] as int? ?? 0;
      final totalPoints = summaryData['totalPoints'] as int? ?? 0;
      final totalEarnings = summaryData['totalEarnings'] as double? ?? 0.0;
      final userName = summaryData['userName'] as String? ?? 'User';
      final completionRate = summaryData['completionRate'] as double? ?? 0.0;

      print('Weekly summary loaded successfully:');
      print('  - Tasks: $totalTasks');
      print('  - Points: $totalPoints');
      print('  - Earnings: RM${totalEarnings.toStringAsFixed(2)}');
      print('  - Completion: ${completionRate.toStringAsFixed(1)}%');
      print('  - User: $userName');
    } catch (e) {
      print('ERROR loading weekly summary: $e');
      print('Stack trace: ${StackTrace.current}');

      setState(() {
        _summaryData = null;
        _dailyBreakdown = [];
        _isLoading = false;
        _errorMessage = 'Error loading weekly summary: ${e.toString()}';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading weekly summary: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Debug method to check what data is actually available
  Future<void> _debugDataFetching() async {
    if (_currentUserId == null) return;

    try {
      print('=== DEBUG DATA FETCHING ===');

      // Test points history
      final pointsData = await UserDataService.fetchUserPointsHistory(
        userId: _currentUserId!,
        startDate: _selectedWeekStart,
        endDate: _selectedWeekStart.add(const Duration(days: 7)),
      );
      print('Points data fetched: ${pointsData.length} records');
      for (var point in pointsData.take(3)) { // Show first 3 records
        print(
            '  - ${point['taskTitle']}: ${point['points']} points at ${point['timestamp']}');
      }

      // Test money history
      final moneyData = await UserDataService.fetchUserMoneyHistory(
        userId: _currentUserId!,
        startDate: _selectedWeekStart,
        endDate: _selectedWeekStart.add(const Duration(days: 7)),
      );
      print('Money data fetched: ${moneyData.length} records');
      for (var money in moneyData.take(3)) { // Show first 3 records
        print(
            '  - ${money['taskTitle']}: RM${money['amount']} at ${money['timestamp']}');
      }

      // Test profile
      final profile = await UserDataService.fetchUserProfileDetails(
          userId: _currentUserId!);
      print('Profile data: ${profile != null ? 'Found' : 'Not found'}');
      if (profile != null) {
        print('  - Name: ${profile['name']}');
        print('  - Total Points: ${profile['totalPoints']}');
        print('  - Total Earnings: ${profile['totalEarnings']}');
      }

      print('========================');
    } catch (e) {
      print('Debug data fetching error: $e');
    }
  }

  Widget _buildWeekNavigationCard() {
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.date_range, color: Colors.blue[600], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Week Selection',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[600],
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.chevron_left, color: Colors.grey[600]),
                  onPressed: () {
                    setState(() {
                      _selectedWeekStart =
                          _selectedWeekStart.subtract(const Duration(days: 7));
                    });
                    _loadWeeklySummary();
                  },
                  tooltip: 'Previous Week',
                ),
                IconButton(
                  icon: Icon(
                      Icons.calendar_today, color: const Color(0xFF006D77)),
                  onPressed: _selectWeek,
                  tooltip: 'Select Week',
                ),
                IconButton(
                  icon: Icon(
                      Icons.chevron_right,
                      color: _selectedWeekStart.add(const Duration(days: 7))
                          .isBefore(DateTime.now())
                          ? Colors.grey[600]
                          : Colors.grey[300]
                  ),
                  onPressed: _selectedWeekStart.add(const Duration(days: 7))
                      .isBefore(DateTime.now())
                      ? () {
                    setState(() {
                      _selectedWeekStart =
                          _selectedWeekStart.add(const Duration(days: 7));
                    });
                    _loadWeeklySummary();
                  }
                      : null,
                  tooltip: 'Next Week',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _formatWeekRange(_selectedWeekStart),
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatDate(weekEnd)} (${_getDaysAgo(
                  _selectedWeekStart)} ago)',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDaysAgo(DateTime weekStart) {
    final now = DateTime.now();
    final currentWeekStart = _getWeekStart(now);
    final diffDays = currentWeekStart
        .difference(weekStart)
        .inDays;

    if (diffDays == 0) return 'This week';
    if (diffDays == 7) return '1 week';
    if (diffDays < 30) return '${(diffDays / 7).round()} weeks';
    if (diffDays < 365) return '${(diffDays / 30).round()} months';
    return '${(diffDays / 365).round()} years';
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }

  // error display
  Widget _buildErrorState() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              'Unable to Load Data',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.red[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_currentUserId != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  children: [
                    Text(
                      'Debug Info:',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Current User: $_currentUserId',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.blue[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'Expected User: N84HVhnPOQeSmozIVDuckPfMfua2',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.blue[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _loadWeeklySummary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006D77),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Retry',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => _debugDataFetching(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF006D77)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Debug Data',
                    style: GoogleFonts.poppins(color: const Color(0xFF006D77)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
      return '${months[weekStart.month - 1]} ${weekStart.day} - ${weekEnd
          .day}, ${weekStart.year}';
    } else {
      return '${months[weekStart.month - 1]} ${weekStart.day} - ${months[weekEnd
          .month - 1]} ${weekEnd.day}, ${weekStart.year}';
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

  Widget _buildUserProfileHeader() {
    if (_summaryData == null) return const SizedBox.shrink();

    final profileData = _summaryData!['profileData'] as Map<String, dynamic>?;
    final userName = _summaryData!['userName'] as String? ?? 'User';

    return Card(
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
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$userName\'s Weekly Summary',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        _formatWeekRange(_selectedWeekStart),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Overall Completion: ${(_summaryData!['completionRate'] as double? ??
                  0.0).toStringAsFixed(1)}%',
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
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.calendar_view_week_outlined, size: 64,
                color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No weekly data found',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'No activities found for the week of ${_formatWeekRange(
                  _selectedWeekStart)}',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_currentUserId != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  children: [
                    Text(
                      'Checked Collections:',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'pointsHistory • moneyHistory • profiledetails',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.blue[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
                const SizedBox(width: 12),
                if (_currentUserId != null)
                  OutlinedButton(
                    onPressed: _loadWeeklySummary,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF006D77)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Retry',
                      style: GoogleFonts.poppins(
                          color: const Color(0xFF006D77)),
                    ),
                  ),
              ],
            ),
          ],
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
            // Debug button for development
            IconButton(
              icon: const Icon(Icons.bug_report),
              onPressed: _debugDataFetching,
              tooltip: 'Debug Data',
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
              // Week Navigation
              _buildWeekNavigationCard(),

              const SizedBox(height: 16),

              // Show error state if there's an error
              if (_errorMessage != null) ...[
                _buildErrorState(),
              ] else
                if (_summaryData != null) ...[
                  // User Profile Header
                  _buildUserProfileHeader(),

                  const SizedBox(height: 20),

                  // Statistics Grid
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
                        value: (_summaryData!['totalTasks'] as int? ?? 0)
                            .toString(),
                        icon: Icons.assignment,
                        color: const Color(0xFF006D77),
                      ),
                      _buildStatCard(
                        title: 'Completed',
                        value: (_summaryData!['completedTasks'] as int? ?? 0)
                            .toString(),
                        icon: Icons.check_circle,
                        color: Colors.green,
                        progress: (_summaryData!['completionRate'] as double? ??
                            0.0),
                      ),
                      _buildStatCard(
                        title: 'Total Points',
                        value: (_summaryData!['totalPoints'] as int? ?? 0)
                            .toString(),
                        icon: Icons.stars,
                        color: Colors.amber[700]!,
                      ),
                      _buildStatCard(
                        title: 'Total Earnings',
                        value: 'RM${(_summaryData!['totalEarnings'] as double? ??
                            0.0).toStringAsFixed(0)}',
                        icon: Icons.attach_money,
                        color: Colors.green[600]!,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Debug Info Card (for development)
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Debug Information',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Current User: $_currentUserId',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          Text(
                            'Week: ${_formatWeekRange(_selectedWeekStart)}',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          Text(
                            'Data Quality: ${_summaryData?['dataQuality']?['pointsRecords'] ??
                                0} points, ${_summaryData?['dataQuality']?['moneyRecords'] ??
                                0} money, ${_summaryData?['dataQuality']?['uniqueTasks'] ??
                                0} unique tasks',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                ] else
                  ...[
                    // Empty state
                    _buildEmptyState(),
                  ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}