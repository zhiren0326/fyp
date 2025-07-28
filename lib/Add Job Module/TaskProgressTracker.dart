import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

class TaskProgressTracker extends StatefulWidget {
  final String? taskId;
  final String? taskTitle;

  const TaskProgressTracker({super.key, this.taskId, this.taskTitle});

  @override
  State<TaskProgressTracker> createState() => _TaskProgressTrackerState();
}

class _TaskProgressTrackerState extends State<TaskProgressTracker> {
  double currentProgress = 0.0;
  List<Map<String, dynamic>> milestones = [];
  List<Map<String, dynamic>> subTasks = [];
  String selectedStatus = 'In Progress';

  final TextEditingController milestoneController = TextEditingController();
  final TextEditingController progressController = TextEditingController();
  final TextEditingController subTaskController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  final List<String> statusOptions = [
    'Not Started',
    'In Progress',
    'On Hold',
    'Completed',
    'Cancelled'
  ];

  bool _isLoading = true;
  bool _canEditProgress = false; // Track if current user can edit progress
  String? _jobCreatorId; // Store job creator ID
  String? _currentUserId; // Store current user ID

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (widget.taskId != null) {
      _checkPermissionsAndLoadData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    milestoneController.dispose();
    progressController.dispose();
    subTaskController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionsAndLoadData() async {
    try {
      // First, check if user has permission to edit this task
      await _checkEditPermissions();

      // Then load the task progress data
      await _loadTaskProgress();
    } catch (e) {
      print('Error checking permissions and loading data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkEditPermissions() async {
    try {
      if (_currentUserId == null || widget.taskId == null) {
        setState(() => _canEditProgress = false);
        return;
      }

      // First check the job document to get the job creator
      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .get();

      if (jobDoc.exists) {
        final jobData = jobDoc.data()!;
        _jobCreatorId = jobData['jobCreator'] ?? jobData['postedBy'];

        // User can edit if they are the job creator
        _canEditProgress = _currentUserId == _jobCreatorId;
      }

      // Also check the taskProgress document for additional permissions
      final taskProgressDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId!)
          .collection('taskProgress')
          .doc(widget.taskId)
          .get();

      if (taskProgressDoc.exists) {
        final taskProgressData = taskProgressDoc.data()!;
        final canEditProgressList = List<String>.from(taskProgressData['canEditProgress'] ?? []);

        // User can edit if they are in the canEditProgress list
        if (canEditProgressList.contains(_currentUserId)) {
          _canEditProgress = true;
        }
      }

      setState(() {});
    } catch (e) {
      print('Error checking edit permissions: $e');
      setState(() => _canEditProgress = false);
    }
  }

  Future<void> _loadTaskProgress() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('taskProgress')
          .doc(widget.taskId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          currentProgress = (data['currentProgress'] ?? 0.0).toDouble();
          milestones = List<Map<String, dynamic>>.from(data['milestones'] ?? []);
          subTasks = List<Map<String, dynamic>>.from(data['subTasks'] ?? []);
          selectedStatus = statusOptions.contains(data['status']) ? data['status']! : 'In Progress';
          notesController.text = data['notes'] ?? '';
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading task progress: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProgress() async {
    if (!_canEditProgress) {
      _showErrorDialog('Permission Denied', 'You do not have permission to edit this task progress. Only the task creator can update progress.');
      return;
    }

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(widget.taskId ?? DateTime.now().millisecondsSinceEpoch.toString())
          .set({
        'taskId': widget.taskId,
        'taskTitle': widget.taskTitle,
        'currentProgress': currentProgress,
        'milestones': milestones,
        'subTasks': subTasks,
        'status': selectedStatus,
        'notes': notesController.text,
        'lastUpdated': Timestamp.now(),
        'jobCreator': _jobCreatorId,
        'canEditProgress': [_jobCreatorId], // Ensure only job creator can edit
        'lastUpdatedBy': _currentUserId, // Track who made the last update
      }, SetOptions(merge: true));

      await _logProgressActivity();

      _showSnackBar('Progress saved successfully!', Colors.green);
    } catch (e) {
      _showSnackBar('Error saving progress: $e', Colors.red);
    }
  }

  Future<void> _logProgressActivity() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('activityLog')
          .add({
        'action': 'Progress Updated',
        'taskId': widget.taskId,
        'taskTitle': widget.taskTitle,
        'progress': currentProgress,
        'status': selectedStatus,
        'timestamp': Timestamp.now(),
        'updatedBy': _currentUserId,
      });
    } catch (e) {
      print('Error logging activity: $e');
    }
  }

  void _addMilestone() {
    if (!_canEditProgress) {
      _showErrorDialog('Permission Denied', 'You do not have permission to add milestones to this task.');
      return;
    }

    if (milestoneController.text.isNotEmpty) {
      setState(() {
        milestones.add({
          'title': milestoneController.text,
          'completed': false,
          'createdAt': DateTime.now().toIso8601String(),
          'targetDate': null,
          'createdBy': _currentUserId,
        });
        milestoneController.clear();
      });
    }
  }

  void _toggleMilestone(int index) {
    if (!_canEditProgress) {
      _showErrorDialog('Permission Denied', 'You do not have permission to update milestones for this task.');
      return;
    }

    setState(() {
      milestones[index]['completed'] = !milestones[index]['completed'];
      milestones[index]['lastUpdatedBy'] = _currentUserId;
      milestones[index]['lastUpdated'] = DateTime.now().toIso8601String();
      _updateProgressFromMilestones();
    });
  }

  void _updateProgressFromMilestones() {
    if (milestones.isEmpty && subTasks.isEmpty) return;

    int completedMilestones = milestones.where((m) => m['completed'] == true).length;
    double milestonesProgress = milestones.isEmpty ? 0 : (completedMilestones / milestones.length) * 100;

    int completedSubTasks = subTasks.where((s) => s['completed'] == true).length;
    double subTasksProgress = subTasks.isEmpty ? 0 : (completedSubTasks / subTasks.length) * 100;

    setState(() {
      currentProgress = ((milestonesProgress + subTasksProgress) / 2).clamp(0.0, 100.0);
    });
  }

  void _addSubTask() {
    if (!_canEditProgress) {
      _showErrorDialog('Permission Denied', 'You do not have permission to add sub-tasks to this task.');
      return;
    }

    if (subTaskController.text.isNotEmpty) {
      setState(() {
        subTasks.add({
          'title': subTaskController.text,
          'completed': false,
          'createdAt': DateTime.now().toIso8601String(),
          'priority': 'Medium',
          'createdBy': _currentUserId,
        });
        subTaskController.clear();
      });
    }
  }

  void _toggleSubTask(int index) {
    if (!_canEditProgress) {
      _showErrorDialog('Permission Denied', 'You do not have permission to update sub-tasks for this task.');
      return;
    }

    setState(() {
      subTasks[index]['completed'] = !subTasks[index]['completed'];
      subTasks[index]['lastUpdatedBy'] = _currentUserId;
      subTasks[index]['lastUpdated'] = DateTime.now().toIso8601String();
      _updateProgressFromMilestones();
    });
  }

  void _removeMilestone(int index) {
    if (!_canEditProgress) {
      _showErrorDialog('Permission Denied', 'You do not have permission to remove milestones from this task.');
      return;
    }

    setState(() {
      milestones.removeAt(index);
      _updateProgressFromMilestones();
    });
  }

  void _removeSubTask(int index) {
    if (!_canEditProgress) {
      _showErrorDialog('Permission Denied', 'You do not have permission to remove sub-tasks from this task.');
      return;
    }

    setState(() {
      subTasks.removeAt(index);
      _updateProgressFromMilestones();
    });
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Not Started': return Colors.grey;
      case 'In Progress': return Colors.blue;
      case 'On Hold': return Colors.orange;
      case 'Completed': return Colors.green;
      case 'Cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildPermissionBanner() {
    if (_canEditProgress) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[300]!),
      ),
      child: Row(
        children: [
          Icon(Icons.info, color: Colors.orange[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Read-Only Mode',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You can view this task progress but cannot make changes. Only the task creator can update progress.',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overall Progress',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF006D77),
                ),
              ),
              Text(
                '${currentProgress.toStringAsFixed(1)}%',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF006D77),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          LinearProgressIndicator(
            value: currentProgress / 100,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              currentProgress < 30 ? Colors.red :
              currentProgress < 70 ? Colors.orange : Colors.green,
            ),
            minHeight: 8,
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: progressController,
                  keyboardType: TextInputType.number,
                  enabled: _canEditProgress, // Disable if no permission
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Update Progress (%)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    enabled: _canEditProgress,
                  ),
                  onChanged: (value) {
                    if (_canEditProgress) {
                      final progress = double.tryParse(value);
                      if (progress != null && progress >= 0 && progress <= 100) {
                        setState(() => currentProgress = progress);
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _canEditProgress ? () {
                  final progress = double.tryParse(progressController.text);
                  if (progress != null && progress >= 0 && progress <= 100) {
                    setState(() => currentProgress = progress);
                    progressController.clear();
                  }
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canEditProgress ? const Color(0xFF006D77) : Colors.grey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Update',
                  style: TextStyle(
                    color: _canEditProgress ? Colors.white : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Task Status',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF006D77),
            ),
          ),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            value: statusOptions.contains(selectedStatus) ? selectedStatus : null,
            items: statusOptions.map((status) {
              return DropdownMenuItem(
                value: status,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _getStatusColor(status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(status, style: GoogleFonts.poppins()),
                  ],
                ),
              );
            }).toList(),
            onChanged: _canEditProgress ? (value) => setState(() => selectedStatus = value ?? 'In Progress') : null,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabled: _canEditProgress,
            ),
            hint: const Text('Select Status', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestonesSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Milestones',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF006D77),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: milestoneController,
                  enabled: _canEditProgress,
                  decoration: InputDecoration(
                    hintText: _canEditProgress ? 'Add new milestone' : 'View-only mode',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    enabled: _canEditProgress,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _canEditProgress ? _addMilestone : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canEditProgress ? const Color(0xFF006D77) : Colors.grey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Icon(
                  Icons.add,
                  color: _canEditProgress ? Colors.white : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ...milestones.asMap().entries.map((entry) {
            int index = entry.key;
            Map<String, dynamic> milestone = entry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Checkbox(
                  value: milestone['completed'],
                  onChanged: _canEditProgress ? (_) => _toggleMilestone(index) : null,
                  activeColor: const Color(0xFF006D77),
                ),
                title: Text(
                  milestone['title'],
                  style: GoogleFonts.poppins(
                    decoration: milestone['completed']
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                trailing: _canEditProgress ? IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeMilestone(index),
                ) : null,
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildSubTasksSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sub-Tasks',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF006D77),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: subTaskController,
                  enabled: _canEditProgress,
                  decoration: InputDecoration(
                    hintText: _canEditProgress ? 'Add new sub-task' : 'View-only mode',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    enabled: _canEditProgress,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _canEditProgress ? _addSubTask : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canEditProgress ? const Color(0xFF006D77) : Colors.grey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Icon(
                  Icons.add,
                  color: _canEditProgress ? Colors.white : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ...subTasks.asMap().entries.map((entry) {
            int index = entry.key;
            Map<String, dynamic> subTask = entry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Checkbox(
                  value: subTask['completed'],
                  onChanged: _canEditProgress ? (_) => _toggleSubTask(index) : null,
                  activeColor: const Color(0xFF006D77),
                ),
                title: Text(
                  subTask['title'],
                  style: GoogleFonts.poppins(
                    decoration: subTask['completed']
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                trailing: _canEditProgress ? IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeSubTask(index),
                ) : null,
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildNotesSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progress Notes',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF006D77),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: notesController,
            maxLines: 4,
            enabled: _canEditProgress,
            decoration: InputDecoration(
              hintText: _canEditProgress ? 'Add notes about your progress...' : 'View-only mode',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.all(12),
              enabled: _canEditProgress,
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
            'Task Progress Tracker',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          actions: [
            if (_canEditProgress)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saveProgress,
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.taskTitle != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF006D77),
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: const EdgeInsets.only(bottom: 16),
                child: Text(
                  widget.taskTitle!,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            _buildPermissionBanner(),
            _buildProgressIndicator(),
            const SizedBox(height: 16),
            _buildStatusSelector(),
            const SizedBox(height: 16),
            _buildMilestonesSection(),
            const SizedBox(height: 16),
            _buildSubTasksSection(),
            const SizedBox(height: 16),
            _buildNotesSection(),
            const SizedBox(height: 20),
            if (_canEditProgress)
              ElevatedButton(
                onPressed: _saveProgress,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D77),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Save Progress',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}