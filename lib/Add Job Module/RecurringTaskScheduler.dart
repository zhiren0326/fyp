import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';

class RecurringTaskScheduler extends StatefulWidget {
  const RecurringTaskScheduler({super.key});

  @override
  State<RecurringTaskScheduler> createState() => _RecurringTaskSchedulerState();
}

class _RecurringTaskSchedulerState extends State<RecurringTaskScheduler> {
  Timer? _schedulerTimer;
  List<Map<String, dynamic>> recurringTasks = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _startScheduler();
    _loadRecurringTasks();
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    super.dispose();
  }

  void _startScheduler() {
    _schedulerTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      _checkAndGenerateRecurringTasks();
    });
  }

  Future<void> _loadRecurringTasks() async {
    setState(() => isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final jobsSnapshot = await FirebaseFirestore.instance
          .collection('jobs')
          .where('postedBy', isEqualTo: currentUser.uid)
          .where('recurring', isEqualTo: true)
          .get();

      final recurringTasksSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('recurringTasks')
          .get();

      List<Map<String, dynamic>> tasks = [];

      for (var doc in jobsSnapshot.docs) {
        final data = doc.data();
        tasks.add({
          'id': doc.id,
          'title': data['jobPosition'] ?? 'Untitled Job',
          'type': 'job',
          'description': data['description'] ?? '',
          'frequency': data['recurringFrequency'] ?? 'daily',
          'time': data['recurringTime'] ?? '09:00',
          'nextOccurrence': data['nextOccurrence'],
          'lastGenerated': data['lastGenerated'],
          'isActive': data['isCompleted'] != true,
          'createdAt': data['postedAt'],
          'priority': data['priority'] ?? 'Medium',
          'dependencies': List<String>.from(data['dependencies'] ?? []),
          'originalData': data,
        });
      }

      for (var doc in recurringTasksSnapshot.docs) {
        final data = doc.data();
        tasks.add({
          'id': doc.id,
          'title': data['title'] ?? 'Untitled Task',
          'type': 'personal',
          'description': data['description'] ?? '',
          'frequency': data['frequency'] ?? 'daily',
          'time': data['time'] ?? '09:00',
          'nextOccurrence': data['nextOccurrence'],
          'lastGenerated': data['lastGenerated'],
          'isActive': data['isActive'] ?? true,
          'createdAt': data['createdAt'],
          'priority': data['priority'] ?? 'Medium',
          'dependencies': List<String>.from(data['dependencies'] ?? []),
          'originalData': data,
        });
      }

      setState(() {
        recurringTasks = tasks;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading recurring tasks: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _checkAndGenerateRecurringTasks() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final now = DateTime.now();

    for (var recurringTask in recurringTasks) {
      if (!recurringTask['isActive']) continue;

      final nextOccurrence = DateTime.tryParse(recurringTask['nextOccurrence'] ?? '');
      if (nextOccurrence == null) continue;

      if (now.isAfter(nextOccurrence) || now.isAtSameMomentAs(nextOccurrence)) {
        await _generateTaskInstance(recurringTask);
      }
    }
  }

  Future<void> _generateTaskInstance(Map<String, dynamic> recurringTask) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      String newTaskId;
      if (recurringTask['type'] == 'job') {
        newTaskId = await _generateJobInstance(recurringTask, currentUser.uid);
      } else {
        newTaskId = await _generatePersonalTaskInstance(recurringTask, currentUser.uid);
      }

      // Log to activity log
      await _logActivity('Generated', newTaskId, recurringTask);

      await _updateNextOccurrence(recurringTask);

      print('Generated instance for: ${recurringTask['title']}');
    } catch (e) {
      print('Error generating task instance: $e');
    }
  }

  Future<String> _generateJobInstance(Map<String, dynamic> recurringTask, String userId) async {
    final originalData = recurringTask['originalData'];
    final now = DateTime.now();

    final newStartDate = _calculateNewDate(now, recurringTask['frequency']);
    final newEndDate = originalData['endDate'] != null
        ? _calculateNewDate(DateTime.parse(originalData['endDate']), recurringTask['frequency'])
        : null;

    final newJobData = Map<String, dynamic>.from(originalData);
    newJobData.update('startDate', (value) => newStartDate.toIso8601String().split('T')[0]);
    if (newEndDate != null) {
      newJobData.update('endDate', (value) => newEndDate.toIso8601String().split('T')[0]);
    }
    newJobData.update('postedAt', (value) => Timestamp.now());
    newJobData['isCompleted'] = false;
    newJobData['applicants'] = [];
    newJobData['acceptedApplicants'] = [];
    newJobData['progressPercentage'] = 0;
    newJobData['isRecurringInstance'] = true;
    newJobData['parentRecurringId'] = recurringTask['id'];

    final docRef = await FirebaseFirestore.instance.collection('jobs').add(newJobData);
    await docRef.update({'jobId': docRef.id});

    if (newJobData['isShortTerm'] == true) {
      await _createTaskProgress(docRef.id, userId, recurringTask['title']);
    }

    return docRef.id;
  }

  Future<String> _generatePersonalTaskInstance(Map<String, dynamic> recurringTask, String userId) async {
    final now = DateTime.now();
    final targetDate = _calculateNewDate(now, recurringTask['frequency']);
    final dateKey = targetDate.toIso8601String().split('T')[0];

    if (await _checkDependencies(recurringTask['dependencies'], userId)) {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tasks')
          .doc(dateKey);

      await docRef.set({
        'tasks': FieldValue.arrayUnion([{
          'title': recurringTask['title'],
          'description': recurringTask['description'],
          'isTimeBlocked': false,
          'completed': false,
          'priority': recurringTask['priority'],
          'isRecurring': true,
          'recurringId': recurringTask['id'],
          'dependencies': recurringTask['dependencies'],
          'createdAt': Timestamp.now(),
          'scheduledTime': recurringTask['time'],
        }]),
      }, SetOptions(merge: true));

      return docRef.id;
    } else {
      print('Dependencies not met for ${recurringTask['title']}, skipping generation');
      return '';
    }
  }

  Future<void> _createTaskProgress(String jobId, String userId, String title) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('taskProgress')
          .doc(jobId)
          .set({
        'taskId': jobId,
        'taskTitle': title,
        'currentProgress': 0,
        'milestones': [],
        'createdAt': Timestamp.now(),
        'lastUpdated': Timestamp.now(),
        'status': 'generated',
        'jobCreator': userId,
        'canEditProgress': [userId],
        'isRecurringInstance': true,
      });
    } catch (e) {
      print('Error creating task progress: $e');
    }
  }

  Future<bool> _checkDependencies(List<String> dependencies, String userId) async {
    if (dependencies.isEmpty) return true;

    try {
      for (String depId in dependencies) {
        final jobDoc = await FirebaseFirestore.instance
            .collection('jobs')
            .doc(depId)
            .get();

        if (jobDoc.exists) {
          final jobData = jobDoc.data()!;
          if (jobData['isCompleted'] != true) {
            if (jobData['isShortTerm'] != true) {
              final progress = jobData['progressPercentage'] ?? 0;
              if (progress < 100) return false;
            } else {
              return false;
            }
          }
        } else {
          final personalTaskFound = await _checkPersonalTaskDependency(depId, userId);
          if (!personalTaskFound) return false;
        }
      }
      return true;
    } catch (e) {
      print('Error checking dependencies: $e');
      return false;
    }
  }

  Future<bool> _checkPersonalTaskDependency(String depId, String userId) async {
    return true;
  }

  DateTime _calculateNewDate(DateTime baseDate, String frequency) {
    switch (frequency.toLowerCase()) {
      case 'daily':
        return baseDate.add(const Duration(days: 1));
      case 'weekly':
        return baseDate.add(const Duration(days: 7));
      case 'monthly':
        return DateTime(baseDate.year, baseDate.month + 1, baseDate.day);
      case 'yearly':
        return DateTime(baseDate.year + 1, baseDate.month, baseDate.day);
      case 'minutes':
        return baseDate.add(const Duration(minutes: 1));
      default:
        return baseDate.add(const Duration(days: 1));
    }
  }

  Future<void> _updateNextOccurrence(Map<String, dynamic> recurringTask) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final now = DateTime.now();
      final nextOccurrence = _calculateNextOccurrence(now, recurringTask['frequency'], recurringTask['time']);

      if (recurringTask['type'] == 'job') {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(recurringTask['id'])
            .update({
          'nextOccurrence': nextOccurrence.toIso8601String(),
          'lastGenerated': Timestamp.now(),
        });
      } else {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('recurringTasks')
            .doc(recurringTask['id'])
            .update({
          'nextOccurrence': nextOccurrence.toIso8601String(),
          'lastGenerated': Timestamp.now(),
        });
      }
    } catch (e) {
      print('Error updating next occurrence: $e');
    }
  }

  DateTime _calculateNextOccurrence(DateTime from, String frequency, String time) {
    final timeParts = time.split(':');
    final hour = int.tryParse(timeParts[0]) ?? 9;
    final minute = int.tryParse(timeParts[1]) ?? 0;

    DateTime next = from;

    switch (frequency.toLowerCase()) {
      case 'hourly':
        next = next.add(const Duration(hours: 1));
        break;
      case 'daily':
        next = DateTime(next.year, next.month, next.day + 1, hour, minute);
        break;
      case 'weekly':
        next = DateTime(next.year, next.month, next.day + 7, hour, minute);
        break;
      case 'monthly':
        next = DateTime(next.year, next.month + 1, next.day, hour, minute);
        break;
      case 'yearly':
        next = DateTime(next.year + 1, next.month, next.day, hour, minute);
        break;
      default:
        next = DateTime(next.year, next.month, next.day + 1, hour, minute);
    }

    return next;
  }

  Future<void> _logActivity(String action, String taskId, Map<String, dynamic> recurringTask) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('activityLog')
          .add({
        'action': action,
        'taskId': taskId,
        'taskTitle': recurringTask['title'],
        'timestamp': Timestamp.now(),
        'details': {
          'type': recurringTask['type'],
          'frequency': recurringTask['frequency'],
          'priority': recurringTask['priority'],
          'isRecurring': true,
        }
      });
    } catch (e) {
      print('Error logging activity: $e');
    }
  }

  Future<void> _manuallyGenerateTask(Map<String, dynamic> recurringTask) async {
    await _generateTaskInstance(recurringTask);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Generated instance for: ${recurringTask['title']}'),
        backgroundColor: Colors.green,
      ),
    );
    _loadRecurringTasks();
  }

  void _showCreateRecurringTaskDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedFrequency = 'daily';
    String selectedPriority = 'Medium';
    TimeOfDay selectedTime = TimeOfDay.now();
    DateTime startDate = DateTime.now();
    List<String> selectedDependencies = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Create Recurring Task',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Task Title*',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedFrequency,
                  decoration: const InputDecoration(
                    labelText: 'Frequency',
                    border: OutlineInputBorder(),
                  ),
                  items: ['hourly', 'daily', 'weekly', 'monthly', 'yearly']
                      .map((freq) => DropdownMenuItem(
                    value: freq,
                    child: Text(freq.capitalize()),
                  ))
                      .toList(),
                  onChanged: (value) => setDialogState(() => selectedFrequency = value!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedPriority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Low', 'Medium', 'High', 'Critical']
                      .map((priority) => DropdownMenuItem(
                    value: priority,
                    child: Text(priority),
                  ))
                      .toList(),
                  onChanged: (value) => setDialogState(() => selectedPriority = value!),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Scheduled Time'),
                  subtitle: Text(selectedTime.format(context)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (pickedTime != null) {
                      setDialogState(() => selectedTime = pickedTime);
                    }
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Start Date'),
                  subtitle: Text(startDate.toLocal().toString().split(' ')[0]),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: startDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (pickedDate != null) {
                      setDialogState(() => startDate = pickedDate);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Dependencies: ${selectedDependencies.length} selected',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isNotEmpty) {
                  await _createRecurringTask(
                    titleController.text,
                    descriptionController.text,
                    selectedFrequency,
                    selectedPriority,
                    selectedTime,
                    startDate,
                    selectedDependencies,
                  );
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006D77),
              ),
              child: const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createRecurringTask(
      String title,
      String description,
      String frequency,
      String priority,
      TimeOfDay time,
      DateTime startDate,
      List<String> dependencies,
      ) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final timeString = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      final nextOccurrence = _calculateNextOccurrence(startDate, frequency, timeString);

      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('recurringTasks')
          .add({
        'title': title,
        'description': description,
        'frequency': frequency,
        'priority': priority,
        'time': timeString,
        'startDate': startDate.toIso8601String(),
        'nextOccurrence': nextOccurrence.toIso8601String(),
        'dependencies': dependencies,
        'isActive': true,
        'createdAt': Timestamp.now(),
        'lastGenerated': null,
        'pattern': 'Every $frequency at $timeString',
      });

      await _logActivity('Created', docRef.id, {
        'title': title,
        'type': 'personal',
        'frequency': frequency,
        'priority': priority
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recurring task created successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _loadRecurringTasks();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating recurring task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showEditRecurringTaskDialog(Map<String, dynamic> task) {
    final titleController = TextEditingController(text: task['title']);
    final descriptionController = TextEditingController(text: task['description']);
    String selectedFrequency = task['frequency'];
    String selectedPriority = task['priority'];
    TimeOfDay selectedTime = TimeOfDay(
      hour: int.parse(task['time'].split(':')[0]),
      minute: int.parse(task['time'].split(':')[1]),
    );
    DateTime startDate = DateTime.parse(task['originalData']['startDate'] ?? DateTime.now().toIso8601String());
    List<String> selectedDependencies = List<String>.from(task['dependencies']);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Edit Recurring Task',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Task Title*',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedFrequency,
                  decoration: const InputDecoration(
                    labelText: 'Frequency',
                    border: OutlineInputBorder(),
                  ),
                  items: ['hourly', 'daily', 'weekly', 'monthly', 'yearly']
                      .map((freq) => DropdownMenuItem(
                    value: freq,
                    child: Text(freq.capitalize()),
                  ))
                      .toList(),
                  onChanged: (value) => setDialogState(() => selectedFrequency = value!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedPriority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Low', 'Medium', 'High', 'Critical']
                      .map((priority) => DropdownMenuItem(
                    value: priority,
                    child: Text(priority),
                  ))
                      .toList(),
                  onChanged: (value) => setDialogState(() => selectedPriority = value!),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Scheduled Time'),
                  subtitle: Text(selectedTime.format(context)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (pickedTime != null) {
                      setDialogState(() => selectedTime = pickedTime);
                    }
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Start Date'),
                  subtitle: Text(startDate.toLocal().toString().split(' ')[0]),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: startDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (pickedDate != null) {
                      setDialogState(() => startDate = pickedDate);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Dependencies: ${selectedDependencies.length} selected',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isNotEmpty) {
                  await _updateRecurringTask(
                    task['id'],
                    task['type'],
                    titleController.text,
                    descriptionController.text,
                    selectedFrequency,
                    selectedPriority,
                    selectedTime,
                    startDate,
                    selectedDependencies,
                  );
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006D77),
              ),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateRecurringTask(
      String taskId,
      String taskType,
      String title,
      String description,
      String frequency,
      String priority,
      TimeOfDay time,
      DateTime startDate,
      List<String> dependencies,
      ) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final timeString = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      final nextOccurrence = _calculateNextOccurrence(startDate, frequency, timeString);

      final updateData = {
        'title': title,
        'description': description,
        'frequency': frequency,
        'priority': priority,
        'time': timeString,
        'startDate': startDate.toIso8601String(),
        'nextOccurrence': nextOccurrence.toIso8601String(),
        'dependencies': dependencies,
        'lastUpdated': Timestamp.now(),
        'pattern': 'Every $frequency at $timeString',
      };

      if (taskType == 'job') {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(taskId)
            .update(updateData);
      } else {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('recurringTasks')
            .doc(taskId)
            .update(updateData);
      }

      await _logActivity('Updated', taskId, {
        'title': title,
        'type': taskType,
        'frequency': frequency,
        'priority': priority
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recurring task updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _loadRecurringTasks();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating recurring task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deleteRecurringTask(String taskId, String taskTitle, String taskType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Recurring Task',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete "$taskTitle"? This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performDeleteRecurringTask(taskId, taskTitle, taskType);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeleteRecurringTask(String taskId, String taskTitle, String taskType) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      if (taskType == 'job') {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(taskId)
            .delete();
      } else {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('recurringTasks')
            .doc(taskId)
            .delete();
      }

      await _logActivity('Deleted', taskId, {
        'title': taskTitle,
        'type': taskType,
        'frequency': 'N/A',
        'priority': 'N/A'
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recurring task "$taskTitle" deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _loadRecurringTasks();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete recurring task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildRecurringTaskCard(Map<String, dynamic> task) {
    final nextOccurrence = DateTime.tryParse(task['nextOccurrence'] ?? '');
    final isOverdue = nextOccurrence?.isBefore(DateTime.now()) ?? false;
    final hasUnmetDependencies = task['dependencies'].isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isOverdue ? Colors.red[50] : (task['isActive'] ? Colors.white : Colors.grey[100]),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getPriorityColor(task['priority']),
                  radius: 20,
                  child: Text(
                    task['type'] == 'job' ? 'J' : 'R',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task['title'],
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: task['isActive'] ? const Color(0xFF006D77) : Colors.grey,
                        ),
                      ),
                      if (task['description'].isNotEmpty)
                        Text(
                          task['description'],
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.play_arrow, color: Colors.green),
                  onPressed: () => _manuallyGenerateTask(task),
                  tooltip: 'Generate Now',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showEditRecurringTaskDialog(task),
                  tooltip: 'Edit Task',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteRecurringTask(task['id'], task['title'], task['type']),
                  tooltip: 'Delete Task',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: Text(
                    '${task['frequency']} at ${task['time'] ?? 'N/A'}',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (hasUnmetDependencies)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Text(
                      '${task['dependencies'].length} deps',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (nextOccurrence != null)
              Text(
                'Next: ${nextOccurrence.toLocal().toString().split('.')[0]}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: isOverdue ? Colors.red : Colors.grey[600],
                  fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            if (task['lastGenerated'] != null)
              Text(
                'Last generated: ${(task['lastGenerated'] as Timestamp).toDate().toLocal().toString().split('.')[0]}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.grey[500],
                ),
              ),
          ],
        ),
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
            'Recurring Task Scheduler',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadRecurringTasks,
            ),
            IconButton(
              icon: const Icon(Icons.play_circle_fill),
              onPressed: _checkAndGenerateRecurringTasks,
              tooltip: 'Check & Generate All',
            ),
          ],
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          '${recurringTasks.where((t) => t['isActive']).length}',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text('Active', style: GoogleFonts.poppins(fontSize: 12)),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '${recurringTasks.where((t) => DateTime.tryParse(t['nextOccurrence'] ?? '')?.isBefore(DateTime.now()) ?? false).length}',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        Text('Overdue', style: GoogleFonts.poppins(fontSize: 12)),
                      ],
                    ),
                    Column(
                      children: [
                        Icon(
                          _schedulerTimer?.isActive == true ? Icons.schedule : Icons.schedule_outlined,
                          color: _schedulerTimer?.isActive == true ? Colors.green : Colors.grey,
                          size: 24,
                        ),
                        Text(
                          'Scheduler ${_schedulerTimer?.isActive == true ? 'ON' : 'OFF'}',
                          style: GoogleFonts.poppins(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: recurringTasks.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.schedule, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No recurring tasks found.',
                      style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: recurringTasks.length,
                itemBuilder: (context, index) => _buildRecurringTaskCard(recurringTasks[index]),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showCreateRecurringTaskDialog,
          backgroundColor: const Color(0xFF006D77),
          child: const Icon(Icons.add, color: Colors.white),
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