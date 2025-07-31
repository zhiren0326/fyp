import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import 'AddJobPage.dart';

enum TaskDependencyLogic {
  strictAnd,      // All dependencies must be completed (current)
  flexibleAnd,    // All dependencies must be started (at least 1% progress)
  partialOr,      // At least 50% of dependencies must be completed
  anyOr,          // At least one dependency must be completed
  weighted,       // Dependencies have weights, need certain threshold
  conditional,    // Dependencies can have conditions
}

class TaskDependenciesManager extends StatefulWidget {
  const TaskDependenciesManager({super.key});

  @override
  State<TaskDependenciesManager> createState() => _TaskDependenciesManagerState();
}

class _TaskDependenciesManagerState extends State<TaskDependenciesManager> {
  List<Map<String, dynamic>> allTasks = [];
  List<Map<String, dynamic>> dependencyChains = [];
  bool isLoading = true;
  DependencyLogic selectedLogic = DependencyLogic.strictAnd;

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
          'dependencyLogic': DependencyLogic.values.firstWhere(
                (e) => e.toString() == data['dependencyLogic'],
            orElse: () => DependencyLogic.strictAnd,
          ),
          'dependencyWeights': Map<String, double>.from(
              data['dependencyWeights'] ?? {}),
          'dependencyThreshold': data['dependencyThreshold'] ?? 100.0,
          'status': data['isCompleted'] == true ? 'Completed' : 'Active',
          'progress': data['progressPercentage'] ?? 0,
          'isBlocked': false, // Will be calculated
          'blockingReasons': <String>[],
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
              'dependencyLogic': DependencyLogic.values.firstWhere(
                    (e) => e.toString() == task['dependencyLogic'],
                orElse: () => DependencyLogic.strictAnd,
              ),
              'dependencyWeights': Map<String, double>.from(
                  task['dependencyWeights'] ?? {}),
              'dependencyThreshold': task['dependencyThreshold'] ?? 100.0,
              'status': task['completed'] == true ? 'Completed' : 'Active',
              'progress': task['completed'] == true ? 100 : (task['progress'] ??
                  0),
              'isBlocked': false,
              'blockingReasons': <String>[],
            });
          }
        }
      }

      // Calculate blocking status for all tasks
      for (var task in tasks) {
        final blockingResult = _calculateBlockingStatus(task, tasks);
        task['isBlocked'] = blockingResult['isBlocked'];
        task['blockingReasons'] = blockingResult['reasons'];
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

  Map<String, dynamic> _calculateBlockingStatus(Map<String, dynamic> task,
      List<Map<String, dynamic>> allTasks) {
    List<String> blockingReasons = [];
    bool isBlocked = false;

    if (task['dependencies'].isEmpty) {
      return {'isBlocked': false, 'reasons': blockingReasons};
    }

    final dependencies = task['dependencies'] as List<String>;
    final logic = task['dependencyLogic'] as DependencyLogic;
    final weights = task['dependencyWeights'] as Map<String, double>;
    final threshold = task['dependencyThreshold'] as double;

    List<Map<String, dynamic>> dependencyTasks = [];

    // Get dependency task details
    for (String depId in dependencies) {
      final depTask = allTasks.firstWhere(
            (t) => t['id'] == depId,
        orElse: () =>
        {
          'id': depId,
          'title': 'Unknown Task',
          'status': 'Unknown',
          'progress': 0
        },
      );
      dependencyTasks.add(depTask);
    }

    switch (logic) {
      case DependencyLogic.strictAnd:
        for (var depTask in dependencyTasks) {
          if (depTask['status'] != 'Completed') {
            isBlocked = true;
            blockingReasons.add('${depTask['title']} must be completed');
          }
        }
        break;

      case DependencyLogic.flexibleAnd:
        for (var depTask in dependencyTasks) {
          if (depTask['progress'] == 0) {
            isBlocked = true;
            blockingReasons.add('${depTask['title']} must be started');
          }
        }
        break;

      case DependencyLogic.partialOr:
        final completedCount = dependencyTasks
            .where((t) => t['status'] == 'Completed')
            .length;
        final requiredCount = (dependencies.length * 0.5).ceil();
        if (completedCount < requiredCount) {
          isBlocked = true;
          blockingReasons.add('At least $requiredCount of ${dependencies
              .length} dependencies must be completed');
        }
        break;

      case DependencyLogic.anyOr:
        final hasAnyCompleted = dependencyTasks.any((t) =>
        t['status'] == 'Completed');
        if (!hasAnyCompleted) {
          isBlocked = true;
          blockingReasons.add('At least one dependency must be completed');
        }
        break;

      case DependencyLogic.weighted:
        double totalWeight = 0;
        double completedWeight = 0;

        for (var depTask in dependencyTasks) {
          final weight = weights[depTask['id']] ?? 1.0;
          totalWeight += weight;
          if (depTask['status'] == 'Completed') {
            completedWeight += weight;
          } else if (depTask['progress'] > 0) {
            completedWeight += weight * (depTask['progress'] / 100);
          }
        }

        final completionPercentage = totalWeight > 0 ? (completedWeight /
            totalWeight) * 100 : 0;
        if (completionPercentage < threshold) {
          isBlocked = true;
          blockingReasons.add(
              'Weighted completion ${completionPercentage.toStringAsFixed(
                  1)}% < ${threshold.toStringAsFixed(1)}% required');
        }
        break;

      case DependencyLogic.conditional:
      // Implement conditional logic based on task priority, dates, etc.
        final highPriorityDeps = dependencyTasks.where((t) =>
        (t['priority'] == 'High' || t['priority'] == 'Critical') &&
            t['status'] != 'Completed'
        ).toList();

        if (highPriorityDeps.isNotEmpty) {
          isBlocked = true;
          blockingReasons.add(
              'High priority dependencies must be completed first');
        }
        break;
    }

    return {'isBlocked': isBlocked, 'reasons': blockingReasons};
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
            'isBlocked': task['isBlocked'],
            'criticalPath': _isCriticalPath(chain),
            'blockingReasons': task['blockingReasons'],
          });
        }
      }
    }
  }

  List<String> _buildDependencyChain(String taskId, List<String> visited) {
    if (visited.contains(taskId)) {
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
      List<String> subChain = _buildDependencyChain(
          dependency, List.from(visited));
      chain.addAll(subChain);
    }

    return chain;
  }

  bool _isCriticalPath(List<String> chain) {
    return chain.length > 3;
  }

  void _showDependencyConfigDialog(String taskId) {
    final task = allTasks.firstWhere((t) => t['id'] == taskId);
    DependencyLogic currentLogic = task['dependencyLogic'];
    double currentThreshold = task['dependencyThreshold'];
    Map<String, double> currentWeights = Map.from(task['dependencyWeights']);

    showDialog(
      context: context,
      builder: (context) =>
          StatefulBuilder(
            builder: (context, setDialogState) =>
                AlertDialog(
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
                            'Task: ${task['title']}',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Dependency Logic:',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<DependencyLogic>(
                            value: currentLogic,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            items: DependencyLogic.values.map((logic) {
                              return DropdownMenuItem(
                                value: logic,
                                child: Text(_getDependencyLogicName(logic)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() => currentLogic = value!);
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _getDependencyLogicDescription(currentLogic),
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),
                          if (currentLogic == DependencyLogic.weighted) ...[
                            Text(
                              'Completion Threshold (%):',
                              style: GoogleFonts.poppins(fontWeight: FontWeight
                                  .w500),
                            ),
                            const SizedBox(height: 8),
                            Slider(
                              value: currentThreshold,
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '${currentThreshold.round()}%',
                              onChanged: (value) {
                                setDialogState(() => currentThreshold = value);
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Dependency Weights:',
                              style: GoogleFonts.poppins(fontWeight: FontWeight
                                  .w500),
                            ),
                            const SizedBox(height: 8),
                            ...task['dependencies'].map<Widget>((depId) {
                              final depTask = allTasks.firstWhere(
                                    (t) => t['id'] == depId,
                                orElse: () => {'title': 'Unknown Task'},
                              );
                              final currentWeight = currentWeights[depId] ??
                                  1.0;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        depTask['title'],
                                        style: GoogleFonts.poppins(
                                            fontSize: 12),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 100,
                                      child: Slider(
                                        value: currentWeight,
                                        min: 0.1,
                                        max: 5.0,
                                        divisions: 49,
                                        label: currentWeight.toStringAsFixed(1),
                                        onChanged: (value) {
                                          setDialogState(() =>
                                          currentWeights[depId] = value);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await _updateDependencyConfiguration(
                          taskId,
                          currentLogic,
                          currentThreshold,
                          currentWeights,
                        );
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006D77),
                      ),
                      child: const Text(
                          'Save', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
          ),
    );
  }

  String _getDependencyLogicName(DependencyLogic logic) {
    switch (logic) {
      case DependencyLogic.strictAnd:
        return 'Strict AND (All Complete)';
      case DependencyLogic.flexibleAnd:
        return 'Flexible AND (All Started)';
      case DependencyLogic.partialOr:
        return 'Partial OR (50% Complete)';
      case DependencyLogic.anyOr:
        return 'Any OR (One Complete)';
      case DependencyLogic.weighted:
        return 'Weighted (Custom Threshold)';
      case DependencyLogic.conditional:
        return 'Conditional (Priority Based)';
    }
  }

  String _getDependencyLogicDescription(DependencyLogic logic) {
    switch (logic) {
      case DependencyLogic.strictAnd:
        return 'Task can only start when ALL dependencies are 100% completed.';
      case DependencyLogic.flexibleAnd:
        return 'Task can start when ALL dependencies have been started (>0% progress).';
      case DependencyLogic.partialOr:
        return 'Task can start when at least 50% of dependencies are completed.';
      case DependencyLogic.anyOr:
        return 'Task can start when ANY ONE dependency is completed.';
      case DependencyLogic.weighted:
        return 'Dependencies have different weights. Task starts when weighted completion reaches threshold.';
      case DependencyLogic.conditional:
        return 'High priority dependencies must be completed first, others can be flexible.';
    }
  }

  Future<void> _updateDependencyConfiguration(String taskId,
      DependencyLogic logic,
      double threshold,
      Map<String, double> weights,) async {
    try {
      final task = allTasks.firstWhere((t) => t['id'] == taskId);

      if (task['type'] == 'job') {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(taskId)
            .update({
          'dependencyLogic': logic.toString(),
          'dependencyThreshold': threshold,
          'dependencyWeights': weights,
        });
      } else {
        // Handle personal tasks - this would require more complex logic
        // to update the nested task structure
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dependency configuration updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _loadAllTasks(); // Reload to recalculate blocking status
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating configuration: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
      }

      _loadAllTasks();

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

      _loadAllTasks();

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
        .where((t) =>
    t['id'] != taskId && !task['dependencies'].contains(t['id']))
        .toList();

    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text(
              'Add Dependency',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
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
                      'Type: ${availableTask['type']} | Priority: ${availableTask['priority']} | Progress: ${availableTask['progress']}%',
                      style: GoogleFonts.poppins(fontSize: 12),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: _getPriorityColor(
                          availableTask['priority']),
                      child: Text(
                        availableTask['type'] == 'job' ? 'J' : 'T',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(availableTask['status'])
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _getStatusColor(availableTask['status'])),
                      ),
                      child: Text(
                        availableTask['status'],
                        style: TextStyle(
                          color: _getStatusColor(availableTask['status']),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
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
      case 'Blocked':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final isBlocked = task['isBlocked'] as bool;
    final blockingReasons = task['blockingReasons'] as List<String>;
    final dependencyLogic = task['dependencyLogic'] as DependencyLogic;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isBlocked ? Colors.red[50] : Colors.white,
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
                        'Logic: ${_getDependencyLogicName(dependencyLogic)}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (dependencyLogic == DependencyLogic.weighted)
                        Text(
                          'Threshold: ${task['dependencyThreshold']}%',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isBlocked ? Colors.red : _getStatusColor(
                            task['status']).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isBlocked ? Colors.red : _getStatusColor(
                                task['status'])),
                      ),
                      child: Text(
                        isBlocked ? 'BLOCKED' : task['status'],
                        style: TextStyle(
                          color: isBlocked ? Colors.red : _getStatusColor(
                              task['status']),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    IconButton(
                      icon: const Icon(Icons.settings, size: 20),
                      onPressed: () => _showDependencyConfigDialog(task['id']),
                      tooltip: 'Configure Dependencies',
                    ),
                  ],
                ),
              ],
            ),
            if (task['dependencies'].isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Dependencies (${task['dependencies'].length}):',
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
                    orElse: () =>
                    {
                      'title': 'Unknown Task',
                      'status': 'Unknown',
                      'progress': 0
                    },
                  );

                  final weight = task['dependencyWeights'][depId] ?? 1.0;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(depTask['status']).withOpacity(
                          0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getStatusColor(depTask['status']),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              depTask['title'],
                              style: GoogleFonts.poppins(fontSize: 10),
                            ),
                            if (dependencyLogic == DependencyLogic.weighted)
                              Text(
                                'Weight: ${weight.toStringAsFixed(1)}',
                                style: GoogleFonts.poppins(
                                    fontSize: 8, color: Colors.grey[600]),
                              ),
                          ],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${depTask['progress']}%',
                          style: GoogleFonts.poppins(fontSize: 8),
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
            if (isBlocked && blockingReasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.block, color: Colors.red, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Blocking Reasons:',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...blockingReasons.map((reason) =>
                        Padding(
                          padding: const EdgeInsets.only(left: 20),
                          child: Text(
                            '• $reason',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.red[700],
                            ),
                          ),
                        )),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Progress: ${task['progress']}%',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 150,
                      child: LinearProgressIndicator(
                        value: task['progress'] / 100,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          task['progress'] < 30
                              ? Colors.red
                              : task['progress'] < 70
                              ? Colors.orange
                              : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _showAddDependencyDialog(task['id']),
                  icon: const Icon(Icons.add_link, size: 16),
                  label: const Text('Add Dependency'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006D77),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: GoogleFonts.poppins(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Task Dependencies',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF006D77),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip: 'Add New Task',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddJobPage(),
                ),
              ).then((_) => _loadAllTasks()); // Reload tasks after adding
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF006D77),
        ),
      )
          : allTasks.isEmpty
          ? Center(
        child: Text(
          'No tasks available. Add a task to get started!',
          style: GoogleFonts.poppins(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
      )
          : Column(
        children: [
          // Optional: Dependency Chains Summary
          if (dependencyChains.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[100],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dependency Chains (${dependencyChains.length})',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF006D77),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: dependencyChains.length,
                      itemBuilder: (context, index) {
                        final chain = dependencyChains[index];
                        final isCritical = chain['criticalPath'] as bool;
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isCritical
                                ? Colors.red[50]
                                : Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isCritical
                                  ? Colors.red
                                  : Colors.green,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment:
                            MainAxisAlignment.center,
                            children: [
                              Text(
                                'Chain: ${(chain['rootTask'] as Map<String, dynamic>)['title']}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'Tasks: ${(chain['chain'] as List).length}',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: Colors.grey[600],
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
            const Divider(height: 1),
          ],
          // Task List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAllTasks,
              color: const Color(0xFF006D77),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: allTasks.length,
                itemBuilder: (context, index) {
                  return _buildTaskCard(allTasks[index]);
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddJobPage(),
            ),
          ).then((_) => _loadAllTasks());
        },
        backgroundColor: const Color(0xFF006D77),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}