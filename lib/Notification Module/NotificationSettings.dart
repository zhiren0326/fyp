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
  int secondWarningHours = 2; // NEW: Second warning time
  bool deadlineNotificationsEnabled = true; // NEW: Toggle for deadline notifications
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // UPDATED: Load settings from both SharedPreferences and Firestore
  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        // Try to load from Firestore first
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
          // Fallback to SharedPreferences if Firestore data doesn't exist
          await _loadFromSharedPreferences();
          // Migrate to Firestore
          await _saveSettings();
          print('Settings migrated from SharedPreferences to Firestore');
        }
      } else {
        // No user, load from SharedPreferences only
        await _loadFromSharedPreferences();
      }
    } catch (e) {
      print('Error loading settings: $e');
      // Fallback to SharedPreferences on error
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

  // UPDATED: Save settings to both SharedPreferences and Firestore
  Future<void> _saveSettings() async {
    try {
      // Save to SharedPreferences for backup
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

      // Save to Firestore (primary storage)
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

              // Deadline Alerts - UPDATED SECTION
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
                max: 168, // 1 week
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
              if (deadlineNotificationsEnabled)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  elevation: 1,
                  color: const Color(0xFF006D77).withOpacity(0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Color(0xFF006D77), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You will receive 3 notifications: ${deadlineWarningHours}h before, ${secondWarningHours}h before, and 30 minutes before the deadline.',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: const Color(0xFF006D77),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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

              // User Role Info
              _buildSectionHeader(
                'Notification Info',
                subtitle: 'Understanding your notifications',
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                elevation: 1,
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
                            'Deadline Notifications',
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
                        '• Employees receive deadline reminders based on their preferences\n'
                            '• Employers do not receive deadline notifications for jobs they post\n'
                            '• Each user can customize their own warning times\n'
                            '• Notifications are automatically scheduled when employees are assigned to jobs',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Test Notification
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _notificationService.sendPriorityNotification(
                      title: '🔔 Test Notification',
                      body: 'This is a test notification with your current settings!',
                      taskId: 'test',
                      priority: 'high',
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Test notification sent!', style: GoogleFonts.poppins()),
                        backgroundColor: const Color(0xFF006D77),
                      ),
                    );
                  },
                  icon: const Icon(Icons.notifications_active),
                  label: Text('Send Test Notification', style: GoogleFonts.poppins()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006D77),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              // Test Deadline Notification
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: OutlinedButton.icon(
                  onPressed: deadlineNotificationsEnabled ? () async {
                    // Test deadline notification with user's current settings
                    final testDeadline = DateTime.now().add(Duration(hours: deadlineWarningHours + 1));

                    await _notificationService.scheduleDeadlineRemindersForEmployees(
                      taskId: 'test-deadline',
                      taskTitle: 'Test Deadline Task',
                      deadline: testDeadline,
                      employeeIds: [FirebaseAuth.instance.currentUser?.uid ?? ''],
                    );

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Test deadline notifications scheduled with your current settings!',
                          style: GoogleFonts.poppins(),
                        ),
                        backgroundColor: const Color(0xFF006D77),
                      ),
                    );
                  } : null,
                  icon: const Icon(Icons.schedule),
                  label: Text('Test Deadline Settings', style: GoogleFonts.poppins()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: deadlineNotificationsEnabled ? const Color(0xFF006D77) : Colors.grey,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(
                      color: deadlineNotificationsEnabled ? const Color(0xFF006D77) : Colors.grey,
                    ),
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