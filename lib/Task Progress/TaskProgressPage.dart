import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../Notification Module/NotificationService.dart';

enum TaskStatus { created, inProgress, completed, paused, blocked, pendingReview }

class TaskProgressPage extends StatefulWidget {
  final String? taskId;
  final String? taskTitle;
  final bool isEmployer;
  final String? applicantId;

  const TaskProgressPage({
    super.key,
    this.taskId,
    this.taskTitle,
    this.isEmployer = false,
    this.applicantId,
  });

  @override
  State<TaskProgressPage> createState() => _TaskProgressPageState();
}

class _TaskProgressPageState extends State<TaskProgressPage> with TickerProviderStateMixin {
  late TabController _tabController;
  String selectedFilter = 'all';
  String sortBy = 'priority';
  bool isAscending = false;

  final List<String> filterOptions = ['all', 'created', 'inProgress', 'completed', 'blocked', 'paused', 'pendingReview'];
  final List<String> sortOptions = ['priority', 'progress', 'deadline', 'created'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final user = FirebaseAuth.instance.currentUser;
    print('TaskProgressPage - User authenticated: ${user != null}');
    print('TaskProgressPage - User ID: ${user?.uid}');
    if (user != null) {
      print('TaskProgressPage - User email: ${user.email}');
    }
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
      case 'pendingreview': return Colors.purple;
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
      case 'pendingreview': return 'Pending Review';
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

  Future<void> _updateTaskProgress(String taskId, int newProgress, {String? completionNotes}) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _showSnackBar('User not authenticated.');
        return;
      }

      // Check if user is allowed to edit
      final taskProgressDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(taskId)
          .get();

      if (!taskProgressDoc.exists) {
        _showSnackBar('Task not found.');
        return;
      }

      final taskData = taskProgressDoc.data()!;
      final canEditProgress = List<String>.from(taskData['canEditProgress'] ?? []);
      if (!canEditProgress.contains(currentUser.uid)) {
        _showSnackBar('You do not have permission to edit this task.');
        return;
      }

      // Prepare update data
      final updateData = {
        'currentProgress': newProgress,
        'lastUpdated': Timestamp.now(),
        'status': newProgress == 100 ? 'pendingReview' : 'inProgress',
      };

      if (newProgress == 100) {
        updateData['completionRequested'] = true;
        updateData['completionNotes'] = completionNotes ?? '';
      }

      // Update taskProgress
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(taskId)
          .update(updateData);

      // Update history
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(taskId)
          .collection('history')
          .add({
        'progress': newProgress,
        'status': newProgress == 100 ? 'pendingReview' : 'inProgress',
        'notes': newProgress == 100 ? 'Completion requested' : 'Progress updated',
        'timestamp': Timestamp.now(),
        'action': newProgress == 100 ? 'completion_requested' : 'progress_updated',
      });

      // Update jobs collection
      final jobDoc = await FirebaseFirestore.instance.collection('jobs').doc(taskId).get();
      if (jobDoc.exists) {
        await FirebaseFirestore.instance.collection('jobs').doc(taskId).update({
          'progressPercentage': newProgress,
          'isCompleted': newProgress == 100 && taskData['completionApproved'] == true,
        });

        // Notify employer for completion review
        if (newProgress == 100) {
          final jobData = jobDoc.data()!;
          final jobCreatorId = jobData['jobCreator'] ?? jobData['postedBy'];
          final taskTitle = jobData['jobPosition'] ?? 'Task';

          // Create notification for employer
          await FirebaseFirestore.instance
              .collection('users')
              .doc(jobCreatorId)
              .collection('notifications')
              .add({
            'message': 'Task "$taskTitle" completion requested by employee. Please review.',
            'timestamp': FieldValue.serverTimestamp(),
            'read': false,
            'type': 'completion_request',
            'taskId': taskId,
            'employeeId': currentUser.uid,
            'completionNotes': completionNotes ?? '',
          });
        }
      }

      _showSnackBar(newProgress == 100 ? 'Completion requested! Waiting for employer review.' : 'Progress updated successfully!');
    } catch (e) {
      _showSnackBar('Error updating progress: $e');
    }
  }

  Future<void> _updateTaskStatus(String taskId, String newStatus) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _showSnackBar('User not authenticated.');
        return;
      }

      if (newStatus == 'completed') {
        _showSnackBar('Please set progress to 100% to request completion.');
        return;
      }

      // Check edit permission
      final taskProgressDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(taskId)
          .get();

      if (!taskProgressDoc.exists) {
        _showSnackBar('Task not found.');
        return;
      }

      final taskData = taskProgressDoc.data()!;
      final canEditProgress = List<String>.from(taskData['canEditProgress'] ?? []);
      if (!canEditProgress.contains(currentUser.uid)) {
        _showSnackBar('You do not have permission to edit this task.');
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(taskId)
          .update({
        'status': newStatus,
        'lastUpdated': Timestamp.now(),
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(taskId)
          .collection('history')
          .add({
        'status': newStatus,
        'notes': 'Status updated to $newStatus',
        'timestamp': Timestamp.now(),
        'action': 'status_updated',
      });

      _showSnackBar('Status updated successfully!');
    } catch (e) {
      _showSnackBar('Error updating status: $e');
    }
  }

  Future<void> _addMilestone(String taskId, String milestoneTitle, String description) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _showSnackBar('User not authenticated.');
        return;
      }

      final taskProgressDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(taskId)
          .get();

      if (!taskProgressDoc.exists) {
        _showSnackBar('Task not found.');
        return;
      }

      final taskData = taskProgressDoc.data()!;
      final canEditProgress = List<String>.from(taskData['canEditProgress'] ?? []);
      if (!canEditProgress.contains(currentUser.uid)) {
        _showSnackBar('You do not have permission to edit this task.');
        return;
      }

      final milestone = {
        'id': (DateTime.now().millisecondsSinceEpoch % 1000000).toString(),
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

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(taskId)
          .collection('history')
          .add({
        'notes': 'Milestone added: $milestoneTitle',
        'timestamp': Timestamp.now(),
        'action': 'milestone_added',
      });

      _showSnackBar('Milestone added successfully!');
    } catch (e) {
      _showSnackBar('Error adding milestone: $e');
    }
  }

  void _showProgressUpdateDialog(String taskId, int currentProgress) {
    int newProgress = currentProgress;
    final completionNotesController = TextEditingController();

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
              if (newProgress == 100) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: completionNotesController,
                  decoration: InputDecoration(
                    labelText: 'Completion Notes (Optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  maxLines: 3,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _updateTaskProgress(taskId, newProgress, completionNotes: completionNotesController.text.trim());
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006D77)),
              child: Text(newProgress == 100 ? 'Request Completion Review' : 'Update Progress', style: GoogleFonts.poppins(color: Colors.white)),
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
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _addMilestone(taskId, titleController.text.trim(), descriptionController.text.trim());
              } else {
                _showSnackBar('Milestone title is required.');
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
          children: TaskStatus.values
              .where((status) => status != TaskStatus.completed)
              .map((status) {
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF006D77),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _viewEmployeeTaskProgress(String jobId, String employeeId, String jobPosition) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaskProgressPage(
          taskId: jobId,
          taskTitle: jobPosition,
          isEmployer: true,
          applicantId: employeeId,
        ),
      ),
    );
  }

  // Created Tasks Tab - Shows tasks created by current user and their employees' progress
  Widget _buildCreatedTasksTab() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Center(child: Text('Please log in.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('postedBy', isEqualTo: currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          print('Error in created tasks StreamBuilder: ${snapshot.error}');
          return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()));
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('No data available.', style: TextStyle(fontSize: 16)));
        }

        final jobs = snapshot.data!.docs;
        print('Found ${jobs.length} created jobs');

        if (jobs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.work_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No tasks created.', style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600])),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final doc = jobs[index];
            final data = doc.data() as Map<String, dynamic>;
            final jobId = doc.id;
            final jobPosition = data['jobPosition'] ?? 'Untitled Job';
            final acceptedApplicants = data['acceptedApplicants'] as List? ?? [];
            final postedAt = data['postedAt'] as Timestamp?;
            final progressPercentage = data['progressPercentage']?.toDouble() ?? 0.0;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ExpansionTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.assignment, color: Colors.teal),
                ),
                title: Text(
                    jobPosition,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16)
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                        'Posted: ${postedAt?.toDate().toString().split('.')[0] ?? 'N/A'}',
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])
                    ),
                    Text(
                        'Team Members: ${acceptedApplicants.length}',
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: progressPercentage / 100,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                                progressPercentage == 100 ? Colors.green : Colors.orange
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${progressPercentage.toStringAsFixed(0)}%',
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
                children: [
                  if (acceptedApplicants.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No team members assigned yet.',
                        style: GoogleFonts.poppins(color: Colors.grey[600]),
                      ),
                    )
                  else
                    ...acceptedApplicants.map<Widget>((employeeId) {
                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('users').doc(employeeId).get(),
                        builder: (context, userSnapshot) {
                          if (!userSnapshot.hasData) {
                            return const SizedBox.shrink();
                          }

                          final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                          final employeeName = userData?['name'] ?? 'Unknown User';

                          return FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .doc(employeeId)
                                .collection('taskProgress')
                                .doc(jobId)
                                .get(),
                            builder: (context, taskSnapshot) {
                              final taskData = taskSnapshot.data?.data() as Map<String, dynamic>?;
                              final progress = taskData?['currentProgress']?.toDouble() ?? 0.0;
                              final status = taskData?['status'] ?? 'created';
                              final lastUpdated = taskData?['lastUpdated'] as Timestamp?;

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _getStatusColor(status),
                                  child: Text(
                                    employeeName.substring(0, 1).toUpperCase(),
                                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(employeeName, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Status: ${_getStatusDisplayName(status)}',
                                      style: GoogleFonts.poppins(fontSize: 12),
                                    ),
                                    if (lastUpdated != null)
                                      Text(
                                        'Last updated: ${lastUpdated.toDate().toString().split('.')[0]}',
                                        style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '${progress.toStringAsFixed(0)}%',
                                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                                        ),
                                        Container(
                                          width: 40,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[300],
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                          child: FractionallySizedBox(
                                            alignment: Alignment.centerLeft,
                                            widthFactor: progress / 100,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: _getStatusColor(status),
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.visibility, color: Colors.teal),
                                      onPressed: () => _viewEmployeeTaskProgress(jobId, employeeId, jobPosition),
                                      tooltip: 'View Progress Details',
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      );
                    }).toList(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Applied Tasks Tab - Shows tasks the current user is working on
  // Replace the _buildAppliedTasksTab() method with this:

  Widget _buildAppliedTasksTab() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return Center(child: Text('Please log in.', style: GoogleFonts.poppins()));
    }

    print('Current user ID: ${currentUser.uid}');

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          print('Error in applied tasks: ${snapshot.error}');
          return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.work_off_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No assigned tasks.', style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600])),
              ],
            ),
          );
        }

        var tasks = snapshot.data!.docs;

        // Apply filter
        if (selectedFilter != 'all') {
          tasks = tasks.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['status']?.toLowerCase() == selectedFilter;
          }).toList();
        }

        return Column(
          children: [
            _buildFilterAndSort(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final taskDoc = tasks[index];
                  final taskData = taskDoc.data() as Map<String, dynamic>;
                  final taskId = taskDoc.id;
                  return _buildTaskCard(taskData, taskId);
                },
              ),
            ),
          ],
        );
      },
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
    final progress = taskData['currentProgress']?.toDouble() ?? 0.0;
    final status = taskData['status'] ?? 'created';
    final priority = taskData['priority'] ?? 'medium';
    final title = taskData['taskTitle'] ?? 'Untitled Task';
    final milestones = (taskData['milestones'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final dependencies = (taskData['dependencies'] as List?)?.cast<String>() ?? [];
    final isBlocked = taskData['isBlocked'] ?? false;
    final completionRequested = taskData['completionRequested'] ?? false;
    final completionApproved = taskData['completionApproved'] ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
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
                    if (completionRequested && !completionApproved) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Pending Review',
                          style: GoogleFonts.poppins(
                            color: Colors.orange[700],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      'Progress: ${progress.toStringAsFixed(1)}%',
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
                // Show completion request status
                if (completionRequested && !completionApproved) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.pending_actions, size: 16, color: Colors.orange[700]),
                            const SizedBox(width: 4),
                            Text(
                              'Awaiting Employer Review',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                        if (taskData['completionNotes'] != null && taskData['completionNotes'].isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Notes: ${taskData['completionNotes']}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.orange[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Action buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionButton(
                  icon: Icons.edit,
                  label: 'Progress',
                  onPressed: (completionRequested && !completionApproved)
                      ? null
                      : () => _showProgressUpdateDialog(taskId, progress.toInt()),
                ),
                _buildActionButton(
                  icon: Icons.flag,
                  label: 'Milestone',
                  onPressed: (completionRequested && !completionApproved)
                      ? null
                      : () => _showMilestoneDialog(taskId),
                ),
                _buildActionButton(
                  icon: Icons.update,
                  label: 'Status',
                  onPressed: (completionRequested && !completionApproved)
                      ? null
                      : () => _showStatusUpdateDialog(taskId, status),
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
    required VoidCallback? onPressed,
  }) {
    final isDisabled = onPressed == null;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(
                icon,
                color: isDisabled ? Colors.grey[400] : const Color(0xFF006D77),
                size: 20
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: isDisabled ? Colors.grey[400] : const Color(0xFF006D77),
                fontWeight: FontWeight.w500,
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
              Tab(text: 'Created Tasks'),
              Tab(text: 'Applied Tasks'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildCreatedTasksTab(),
            _buildAppliedTasksTab(),
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