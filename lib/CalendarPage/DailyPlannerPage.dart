import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';

class DailyPlannerPage extends StatefulWidget {
  final DateTime selectedDate;

  const DailyPlannerPage({super.key, required this.selectedDate});

  @override
  State<DailyPlannerPage> createState() => _DailyPlannerPageState();
}

class _DailyPlannerPageState extends State<DailyPlannerPage> {
  List<Task> _tasks = [];
  List<Task> _completedTasks = [];
  bool _isLoading = true;
  String _dailyGoal = '';
  int _totalEstimatedTime = 0;
  int _completedTime = 0;

  @override
  void initState() {
    super.initState();
    _loadDailyData();
  }

  Future<void> _loadDailyData() async {
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);

        // Load regular tasks
        final taskDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('tasks')
            .doc(dateStr)
            .get();

        // Load jobs for this date
        final jobSnapshot = await FirebaseFirestore.instance
            .collection('jobs')
            .where('acceptedApplicants', arrayContains: user.uid)
            .get();

        // Load daily goal
        final plannerDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('dailyPlanner')
            .doc(dateStr)
            .get();

        setState(() {
          _tasks = [];
          _completedTasks = [];

          // Process regular tasks
          if (taskDoc.exists) {
            final data = taskDoc.data()!;
            final tasksData = data['tasks'] as List<dynamic>? ?? [];
            for (var taskData in tasksData) {
              final task = Task.fromMap(taskData);
              if (task.isCompleted) {
                _completedTasks.add(task);
              } else {
                _tasks.add(task);
              }
            }
          }

          if (plannerDoc.exists) {
            _dailyGoal = plannerDoc.data()?['dailyGoal'] ?? '';
          }

          _isLoading = false;
        });

        // Process jobs asynchronously
        await _processJobsAsync(jobSnapshot.docs, dateStr, user.uid);

        setState(() {
          _calculateTotalTime();
        });
      } catch (e) {
        print('Error loading daily data: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _processJobsAsync(List<QueryDocumentSnapshot> jobDocs, String dateStr, String userId) async {
    final selectedDate = widget.selectedDate;
    final selectedDateOnly = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

    for (var doc in jobDocs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final jobId = doc.id;

        // Check if job is scheduled for the selected date
        final startDate = data['startDate'] != null
            ? DateTime.parse(data['startDate']).toLocal()
            : selectedDate;
        final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);

        final isShortTerm = data['isShortTerm'] == true;
        final endDate = isShortTerm && data['endDate'] != null
            ? DateTime.parse(data['endDate']).toLocal()
            : startDate;
        final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);

        bool shouldIncludeJob = false;

        if (!isShortTerm) {
          // Single day job
          shouldIncludeJob = startDateOnly.isAtSameMomentAs(selectedDateOnly);
        } else {
          // Multi-day job
          shouldIncludeJob = selectedDateOnly.isAtSameMomentAs(startDateOnly) ||
              selectedDateOnly.isAtSameMomentAs(endDateOnly) ||
              (selectedDateOnly.isAfter(startDateOnly) && selectedDateOnly.isBefore(endDateOnly));
        }

        if (shouldIncludeJob) {
          // Check job completion status from taskProgress
          final taskProgressDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('taskProgress')
              .doc(jobId)
              .get();

          bool isJobCompleted = false;
          String jobStatus = 'created';

          if (taskProgressDoc.exists) {
            final progressData = taskProgressDoc.data()!;
            isJobCompleted = progressData['completionApproved'] == true;
            jobStatus = progressData['status'] ?? 'created';

            // Also check if status is 'completed'
            if (jobStatus.toLowerCase() == 'completed') {
              isJobCompleted = true;
            }
          }

          // Create task object from job
          final jobTask = Task(
            id: 'job_$jobId',
            title: data['jobPosition'] ?? 'Unnamed Job',
            description: data['description'] ?? '',
            category: 'Work', // Job category
            priority: _parsePriority(data['priority']),
            estimatedDuration: (data['estimatedDuration'] ?? 60).toInt(),
            isCompleted: isJobCompleted,
            startTime: _parseTimeOfDay(data['startTime'] ?? '9:00 AM'),
            endTime: _parseTimeOfDay(data['endTime'] ?? '10:00 AM'),
            isTimeBlocked: data['isTimeBlocked'] ?? false,
            jobId: jobId,
          );

          // Add to appropriate list based on completion status
          setState(() {
            if (isJobCompleted) {
              _completedTasks.add(jobTask);
            } else {
              _tasks.add(jobTask);
            }
          });

          print('Job ${data['jobPosition']} - Status: $jobStatus, Completed: $isJobCompleted');
        }
      } catch (e) {
        print('Error processing job ${doc.id}: $e');
      }
    }
  }

  TaskPriority _parsePriority(dynamic priority) {
    if (priority is String) {
      switch (priority.toLowerCase()) {
        case 'high':
          return TaskPriority.high;
        case 'medium':
          return TaskPriority.medium;
        case 'low':
          return TaskPriority.low;
        default:
          return TaskPriority.medium;
      }
    }
    return TaskPriority.medium;
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    try {
      timeStr = timeStr.trim().toUpperCase().replaceAll(' ', '');
      String period = 'AM';
      String normalizedTime;

      if (timeStr.contains('PM')) {
        period = 'PM';
        normalizedTime = timeStr.replaceAll('PM', '');
      } else if (timeStr.contains('AM')) {
        normalizedTime = timeStr.replaceAll('AM', '');
      } else {
        normalizedTime = timeStr;
      }

      List<String> parts = normalizedTime.split(':');
      if (parts.length != 2) throw FormatException('Invalid time format: $timeStr');

      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);

      if (period == 'PM' && hour != 12) hour += 12;
      else if (period == 'AM' && hour == 12) hour = 0;

      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      print('Error parsing time: $timeStr, $e');
      return const TimeOfDay(hour: 9, minute: 0);
    }
  }

  void _calculateTotalTime() {
    _totalEstimatedTime = _tasks.fold(0, (sum, task) => sum + task.estimatedDuration);
    _completedTime = _completedTasks.fold(0, (sum, task) => sum + task.estimatedDuration);
  }

  Future<void> _saveDailyData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);

        // Only save regular tasks (not jobs) to the tasks collection
        // Jobs completion is handled in the taskProgress collection
        final regularTasks = [..._tasks, ..._completedTasks]
            .where((task) => !task.id.startsWith('job_'))
            .toList();

        if (regularTasks.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('tasks')
              .doc(dateStr)
              .set({
            'date': dateStr,
            'tasks': regularTasks.map((task) => task.toMap()).toList(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // Save daily goal
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('dailyPlanner')
            .doc(dateStr)
            .set({
          'dailyGoal': _dailyGoal,
          'date': dateStr,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        print('Error saving daily data: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  void _showAddTaskDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final categoryController = TextEditingController(text: 'General');
    TaskPriority selectedPriority = TaskPriority.medium;
    int estimatedDuration = 30;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add New Task', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Task Title',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: categoryController,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Priority', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                          DropdownButton<TaskPriority>(
                            value: selectedPriority,
                            isExpanded: true,
                            items: TaskPriority.values.map((priority) {
                              Color color = priority == TaskPriority.high ? Colors.red :
                              priority == TaskPriority.medium ? Colors.orange : Colors.green;
                              return DropdownMenuItem(
                                value: priority,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(priority.name.toUpperCase()),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) => setDialogState(() => selectedPriority = value!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Duration (min)', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                          DropdownButton<int>(
                            value: estimatedDuration,
                            isExpanded: true,
                            items: [15, 30, 45, 60, 90, 120, 180].map((duration) {
                              return DropdownMenuItem(
                                value: duration,
                                child: Text('$duration min'),
                              );
                            }).toList(),
                            onChanged: (value) => setDialogState(() => estimatedDuration = value!),
                          ),
                        ],
                      ),
                    ),
                  ],
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
              onPressed: () {
                if (titleController.text.trim().isNotEmpty) {
                  final newTask = Task(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: titleController.text.trim(),
                    description: descriptionController.text.trim(),
                    category: categoryController.text.trim(),
                    priority: selectedPriority,
                    estimatedDuration: estimatedDuration,
                    isCompleted: false,
                    startTime: const TimeOfDay(hour: 9, minute: 0),
                    endTime: const TimeOfDay(hour: 10, minute: 0),
                  );

                  setState(() {
                    _tasks.add(newTask);
                    _calculateTotalTime();
                  });

                  _saveDailyData();
                  Navigator.pop(context);
                }
              },
              child: const Text('Add Task'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleTaskCompletion(Task task) {
    // Don't allow toggling completion for job tasks
    if (task.id.startsWith('job_')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Job completion is managed through the Task Progress page'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      if (task.isCompleted) {
        _completedTasks.remove(task);
        _tasks.add(task.copyWith(isCompleted: false));
      } else {
        _tasks.remove(task);
        _completedTasks.add(task.copyWith(isCompleted: true));
      }
      _calculateTotalTime();
    });
    _saveDailyData();
  }

  void _deleteTask(Task task) {
    // Don't allow deleting job tasks
    if (task.id.startsWith('job_')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Job tasks cannot be deleted from here'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _tasks.remove(task);
      _completedTasks.remove(task);
      _calculateTotalTime();
    });
    _saveDailyData();
  }

  void _editTask(Task task) {
    // Don't allow editing job tasks
    if (task.id.startsWith('job_')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Job tasks cannot be edited from here'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final titleController = TextEditingController(text: task.title);
    final descriptionController = TextEditingController(text: task.description);
    final categoryController = TextEditingController(text: task.category);
    TaskPriority selectedPriority = task.priority;
    int estimatedDuration = task.estimatedDuration;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit Task', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Task Title',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: categoryController,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Priority', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                          DropdownButton<TaskPriority>(
                            value: selectedPriority,
                            isExpanded: true,
                            items: TaskPriority.values.map((priority) {
                              Color color = priority == TaskPriority.high ? Colors.red :
                              priority == TaskPriority.medium ? Colors.orange : Colors.green;
                              return DropdownMenuItem(
                                value: priority,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(priority.name.toUpperCase()),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) => setDialogState(() => selectedPriority = value!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Duration (min)', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                          DropdownButton<int>(
                            value: estimatedDuration,
                            isExpanded: true,
                            items: [15, 30, 45, 60, 90, 120, 180].map((duration) {
                              return DropdownMenuItem(
                                value: duration,
                                child: Text('$duration min'),
                              );
                            }).toList(),
                            onChanged: (value) => setDialogState(() => estimatedDuration = value!),
                          ),
                        ],
                      ),
                    ),
                  ],
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
              onPressed: () {
                if (titleController.text.trim().isNotEmpty) {
                  final updatedTask = task.copyWith(
                    title: titleController.text.trim(),
                    description: descriptionController.text.trim(),
                    category: categoryController.text.trim(),
                    priority: selectedPriority,
                    estimatedDuration: estimatedDuration,
                  );

                  setState(() {
                    final index = _tasks.indexOf(task);
                    if (index != -1) {
                      _tasks[index] = updatedTask;
                    } else {
                      final completedIndex = _completedTasks.indexOf(task);
                      if (completedIndex != -1) {
                        _completedTasks[completedIndex] = updatedTask;
                      }
                    }
                    _calculateTotalTime();
                  });

                  _saveDailyData();
                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final totalTasks = _tasks.length + _completedTasks.length;
    final completedTasksCount = _completedTasks.length;
    final progressPercentage = totalTasks > 0 ? completedTasksCount / totalTasks : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Progress',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progressPercentage,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$completedTasksCount / $totalTasks tasks completed',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                Text(
                  '${(progressPercentage * 100).toInt()}%',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estimated Time', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                      Text('${_totalEstimatedTime}min', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Completed Time', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                      Text('${_completedTime}min', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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

  Widget _buildDailyGoalSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  'Daily Goal',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) {
                _dailyGoal = value;
                _saveDailyData();
              },
              decoration: InputDecoration(
                hintText: 'What do you want to achieve today?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(12),
              ),
              controller: TextEditingController(text: _dailyGoal),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(String title, List<Task> tasks, bool isCompleted) {
    return Card(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isCompleted ? Colors.green[50] : Colors.blue[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isCompleted ? Colors.green : Colors.blue,
                ),
                const SizedBox(width: 8),
                Text(
                  '$title (${tasks.length})',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    isCompleted ? Icons.celebration : Icons.add_task,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isCompleted ? 'No completed tasks yet' : 'No tasks planned',
                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                Color priorityColor = task.priority == TaskPriority.high ? Colors.red :
                task.priority == TaskPriority.medium ? Colors.orange : Colors.green;

                final isJobTask = task.id.startsWith('job_');

                return ListTile(
                  leading: Checkbox(
                    value: task.isCompleted,
                    onChanged: isJobTask ? null : (_) => _toggleTaskCompletion(task),
                    activeColor: Colors.teal,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (isJobTask)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: task.isCompleted ? Colors.grey[300] : Colors.blue[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'JOB',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: task.isCompleted ? Colors.grey[600] : Colors.blue[700],
                            ),
                          ),
                        ),
                      if (task.isCompleted)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'COMPLETED',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task.description.isNotEmpty)
                        Text(task.description, style: GoogleFonts.poppins(fontSize: 12)),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: priorityColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          Text('${task.category} • ${task.estimatedDuration}min'),
                        ],
                      ),
                    ],
                  ),
                  trailing: isJobTask ? null : PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _editTask(task);
                          break;
                        case 'delete':
                          _deleteTask(task);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily Planner',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.teal[800]),
              ),
              Text(
                DateFormat('EEEE, MMMM d, y').format(widget.selectedDate),
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.teal[600]),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _showAddTaskDialog,
              icon: const Icon(Icons.add, color: Colors.teal),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _loadDailyData,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                _buildProgressIndicator(),
                const SizedBox(height: 16),
                _buildDailyGoalSection(),
                const SizedBox(height: 16),
                _buildTaskList('Pending Tasks', _tasks, false),
                const SizedBox(height: 16),
                _buildTaskList('Completed Tasks', _completedTasks, true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}