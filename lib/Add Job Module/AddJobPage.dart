import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../Notification Module/NotificationService.dart';
import 'LocationPickerPage.dart';

class AddJobPage extends StatefulWidget {
  final String? jobId;
  final Map<String, dynamic>? initialData;

  const AddJobPage({super.key, this.jobId, this.initialData});

  @override
  State<AddJobPage> createState() => _AddJobPageState();
}

class _AddJobPageState extends State<AddJobPage> {
  bool isShortTerm = true;
  bool isRecurring = false;
  bool isTimeBlocked = false;

  // recurring task features
  String recurringFrequency = 'daily';
  TimeOfDay recurringTime = TimeOfDay(hour: 9, minute: 0);
  DateTime? recurringEndDate;

  String selectedPriority = 'Medium';

  final Map<String, TextEditingController> controllers = {
    'Job position*': TextEditingController(),
    'Type of workplace*': TextEditingController(),
    'Job location*': TextEditingController(),
    'Employer/Company Name*': TextEditingController(),
    'Employment type*': TextEditingController(),
    'Salary (RM)*': TextEditingController(),
    'Description': TextEditingController(),
    'Required Skill*': TextEditingController(),
    'Start date*': TextEditingController(),
    'Start time*': TextEditingController(),
    'End date*': TextEditingController(),
    'End time*': TextEditingController(),
    'Required People*': TextEditingController(),
  };

  final Set<String> visibleInputs = {};

  final List<String> workplaceOptions = ["On-site", "Remote", "Hybrid"];
  final List<String> employmentOptions = [
    "Full-time",
    "Part-time",
    "Contract",
    "Temporary",
    "Internship"
  ];
  final List<String> priorityLevels = ["Low", "Medium", "High", "Critical"];
  final List<String> frequencyOptions = ["hourly", "daily", "weekly", "monthly", "yearly"];

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _populateFromInitialData();
    }
  }

  void _populateFromInitialData() {
    final data = widget.initialData!;
    controllers['Job position*']?.text = data['jobPosition'] ?? '';
    controllers['Type of workplace*']?.text = data['workplaceType'] ?? '';
    controllers['Job location*']?.text = data['location'] ?? '';
    controllers['Employer/Company Name*']?.text = data['employerName'] ?? '';
    controllers['Employment type*']?.text = data['employmentType'] ?? '';
    controllers['Salary (RM)*']?.text = data['salary']?.toString() ?? '';
    controllers['Description']?.text = data['description'] ?? '';
    controllers['Required Skill*']?.text = data['requiredSkill'] is List
        ? (data['requiredSkill'] as List).join(', ')
        : data['requiredSkill']?.toString() ?? '';
    controllers['Start date*']?.text = data['startDate'] ?? '';
    controllers['Start time*']?.text = data['startTime'] ?? '';
    controllers['End date*']?.text = data['endDate'] ?? '';
    controllers['End time*']?.text = data['endTime'] ?? '';
    controllers['Required People*']?.text = data['requiredPeople']?.toString() ?? '1';

    // features
    isShortTerm = data['isShortTerm'] ?? true;
    isRecurring = data['recurring'] ?? false;
    selectedPriority = data['priority'] ?? 'Medium';
    isTimeBlocked = data['isTimeBlocked'] ?? false;

    // Recurring features
    recurringFrequency = data['recurringFrequency'] ?? 'daily';
    if (data['recurringTime'] != null) {
      final timeParts = data['recurringTime'].split(':');
      recurringTime = TimeOfDay(
        hour: int.tryParse(timeParts[0]) ?? 9,
        minute: int.tryParse(timeParts[1]) ?? 0,
      );
    }
    recurringEndDate = data['recurringEndDate'] != null
        ? DateTime.tryParse(data['recurringEndDate'])
        : null;

    visibleInputs.addAll(controllers.keys.where((key) => (controllers[key]?.text ?? '').isNotEmpty));
  }

  @override
  void dispose() {
    controllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _submitJob() async {
    print('=== _submitJob started ===');
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      _showSnackBar('User not authenticated.');
      return;
    }

    if (!_validateDeadlines()) return;

    if (!_isFormValid()) {
      _showSnackBar('Please fill out all required fields with (*) sign.');
      return;
    }

    if (!isShortTerm && isRecurring) {
      _showSnackBar('Long-term jobs cannot be set as recurring.');
      return;
    }

    final startDateTime = _parseDateTime(controllers['Start date*']?.text ?? '', controllers['Start time*']?.text ?? '');
    if (startDateTime != null && startDateTime.isBefore(DateTime.now())) {
      _showSnackBar('Start date and time cannot be in the past.');
      return;
    }

    if (isShortTerm) {
      final endDateTime = _parseDateTime(controllers['End date*']?.text ?? '', controllers['End time*']?.text ?? '');
      if (startDateTime == null || endDateTime == null || startDateTime.isAfter(endDateTime)) {
        _showSnackBar('Start date and time must be earlier than end date and time.');
        return;
      }
    }

    final requiredPeople = int.tryParse(controllers['Required People*']?.text ?? '1') ?? 1;
    if (requiredPeople < 1) {
      _showSnackBar('Required people must be at least 1.');
      return;
    }

    final jobData = _buildJobData(currentUser.uid, requiredPeople);

    try {
      DocumentReference docRef;
      final jobTitle = controllers['Job position*']?.text ?? 'New Job';
      print('Job title: $jobTitle');

      if (widget.jobId != null) {
        // Updating existing job
        print('Updating existing job: ${widget.jobId}');
        docRef = FirebaseFirestore.instance.collection('jobs').doc(widget.jobId);
        await docRef.update(jobData);
        _showSnackBar('Job updated successfully!');

        if (isShortTerm) {
          await _updateTaskProgress(docRef.id, true);
        }
      } else {
        // Creating new job
        print('Creating new job...');
        docRef = await FirebaseFirestore.instance.collection('jobs').add(jobData);
        await docRef.update({'jobId': docRef.id});
        print('Job created with ID: ${docRef.id}');

        _showSnackBar('Job posted successfully!');

        // Create notification in Firestore - this will trigger the listener to send it
        print('Creating job creation notification in Firestore...');
        await NotificationService().showJobCreatedNotificationToAllUsers(
          jobId: docRef.id,
          jobTitle: jobTitle,
          jobLocation: controllers['Job location*']?.text ?? '',
          employmentType: controllers['Employment type*']?.text ?? '',
          salary: double.tryParse(controllers['Salary (RM)*']?.text ?? '0') ?? 0.0,
        );
        print('Job creation notification created in Firestore');

        if (isShortTerm) {
          await _createTaskProgress(docRef.id, currentUser.uid);
        }

        // Handle recurring tasks
        if (isRecurring) {
          await _setupRecurringTask(docRef.id, jobData);
        }

        // UPDATED: Schedule deadline notifications only for employees with user preferences
        if (isShortTerm) {
          final endDateTime = _parseDateTime(controllers['End date*']?.text ?? '', controllers['End time*']?.text ?? '');
          if (endDateTime != null) {
            print('Scheduling deadline notifications for employees in Firestore...');

            // Get the list of employees who will be assigned to this job
            // For now, we'll use the acceptedApplicants field, but you might want to
            // wait until employees are actually assigned
            final jobDoc = await docRef.get();
            final jobData = jobDoc.data() as Map<String, dynamic>;
            final List<String> employeeIds = List<String>.from(jobData['acceptedApplicants'] ?? []);

            // If no employees assigned yet, you might want to store this for later
            // or handle it when employees are assigned
            if (employeeIds.isNotEmpty) {
              await NotificationService().scheduleDeadlineRemindersForEmployees(
                taskId: docRef.id,
                taskTitle: jobTitle,
                deadline: endDateTime,
                employeeIds: employeeIds,
                employerUserId: currentUser.uid, // Employer won't get notifications
              );
              print('Deadline notifications scheduled for ${employeeIds.length} employees');
            } else {
              // Store the deadline info for later when employees are assigned
              await docRef.update({
                'pendingDeadlineSetup': {
                  'deadline': endDateTime.toIso8601String(),
                  'taskTitle': jobTitle,
                  'needsDeadlineNotifications': true,
                }
              });
              print('Deadline info stored for later employee assignment');
            }
          }
        }
      }

      await _logActivity(widget.jobId != null ? 'Updated' : 'Created', docRef.id);
      print('=== _submitJob completed successfully ===');
      Navigator.pop(context, docRef.id);
    } catch (e) {
      print('Error in _submitJob: $e');
      _showSnackBar('Failed to ${widget.jobId != null ? 'update' : 'post'} job: $e');
    }
  }

  Map<String, dynamic> _buildJobData(String userId, int requiredPeople) {
    final baseData = {
      'jobPosition': controllers['Job position*']?.text ?? '',
      'workplaceType': controllers['Type of workplace*']?.text ?? '',
      'location': controllers['Job location*']?.text ?? '',
      'employerName': controllers['Employer/Company Name*']?.text ?? '',
      'employmentType': controllers['Employment type*']?.text ?? '',
      'salary': int.tryParse(controllers['Salary (RM)*']?.text ?? '0') ?? 0,
      'description': controllers['Description']?.text ?? '',
      'requiredSkill': (controllers['Required Skill*']?.text ?? '').split(',').map((s) => s.trim()).toList(),
      'startDate': controllers['Start date*']?.text ?? '',
      'startTime': isShortTerm ? controllers['Start time*']?.text : null,
      'endDate': isShortTerm ? controllers['End date*']?.text : null,
      'endTime': isShortTerm ? controllers['End time*']?.text : null,
      'recurring': isRecurring,
      'isShortTerm': isShortTerm,
      'requiredPeople': requiredPeople,
      'applicants': [],
      'acceptedApplicants': [],
      'isCompleted': false,
      'postedAt': widget.jobId == null ? Timestamp.now() : FieldValue.serverTimestamp(),
      'postedBy': userId,
      'jobCreator': userId,
      // task management
      'priority': selectedPriority,
      'isTimeBlocked': isTimeBlocked,
      'progressPercentage': 0,
      'milestones': [],
      'estimatedDuration': _calculateEstimatedDuration(),
      'actualDuration': null,
      'deadlineReminders': _createDeadlineReminders(),
    };

    // Add recurring-specific fields
    if (isRecurring) {
      baseData.addAll({
        'recurringFrequency': recurringFrequency,
        'recurringTime': '${recurringTime.hour.toString().padLeft(2, '0')}:${recurringTime.minute.toString().padLeft(2, '0')}',
        'recurringEndDate': recurringEndDate?.toIso8601String(),
        'nextOccurrence': _calculateNextOccurrence().toIso8601String(),
        'lastGenerated': null,
      });
    }

    return baseData;
  }

  Future<void> setupDeadlineNotificationsForNewEmployees({
    required String jobId,
    required List<String> newEmployeeIds,
  }) async {
    try {
      // Get job details
      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(jobId)
          .get();

      if (!jobDoc.exists) return;

      final jobData = jobDoc.data() as Map<String, dynamic>;
      final pendingDeadline = jobData['pendingDeadlineSetup'];

      if (pendingDeadline != null && pendingDeadline['needsDeadlineNotifications'] == true) {
        final deadline = DateTime.parse(pendingDeadline['deadline']);
        final taskTitle = pendingDeadline['taskTitle'] ?? 'Task';
        final employerUserId = jobData['postedBy'];

        print('Setting up deadline notifications for newly assigned employees: $newEmployeeIds');

        await NotificationService().scheduleDeadlineRemindersForEmployees(
          taskId: jobId,
          taskTitle: taskTitle,
          deadline: deadline,
          employeeIds: newEmployeeIds,
          employerUserId: employerUserId,
        );

        // Mark as processed
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(jobId)
            .update({
          'pendingDeadlineSetup.needsDeadlineNotifications': false,
          'pendingDeadlineSetup.processedAt': FieldValue.serverTimestamp(),
        });

        print('Deadline notifications set up for ${newEmployeeIds.length} new employees');
      }
    } catch (e) {
      print('Error setting up deadline notifications for new employees: $e');
    }
  }

  Future<void> acceptJobApplication(String jobId, String employeeId) async {
    try {
      final jobRef = FirebaseFirestore.instance.collection('jobs').doc(jobId);

      // Add employee to accepted applicants
      await jobRef.update({
        'acceptedApplicants': FieldValue.arrayUnion([employeeId])
      });

      // Get job details for deadline notifications
      final jobDoc = await jobRef.get();
      final jobData = jobDoc.data() as Map<String, dynamic>;

      // Set up deadline notifications for this new employee with their preferences
      if (jobData['isShortTerm'] == true && jobData['endDate'] != null && jobData['endTime'] != null) {
        final endDateTime = _parseDateTime(jobData['endDate'], jobData['endTime']);
        if (endDateTime != null) {
          await NotificationService().scheduleDeadlineRemindersForEmployees(
            taskId: jobId,
            taskTitle: jobData['jobPosition'] ?? 'Task',
            deadline: endDateTime,
            employeeIds: [employeeId],
            employerUserId: jobData['postedBy'],
          );
          print('Deadline notifications scheduled for employee $employeeId');
        }
      }

      // Send assignment notification to the employee
      await NotificationService().sendRealTimeNotification(
        userId: employeeId,
        title: '🎉 Job Assignment Confirmed!',
        body: 'You have been assigned to a new job. Check your tasks for details.',
        data: {
          'type': NotificationService.typeTaskAssigned,
          'jobId': jobId,
        },
        priority: NotificationPriority.high,
      );

      print('Employee $employeeId accepted and notifications set up');
    } catch (e) {
      print('Error accepting job application: $e');
    }
  }

  Future<void> _setupRecurringTask(String jobId, Map<String, dynamic> jobData) async {
    try {
      // Update the job document with recurring information
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(jobId)
          .update({
        'isRecurringParent': true,
        'recurringInstances': [],
      });

      if (isRecurring) {
        // Get the job position from the controller
        final jobPosition = controllers['Job position*']?.text ?? 'Task';

        // Schedule notifications for recurring tasks using Firestore
        final nextOccurrence = _calculateNextOccurrence();
        await NotificationService().createFirestoreNotification(
          userId: FirebaseAuth.instance.currentUser!.uid,
          title: '🔄 Recurring Task',
          body: '$jobPosition is scheduled to run again',
          data: {
            'type': 'recurring_task',
            'taskId': jobId,
          },
          priority: NotificationPriority.normal,
          sendImmediately: false,
          scheduledFor: nextOccurrence,
        );
      }
      _showSnackBar('Recurring job setup completed!');
    } catch (e) {
      print('Error setting up recurring task: $e');
    }
  }

  DateTime _calculateNextOccurrence() {
    final startDate = DateTime.tryParse(controllers['Start date*']?.text ?? '') ?? DateTime.now();

    switch (recurringFrequency) {
      case 'hourly':
        return DateTime(startDate.year, startDate.month, startDate.day,
            recurringTime.hour, recurringTime.minute).add(const Duration(hours: 1));
      case 'daily':
        return DateTime(startDate.year, startDate.month, startDate.day + 1,
            recurringTime.hour, recurringTime.minute);
      case 'weekly':
        return DateTime(startDate.year, startDate.month, startDate.day + 7,
            recurringTime.hour, recurringTime.minute);
      case 'monthly':
        return DateTime(startDate.year, startDate.month + 1, startDate.day,
            recurringTime.hour, recurringTime.minute);
      case 'yearly':
        return DateTime(startDate.year + 1, startDate.month, startDate.day,
            recurringTime.hour, recurringTime.minute);
      default:
        return DateTime(startDate.year, startDate.month, startDate.day + 1,
            recurringTime.hour, recurringTime.minute);
    }
  }

  bool _validateDeadlines() {
    if ((controllers['Start date*']?.text ?? '').isEmpty) {
      _showSnackBar('Start date is required.');
      return false;
    }

    final startDate = DateTime.tryParse(controllers['Start date*']?.text ?? '');
    if (startDate == null) {
      _showSnackBar('Invalid start date format.');
      return false;
    }

    if (isShortTerm && (controllers['End date*']?.text ?? '').isNotEmpty) {
      final endDate = DateTime.tryParse(controllers['End date*']?.text ?? '');
      if (endDate == null) {
        _showSnackBar('Invalid end date format.');
        return false;
      }
      if (endDate.isBefore(startDate)) {
        _showSnackBar('End date must be after start date.');
        return false;
      }
    }

    if (isRecurring && recurringEndDate != null && recurringEndDate!.isBefore(startDate)) {
      _showSnackBar('Recurring end date must be after start date.');
      return false;
    }

    return true;
  }

  int _calculateEstimatedDuration() {
    if (!isShortTerm) return 0;

    final startDate = DateTime.tryParse(controllers['Start date*']?.text ?? '');
    final endDate = DateTime.tryParse(controllers['End date*']?.text ?? '');

    if (startDate != null && endDate != null) {
      return endDate.difference(startDate).inDays;
    }
    return 0;
  }

  List<Map<String, dynamic>> _createDeadlineReminders() {
    List<Map<String, dynamic>> reminders = [];

    if ((controllers['Start date*']?.text ?? '').isNotEmpty) {
      final startDate = DateTime.tryParse(controllers['Start date*']?.text ?? '');
      if (startDate != null) {
        reminders.add({
          'type': 'start_reminder',
          'reminderDate': startDate.subtract(const Duration(days: 1)).toIso8601String(),
          'message': 'Task "${controllers['Job position*']?.text ?? 'Task'}" starts tomorrow',
          'sent': false,
        });
      }
    }
    return reminders;
  }

  Future<void> _createTaskProgress(String jobId, String jobCreatorId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('taskProgress')
          .doc(jobId)
          .set({
        'taskId': jobId,
        'taskTitle': controllers['Job position*']?.text ?? 'Task',
        'currentProgress': 0,
        'milestones': [],
        'createdAt': Timestamp.now(),
        'lastUpdated': Timestamp.now(),
        'status': 'created',
        'jobCreator': jobCreatorId,
        'canEditProgress': [jobCreatorId],
      });
    } catch (e) {
      print('Error creating task progress: $e');
    }
  }

  Future<void> _updateTaskProgress(String jobId, bool isUpdate) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('taskProgress')
          .doc(jobId)
          .update({
        'taskTitle': controllers['Job position*']?.text ?? 'Task',
        'lastUpdated': Timestamp.now(),
        'status': 'updated',
      });
    } catch (e) {
      print('Error updating task progress: $e');
    }
  }

  Future<void> _logActivity(String action, String taskId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('activityLog')
          .add({
        'action': action,
        'taskId': taskId,
        'taskTitle': controllers['Job position*']?.text ?? 'Task',
        'timestamp': Timestamp.now(),
        'details': {
          'priority': selectedPriority,
          'isRecurring': isRecurring,
          'recurringFrequency': isRecurring ? recurringFrequency : null,
          'isTimeBlocked': isTimeBlocked,
        }
      });
    } catch (e) {
      print('Error logging activity: $e');
    }
  }

  DateTime? _parseDateTime(String dateStr, String timeStr) {
    try {
      if (dateStr.isEmpty || timeStr.isEmpty) return null;

      final dateParts = dateStr.split('-');
      if (dateParts.length != 3) return null;
      final timeParts = timeStr.split(':');
      if (timeParts.length != 2) return null;

      final hour = int.parse(timeParts[0].replaceAll(RegExp(r'[^0-9]'), ''));
      final minute = int.parse(timeParts[1].replaceAll(RegExp(r'[^0-9]'), ''));
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      final period = timeStr.contains('PM') && hour != 12 ? 12 : (timeStr.contains('AM') && hour == 12 ? -12 : 0);
      final adjustedHour = (hour + period) % 24;

      return DateTime(year, month, day, adjustedHour, minute);
    } catch (e) {
      print('Error parsing date-time: $e');
      return null;
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF006D77),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _checkFirestoreNotifications() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('No authenticated user');
        return;
      }

      // Print all notifications in Firestore
      final notifications = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      print('=== Firestore Notifications (${notifications.docs.length}) ===');
      for (var doc in notifications.docs) {
        final data = doc.data();
        print('ID: ${doc.id}');
        print('Title: ${data['title']}');
        print('Body: ${data['body']}');
        print('Sent: ${data['sent']}');
        print('Priority: ${data['priority']}');
        print('Timestamp: ${data['timestamp']}');
        print('---');
      }

      _showSnackBar('Check console for notification details');
    } catch (e) {
      print('Error checking Firestore notifications: $e');
      _showSnackBar('Error: $e');
    }
  }

  // UI Widgets
  Widget _buildRecurringSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))],
        border: isRecurring ? Border.all(color: const Color(0xFF006D77), width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recurring Task',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: const Color(0xFF006D77),
                ),
              ),
              Switch(
                value: isRecurring,
                onChanged: (value) => setState(() {
                  if (!isShortTerm && value) {
                    _showSnackBar('Long-term jobs cannot be set as recurring.');
                    return;
                  }
                  isRecurring = value;
                }),
                activeColor: const Color(0xFF006D77),
              ),
            ],
          ),
          if (isRecurring) ...[
            const SizedBox(height: 16),
            Text(
              'Frequency',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 12),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: recurringFrequency,
              items: frequencyOptions.map((freq) => DropdownMenuItem(
                value: freq,
                child: Text(freq.capitalize(), style: GoogleFonts.poppins()),
              )).toList(),
              onChanged: (val) => setState(() => recurringFrequency = val ?? 'daily'),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF9F9F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Time',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: recurringTime,
                          );
                          if (time != null) {
                            setState(() => recurringTime = time);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9F9F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Text(
                                recurringTime.format(context),
                                style: GoogleFonts.poppins(),
                              ),
                              const Spacer(),
                              const Icon(Icons.access_time, color: Color(0xFF006D77)),
                            ],
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
                        'End Date (Optional)',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: recurringEndDate ?? DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() => recurringEndDate = date);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9F9F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Text(
                                recurringEndDate?.toLocal().toString().split(' ')[0] ?? 'Select',
                                style: GoogleFonts.poppins(),
                              ),
                              const Spacer(),
                              const Icon(Icons.calendar_today, color: Color(0xFF006D77)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrioritySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Task Priority', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF006D77))),
          const SizedBox(height: 8),
          Row(
            children: priorityLevels.map((priority) {
              final isSelected = selectedPriority == priority;
              Color priorityColor = _getPriorityColor(priority);
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => selectedPriority = priority),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? priorityColor : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: priorityColor, width: isSelected ? 2 : 1),
                    ),
                    child: Text(
                      priority,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: isSelected ? Colors.white : priorityColor,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'Low': return Colors.green;
      case 'Medium': return Colors.orange;
      case 'High': return Colors.red;
      case 'Critical': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Widget _buildDropdownField(String label, List<String> options) {
    final controller = controllers[label];
    if (controller == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF006D77))),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: controller.text.isNotEmpty ? controller.text : null,
            items: options.map((e) => DropdownMenuItem(value: e, child: Text(e, style: GoogleFonts.poppins(color: const Color(0xFF006D77))))).toList(),
            onChanged: (val) => setState(() => controller.text = val ?? ''),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF9F9F9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            dropdownColor: Colors.white,
            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF006D77)),
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimePicker(String label, bool isDate) {
    final controller = controllers[label];
    if (controller == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF006D77))),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            readOnly: true,
            onTap: () async {
              final now = DateTime.now();
              final result = isDate
                  ? await showDatePicker(
                context: context,
                initialDate: controller.text.isNotEmpty ? DateTime.parse(controller.text) : now,
                firstDate: now,
                lastDate: DateTime(2100),
              )
                  : await showTimePicker(context: context, initialTime: TimeOfDay.now());
              if (result != null) {
                final formatted = isDate
                    ? (result as DateTime).toLocal().toString().split(" ")[0]
                    : (result as TimeOfDay).format(context);
                setState(() => controller.text = formatted);
              }
            },
            decoration: InputDecoration(
              hintText: 'Pick $label',
              filled: true,
              fillColor: const Color(0xFFF9F9F9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFF006D77)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldTile(String label) {
    final controller = controllers[label];
    if (controller == null) return const SizedBox.shrink();

    final isVisible = visibleInputs.contains(label);
    final hasText = controller.text.isNotEmpty;
    final isSalaryField = label == 'Salary (RM)*';
    final isRequiredPeopleField = label == 'Required People*';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF006D77))),
              IconButton(
                icon: Icon(hasText ? Icons.edit : Icons.add, color: const Color(0xFF006D77)),
                onPressed: () async {
                  if (label == 'Job location*') {
                    final selected = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LocationPickerPage()),
                    );
                    if (selected != null && selected is String) {
                      setState(() {
                        controller.text = selected;
                        visibleInputs.add(label);
                      });
                    }
                  } else {
                    setState(() => visibleInputs.add(label));
                  }
                },
              ),
            ],
          ),
          if (isVisible) ...[
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: isSalaryField || isRequiredPeopleField ? TextInputType.number : TextInputType.text,
              inputFormatters: _getInputFormatters(label),
              maxLines: label == 'Description' ? 4 : 1,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Enter $label',
                filled: true,
                fillColor: const Color(0xFFF9F9F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<TextInputFormatter>? _getInputFormatters(String label) {
    final isSalaryField = label == 'Salary (RM)*';
    final isRequiredPeopleField = label == 'Required People*';
    if (isSalaryField || isRequiredPeopleField) {
      return [FilteringTextInputFormatter.digitsOnly];
    }
    switch (label) {
      case 'Required Skill*':
        return [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s,.-]+'))];
      case 'Job position*':
      case 'Employer/Company Name*':
      case 'Description':
        return null;
      default:
        return null;
    }
  }

  bool _isFormValid() {
    for (var entry in controllers.entries) {
      final isRequired = entry.key.endsWith('*');
      final isTimeField = entry.key == 'Start time*' || entry.key == 'End time*';
      if (!isRequired) continue;
      if (!isShortTerm && (entry.key == 'End date*' || isTimeField)) continue;
      if ((entry.value.text).trim().isEmpty) {
        print('Missing required field: ${entry.key}');
        return false;
      }
    }
    return true;
  }

  Widget _buildSwitchRow({required String label, required bool value, required Function(bool) onChanged}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF006D77))),
          Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFF006D77)),
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF006D77)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.jobId == null ? 'Add Job' : 'Edit Job',
            style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w600, color: const Color(0xFF006D77)),
          ),
          actions: [
            TextButton(
              onPressed: _submitJob,
              child: Text(
                widget.jobId == null ? 'Post' : 'Save',
                style: GoogleFonts.poppins(color: const Color(0xFF006D77), fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.jobId == null ? 'Create job' : 'Edit your job',
                style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600, color: const Color(0xFF006D77)),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [

                    // Basic job information
                    _buildFieldTile('Job position*'),
                    _buildDropdownField('Type of workplace*', workplaceOptions),
                    _buildFieldTile('Job location*'),
                    _buildFieldTile('Employer/Company Name*'),
                    _buildDropdownField('Employment type*', employmentOptions),
                    _buildFieldTile('Salary (RM)*'),
                    _buildFieldTile('Required Skill*'),
                    _buildFieldTile('Description'),

                    // features section
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Features',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF006D77),
                        ),
                      ),
                    ),
                    _buildSwitchRow(
                      label: isShortTerm ? 'Job Type: Short-term' : 'Job Type: Long-term',
                      value: isShortTerm,
                      onChanged: (val) => setState(() {
                        isShortTerm = val;
                        if (!val && isRecurring) {
                          isRecurring = false;
                          _showSnackBar('Long-term jobs cannot be set as recurring.');
                        }
                      }),
                    ),
                    _buildSwitchRow(
                      label: 'Time Blocking',
                      value: isTimeBlocked,
                      onChanged: (val) => setState(() => isTimeBlocked = val),
                    ),
                    _buildPrioritySelector(),

                    // Recurring task section
                    _buildRecurringSection(),

                    // Date and time fields
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Schedule & Timing',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF006D77),
                        ),
                      ),
                    ),
                    _buildDateTimePicker('Start date*', true),
                    if (isShortTerm) _buildDateTimePicker('Start time*', false),
                    if (isShortTerm) _buildDateTimePicker('End date*', true),
                    if (isShortTerm) _buildDateTimePicker('End time*', false),
                    _buildFieldTile('Required People*'),

                    // Summary card
                    if (isRecurring)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF006D77).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF006D77)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Features Summary',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF006D77),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (isRecurring) ...[
                              Row(
                                children: [
                                  const Icon(Icons.repeat, size: 16, color: Color(0xFF006D77)),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Recurring: $recurringFrequency at ${recurringTime.format(context)}',
                                    style: GoogleFonts.poppins(fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                            ],
                            Row(
                              children: [
                                const Icon(Icons.priority_high, size: 16, color: Color(0xFF006D77)),
                                const SizedBox(width: 8),
                                Text(
                                  'Priority: $selectedPriority',
                                  style: GoogleFonts.poppins(fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}