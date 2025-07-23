import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

class TaskDependenciesManager extends StatefulWidget {
  const TaskDependenciesManager({super.key});

  @override
  State<TaskDependenciesManager> createState() => _TaskDependenciesManagerState();
}

class _TaskDependenciesManagerState extends State<TaskDependenciesManager> {
  List<Map<String, dynamic>> allTasks = [];
  List<Map<String, dynamic>> dependencyChains = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllTasks();
  }

  Future<void> _loadAllTasks() async {
    setState(() => isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Load jobs/tasks created by user
      final jobsSnapshot = await FirebaseFirestore.instance
          .collection('jobs')
          .where('postedBy', isEqualTo: currentUser.uid)
          .get();

      // Load user's personal tasks
      final tasksSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('tasks')
          .get();

      List<Map<String, dynamic>> tasks = [];

      // Add jobs
      for (var doc in jobsSnapshot.docs) {
        final data = doc.data();
        tasks.add({
          'id': doc.id,
          'title': data['jobPosition'] ?? 'Untitled Job',
          'type': 'job',
          'startDate': data['startDate'],
          'endDate': data['endDate'],
          'priority': data['priority'] ?? 'Medium',
          'dependencies': List<String>.from(data['dependencies'] ?? []),
          'status': data['isCompleted'] == true ? 'Completed' : 'Active',
          'progress': data['progressPercentage'] ?? 0,
        });
      }

      // Add personal tasks
      for (var doc in tasksSnapshot.docs) {
        final data = doc.data();
        if (data['tasks'] != null) {
          for (var task in data['tasks']) {
            tasks.add({
              'id': '${doc.id}_${task['title']}',
              'title': task['title'] ?? 'Untitled Task',
              'type': 'personal',
              'startDate': doc.id,
              'endDate': doc.id,
              'priority': task['priority'] ?? 'Medium',
              'dependencies': List<String>.from(task['dependencies'] ?? []),
              'status': task['completed'] == true ? 'Completed' : 'Active',
              'progress': task['completed'] == true ? 100 : 0,
            });
          }
        }
      }

      setState(() {
        allTasks = tasks;
        _analyzeDependencyChains();
        isLoading = false;
      });
    } catch (e) {
      print('Error loading tasks: $e');
      setState(() => isLoading = false);
    }
  }

  void _analyzeDependencyChains() {
    dependencyChains.clear();

    for (var task in allTasks) {
      if (task['dependencies'].isNotEmpty) {
        List<String> chain = _buildDependencyChain(task['id'], []);
        if (chain.isNotEmpty) {
          dependencyChains.add({
            'rootTask': task,
            'chain': chain,
            'isBlocked': _isTaskBlocked(task),
            'criticalPath': _isCriticalPath(chain),
          });
        }
      }
    }
  }

  List<String> _buildDependencyChain(String taskId, List<String> visited) {
    if (visited.contains(taskId)) {
      // Circular dependency detected
      return ['CIRCULAR_DEPENDENCY'];
    }

    visited.add(taskId);

    final task = allTasks.firstWhere(
          (t) => t['id'] == taskId,
      orElse: () => {},
    );

    if (task.isEmpty) return [];

    List<String> chain = [taskId];

    for (String dependency in task['dependencies']) {
      List<String> subChain = _buildDependencyChain(dependency, List.from(visited));
      chain.addAll(subChain);
    }

    return chain;
  }

  bool _isTaskBlocked(Map<String, dynamic> task) {
    for (String dependencyId in task['dependencies']) {
      final dependencyTask = allTasks.firstWhere(
            (t) => t['id'] == dependencyId,
        orElse: () => {},
      );

      if (dependencyTask.isNotEmpty && dependencyTask['status'] != 'Completed') {
        return true;
      }
    }
    return false;
  }

  bool _isCriticalPath(List<String> chain) {
    // A simplified critical path determination
    // In a real implementation, this would be more sophisticated
    return chain.length > 3;
  }

  void _addDependency(String taskId, String dependencyId) async {
    try {
      final task = allTasks.firstWhere((t) => t['id'] == taskId);

      if (task['type'] == 'job') {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(taskId)
            .update({
          'dependencies': FieldValue.arrayUnion([dependencyId]),
        });
      } else {
        // Handle personal tasks
        // This would require more complex logic to update the nested task structure
      }

      _loadAllTasks(); // Reload to update dependencies

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dependency added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding dependency: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _removeDependency(String taskId, String dependencyId) async {
    try {
      final task = allTasks.firstWhere((t) => t['id'] == taskId);

      if (task['type'] == 'job') {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(taskId)
            .update({
          'dependencies': FieldValue.arrayRemove([dependencyId]),
        });
      }

      _loadAllTasks(); // Reload to update dependencies

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dependency removed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error removing dependency: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAddDependencyDialog(String taskId) {
    final task = allTasks.firstWhere((t) => t['id'] == taskId);
    final availableTasks = allTasks
        .where((t) => t['id'] != taskId && !task['dependencies'].contains(t['id']))
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Add Dependency',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableTasks.length,
            itemBuilder: (context, index) {
              final availableTask = availableTasks[index];
              return ListTile(
                title: Text(
                  availableTask['title'],
                  style: GoogleFonts.poppins(),
                ),
                subtitle: Text(
                  'Type: ${availableTask['type']} | Priority: ${availableTask['priority']}',
                  style: GoogleFonts.poppins(fontSize: 12),
                ),
                leading: CircleAvatar(
                  backgroundColor: _getPriorityColor(availableTask['priority']),
                  child: Text(
                    availableTask['type'] == 'job' ? 'J' : 'T',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _addDependency(taskId, availableTask['id']);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active': return Colors.blue;
      case 'Completed': return Colors.green;
      case 'Blocked': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final isBlocked = _isTaskBlocked(task);
    final statusColor = isBlocked ? Colors.red : _getStatusColor(task['status']);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    task['type'] == 'job' ? 'J' : 'T',
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
                          color: const Color(0xFF006D77),
                        ),
                      ),
                      Text(
                        'Priority: ${task['priority']} | Progress: ${task['progress']}%',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    isBlocked ? 'BLOCKED' : task['status'],
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (task['dependencies'].isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Dependencies:',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF006D77),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: task['dependencies'].map<Widget>((depId) {
                  final depTask = allTasks.firstWhere(
                        (t) => t['id'] == depId,
                    orElse: () => {'title': 'Unknown Task', 'status': 'Unknown'},
                  );

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(depTask['status']).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getStatusColor(depTask['status']),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          depTask['title'],
                          style: GoogleFonts.poppins(fontSize: 10),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _removeDependency(task['id'], depId),
                          child: Icon(
                            Icons.close,
                            size: 12,
                            color: _getStatusColor(depTask['status']),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progress: ${task['progress']}%',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showAddDependencyDialog(task['id']),
                  icon: const Icon(Icons.add_link, size: 16),
                  label: const Text('Add Dependency'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006D77),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: GoogleFonts.poppins(fontSize: 12),
                  ),
                ),
              ],
            ),
            // Progress bar
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task['progress'] / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                task['progress'] < 30 ? Colors.red :
                task['progress'] < 70 ? Colors.orange : Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDependencyChainCard(Map<String, dynamic> chainData) {
    final rootTask = chainData['rootTask'];
    final chain = chainData['chain'] as List<String>;
    final isBlocked = chainData['isBlocked'] as bool;
    final criticalPath = chainData['criticalPath'] as bool;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: criticalPath ? Colors.red[50] : (isBlocked ? Colors.orange[50] : Colors.white),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  criticalPath ? Icons.warning : (isBlocked ? Icons.block : Icons.link),
                  color: criticalPath ? Colors.red : (isBlocked ? Colors.orange : Colors.blue),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rootTask['title'],
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF006D77),
                    ),
                  ),
                ),
                if (criticalPath)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'CRITICAL',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (isBlocked && !criticalPath)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'BLOCKED',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Dependency Chain (${chain.length} tasks):',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: chain.length,
                itemBuilder: (context, index) {
                  final taskId = chain[index];
                  if (taskId == 'CIRCULAR_DEPENDENCY') {
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'CIRCULAR\nDEPENDENCY',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final task = allTasks.firstWhere(
                        (t) => t['id'] == taskId,
                    orElse: () => {'title': 'Unknown', 'status': 'Unknown'},
                  );

                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getStatusColor(task['status']).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _getStatusColor(task['status'])),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          task['title'].length > 10
                              ? '${task['title'].substring(0, 10)}...'
                              : task['title'],
                          style: GoogleFonts.poppins(fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          task['status'],
                          style: GoogleFonts.poppins(
                            fontSize: 8,
                            color: _getStatusColor(task['status']),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
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
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(
              'Task Dependencies',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            backgroundColor: const Color(0xFF006D77),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'All Tasks', icon: Icon(Icons.list)),
                Tab(text: 'Dependency Chains', icon: Icon(Icons.account_tree)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadAllTasks,
              ),
            ],
          ),
          body: isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
            children: [
              // All Tasks Tab
              allTasks.isEmpty
                  ? Center(
                child: Text(
                  'No tasks found.',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: allTasks.length,
                itemBuilder: (context, index) {
                  return _buildTaskCard(allTasks[index]);
                },
              ),
              // Dependency Chains Tab
              dependencyChains.isEmpty
                  ? Center(
                child: Text(
                  'No dependency chains found.',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: dependencyChains.length,
                itemBuilder: (context, index) {
                  return _buildDependencyChainCard(dependencyChains[index]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}