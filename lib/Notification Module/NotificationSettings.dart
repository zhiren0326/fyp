import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationSettings {
  final bool taskReminders;
  final bool deadlineAlerts;
  final bool jobUpdates;
  final bool systemNotifications;
  final bool pushNotifications;
  final bool emailNotifications;
  final int reminderTimeBefore; // minutes before deadline
  final List<String> quietHours; // ["22:00", "08:00"] format
  final String priority; // all, high, critical

  NotificationSettings({
    this.taskReminders = true,
    this.deadlineAlerts = true,
    this.jobUpdates = true,
    this.systemNotifications = true,
    this.pushNotifications = true,
    this.emailNotifications = false,
    this.reminderTimeBefore = 60,
    this.quietHours = const ["22:00", "08:00"],
    this.priority = "all",
  });

  factory NotificationSettings.fromFirestore(Map<String, dynamic> data) {
    return NotificationSettings(
      taskReminders: data['taskReminders'] ?? true,
      deadlineAlerts: data['deadlineAlerts'] ?? true,
      jobUpdates: data['jobUpdates'] ?? true,
      systemNotifications: data['systemNotifications'] ?? true,
      pushNotifications: data['pushNotifications'] ?? true,
      emailNotifications: data['emailNotifications'] ?? false,
      reminderTimeBefore: data['reminderTimeBefore'] ?? 60,
      quietHours: List<String>.from(data['quietHours'] ?? ["22:00", "08:00"]),
      priority: data['priority'] ?? "all",
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'taskReminders': taskReminders,
      'deadlineAlerts': deadlineAlerts,
      'jobUpdates': jobUpdates,
      'systemNotifications': systemNotifications,
      'pushNotifications': pushNotifications,
      'emailNotifications': emailNotifications,
      'reminderTimeBefore': reminderTimeBefore,
      'quietHours': quietHours,
      'priority': priority,
    };
  }

  NotificationSettings copyWith({
    bool? taskReminders,
    bool? deadlineAlerts,
    bool? jobUpdates,
    bool? systemNotifications,
    bool? pushNotifications,
    bool? emailNotifications,
    int? reminderTimeBefore,
    List<String>? quietHours,
    String? priority,
  }) {
    return NotificationSettings(
      taskReminders: taskReminders ?? this.taskReminders,
      deadlineAlerts: deadlineAlerts ?? this.deadlineAlerts,
      jobUpdates: jobUpdates ?? this.jobUpdates,
      systemNotifications: systemNotifications ?? this.systemNotifications,
      pushNotifications: pushNotifications ?? this.pushNotifications,
      emailNotifications: emailNotifications ?? this.emailNotifications,
      reminderTimeBefore: reminderTimeBefore ?? this.reminderTimeBefore,
      quietHours: quietHours ?? this.quietHours,
      priority: priority ?? this.priority,
    );
  }
}

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  late NotificationSettings settings;
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('notifications')
          .get();

      setState(() {
        if (doc.exists) {
          settings = NotificationSettings.fromFirestore(doc.data()!);
        } else {
          settings = NotificationSettings();
        }
        isLoading = false;
      });
    } catch (e) {
      print('Error loading notification settings: $e');
      setState(() {
        settings = NotificationSettings();
        isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('notifications')
          .set(settings.toFirestore());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification settings saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error saving notification settings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving settings: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() {
      isSaving = false;
    });
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    IconData? icon,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SwitchListTile(
        title: Text(
          title,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: Colors.teal,
        secondary: icon != null ? Icon(icon, color: Colors.teal) : null,
      ),
    );
  }

  Widget _buildReminderTimeSelector() {
    final reminderOptions = [15, 30, 60, 120, 1440]; // minutes
    final reminderLabels = ["15 min", "30 min", "1 hour", "2 hours", "1 day"];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, color: Colors.teal),
                const SizedBox(width: 12),
                Text(
                  'Reminder Time',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Get reminded before task deadlines',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: reminderOptions.asMap().entries.map((entry) {
                final minutes = entry.value;
                final label = reminderLabels[entry.key];
                final isSelected = settings.reminderTimeBefore == minutes;

                return FilterChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        settings = settings.copyWith(reminderTimeBefore: minutes);
                      });
                    }
                  },
                  selectedColor: Colors.teal.withOpacity(0.3),
                  labelStyle: GoogleFonts.poppins(
                    color: isSelected ? Colors.teal[800] : Colors.grey[600],
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrioritySelector() {
    final priorityOptions = ["all", "high", "critical"];
    final priorityLabels = ["All", "High Priority", "Critical Only"];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.priority_high, color: Colors.teal),
                const SizedBox(width: 12),
                Text(
                  'Notification Priority',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Which notifications do you want to receive?',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Column(
              children: priorityOptions.asMap().entries.map((entry) {
                final priority = entry.value;
                final label = priorityLabels[entry.key];
                final isSelected = settings.priority == priority;

                return RadioListTile<String>(
                  title: Text(
                    label,
                    style: GoogleFonts.poppins(fontSize: 14),
                  ),
                  value: priority,
                  groupValue: settings.priority,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        settings = settings.copyWith(priority: value);
                      });
                    }
                  },
                  activeColor: Colors.teal,
                  contentPadding: EdgeInsets.zero,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuietHoursSelector() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bedtime, color: Colors.teal),
                const SizedBox(width: 12),
                Text(
                  'Quiet Hours',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'No notifications during these hours',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start Time',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _selectTime(0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            settings.quietHours[0],
                            style: GoogleFonts.poppins(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'End Time',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _selectTime(1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            settings.quietHours[1],
                            style: GoogleFonts.poppins(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectTime(int index) async {
    final currentTime = settings.quietHours[index];
    final timeParts = currentTime.split(':');
    final initialTime = TimeOfDay(
      hour: int.parse(timeParts[0]),
      minute: int.parse(timeParts[1]),
    );

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (selectedTime != null) {
      final formattedTime = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
      final newQuietHours = List<String>.from(settings.quietHours);
      newQuietHours[index] = formattedTime;

      setState(() {
        settings = settings.copyWith(quietHours: newQuietHours);
      });
    }
  }


  Widget _buildTestNotificationButton() {
    const SizedBox(width: 16);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Test Notifications',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a test notification to check your settings',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _sendTestNotification,
              icon: const Icon(Icons.send),
              label: const Text('Send Test Notification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .add({
        'message': 'This is a test notification to verify your settings are working correctly.',
        'title': 'Test Notification',
        'type': 'system',
        'priority': 'medium',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'data': {'isTest': true},
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test notification sent successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error sending test notification: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending test notification: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Notification Settings',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.teal,
        ),
        body: const Center(child: CircularProgressIndicator()),
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
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.teal,
          elevation: 0,
          actions: [
            if (isSaving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              )
            else
              TextButton(
                onPressed: _saveSettings,
                child: Text(
                  'Save',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // General Notification Types
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Notification Types',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal[800],
                  ),
                ),
              ),

              _buildSwitchTile(
                title: 'Task Reminders',
                subtitle: 'Get notified about upcoming tasks and deadlines',
                value: settings.taskReminders,
                onChanged: (value) {
                  setState(() {
                    settings = settings.copyWith(taskReminders: value);
                  });
                },
                icon: Icons.task_alt,
              ),

              _buildSwitchTile(
                title: 'Deadline Alerts',
                subtitle: 'Critical notifications for approaching deadlines',
                value: settings.deadlineAlerts,
                onChanged: (value) {
                  setState(() {
                    settings = settings.copyWith(deadlineAlerts: value);
                  });
                },
                icon: Icons.alarm,
              ),

              _buildSwitchTile(
                title: 'Job Updates',
                subtitle: 'Notifications about job applications and updates',
                value: settings.jobUpdates,
                onChanged: (value) {
                  setState(() {
                    settings = settings.copyWith(jobUpdates: value);
                  });
                },
                icon: Icons.work,
              ),

              _buildSwitchTile(
                title: 'System Notifications',
                subtitle: 'App updates and general system messages',
                value: settings.systemNotifications,
                onChanged: (value) {
                  setState(() {
                    settings = settings.copyWith(systemNotifications: value);
                  });
                },
                icon: Icons.info,
              ),

              const SizedBox(height: 24),

              // Delivery Methods
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Delivery Methods',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal[800],
                  ),
                ),
              ),

              _buildSwitchTile(
                title: 'Push Notifications',
                subtitle: 'Receive notifications on your device',
                value: settings.pushNotifications,
                onChanged: (value) {
                  setState(() {
                    settings = settings.copyWith(pushNotifications: value);
                  });
                },
                icon: Icons.notifications,
              ),

              _buildSwitchTile(
                title: 'Email Notifications',
                subtitle: 'Receive notifications via email',
                value: settings.emailNotifications,
                onChanged: (value) {
                  setState(() {
                    settings = settings.copyWith(emailNotifications: value);
                  });
                },
                icon: Icons.email,
              ),

              const SizedBox(height: 24),

              // Advanced Settings
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Advanced Settings',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal[800],
                  ),
                ),
              ),

              _buildReminderTimeSelector(),
              _buildPrioritySelector(),
              _buildQuietHoursSelector(),
              _buildTestNotificationButton(),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}