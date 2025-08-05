// Updated DailySummaryPage.dart - Using UserDataService for user-specific data
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'UserDataService.dart'; // Import the new service

class DailySummaryPage extends StatefulWidget {
  final Map<String, dynamic>? summaryData;
  final String? date;

  const DailySummaryPage({
    super.key,
    this.summaryData,
    this.date,
  });

  @override
  State<DailySummaryPage> createState() => _DailySummaryPageState();
}

class _DailySummaryPageState extends State<DailySummaryPage> {
  Map<String, dynamic>? _summaryData;
  bool _isLoading = true;
  String _selectedDate = '';
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.date ?? DateTime.now().toIso8601String().split('T')[0];
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
          setState(() => _isLoading = false);
        } else {
          _loadDailySummary();
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error initializing user: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDailySummary() async {
    if (_currentUserId == null) {
      print('No current user ID available');
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final selectedDateTime = DateTime.parse(_selectedDate);
      print('Loading daily summary for user: $_currentUserId on date: $_selectedDate');

      // Check if user has any data
      final hasData = await UserDataService.userHasData(_currentUserId!);
      if (!hasData) {
        print('User has no data available');
        setState(() {
          _summaryData = null;
          _isLoading = false;
        });
        return;
      }

      // Use the new service to generate user-specific summary
      final summaryData = await UserDataService.generateDailySummaryForUser(
        userId: _currentUserId!,
        date: selectedDateTime,
      );

      setState(() {
        _summaryData = summaryData;
        _isLoading = false;
      });

      print('Daily summary loaded successfully: ${summaryData['totalTasks']} tasks, ${summaryData['pointsEarned']} points');

    } catch (e) {
      print('Error loading daily summary: $e');
      setState(() {
        _summaryData = null;
        _isLoading = false;
      });

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading daily summary: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_selectedDate),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
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
        _selectedDate = picked.toIso8601String().split('T')[0];
      });
      _loadDailySummary();
    }
  }

  String _formatDate(DateTime date) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

    return '${days[date.weekday % 7]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
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
          ],
        ),
      ),
    );
  }

  Widget _buildActivityOverview() {
    if (_summaryData == null) return const SizedBox.shrink();

    final totalTasks = _summaryData!['totalTasks'] as int? ?? 0;
    final pointsEarned = _summaryData!['pointsEarned'] as int? ?? 0;
    final translationsCount = _summaryData!['translationsCount'] as int? ?? 0;
    final totalEarnings = _summaryData!['totalEarnings'] as double? ?? 0.0;
    final pointTransactions = _summaryData!['pointTransactions'] as List? ?? [];
    final totalCharacters = _summaryData!['totalCharacters'] as int? ?? 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Activity Overview',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 16),
            if (totalTasks > 0) ...[
              _buildActivityItem(
                icon: Icons.task_alt,
                title: 'Tasks Completed',
                value: '$totalTasks tasks',
                subtitle: 'Earned RM${totalEarnings.toStringAsFixed(2)}',
                color: Colors.green,
              ),
            ],
            if (pointsEarned > 0) ...[
              const SizedBox(height: 12),
              _buildActivityItem(
                icon: Icons.stars,
                title: 'Points Earned',
                value: '$pointsEarned points',
                subtitle: '${pointTransactions.length} transactions',
                color: Colors.amber[700]!,
              ),
            ],
            if (translationsCount > 0) ...[
              const SizedBox(height: 12),
              _buildActivityItem(
                icon: Icons.translate,
                title: 'Translations',
                value: '$translationsCount translations',
                subtitle: '$totalCharacters characters translated',
                color: Colors.blue,
              ),
            ],
            if (totalTasks == 0 && pointsEarned == 0 && translationsCount == 0) ...[
              Center(
                child: Column(
                  children: [
                    Icon(Icons.self_improvement, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No activities recorded for this day',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Take a well-deserved rest or plan for tomorrow!',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
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

  Widget _buildTaskBreakdown() {
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
              'Task Categories',
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

  Widget _buildDetailedTimeline() {
    if (_summaryData == null) return const SizedBox.shrink();

    final taskDetails = _summaryData!['taskDetails'] as List<Map<String, dynamic>>? ?? [];
    final pointTransactions = _summaryData!['pointTransactions'] as List<Map<String, dynamic>>? ?? [];
    final translationDetails = _summaryData!['translationDetails'] as List<Map<String, dynamic>>? ?? [];

    // Combine all activities and sort by time
    List<Widget> timelineItems = [];

    for (var task in taskDetails) {
      try {
        timelineItems.add(_buildTimelineItem(
          time: DateFormat('HH:mm').format(task['time']),
          title: task['title'],
          subtitle: 'Earned RM${(task['earnings'] as double).toStringAsFixed(2)}',
          icon: Icons.task_alt,
          color: Colors.green,
        ));
      } catch (e) {
        print('Error building task timeline item: $e');
      }
    }

    for (var point in pointTransactions) {
      try {
        timelineItems.add(_buildTimelineItem(
          time: DateFormat('HH:mm').format(point['timestamp']),
          title: point['description'],
          subtitle: '+${point['points']} points',
          icon: Icons.stars,
          color: Colors.amber[700]!,
        ));
      } catch (e) {
        print('Error building point timeline item: $e');
      }
    }

    for (var translation in translationDetails) {
      try {
        timelineItems.add(_buildTimelineItem(
          time: DateFormat('HH:mm').format(translation['timestamp']),
          title: '${translation['fromLanguage']} → ${translation['toLanguage']}',
          subtitle: '${translation['characters']} characters',
          icon: Icons.translate,
          color: Colors.blue,
        ));
      } catch (e) {
        print('Error building translation timeline item: $e');
      }
    }

    if (timelineItems.isEmpty) {
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
              'Activity Timeline',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 16),
            ...timelineItems,
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem({
    required String time,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 50,
            child: Text(
              time,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
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
            'Daily Summary',
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
              onPressed: _selectDate,
              tooltip: 'Select Date',
            ),
            if (_currentUserId != null)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadDailySummary,
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

              // Date Header
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
                        _formatDate(DateTime.parse(_selectedDate)),
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_summaryData != null) ...[
                        Text(
                          'Productivity Score: ${(_summaryData!['completionRate'] as double? ?? 0.0).toStringAsFixed(1)}%',
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
                  childAspectRatio: 1.4,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildStatCard(
                      title: 'Tasks Completed',
                      value: (_summaryData!['totalTasks'] as int? ?? 0).toString(),
                      icon: Icons.task_alt,
                      color: const Color(0xFF006D77),
                    ),
                    _buildStatCard(
                      title: 'Points Earned',
                      value: (_summaryData!['pointsEarned'] as int? ?? 0).toString(),
                      icon: Icons.stars,
                      color: Colors.amber[700]!,
                    ),
                    _buildStatCard(
                      title: 'Total Earnings',
                      value: 'RM${(_summaryData!['totalEarnings'] as double? ?? 0.0).toStringAsFixed(2)}',
                      icon: Icons.attach_money,
                      color: Colors.green,
                    ),
                    _buildStatCard(
                      title: 'Translations',
                      value: (_summaryData!['translationsCount'] as int? ?? 0).toString(),
                      icon: Icons.translate,
                      color: Colors.blue,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Activity Overview
                _buildActivityOverview(),

                const SizedBox(height: 20),

                // Task Categories
                _buildTaskBreakdown(),

                const SizedBox(height: 20),

                // Activity Timeline
                _buildDetailedTimeline(),
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
                          'No activities found for this date',
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
                          onPressed: _selectDate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF006D77),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Select Different Date',
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