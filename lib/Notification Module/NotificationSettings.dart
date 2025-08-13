// Updated NotificationSettingsPage.dart - Removed Task Notifications, Priority Filter, and most testing methods
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'NotificationService.dart';
import 'UserDataService.dart'; // Import the updated service

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final NotificationService _notificationService = NotificationService();

  // Settings variables (removed general settings)
  int deadlineWarningHours = 24;
  int secondWarningHours = 2;
  bool deadlineNotificationsEnabled = true;
  bool dailySummaryEnabled = true;
  bool weeklySummaryEnabled = true;
  String dailySummaryTime = '09:00';
  bool highPriorityOnly = false;

  // Additional settings (keep in state but don't show in UI)
  bool taskAssignedNotifications = true;
  bool statusChangeNotifications = true;
  bool completionReviewNotifications = true;
  bool milestoneNotifications = true;

  // Keep soundEnabled and vibrationEnabled for compatibility but don't show in UI
  bool soundEnabled = true;
  bool vibrationEnabled = true;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
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
        await _loadSettings();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error initializing user: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final firestoreDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('preferences')
            .doc('notifications')
            .get();

        if (firestoreDoc.exists) {
          final data = firestoreDoc.data()!;
          setState(() {
            deadlineWarningHours = data['deadlineWarningHours'] ?? 24;
            secondWarningHours = data['secondWarningHours'] ?? 2;
            deadlineNotificationsEnabled = data['deadlineNotificationsEnabled'] ?? true;
            dailySummaryEnabled = data['dailySummaryEnabled'] ?? false; // Default to false for new users
            weeklySummaryEnabled = data['weeklySummaryEnabled'] ?? false; // Default to false for new users
            dailySummaryTime = data['dailySummaryTime'] ?? '09:00';
            soundEnabled = data['soundEnabled'] ?? true;
            vibrationEnabled = data['vibrationEnabled'] ?? true;
            highPriorityOnly = data['highPriorityOnly'] ?? false;
            taskAssignedNotifications = data['taskAssignedNotifications'] ?? true;
            statusChangeNotifications = data['statusChangeNotifications'] ?? true;
            completionReviewNotifications = data['completionReviewNotifications'] ?? true;
            milestoneNotifications = data['milestoneNotifications'] ?? true;
          });
          print('Settings loaded from Firestore');
        } else {
          await _loadFromSharedPreferences();
          await _saveSettings();
          print('Settings migrated from SharedPreferences to Firestore');
        }
      } else {
        await _loadFromSharedPreferences();
      }
    } catch (e) {
      print('Error loading settings: $e');
      await _loadFromSharedPreferences();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      deadlineWarningHours = prefs.getInt('deadline_warning_hours') ?? 24;
      secondWarningHours = prefs.getInt('second_warning_hours') ?? 2;
      deadlineNotificationsEnabled = prefs.getBool('deadline_notifications_enabled') ?? true;
      dailySummaryEnabled = prefs.getBool('daily_summary_enabled') ?? false;
      weeklySummaryEnabled = prefs.getBool('weekly_summary_enabled') ?? false;
      dailySummaryTime = prefs.getString('daily_summary_time') ?? '09:00';
      soundEnabled = prefs.getBool('sound_enabled') ?? true;
      vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
      highPriorityOnly = prefs.getBool('high_priority_only') ?? false;
      taskAssignedNotifications = prefs.getBool('task_assigned_notifications') ?? true;
      statusChangeNotifications = prefs.getBool('status_change_notifications') ?? true;
      completionReviewNotifications = prefs.getBool('completion_review_notifications') ?? true;
      milestoneNotifications = prefs.getBool('milestone_notifications') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return; // Prevent multiple saves

    setState(() => _isSaving = true);

    try {
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('deadline_warning_hours', deadlineWarningHours);
      await prefs.setInt('second_warning_hours', secondWarningHours);
      await prefs.setBool('deadline_notifications_enabled', deadlineNotificationsEnabled);
      await prefs.setBool('daily_summary_enabled', dailySummaryEnabled);
      await prefs.setBool('weekly_summary_enabled', weeklySummaryEnabled);
      await prefs.setString('daily_summary_time', dailySummaryTime);
      await prefs.setBool('sound_enabled', soundEnabled);
      await prefs.setBool('vibration_enabled', vibrationEnabled);
      await prefs.setBool('high_priority_only', highPriorityOnly);
      await prefs.setBool('task_assigned_notifications', taskAssignedNotifications);
      await prefs.setBool('status_change_notifications', statusChangeNotifications);
      await prefs.setBool('completion_review_notifications', completionReviewNotifications);
      await prefs.setBool('milestone_notifications', milestoneNotifications);

      // Save to Firestore and reinitialize notification service
      await _notificationService.saveNotificationPreferences(
        deadlineWarningHours: deadlineWarningHours,
        secondWarningHours: secondWarningHours,
        deadlineNotificationsEnabled: deadlineNotificationsEnabled,
        dailySummaryEnabled: dailySummaryEnabled,
        weeklySummaryEnabled: weeklySummaryEnabled,
        dailySummaryTime: dailySummaryTime,
        soundEnabled: soundEnabled,
        vibrationEnabled: vibrationEnabled,
        highPriorityOnly: highPriorityOnly,
        taskAssignedNotifications: taskAssignedNotifications,
        statusChangeNotifications: statusChangeNotifications,
        completionReviewNotifications: completionReviewNotifications,
        milestoneNotifications: milestoneNotifications,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Settings saved and notification timers updated!', style: GoogleFonts.poppins()),
            backgroundColor: const Color(0xFF006D77),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error saving settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error saving settings: $e', style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _selectTime() async {
    final timeParts = dailySummaryTime.split(':');
    final initialTime = TimeOfDay(
      hour: int.parse(timeParts[0]),
      minute: int.parse(timeParts[1]),
    );

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
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
        dailySummaryTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });

      // Show immediate feedback about the time change
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Daily summary time set to $dailySummaryTime. Save settings to apply!', style: GoogleFonts.poppins()),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatCurrentDate() {
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[now.month - 1]} ${now.day}';
  }

  // TEST METHODS - Keep only daily and weekly summary tests (FIXED to not interfere with automatic system)
  Future<void> _testDailySummary() async {
    try {
      if (_currentUserId == null) {
        _showErrorSnackBar('No user ID available');
        return;
      }

      _showTestSnackBar('📊 Testing daily summary...');

      // Create a test notification that doesn't interfere with the automatic system
      await _notificationService.createFirestoreNotification(
        userId: _currentUserId!,
        title: '📊 TEST: Daily Summary - ${_formatCurrentDate()}',
        body: '🧪 This is a test daily summary notification. Today: 5/8 tasks completed • 250 points earned!',
        data: {
          'type': 'daily_summary',
          'date': DateTime.now().toIso8601String(),
          'totalTasks': 8,
          'completedTasks': 5,
          'inProgressTasks': 2,
          'pendingTasks': 1,
          'pointsEarned': 250,
          'totalEarnings': 120.0,
          'completionRate': 62.5,
          'isTest': true, // Mark as test
          'isManualTest': true,
        },
        priority: NotificationPriority.low,
        sendImmediately: true,
      );

      _showTestSnackBar('✅ Daily summary test sent successfully!');
    } catch (e) {
      _showErrorSnackBar('Failed to send daily summary: $e');
    }
  }

  Future<void> _testWeeklySummary() async {
    try {
      if (_currentUserId == null) {
        _showErrorSnackBar('No user ID available');
        return;
      }

      _showTestSnackBar('📈 Testing weekly summary...');

      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);

      // Create a test notification that doesn't interfere with the automatic system
      await _notificationService.createFirestoreNotification(
        userId: _currentUserId!,
        title: '📈 TEST: Weekly Summary - Week of ${_formatDate(weekStartDate)}',
        body: '🧪 This is a test weekly summary. This week: 18/25 tasks completed (72.0% rate) • 900 points earned!',
        data: {
          'type': 'weekly_summary',
          'weekStart': weekStartDate.toIso8601String(),
          'weekEnd': weekStartDate.add(const Duration(days: 7)).toIso8601String(),
          'totalTasks': 25,
          'completedTasks': 18,
          'totalPoints': 900,
          'totalEarnings': 540.0,
          'completionRate': 72.0,
          'isTest': true, // Mark as test
          'isManualTest': true,
        },
        priority: NotificationPriority.low,
        sendImmediately: true,
      );

      _showTestSnackBar('✅ Weekly summary test sent successfully!');
    } catch (e) {
      _showErrorSnackBar('Failed to send weekly summary: $e');
    }
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }

  void _showTestSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: const Color(0xFF006D77),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF006D77),
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
    );
  }

  Widget _buildSettingTile({
    required String title,
    String? subtitle,
    required bool value,
    required Function(bool) onChanged,
    IconData? icon,
    bool enabled = true,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        enabled: enabled,
        leading: icon != null
            ? Icon(icon, color: enabled ? const Color(0xFF006D77) : Colors.grey)
            : null,
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            color: enabled ? null : Colors.grey,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
            subtitle,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: enabled ? null : Colors.grey,
            )
        )
            : null,
        trailing: Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeColor: const Color(0xFF006D77),
        ),
      ),
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required int value,
    required int min,
    required int max,
    required Function(int) onChanged,
    String Function(int)? format,
    bool enabled = true,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    color: enabled ? null : Colors.grey,
                  ),
                ),
                Text(
                  format != null ? format(value) : value.toString(),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: enabled ? const Color(0xFF006D77) : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: enabled ? (val) => onChanged(val.round()) : null,
              activeColor: const Color(0xFF006D77),
              inactiveColor: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker({
    required String title,
    required String time,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        enabled: enabled,
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            color: enabled ? null : Colors.grey,
          ),
        ),
        subtitle: Text(
          'Current time: $time ${dailySummaryEnabled ? "(Active)" : "(Inactive)"}',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: dailySummaryEnabled ? const Color(0xFF006D77) : Colors.grey,
            fontWeight: dailySummaryEnabled ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        trailing: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (enabled ? const Color(0xFF006D77) : Colors.grey).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: enabled ? const Color(0xFF006D77) : Colors.grey,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: enabled ? const Color(0xFF006D77) : Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTestButton({
    required String title,
    required VoidCallback onPressed,
    required IconData icon,
    Color? color,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
        label: Text(title, style: GoogleFonts.poppins()),
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? const Color(0xFF006D77),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: enabled ? 2 : 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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
              'Notification Settings',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
            ),
            backgroundColor: const Color(0xFF006D77),
            elevation: 0,
          ),
          body: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF006D77)),
            ),
          ),
        ),
      );
    }

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
            'Notification Settings',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
          ),
          backgroundColor: const Color(0xFF006D77),
          elevation: 0,
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 2,
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saveSettings,
                tooltip: 'Save Settings',
              ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Info Card
              if (_currentUserId != null)
                Card(
                  margin: const EdgeInsets.all(16),
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
                        const Spacer(),
                        Icon(
                          _notificationService.isInitialized ? Icons.check_circle : Icons.error,
                          color: _notificationService.isInitialized ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _notificationService.isInitialized ? 'Service Ready' : 'Service Error',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: _notificationService.isInitialized ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Deadline Alerts
              _buildSectionHeader(
                'Deadline Alerts',
                subtitle: 'Customize when you receive deadline warnings (employees only)',
              ),
              _buildSettingTile(
                title: 'Deadline Notifications',
                subtitle: 'Enable/disable all deadline warning notifications',
                value: deadlineNotificationsEnabled,
                onChanged: (val) => setState(() => deadlineNotificationsEnabled = val),
                icon: Icons.schedule,
              ),
              _buildSliderSetting(
                title: 'Primary Deadline Warning',
                value: deadlineWarningHours,
                min: 1,
                max: 168,
                onChanged: (val) => setState(() => deadlineWarningHours = val),
                format: (val) => val > 24 ? '${(val / 24).toStringAsFixed(1)} days before' : '$val hours before',
                enabled: deadlineNotificationsEnabled,
              ),
              _buildSliderSetting(
                title: 'Urgent Warning',
                value: secondWarningHours,
                min: 1,
                max: 24,
                onChanged: (val) => setState(() => secondWarningHours = val),
                format: (val) => '$val hours before',
                enabled: deadlineNotificationsEnabled,
              ),

              // Summary Notifications
              _buildSectionHeader(
                '📊 Summary Notifications',
                subtitle: 'Get automatic daily and weekly progress reports',
              ),

              // Enhanced Daily Summary Section
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    _buildSettingTile(
                      title: 'Daily Summary',
                      subtitle: 'Receive daily task progress summary automatically',
                      value: dailySummaryEnabled,
                      onChanged: (val) => setState(() => dailySummaryEnabled = val),
                      icon: Icons.today,
                    ),
                    if (dailySummaryEnabled) ...[
                      const Divider(height: 1),
                      _buildTimePicker(
                        title: 'Daily Summary Time',
                        time: dailySummaryTime,
                        onTap: _selectTime,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '💡 Summary will be sent automatically every day at $dailySummaryTime if you have activity data.',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              _buildSettingTile(
                title: 'Weekly Summary',
                subtitle: 'Receive weekly task report every Monday morning',
                value: weeklySummaryEnabled,
                onChanged: (val) => setState(() => weeklySummaryEnabled = val),
                icon: Icons.date_range,
              ),

              // Summary Testing Section
              _buildSectionHeader(
                '🧪 Summary Testing',
                subtitle: 'Test summary notifications',
              ),

              Row(
                children: [
                  Expanded(
                    child: _buildTestButton(
                      title: 'Test Daily Summary',
                      onPressed: _testDailySummary,
                      icon: Icons.today,
                      color: Colors.green,
                    ),
                  ),
                  Expanded(
                    child: _buildTestButton(
                      title: 'Test Weekly Summary',
                      onPressed: _testWeeklySummary,
                      icon: Icons.date_range,
                      color: Colors.purple,
                    ),
                  ),
                ],
              ),

              // Clear All Notifications
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Clear All Notifications?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        content: Text(
                          'This will cancel all scheduled notifications. You can reconfigure them anytime.',
                          style: GoogleFonts.poppins(),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('Cancel', style: GoogleFonts.poppins()),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              await _notificationService.clearAllNotifications();
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('All notifications cleared', style: GoogleFonts.poppins()),
                                  backgroundColor: const Color(0xFF006D77),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: Text('Clear All', style: GoogleFonts.poppins(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.clear_all),
                  label: Text('Clear All Notifications', style: GoogleFonts.poppins()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
        // Floating save button for easy access
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isSaving ? null : _saveSettings,
          backgroundColor: _isSaving ? Colors.grey : const Color(0xFF006D77),
          icon: _isSaving
              ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
          )
              : const Icon(Icons.save, color: Colors.white),
          label: Text(
            _isSaving ? 'Saving...' : 'Save Settings',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
        ),
      ),
    );
  }
}