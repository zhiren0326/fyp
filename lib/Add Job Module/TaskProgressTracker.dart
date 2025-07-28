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
  String selectedStatus = 'In Progress'; // Default value

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

  bool _isLoading = true; // Track loading state

  @override
  void initState() {
    super.initState();
    if (widget.taskId != null) {
      _loadTaskProgress();
    } else {
      setState(() => _isLoading = false); // No taskId, no loading needed
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
          selectedStatus = statusOptions.contains(data['status']) ? data['status']! : 'In Progress'; // Validate status
          notesController.text = data['notes'] ?? '';
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false); // Handle non-existent document
      }
    } catch (e) {
      print('Error loading task progress: $e');
      setState(() => _isLoading = false); // Ensure UI updates even on error
    }
  }

  Future<void> _saveProgress() async {
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
      }, SetOptions(merge: true));

      await _logProgressActivity();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Progress saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving progress: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
      });
    } catch (e) {
      print('Error logging activity: $e');
    }
  }

  void _addMilestone() {
    if (milestoneController.text.isNotEmpty) {
      setState(() {
        milestones.add({
          'title': milestoneController.text,
          'completed': false,
          'createdAt': DateTime.now().toIso8601String(),
          'targetDate': null,
        });
        milestoneController.clear();
      });
    }
  }

  void _toggleMilestone(int index) {
    setState(() {
      milestones[index]['completed'] = !milestones[index]['completed'];
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
    if (subTaskController.text.isNotEmpty) {
      setState(() {
        subTasks.add({
          'title': subTaskController.text,
          'completed': false,
          'createdAt': DateTime.now().toIso8601String(),
          'priority': 'Medium',
        });
        subTaskController.clear();
      });
    }
  }

  void _toggleSubTask(int index) {
    setState(() {
      subTasks[index]['completed'] = !subTasks[index]['completed'];
      _updateProgressFromMilestones();
    });
  }

  void _removeMilestone(int index) {
    setState(() {
      milestones.removeAt(index);
      _updateProgressFromMilestones();
    });
  }

  void _removeSubTask(int index) {
    setState(() {
      subTasks.removeAt(index);
      _updateProgressFromMilestones();
    });
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
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Update Progress (%)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) {
                    final progress = double.tryParse(value);
                    if (progress != null && progress >= 0 && progress <= 100) {
                      setState(() => currentProgress = progress);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  final progress = double.tryParse(progressController.text);
                  if (progress != null && progress >= 0 && progress <= 100) {
                    setState(() => currentProgress = progress);
                    progressController.clear();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D77),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Update', style: TextStyle(color: Colors.white)),
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
            value: statusOptions.contains(selectedStatus) ? selectedStatus : null, // Use null if invalid
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
            onChanged: (value) => setState(() => selectedStatus = value ?? 'In Progress'), // Fallback to default
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  decoration: InputDecoration(
                    hintText: 'Add new milestone',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _addMilestone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D77),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Icon(Icons.add, color: Colors.white),
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
                  onChanged: (_) => _toggleMilestone(index),
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
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeMilestone(index),
                ),
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
                  decoration: InputDecoration(
                    hintText: 'Add new sub-task',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _addSubTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D77),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Icon(Icons.add, color: Colors.white),
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
                  onChanged: (_) => _toggleSubTask(index),
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
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeSubTask(index),
                ),
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
            decoration: InputDecoration(
              hintText: 'Add notes about your progress...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.all(12),
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