import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'NotificationService.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final NotificationService _notificationService = NotificationService();

  // Settings variables
  int deadlineWarningHours = 24;
  int secondWarningHours = 2;
  bool deadlineNotificationsEnabled = true;
  bool dailySummaryEnabled = true;
  bool weeklySummaryEnabled = true;
  String dailySummaryTime = '09:00';
  bool soundEnabled = true;
  bool vibrationEnabled = true;
  bool highPriorityOnly = false;

  // Additional settings
  bool taskAssignedNotifications = true;
  bool statusChangeNotifications = true;
  bool completionReviewNotifications = true;
  bool milestoneNotifications = true;

  bool _isLoading = true;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ... existing _loadSettings, _saveSettings, etc. methods remain the same ...

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
            dailySummaryEnabled = data['dailySummaryEnabled'] ?? true;
            weeklySummaryEnabled = data['weeklySummaryEnabled'] ?? true;
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
      dailySummaryEnabled = prefs.getBool('daily_summary_enabled') ?? true;
      weeklySummaryEnabled = prefs.getBool('weekly_summary_enabled') ?? true;
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
    try {
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings saved successfully', style: GoogleFonts.poppins()),
          backgroundColor: const Color(0xFF006D77),
        ),
      );
    } catch (e) {
      print('Error saving settings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving settings: $e', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ),
      );
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
    );

    if (picked != null) {
      setState(() {
        dailySummaryTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  // TEST METHODS
  Future<void> _runTestSuite() async {
    setState(() => _isTesting = true);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🧪 Running notification test suite...', style: GoogleFonts.poppins()),
          backgroundColor: const Color(0xFF006D77),
          duration: const Duration(seconds: 2),
        ),
      );

      await _notificationService.runNotificationTestSuite();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Test suite completed! Check your notifications.', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Test failed: $e', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _testUrgentNotification() async {
    try {
      await _notificationService.testUrgentNotification();
      _showTestSnackBar('🚨 Urgent notification sent!');
    } catch (e) {
      _showErrorSnackBar('Failed to send urgent notification: $e');
    }
  }

  Future<void> _testPriorityLevels() async {
    try {
      await _notificationService.testPriorityLevels();
      _showTestSnackBar('🎨 Priority level test notifications sent! (4 notifications with 3s intervals)');
    } catch (e) {
      _showErrorSnackBar('Failed to send priority test: $e');
    }
  }

  Future<void> _testDailySummary() async {
    try {
      await _notificationService.testDailySummary();
      _showTestSnackBar('📊 Daily summary test sent!');
    } catch (e) {
      _showErrorSnackBar('Failed to send daily summary: $e');
    }
  }

  Future<void> _testWeeklySummary() async {
    try {
      await _notificationService.testWeeklySummary();
      _showTestSnackBar('📈 Weekly summary test sent!');
    } catch (e) {
      _showErrorSnackBar('Failed to send weekly summary: $e');
    }
  }

  Future<void> _testScheduledNotification() async {
    try {
      await _notificationService.testScheduledNotification();
      _showTestSnackBar('⏰ Scheduled notification test created! Will arrive in 30 seconds.');
    } catch (e) {
      _showErrorSnackBar('Failed to schedule notification: $e');
    }
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
              // General Settings
              _buildSectionHeader(
                'General Settings',
                subtitle: 'Configure basic notification preferences',
              ),
              _buildSettingTile(
                title: 'Sound',
                subtitle: 'Play sound for notifications',
                value: soundEnabled,
                onChanged: (val) => setState(() => soundEnabled = val),
                icon: Icons.volume_up,
              ),
              _buildSettingTile(
                title: 'Vibration',
                subtitle: 'Vibrate for notifications',
                value: vibrationEnabled,
                onChanged: (val) => setState(() => vibrationEnabled = val),
                icon: Icons.vibration,
              ),
              _buildSettingTile(
                title: 'High Priority Only',
                subtitle: 'Only show urgent and high priority notifications',
                value: highPriorityOnly,
                onChanged: (val) => setState(() => highPriorityOnly = val),
                icon: Icons.priority_high,
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
                'Summary Notifications',
                subtitle: 'Get daily and weekly task summaries',
              ),
              _buildSettingTile(
                title: 'Daily Summary',
                subtitle: 'Receive daily task progress summary',
                value: dailySummaryEnabled,
                onChanged: (val) => setState(() => dailySummaryEnabled = val),
                icon: Icons.today,
              ),
              if (dailySummaryEnabled)
                _buildTimePicker(
                  title: 'Daily Summary Time',
                  time: dailySummaryTime,
                  onTap: _selectTime,
                ),
              _buildSettingTile(
                title: 'Weekly Summary',
                subtitle: 'Receive weekly task report every Monday',
                value: weeklySummaryEnabled,
                onChanged: (val) => setState(() => weeklySummaryEnabled = val),
                icon: Icons.date_range,
              ),

              // Task Notifications
              _buildSectionHeader(
                'Task Notifications',
                subtitle: 'Choose which task updates you want to receive',
              ),
              _buildSettingTile(
                title: 'New Task Assigned',
                subtitle: 'Notify when a new task is assigned to you',
                value: taskAssignedNotifications,
                onChanged: (val) => setState(() => taskAssignedNotifications = val),
                icon: Icons.assignment_turned_in,
              ),
              _buildSettingTile(
                title: 'Status Changes',
                subtitle: 'Notify when task status changes',
                value: statusChangeNotifications,
                onChanged: (val) => setState(() => statusChangeNotifications = val),
                icon: Icons.update,
              ),
              _buildSettingTile(
                title: 'Completion Reviews',
                subtitle: 'Notify when your task completion is reviewed',
                value: completionReviewNotifications,
                onChanged: (val) => setState(() => completionReviewNotifications = val),
                icon: Icons.rate_review,
              ),
              _buildSettingTile(
                title: 'Milestone Updates',
                subtitle: 'Notify when milestones are added or completed',
                value: milestoneNotifications,
                onChanged: (val) => setState(() => milestoneNotifications = val),
                icon: Icons.flag,
              ),

              // TESTING SECTION
              _buildSectionHeader(
                '🧪 Notification Testing',
                subtitle: 'Test different notification types and priorities',
              ),

              // Comprehensive Test Suite
              _buildTestButton(
                title: _isTesting ? 'Running Test Suite...' : 'Run Complete Test Suite',
                onPressed: _runTestSuite,
                icon: _isTesting ? Icons.hourglass_empty : Icons.science,
                enabled: !_isTesting,
              ),

              // Individual Tests
              _buildTestButton(
                title: 'Test Urgent Notification (Red + Vibration)',
                onPressed: _testUrgentNotification,
                icon: Icons.warning,
                color: Colors.red,
              ),

              _buildTestButton(
                title: 'Test Priority Levels (4 notifications)',
                onPressed: _testPriorityLevels,
                icon: Icons.layers,
                color: Colors.orange,
              ),

              _buildTestButton(
                title: 'Test Scheduled Notification (30s delay)',
                onPressed: _testScheduledNotification,
                icon: Icons.schedule,
                color: Colors.blue,
              ),

              // Summary Tests
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

              // Info Card
              Card(
                margin: const EdgeInsets.all(16),
                elevation: 2,
                color: Colors.blue.withOpacity(0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Notification Priority Guide',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '🔴 URGENT: Red color, strong vibration, stays until dismissed\n'
                            '🟡 HIGH: Orange color, medium vibration, heads-up display\n'
                            '⚪ NORMAL: Default color, standard notification\n'
                            '🔵 LOW: Minimal styling, no heads-up display\n\n'
                            '• Summary notifications are sent automatically based on your schedule\n'
                            '• Deadline reminders are personalized per user\n'
                            '• Test notifications help you see how each priority looks',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
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
      ),
    );
  }
}