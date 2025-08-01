import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

// Simplified enum with just the essential dependency types
enum DependencyLogic {
  all,        // All dependencies must be completed (was strictAnd)
  any,        // At least one dependency must be completed (was anyOr)
  weighted,   // Weighted completion with threshold
}

class TaskDependenciesManager extends StatefulWidget {
  const TaskDependenciesManager({super.key});

  @override
  State<TaskDependenciesManager> createState() => _TaskDependenciesManagerState();
}

class _TaskDependenciesManagerState extends State<TaskDependenciesManager> {
  List<TaskItem> allTasks = [];
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

      final tasks = await _fetchUserTasks(currentUser.uid);

      // Calculate blocking status for all tasks
      for (var task in tasks) {
        task.updateBlockingStatus(tasks);
      }

      setState(() {
        allTasks = tasks;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading tasks: $e');
      setState(() => isLoading = false);
    }
  }

  Future<List<TaskItem>> _fetchUserTasks(String userId) async {
    List<TaskItem> tasks = [];

    // Load jobs
    final jobsSnapshot = await FirebaseFirestore.instance
        .collection('jobs')
        .where('postedBy', isEqualTo: userId)
        .get();

    for (var doc in jobsSnapshot.docs) {
      tasks.add(TaskItem.fromJobDocument(doc));
    }

    // Load personal tasks
    final tasksSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('tasks')
        .get();

    for (var doc in tasksSnapshot.docs) {
      final data = doc.data();
      if (data['tasks'] != null) {
        for (var taskData in data['tasks']) {
          tasks.add(TaskItem.fromPersonalTask(doc.id, taskData));
        }
      }
    }

    return tasks;
  }

  // Simplified dependency configuration
  void _showDependencyConfigDialog(TaskItem task) {
    showDialog(
      context: context,
      builder: (context) => DependencyConfigDialog(
        task: task,
        allTasks: allTasks,
        onSave: (updatedTask) async {
          await _updateTaskDependencies(updatedTask);
          _loadAllTasks();
        },
      ),
    );
  }

  Future<void> _updateTaskDependencies(TaskItem task) async {
    try {
      if (task.type == 'job') {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(task.id)
            .update({
          'dependencies': task.dependencies,
          'dependencyLogic': task.dependencyLogic.toString(),
          'dependencyWeights': task.dependencyWeights,
          'dependencyThreshold': task.dependencyThreshold,
        });
      }
      // Handle personal tasks update here if needed

      await _logActivity('Updated Dependencies', task.id, task.title);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dependencies updated for ${task.title}!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _logActivity(String action, String taskId, String taskTitle) async {
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
        'taskTitle': taskTitle,
        'timestamp': Timestamp.now(),
        'details': {
          'type': 'dependency_update',
        },
      });
    } catch (e) {
      print('Error logging activity: $e');
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
            'Task Dependencies',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadAllTasks,
              tooltip: 'Refresh Tasks',
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
                          '${allTasks.length}',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text('Total Tasks', style: GoogleFonts.poppins(fontSize: 12)),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '${allTasks.where((t) => t.isBlocked).length}',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        Text('Blocked', style: GoogleFonts.poppins(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: allTasks.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.link_off, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No tasks found.',
                      style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: allTasks.length,
                itemBuilder: (context, index) => TaskCard(
                  task: allTasks[index],
                  allTasks: allTasks,
                  onConfigureDependencies: () => _showDependencyConfigDialog(allTasks[index]),
                  onDependencyChanged: _loadAllTasks,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Simplified Task Item class
class TaskItem {
  final String id;
  final String title;
  final String type;
  final String priority;
  final String status;
  final int progress;
  List<String> dependencies;
  DependencyLogic dependencyLogic;
  Map<String, double> dependencyWeights;
  double dependencyThreshold;
  bool isBlocked;
  List<String> blockingReasons;

  TaskItem({
    required this.id,
    required this.title,
    required this.type,
    required this.priority,
    required this.status,
    required this.progress,
    required this.dependencies,
    required this.dependencyLogic,
    required this.dependencyWeights,
    required this.dependencyThreshold,
    this.isBlocked = false,
    this.blockingReasons = const [],
  });

  factory TaskItem.fromJobDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return TaskItem(
      id: doc.id,
      title: data['jobPosition'] ?? 'Untitled Job',
      type: 'job',
      priority: data['priority'] ?? 'Medium',
      status: data['isCompleted'] == true ? 'Completed' : 'Active',
      progress: data['progressPercentage'] ?? 0,
      dependencies: List<String>.from(data['dependencies'] ?? []),
      dependencyLogic: _parseDependencyLogic(data['dependencyLogic']),
      dependencyWeights: Map<String, double>.from(data['dependencyWeights'] ?? {}),
      dependencyThreshold: data['dependencyThreshold'] ?? 100.0,
    );
  }

  factory TaskItem.fromPersonalTask(String docId, Map<String, dynamic> taskData) {
    return TaskItem(
      id: '${docId}_${taskData['title']}',
      title: taskData['title'] ?? 'Untitled Task',
      type: 'personal',
      priority: taskData['priority'] ?? 'Medium',
      status: taskData['completed'] == true ? 'Completed' : 'Active',
      progress: taskData['completed'] == true ? 100 : (taskData['progress'] ?? 0),
      dependencies: List<String>.from(taskData['dependencies'] ?? []),
      dependencyLogic: _parseDependencyLogic(taskData['dependencyLogic']),
      dependencyWeights: Map<String, double>.from(taskData['dependencyWeights'] ?? {}),
      dependencyThreshold: taskData['dependencyThreshold'] ?? 100.0, // Changed 'data' to 'taskData'
    );
  }

  static DependencyLogic _parseDependencyLogic(dynamic logic) {
    if (logic == null) return DependencyLogic.all;

    final logicStr = logic.toString();
    if (logicStr.contains('any') || logicStr.contains('anyOr')) {
      return DependencyLogic.any;
    } else if (logicStr.contains('weighted')) {
      return DependencyLogic.weighted;
    } else {
      return DependencyLogic.all;
    }
  }

  // Simplified blocking calculation
  void updateBlockingStatus(List<TaskItem> allTasks) {
    blockingReasons = [];
    isBlocked = false;

    if (dependencies.isEmpty) return;

    final dependencyTasks = dependencies
        .map((depId) => allTasks.firstWhere(
          (task) => task.id == depId,
      orElse: () => TaskItem(
        id: depId,
        title: 'Unknown Task',
        type: 'unknown',
        priority: 'Medium',
        status: 'Unknown',
        progress: 0,
        dependencies: [],
        dependencyLogic: DependencyLogic.all,
        dependencyWeights: {},
        dependencyThreshold: 100.0,
      ),
    ))
        .toList();

    switch (dependencyLogic) {
      case DependencyLogic.all:
        for (var dep in dependencyTasks) {
          if (dep.status != 'Completed') {
            isBlocked = true;
            blockingReasons.add('${dep.title} must be completed');
          }
        }
        break;

      case DependencyLogic.any:
        final hasCompleted = dependencyTasks.any((dep) => dep.status == 'Completed');
        if (!hasCompleted) {
          isBlocked = true;
          blockingReasons.add('At least one dependency must be completed');
        }
        break;

      case DependencyLogic.weighted:
        double totalWeight = 0;
        double completedWeight = 0;

        for (var dep in dependencyTasks) {
          final weight = dependencyWeights[dep.id] ?? 1.0;
          totalWeight += weight;

          if (dep.status == 'Completed') {
            completedWeight += weight;
          } else if (dep.progress > 0) {
            completedWeight += weight * (dep.progress / 100);
          }
        }

        final completionPercentage = totalWeight > 0 ? (completedWeight / totalWeight) * 100 : 0;
        if (completionPercentage < dependencyThreshold) {
          isBlocked = true;
          blockingReasons.add(
            'Weighted completion ${completionPercentage.toStringAsFixed(1)}% < ${dependencyThreshold.toStringAsFixed(1)}% required',
          );
        }
        break;
    }
  }
}

// Simplified Task Card Widget
class TaskCard extends StatelessWidget {
  final TaskItem task;
  final List<TaskItem> allTasks;
  final VoidCallback onConfigureDependencies;
  final VoidCallback onDependencyChanged;

  const TaskCard({
    super.key,
    required this.task,
    required this.allTasks,
    required this.onConfigureDependencies,
    required this.onDependencyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: task.isBlocked ? Colors.red[50] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getPriorityColor(task.priority),
                  radius: 20,
                  child: Text(
                    task.type == 'job' ? 'J' : 'T',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF006D77),
                        ),
                      ),
                      Text(
                        'Logic: ${_getDependencyLogicName(task.dependencyLogic)}',
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: onConfigureDependencies,
                  tooltip: 'Configure Dependencies',
                ),
              ],
            ),
            // Dependencies
            if (task.dependencies.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Text(
                      '${task.dependencies.length} deps',
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
              Wrap(
                spacing: 8,
                children: task.dependencies.map(_buildDependencyChip).toList(),
              ),
            ],
            // Blocking reasons
            if (task.isBlocked) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.block, color: Colors.red, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Blocked:',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red),
                        ),
                      ],
                    ),
                    ...task.blockingReasons.map(
                          (reason) => Text('• $reason', style: GoogleFonts.poppins(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
            // Progress
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progress: ${task.progress}%',
                        style: GoogleFonts.poppins(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: task.progress / 100,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(_getProgressColor(task.progress)),
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

  Widget _buildDependencyChip(String depId) {
    final dep = allTasks.firstWhere(
          (task) => task.id == depId,
      orElse: () => TaskItem(
        id: depId,
        title: 'Unknown',
        type: 'unknown',
        priority: 'Medium',
        status: 'Unknown',
        progress: 0,
        dependencies: [],
        dependencyLogic: DependencyLogic.all,
        dependencyWeights: {},
        dependencyThreshold: 100.0,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(dep.status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _getStatusColor(dep.status)),
      ),
      child: Text(
        '${dep.title} (${dep.progress}%)',
        style: GoogleFonts.poppins(fontSize: 10),
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'Low':
        return Colors.green;
      case 'Medium':
        return Colors.orange;
      case 'High':
        return Colors.red;
      case 'Critical':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.blue;
      case 'Completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getProgressColor(int progress) {
    if (progress < 30) return Colors.red;
    if (progress < 70) return Colors.orange;
    return Colors.green;
  }

  String _getDependencyLogicName(DependencyLogic logic) {
    switch (logic) {
      case DependencyLogic.all:
        return 'All Complete';
      case DependencyLogic.any:
        return 'Any Complete';
      case DependencyLogic.weighted:
        return 'Weighted';
    }
  }
}

// Simplified Dependency Configuration Dialog
class DependencyConfigDialog extends StatefulWidget {
  final TaskItem task;
  final List<TaskItem> allTasks;
  final Function(TaskItem) onSave;

  const DependencyConfigDialog({
    super.key,
    required this.task,
    required this.allTasks,
    required this.onSave,
  });

  @override
  State<DependencyConfigDialog> createState() => _DependencyConfigDialogState();
}

class _DependencyConfigDialogState extends State<DependencyConfigDialog> {
  late DependencyLogic selectedLogic;
  late double threshold;
  late Map<String, double> weights;
  late List<String> dependencies;

  @override
  void initState() {
    super.initState();
    selectedLogic = widget.task.dependencyLogic;
    threshold = widget.task.dependencyThreshold;
    weights = Map.from(widget.task.dependencyWeights);
    dependencies = List.from(widget.task.dependencies);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Configure Dependencies',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Task: ${widget.task.title}',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              // Logic selection
              Text(
                'Dependency Logic:',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
              DropdownButtonFormField<DependencyLogic>(
                value: selectedLogic,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: DependencyLogic.values.map((logic) {
                  return DropdownMenuItem(
                    value: logic,
                    child: Text(
                      _getLogicName(logic),
                      style: GoogleFonts.poppins(fontSize: 12),
                    ),
                  );
                }).toList(),
                onChanged: (value) => setState(() => selectedLogic = value!),
              ),
              const SizedBox(height: 16),
              Text(
                _getLogicDescription(selectedLogic),
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
              ),
              // Threshold for weighted logic
              if (selectedLogic == DependencyLogic.weighted) ...[
                const SizedBox(height: 16),
                Text(
                  'Threshold: ${threshold.round()}%',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
                Slider(
                  value: threshold,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${threshold.round()}%',
                  onChanged: (value) => setState(() => threshold = value),
                  activeColor: const Color(0xFF006D77),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Dependencies: ${dependencies.length} selected',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
              // Dependencies list
              ...widget.allTasks
                  .where((task) => task.id != widget.task.id)
                  .map((task) {
                final isSelected = dependencies.contains(task.id);
                return CheckboxListTile(
                  title: Text(task.title, style: GoogleFonts.poppins(fontSize: 12)),
                  subtitle: Text(
                    '${task.type} - ${task.progress}%',
                    style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey[600]),
                  ),
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        dependencies.add(task.id);
                        weights[task.id] = 1.0;
                      } else {
                        dependencies.remove(task.id);
                        weights.remove(task.id);
                      }
                    });
                  },
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: GoogleFonts.poppins(color: Colors.grey),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            final updatedTask = TaskItem(
              id: widget.task.id,
              title: widget.task.title,
              type: widget.task.type,
              priority: widget.task.priority,
              status: widget.task.status,
              progress: widget.task.progress,
              dependencies: dependencies,
              dependencyLogic: selectedLogic,
              dependencyWeights: weights,
              dependencyThreshold: threshold,
            );
            widget.onSave(updatedTask);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF006D77),
          ),
          child: Text(
            'Save',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
        ),
      ],
    );
  }

  String _getLogicName(DependencyLogic logic) {
    switch (logic) {
      case DependencyLogic.all:
        return 'All Dependencies Must Complete';
      case DependencyLogic.any:
        return 'Any One Dependency Must Complete';
      case DependencyLogic.weighted:
        return 'Weighted Completion Threshold';
    }
  }

  String _getLogicDescription(DependencyLogic logic) {
    switch (logic) {
      case DependencyLogic.all:
        return 'Task can only start when ALL dependencies are 100% completed.';
      case DependencyLogic.any:
        return 'Task can start when ANY ONE dependency is completed.';
      case DependencyLogic.weighted:
        return 'Dependencies have weights. Task starts when weighted completion reaches threshold.';
    }
  }
}