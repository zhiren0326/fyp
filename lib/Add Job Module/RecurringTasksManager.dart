import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

class RecurringTasksManager extends StatefulWidget {
  const RecurringTasksManager({super.key});

  @override
  State<RecurringTasksManager> createState() => _RecurringTasksManagerState();
}

class _RecurringTasksManagerState extends State<RecurringTasksManager> {
  List<Map<String, dynamic>> recurringTasks = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecurringTasks();
  }

  Future<void> _loadRecurringTasks() async {
    setState(() => isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Load recurring jobs
      final jobsSnapshot = await FirebaseFirestore.instance
          .collection('jobs')
          .where('postedBy', isEqualTo: currentUser.uid)
          .where('recurring', isEqualTo: true)
          .get();

      // Load recurring personal tasks
      final recurringTasksSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('recurringTasks')
          .get();

      List<Map<String, dynamic>> tasks = [];

      // Add recurring jobs
      for (var doc in jobsSnapshot.docs) {
        final data = doc.data();
        tasks.add({
          'id': doc.id,
          'title': data['jobPosition'] ?? 'Untitled Job',
          'type': 'job',
          'description': data['description'] ?? '',
          'startDate': data['startDate'],
          'frequency': _extractFrequencyFromRecurringTasks(data['recurringTasks']),
          'nextOccurrence': _calculateNextOccurrence(data['startDate'],
              _extractFrequencyFromRecurringTasks(data['recurringTasks'])),
          'isActive': data['isCompleted'] != true,
          'createdAt': data['postedAt'],
          'priority': data['priority'] ?? 'Medium',
          'recurringPattern': data['recurringTasks'] ?? '',
        });
      }

      // Add personal recurring tasks
      for (var doc in recurringTasksSnapshot.docs) {
        final data = doc.data();
        tasks.add({
          'id': doc.id,
          'title': data['title'] ?? 'Untitled Task',
          'type': 'personal',
          'description': data['description'] ?? '',
          'startDate': data['startDate'],
          'frequency': data['frequency'] ?? 'daily',
          'nextOccurrence': data['nextOccurrence'],
          'isActive': data['isActive'] ?? true,
          'createdAt': data['createdAt'],
          'priority': data['priority'] ?? 'Medium',
          'recurringPattern': data['pattern'] ?? '',
        });
      }

      // Sort by next occurrence
      tasks.sort((a, b) {
        final aNext = DateTime.tryParse(a['nextOccurrence'] ?? '') ?? DateTime.now();
        final bNext = DateTime.tryParse(b['nextOccurrence'] ?? '') ?? DateTime.now();
        return aNext.compareTo(bNext);
      });

      setState(() {
        recurringTasks = tasks;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading recurring tasks: $e');
      setState(() => isLoading = false);
    }
  }

  String _extractFrequencyFromRecurringTasks(String? recurringTasks) {
    if (recurringTasks == null || recurringTasks.isEmpty) return 'daily';

    final lowerCase = recurringTasks.toLowerCase();
    if (lowerCase.contains('daily')) return 'daily';
    if (lowerCase.contains('weekly')) return 'weekly';
    if (lowerCase.contains('monthly')) return 'monthly';
    if (lowerCase.contains('yearly')) return 'yearly';

    return 'daily';
  }

  String _calculateNextOccurrence(String? startDate, String frequency) {
    if (startDate == null) return DateTime.now().toIso8601String();

    try {
      DateTime start = DateTime.parse(startDate);
      DateTime now = DateTime.now();

      // If start date is in the future, that's the next occurrence
      if (start.isAfter(now)) return start.toIso8601String();

      DateTime next = start;

      switch (frequency) {
        case 'daily':
          while (next.isBefore(now)) {
            next = next.add(const Duration(days: 1));
          }
          break;
        case 'weekly':
          while (next.isBefore(now)) {
            next = next.add(const Duration(days: 7));
          }
          break;
        case 'monthly':
          while (next.isBefore(now)) {
            next = DateTime(next.year, next.month + 1, next.day);
          }
          break;
        case 'yearly':
          while (next.isBefore(now)) {
            next = DateTime(next.year + 1, next.month, next.day);
          }
          break;
      }

      return next.toIso8601String();
    } catch (e) {
      return DateTime.now().add(const Duration(days: 1)).toIso8601String();
    }
  }

  Future<void> _generateNextInstance(Map<String, dynamic> task) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      DateTime nextOccurrence = DateTime.parse(task['nextOccurrence']);

      if (task['type'] == 'job') {
        // For jobs, we might want to create a new job instance or update the existing one
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(task['id'])
            .update({
          'lastGenerated': Timestamp.now(),
          'nextOccurrence': _calculateNextOccurrence(
              nextOccurrence.toIso8601String(),
              task['frequency']
          ),
        });
      } else {
        // For personal tasks, add to the user's tasks for the specific date
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('tasks')
            .doc(nextOccurrence.toIso8601String().split('T')[0])
            .set({
          'tasks': FieldValue.arrayUnion([{
            'title': task['title'],
            'isTimeBlocked': false,
            'completed': false,
            'priority': task['priority'],
            'isRecurring': true,
            'recurringId': task['id'],
            'createdAt': Timestamp.now(),
          }]),
        }, SetOptions(merge: true));

        // Update the recurring task's next occurrence
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('recurringTasks')
            .doc(task['id'])
            .update({
          'nextOccurrence': _calculateNextOccurrence(
              nextOccurrence.toIso8601String(),
              task['frequency']
          ),
          'lastGenerated': Timestamp.now(),
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Next instance generated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _loadRecurringTasks(); // Reload to update the list
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating next instance: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleTaskStatus(Map<String, dynamic> task) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final newStatus = !task['isActive'];

      if (task['type'] == 'job') {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(task['id'])
            .update({'isCompleted': !newStatus});
      } else {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('recurringTasks')
            .doc(task['id'])
            .update({'isActive': newStatus});
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task ${newStatus ? 'activated' : 'deactivated'} successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _loadRecurringTasks();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating task status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteRecurringTask(Map<String, dynamic> task) async {
    // Show confirmation dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Recurring Task',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete "${task['title']}"? This will stop all future occurrences.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      if (task['type'] == 'job') {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(task['id'])
            .delete();
      } else {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('recurringTasks')
            .doc(task['id'])
            .delete();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recurring task deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _loadRecurringTasks();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showCreateRecurringTaskDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedFrequency = 'daily';
    String selectedPriority = 'Medium';
    DateTime startDate = DateTime.now();

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
                  items: ['daily', 'weekly', 'monthly', 'yearly']
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
                    startDate,
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
      DateTime startDate,
      ) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('recurringTasks')
          .add({
        'title': title,
        'description': description,
        'frequency': frequency,
        'priority': priority,
        'startDate': startDate.toIso8601String(),
        'nextOccurrence': _calculateNextOccurrence(startDate.toIso8601String(), frequency),
        'isActive': true,
        'createdAt': Timestamp.now(),
        'pattern': 'Every $frequency',
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

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'Low': return Colors.green;
      case 'Medium': return Colors.orange;
      case 'High': return Colors.red;
      case 'Critical': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Color _getFrequencyColor(String frequency) {
    switch (frequency) {
      case 'daily': return Colors.blue;
      case 'weekly': return Colors.green;
      case 'monthly': return Colors.orange;
      case 'yearly': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getTimeUntilNext(String nextOccurrence) {
    try {
      final next = DateTime.parse(nextOccurrence);
      final now = DateTime.now();
      final difference = next.difference(now);

      if (difference.isNegative) return 'Overdue';

      if (difference.inDays > 0) {
        return '${difference.inDays} days';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hours';
      } else {
        return '${difference.inMinutes} minutes';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  Widget _buildRecurringTaskCard(Map<String, dynamic> task) {
    final isOverdue = DateTime.tryParse(task['nextOccurrence'] ?? '')?.isBefore(DateTime.now()) ?? false;

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
                          decoration: task['isActive'] ? null : TextDecoration.lineThrough,
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
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'toggle':
                        _toggleTaskStatus(task);
                        break;
                      case 'generate':
                        _generateNextInstance(task);
                        break;
                      case 'delete':
                        _deleteRecurringTask(task);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(task['isActive'] ? Icons.pause : Icons.play_arrow),
                          const SizedBox(width: 8),
                          Text(task['isActive'] ? 'Deactivate' : 'Activate'),
                        ],
                      ),
                    ),
                    if (task['isActive'])
                      const PopupMenuItem(
                        value: 'generate',
                        child: Row(
                          children: [
                            Icon(Icons.add_task),
                            SizedBox(width: 8),
                            Text('Generate Now'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getFrequencyColor(task['frequency']).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _getFrequencyColor(task['frequency'])),
                  ),
                  child: Text(
                    task['frequency'].toString().capitalize(),
                    style: TextStyle(
                      color: _getFrequencyColor(task['frequency']),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(task['priority']).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _getPriorityColor(task['priority'])),
                  ),
                  child: Text(
                    task['priority'],
                    style: TextStyle(
                      color: _getPriorityColor(task['priority']),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                if (task['isActive'])
                  Text(
                    'Next: ${_getTimeUntilNext(task['nextOccurrence'])}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: isOverdue ? Colors.red : Colors.grey[600],
                      fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (task['nextOccurrence'] != null)
              Text(
                'Next occurrence: ${DateTime.tryParse(task['nextOccurrence'])?.toLocal().toString().split('.')[0] ?? 'Unknown'}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.grey[500],
                ),
              ),
            if (task['recurringPattern'].isNotEmpty)
              Text(
                'Pattern: ${task['recurringPattern']}',
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

  Widget _buildStatsCard() {
    final activeCount = recurringTasks.where((t) => t['isActive']).length;
    final overdueCount = recurringTasks.where((t) {
      if (!t['isActive']) return false;
      final next = DateTime.tryParse(t['nextOccurrence'] ?? '');
      return next?.isBefore(DateTime.now()) ?? false;
    }).length;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    '$activeCount',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  Text(
                    'Active',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 40,
              width: 1,
              color: Colors.grey[300],
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '$overdueCount',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  Text(
                    'Overdue',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 40,
              width: 1,
              color: Colors.grey[300],
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${recurringTasks.length}',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Text(
                    'Total',
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
            'Recurring Tasks',
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
          ],
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            _buildStatsCard(),
            Expanded(
              child: recurringTasks.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.repeat,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No recurring tasks found.',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create your first recurring task!',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: recurringTasks.length,
                itemBuilder: (context, index) {
                  return _buildRecurringTaskCard(recurringTasks[index]);
                },
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