import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

enum TaskStatus { created, inProgress, completed, paused, blocked }

class TaskProgressPage extends StatefulWidget {
  final String? taskId;
  final String? taskTitle;

  const TaskProgressPage({super.key, this.taskId, this.taskTitle});

  @override
  State<TaskProgressPage> createState() => _TaskProgressPageState();
}

class _TaskProgressPageState extends State<TaskProgressPage> with TickerProviderStateMixin {
  late TabController _tabController;
  String selectedFilter = 'all';
  String sortBy = 'priority';
  bool isAscending = false;

  final List<String> filterOptions = ['all', 'created', 'inProgress', 'completed', 'blocked', 'paused'];
  final List<String> sortOptions = ['priority', 'progress', 'deadline', 'created'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'created': return Colors.blue;
      case 'inprogress': return Colors.orange;
      case 'completed': return Colors.green;
      case 'paused': return Colors.amber;
      case 'blocked': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getStatusDisplayName(String status) {
    switch (status.toLowerCase()) {
      case 'inprogress': return 'In Progress';
      case 'created': return 'Created';
      case 'completed': return 'Completed';
      case 'paused': return 'Paused';
      case 'blocked': return 'Blocked';
      default: return status;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'low': return Colors.green;
      case 'medium': return Colors.orange;
      case 'high': return Colors.red;
      case 'critical': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Future<void> _updateTaskProgress(String taskId, int newProgress) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Update in taskProgress collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(taskId)
          .update({
        'currentProgress': newProgress,
        'lastUpdated': Timestamp.now(),
        'status': newProgress == 100 ? 'completed' : 'inProgress',
      });

      // Update in jobs collection if it exists
      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(taskId)
          .get();

      if (jobDoc.exists) {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(taskId)
            .update({
          'progressPercentage': newProgress,
          'isCompleted': newProgress == 100,
        });
      }

      _showSnackBar('Progress updated successfully!');
    } catch (e) {
      _showSnackBar('Error updating progress: $e');
    }
  }

  Future<void> _updateTaskStatus(String taskId, String newStatus) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(taskId)
          .update({
        'status': newStatus,
        'lastUpdated': Timestamp.now(),
      });

      _showSnackBar('Status updated successfully!');
    } catch (e) {
      _showSnackBar('Error updating status: $e');
    }
  }

  Future<void> _addMilestone(String taskId, String milestoneTitle, String description) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final milestone = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': milestoneTitle,
        'description': description,
        'createdAt': Timestamp.now(),
        'isCompleted': false,
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(taskId)
          .update({
        'milestones': FieldValue.arrayUnion([milestone]),
        'lastUpdated': Timestamp.now(),
      });

      _showSnackBar('Milestone added successfully!');
    } catch (e) {
      _showSnackBar('Error adding milestone: $e');
    }
  }

  void _showProgressUpdateDialog(String taskId, int currentProgress) {
    int newProgress = currentProgress;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Update Progress', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current Progress: $currentProgress%', style: GoogleFonts.poppins()),
              const SizedBox(height: 16),
              Slider(
                value: newProgress.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '$newProgress%',
                onChanged: (value) => setStateDialog(() => newProgress = value.round()),
                activeColor: const Color(0xFF006D77),
              ),
              Text('New Progress: $newProgress%', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _updateTaskProgress(taskId, newProgress);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006D77)),
              child: Text('Update', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showMilestoneDialog(String taskId) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Milestone', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Milestone Title',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _addMilestone(taskId, titleController.text.trim(), descriptionController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006D77)),
            child: Text('Add', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showStatusUpdateDialog(String taskId, String currentStatus) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Status', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: TaskStatus.values.map((status) {
            final statusString = status.toString().split('.').last;
            return ListTile(
              title: Text(_getStatusDisplayName(statusString), style: GoogleFonts.poppins()),
              leading: Icon(
                Icons.circle,
                color: _getStatusColor(statusString),
              ),
              onTap: () {
                Navigator.pop(context);
                _updateTaskStatus(taskId, statusString);
              },
            );
          }).toList(),
        ),
      ),
    );
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

  Widget _buildFilterAndSort() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: selectedFilter,
              decoration: InputDecoration(
                labelText: 'Filter',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: filterOptions.map((filter) => DropdownMenuItem(
                value: filter,
                child: Text(_getStatusDisplayName(filter), style: GoogleFonts.poppins()),
              )).toList(),
              onChanged: (value) => setState(() => selectedFilter = value ?? 'all'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: sortBy,
              decoration: InputDecoration(
                labelText: 'Sort By',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: sortOptions.map((sort) => DropdownMenuItem(
                value: sort,
                child: Text(sort.capitalize(), style: GoogleFonts.poppins()),
              )).toList(),
              onChanged: (value) => setState(() => sortBy = value ?? 'priority'),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => isAscending = !isAscending),
            icon: Icon(isAscending ? Icons.arrow_upward : Icons.arrow_downward),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> taskData, String taskId) {
    final progress = taskData['currentProgress'] ?? 0;
    final status = taskData['status'] ?? 'created';
    final priority = taskData['priority'] ?? 'medium';
    final title = taskData['taskTitle'] ?? 'Untitled Task';
    final milestones = (taskData['milestones'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final dependencies = (taskData['dependencies'] as List?)?.cast<String>() ?? [];
    final isBlocked = taskData['isBlocked'] ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_getPriorityColor(priority).withOpacity(0.1), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: const Color(0xFF006D77),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getStatusDisplayName(status),
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getPriorityColor(priority),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        priority.toUpperCase(),
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isBlocked) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.block, color: Colors.red, size: 16),
                      Text(
                        'BLOCKED',
                        style: GoogleFonts.poppins(
                          color: Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      'Progress: $progress%',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress / 100,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(status)),
                ),
                if (dependencies.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.link, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Dependencies: ${dependencies.length}',
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
                if (milestones.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.flag, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Milestones: ${milestones.where((m) => m['isCompleted'] == true).length}/${milestones.length}',
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionButton(
                  icon: Icons.edit,
                  label: 'Progress',
                  onPressed: () => _showProgressUpdateDialog(taskId, progress),
                ),
                _buildActionButton(
                  icon: Icons.flag,
                  label: 'Milestone',
                  onPressed: () => _showMilestoneDialog(taskId),
                ),
                _buildActionButton(
                  icon: Icons.update,
                  label: 'Status',
                  onPressed: () => _showStatusUpdateDialog(taskId, status),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF006D77), size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: const Color(0xFF006D77),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please log in.'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var tasks = snapshot.data!.docs;

        // Apply filters
        if (selectedFilter != 'all') {
          tasks = tasks.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] ?? 'created';
            return status.toLowerCase() == selectedFilter.toLowerCase();
          }).toList();
        }

        // Apply sorting
        tasks.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;

          switch (sortBy) {
            case 'priority':
              final priorityOrder = {'low': 1, 'medium': 2, 'high': 3, 'critical': 4};
              final priorityA = priorityOrder[dataA['priority']?.toLowerCase()] ?? 0;
              final priorityB = priorityOrder[dataB['priority']?.toLowerCase()] ?? 0;
              return isAscending ? priorityA.compareTo(priorityB) : priorityB.compareTo(priorityA);
            case 'progress':
              final progressA = dataA['currentProgress'] ?? 0;
              final progressB = dataB['currentProgress'] ?? 0;
              return isAscending ? progressA.compareTo(progressB) : progressB.compareTo(progressA);
            case 'created':
              final createdA = dataA['createdAt'] as Timestamp?;
              final createdB = dataB['createdAt'] as Timestamp?;
              if (createdA == null || createdB == null) return 0;
              return isAscending ? createdA.compareTo(createdB) : createdB.compareTo(createdA);
            default:
              return 0;
          }
        });

        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No tasks found',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  selectedFilter == 'all'
                      ? 'Create your first task to get started!'
                      : 'No tasks match the selected filter.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final taskData = tasks[index].data() as Map<String, dynamic>;
            final taskId = tasks[index].id;
            return _buildTaskCard(taskData, taskId);
          },
        );
      },
    );
  }

  Widget _buildOverviewTab() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please log in.'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final tasks = snapshot.data!.docs;
        final totalTasks = tasks.length;
        final completedTasks = tasks.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['status'] == 'completed';
        }).length;
        final inProgressTasks = tasks.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['status'] == 'inProgress';
        }).length;
        final blockedTasks = tasks.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['isBlocked'] == true;
        }).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Overview',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF006D77),
                ),
              ),
              const SizedBox(height: 20),
              _buildStatCard('Total Tasks', totalTasks.toString(), Icons.assignment, Colors.blue),
              _buildStatCard('Completed', completedTasks.toString(), Icons.check_circle, Colors.green),
              _buildStatCard('In Progress', inProgressTasks.toString(), Icons.hourglass_empty, Colors.orange),
              _buildStatCard('Blocked', blockedTasks.toString(), Icons.block, Colors.red),
              const SizedBox(height: 20),
              if (totalTasks > 0) ...[
                Text(
                  'Progress Overview',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF006D77),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Overall Completion',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '${((completedTasks / totalTasks) * 100).round()}%',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: completedTasks / totalTasks,
                        backgroundColor: Colors.grey[300],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF006D77),
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
            'Task Progress',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'All Tasks'),
              Tab(text: 'Analytics'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(),
            Column(
              children: [
                _buildFilterAndSort(),
                Expanded(child: _buildTaskList()),
              ],
            ),
            Center(
              child: Text(
                'Analytics Coming Soon',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
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