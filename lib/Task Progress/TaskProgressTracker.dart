import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'ProgressUpdateNotifier.dart';
import 'TaskProgressTrackerDetail.dart';

class ProgressService {
  static Stream<double> getTaskProgressStream(String taskId, String userId) {
    if (taskId.isEmpty) return Stream.value(0.0);

    return FirebaseFirestore.instance.collection('jobs').doc(taskId).snapshots().map((snapshot) {
      if (!snapshot.exists) return 0.0;

      final progressList = snapshot.data()?['progressPercentage'] as List<dynamic>? ?? [];
      final userProgress = progressList.firstWhere(
            (item) => item is Map && item['userId'] == userId,
        orElse: () => {'progress': 0.0},
      );
      return (userProgress['progress'] as num).toDouble();
    });
  }

  static Stream<double> getEmployerProgressStream(String taskId) {
    return FirebaseFirestore.instance.collection('jobs').doc(taskId).snapshots().map((snapshot) {
      if (!snapshot.exists) return 0.0;

      final progressList = snapshot.data()?['progressPercentage'] as List<dynamic>? ?? [];
      if (progressList.isEmpty) return 0.0;

      final total = progressList.fold(0.0, (sum, item) {
        return sum + (item is Map ? (item['progress'] as num).toDouble() : 0.0);
      });

      return total / progressList.length;
    });
  }
}

class TaskProgressTracker extends StatefulWidget {
  const TaskProgressTracker({super.key});

  @override
  State<TaskProgressTracker> createState() => _TaskProgressTrackerState();
}

class _TaskProgressTrackerState extends State<TaskProgressTracker> with SingleTickerProviderStateMixin {
  String? _currentUserId;
  late TabController _tabController;
  final ProgressUpdateNotifier _updateNotifier = ProgressUpdateNotifier();

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _extractStringFromDynamic(dynamic value, String fallback) {
    if (value == null) return fallback;

    if (value is String) {
      return value.isNotEmpty ? value : fallback;
    } else if (value is List<dynamic>) {
      if (value.isNotEmpty) {
        final first = value.firstWhere((v) => v is String && v.isNotEmpty, orElse: () => fallback);
        return first.toString();
      }
      return fallback;
    } else if (value is Map<String, dynamic>) {
      return value['title']?.toString() ??
          value['name']?.toString() ??
          value['jobPosition']?.toString() ??
          fallback;
    }
    return value.toString().isNotEmpty ? value.toString() : fallback;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Not Started': return Colors.grey;
      case 'In Progress': return Colors.blue;
      case 'On Hold': return Colors.orange;
      case 'Completed': return Colors.green;
      case 'Pending Review': return Colors.yellow;
      case 'Rejected': return Colors.red;
      case 'Cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildTaskCard(Map<String, dynamic> task, bool isEmployer) {
    return StreamBuilder<double>(
      stream: isEmployer
          ? ProgressService.getEmployerProgressStream(task['id'])
          : ProgressService.getTaskProgressStream(task['id'], _currentUserId!),
      builder: (context, progressSnapshot) {
        final progress = progressSnapshot.data ?? 0.0;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            title: Text(
              task['title'],
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF006D77)),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Progress: ${progress.toStringAsFixed(1)}%', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[700])),
                Text('Status: ${task['status']}', style: GoogleFonts.poppins(fontSize: 14, color: _getStatusColor(task['status']))),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TaskProgressTrackerDetail(
                    taskId: task['id'],
                    taskTitle: task['title'],
                    updateNotifier: _updateNotifier,
                  ),
                ),
              );
            },
          ),
        );
      },
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
            'My Tasks',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
          ),
          backgroundColor: const Color(0xFF006D77),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {}),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Created Jobs'),
              Tab(text: 'Applied Jobs'),
            ],
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
        ),
        body: _currentUserId == null
            ? const Center(child: Text('Please log in.'))
            : TabBarView(
          controller: _tabController,
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('jobs')
                  .where('postedBy', isEqualTo: _currentUserId)
                  .where('isShortTerm', isEqualTo: true)
                  .snapshots(),
              builder: (context, employerSnapshot) {
                if (employerSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final createdTasks = employerSnapshot.data?.docs ?? [];
                if (createdTasks.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.task_alt, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No short-term tasks found.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                        SizedBox(height: 8),
                        Text('Long-term tasks don\'t use progress tracking.', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      ],
                    ),
                  );
                }

                final tasks = createdTasks.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  String title = _extractStringFromDynamic(data['jobPosition'], 'Unnamed Task');
                  String status = _extractStringFromDynamic(data['submissionStatus'], 'In Progress');
                  return {
                    'id': doc.id,
                    'title': title,
                    'status': status,
                  };
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) => _buildTaskCard(tasks[index], true),
                );
              },
            ),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('jobs')
                  .where('acceptedApplicants', arrayContains: _currentUserId)
                  .where('isShortTerm', isEqualTo: true)
                  .snapshots(),
              builder: (context, employeeSnapshot) {
                if (employeeSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final appliedTasks = employeeSnapshot.data?.docs ?? [];
                if (appliedTasks.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No short-term applied tasks found.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                        SizedBox(height: 8),
                        Text('Long-term tasks don\'t use progress tracking.', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      ],
                    ),
                  );
                }

                final tasks = appliedTasks.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  String title = _extractStringFromDynamic(data['jobPosition'], 'Unnamed Task');
                  String status = _extractStringFromDynamic(data['submissionStatus'], 'In Progress');
                  return {
                    'id': doc.id,
                    'title': title,
                    'status': status,
                  };
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) => _buildTaskCard(tasks[index], false),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}