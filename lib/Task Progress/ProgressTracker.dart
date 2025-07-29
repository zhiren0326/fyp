import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class ProgressTrackerPage extends StatefulWidget {
  final String jobId;
  final String jobTitle;
  final bool isEmployer;

  const ProgressTrackerPage({
    super.key,
    required this.jobId,
    required this.jobTitle,
    this.isEmployer = false,
  });

  @override
  State<ProgressTrackerPage> createState() => _ProgressTrackerPageState();
}

class _ProgressTrackerPageState extends State<ProgressTrackerPage> {
  final TextEditingController _milestoneController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  double _currentProgress = 0.0;
  String _currentStatus = 'Not Started';
  List<Map<String, dynamic>> _milestones = [];
  List<Map<String, dynamic>> _progressHistory = [];
  bool _isLoading = true;
  bool _isJobCreator = false;
  String _jobCreatorId = '';
  String _employeeName = '';
  bool _isCompletionRequested = false;
  String _completionNotes = '';

  final List<String> _statusOptions = [
    'Not Started',
    'In Progress',
    'On Hold',
    'Pending Review',
    'Completed',
  ];

  @override
  void initState() {
    super.initState();
    _loadProgressData();
    _checkJobCreator();
  }

  @override
  void dispose() {
    _milestoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _checkJobCreator() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .get();

      if (jobDoc.exists) {
        final jobData = jobDoc.data()!;
        _jobCreatorId = jobData['jobCreator'] ?? jobData['postedBy'] ?? '';
        setState(() {
          _isJobCreator = currentUser.uid == _jobCreatorId;
        });

        if (widget.isEmployer || _isJobCreator) {
          await _getEmployeeName();
        }
      }
    } catch (e) {
      print('Error checking job creator: $e');
    }
  }

  Future<void> _getEmployeeName() async {
    try {
      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .get();

      if (jobDoc.exists) {
        final acceptedApplicants = jobDoc.data()!['acceptedApplicants'] as List? ?? [];
        if (acceptedApplicants.isNotEmpty) {
          final userId = acceptedApplicants.first; // Get first accepted applicant

          final profileDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('profiledetails')
              .doc('profile')
              .get();

          if (profileDoc.exists) {
            setState(() {
              _employeeName = profileDoc.data()!['name'] ?? 'Unknown User';
            });
          }
        }
      }
    } catch (e) {
      print('Error getting employee name: $e');
    }
  }

  Future<void> _loadProgressData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      String userId = currentUser.uid;

      if (widget.isEmployer) {
        final jobDoc = await FirebaseFirestore.instance
            .collection('jobs')
            .doc(widget.jobId)
            .get();

        if (jobDoc.exists) {
          final acceptedApplicants = jobDoc.data()!['acceptedApplicants'] as List? ?? [];
          if (acceptedApplicants.isNotEmpty) {
            userId = acceptedApplicants.first;
          }
        }
      }

      final progressDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('taskProgress')
          .doc(widget.jobId)
          .get();

      if (progressDoc.exists) {
        final data = progressDoc.data()!;
        setState(() {
          _currentProgress = (data['currentProgress'] ?? 0.0).toDouble();
          _currentStatus = data['status'] ?? 'Not Started';
          _milestones = List<Map<String, dynamic>>.from(data['milestones'] ?? []);
          _isCompletionRequested = data['completionRequested'] ?? false;
          _completionNotes = data['completionNotes'] ?? '';
        });
      }

      final historySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('taskProgress')
          .doc(widget.jobId)
          .collection('history')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      setState(() {
        _progressHistory = historySnapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading progress data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProgress(double newProgress, String status, String notes) async {
    if (widget.isEmployer) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final updateData = {
        'currentProgress': newProgress,
        'status': status,
        'lastUpdated': Timestamp.now(),
        'notes': notes,
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(widget.jobId)
          .update(updateData);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(widget.jobId)
          .collection('history')
          .add({
        'progress': newProgress,
        'status': status,
        'notes': notes,
        'timestamp': Timestamp.now(),
        'action': 'progress_update',
      });

      await _updateJobOverallProgress();

      setState(() {
        _currentProgress = newProgress;
        _currentStatus = status;
      });

      _showSnackBar('Progress updated successfully!', Colors.green);
      _loadProgressData();
    } catch (e) {
      _showSnackBar('Error updating progress: $e', Colors.red);
    }
  }

  Future<void> _updateJobOverallProgress() async {
    try {
      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .get();

      if (!jobDoc.exists) return;

      final acceptedApplicants = jobDoc.data()!['acceptedApplicants'] as List? ?? [];
      if (acceptedApplicants.isEmpty) return;

      double totalProgress = 0.0;
      int completedTasks = 0;

      for (String applicantId in acceptedApplicants) {
        final progressDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(applicantId)
            .collection('taskProgress')
            .doc(widget.jobId)
            .get();

        if (progressDoc.exists) {
          final progress = (progressDoc.data()!['currentProgress'] ?? 0.0).toDouble();
          totalProgress += progress;
          if (progress >= 100.0) completedTasks++;
        }
      }

      final overallProgress = acceptedApplicants.isNotEmpty
          ? totalProgress / acceptedApplicants.length
          : 0.0;

      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .update({
        'overallProgress': overallProgress,
        'completedTasks': completedTasks,
        'totalTasks': acceptedApplicants.length,
      });
    } catch (e) {
      print('Error updating job overall progress: $e');
    }
  }

  Future<void> _addMilestone(String milestone) async {
    if (widget.isEmployer) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final newMilestone = {
        'title': milestone,
        'completed': false,
        'createdAt': Timestamp.now(),
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
      };

      final updatedMilestones = [..._milestones, newMilestone];

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(widget.jobId)
          .update({
        'milestones': updatedMilestones,
        'lastUpdated': Timestamp.now(),
      });

      setState(() {
        _milestones = updatedMilestones;
      });

      _milestoneController.clear();
      Navigator.pop(context);
      _showSnackBar('Milestone added successfully!', Colors.green);
    } catch (e) {
      _showSnackBar('Error adding milestone: $e', Colors.red);
    }
  }

  Future<void> _toggleMilestone(int index) async {
    if (widget.isEmployer) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final updatedMilestones = [..._milestones];
      updatedMilestones[index]['completed'] = !updatedMilestones[index]['completed'];
      updatedMilestones[index]['completedAt'] = updatedMilestones[index]['completed']
          ? Timestamp.now()
          : null;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(widget.jobId)
          .update({
        'milestones': updatedMilestones,
        'lastUpdated': Timestamp.now(),
      });

      setState(() {
        _milestones = updatedMilestones;
      });
    } catch (e) {
      _showSnackBar('Error updating milestone: $e', Colors.red);
    }
  }

  Future<void> _requestCompletion(String notes) async {
    if (widget.isEmployer) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(widget.jobId)
          .update({
        'completionRequested': true,
        'completionNotes': notes,
        'completionRequestedAt': Timestamp.now(),
        'status': 'Pending Review',
        'lastUpdated': Timestamp.now(),
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_jobCreatorId)
          .collection('notifications')
          .add({
        'message': 'Task completion requested for "${widget.jobTitle}"',
        'timestamp': Timestamp.now(),
        'read': false,
        'type': 'completion_request',
        'jobId': widget.jobId,
        'applicantId': currentUser.uid,
      });

      setState(() {
        _isCompletionRequested = true;
        _completionNotes = notes;
        _currentStatus = 'Pending Review';
      });

      _showSnackBar('Completion request sent to employer!', Colors.green);
    } catch (e) {
      _showSnackBar('Error requesting completion: $e', Colors.red);
    }
  }

  Future<void> _handleCompletionResponse(bool approved, String response) async {
    if (!_isJobCreator) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .get();

      final acceptedApplicants = jobDoc.data()!['acceptedApplicants'] as List? ?? [];
      if (acceptedApplicants.isEmpty) return;

      final employeeId = acceptedApplicants.first;

      if (approved) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(employeeId)
            .collection('taskProgress')
            .doc(widget.jobId)
            .update({
          'status': 'Completed',
          'currentProgress': 100.0,
          'completionApproved': true,
          'employerResponse': response,
          'completedAt': Timestamp.now(),
          'lastUpdated': Timestamp.now(),
        });

        await FirebaseFirestore.instance
            .collection('users')
            .doc(employeeId)
            .collection('taskProgress')
            .doc(widget.jobId)
            .collection('history')
            .add({
          'progress': 100.0,
          'status': 'Completed',
          'notes': 'Task marked as complete by employer',
          'timestamp': Timestamp.now(),
          'action': 'task_completed',
        });

        await _awardPoints(employeeId);

        await _updateJobOverallProgress();

        _showSnackBar('Task approved and completed! 100 points awarded.', Colors.green);
      } else {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(employeeId)
            .collection('taskProgress')
            .doc(widget.jobId)
            .update({
          'completionRequested': false,
          'completionApproved': false,
          'employerResponse': response,
          'status': 'In Progress',
          'lastUpdated': Timestamp.now(),
        });

        _showSnackBar('Completion rejected. Employee has been notified.', Colors.orange);
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('notifications')
          .add({
        'message': approved
            ? 'Your task "${widget.jobTitle}" has been approved and completed! 100 points awarded.'
            : 'Your completion request for "${widget.jobTitle}" was not approved.',
        'timestamp': Timestamp.now(),
        'read': false,
        'type': approved ? 'completion_approved' : 'completion_rejected',
        'jobId': widget.jobId,
        'response': response,
      });

      _loadProgressData();
    } catch (e) {
      _showSnackBar('Error processing completion response: $e', Colors.red);
    }
  }

  Future<void> _awardPoints(String employeeId) async {
    try {
      const int pointsToAward = 100; // Fixed 100 points for task completion

      final profileRef = FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('profiledetails')
          .doc('profile');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final profileDoc = await transaction.get(profileRef);
        final currentPoints = (profileDoc.data()?['points'] ?? 0) as int;

        transaction.update(profileRef, {
          'points': currentPoints + pointsToAward,
          'lastPointsUpdate': Timestamp.now(),
        });
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('pointsHistory')
          .add({
        'points': pointsToAward,
        'source': 'task_completion',
        'jobId': widget.jobId,
        'jobTitle': widget.jobTitle,
        'timestamp': Timestamp.now(),
        'description': 'Completed task: ${widget.jobTitle}',
      });

      print('Awarded $pointsToAward points to user $employeeId');
    } catch (e) {
      print('Error awarding points: $e');
    }
  }

  void _showProgressUpdateDialog() {
    double tempProgress = _currentProgress;
    String tempStatus = _currentStatus;
    final tempNotesController = TextEditingController(text: _notesController.text);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(
            'Update Progress',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Progress: ${tempProgress.toInt()}%',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
                Slider(
                  value: tempProgress,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  activeColor: const Color(0xFF006D77),
                  onChanged: (value) {
                    setDialogState(() => tempProgress = value);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Status',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
                DropdownButton<String>(
                  value: tempStatus,
                  isExpanded: true,
                  items: _statusOptions.map((status) {
                    return DropdownMenuItem<String>(
                      value: status,
                      child: Text(status, style: GoogleFonts.poppins()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() => tempStatus = value!);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: tempNotesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _updateProgress(tempProgress, tempStatus, tempNotesController.text);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006D77),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Update',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMilestoneDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          'Add Milestone',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: _milestoneController,
          decoration: InputDecoration(
            labelText: 'Milestone title',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              if (_milestoneController.text.trim().isNotEmpty) {
                _addMilestone(_milestoneController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006D77),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Add',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCompletionDialog() {
    final completionNotesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          'Request Completion',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Request employer to review task completion.',
              style: GoogleFonts.poppins(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: completionNotesController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Completion summary',
                hintText: 'Describe what you have accomplished...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
              Navigator.pop(context);
              _requestCompletion(completionNotesController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006D77),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Request Completion',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCompletionResponseDialog() {
    final responseController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          'Review Completion Request',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Employee Notes:',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _completionNotes.isEmpty ? 'No notes provided' : _completionNotes,
                    style: GoogleFonts.poppins(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: responseController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Your response',
                hintText: 'Provide feedback...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
              Navigator.pop(context);
              _handleCompletionResponse(false, responseController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Reject',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _handleCompletionResponse(true, responseController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Approve',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Completed': return Colors.green;
      case 'In Progress': return Colors.blue;
      case 'Pending Review': return Colors.orange;
      case 'On Hold': return Colors.amber;
      case 'Not Started': return Colors.grey;
      default: return Colors.grey;
    }
  }

  Widget _buildProgressCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Task Progress',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF006D77),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(_currentStatus).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getStatusColor(_currentStatus)),
                  ),
                  child: Text(
                    _currentStatus,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(_currentStatus),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progress',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${_currentProgress.toInt()}%',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF006D77),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _currentProgress / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                _currentProgress < 30
                    ? Colors.red
                    : _currentProgress < 70
                    ? Colors.orange
                    : Colors.green,
              ),
              minHeight: 8,
            ),
            if (widget.isEmployer && _employeeName.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Employee: $_employeeName',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMilestonesCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Milestones',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF006D77),
                  ),
                ),
                if (!widget.isEmployer)
                  IconButton(
                    icon: const Icon(Icons.add, color: Color(0xFF006D77)),
                    onPressed: _showMilestoneDialog,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_milestones.isEmpty)
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.flag_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No milestones yet',
                      style: GoogleFonts.poppins(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: _milestones.asMap().entries.map((entry) {
                  int index = entry.key;
                  Map<String, dynamic> milestone = entry.value;
                  bool isCompleted = milestone['completed'] ?? false;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCompleted ? Colors.green[50] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCompleted ? Colors.green : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: widget.isEmployer ? null : () => _toggleMilestone(index),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isCompleted ? Colors.green : Colors.white,
                              border: Border.all(
                                color: isCompleted ? Colors.green : Colors.grey,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: isCompleted
                                ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                milestone['title'] ?? 'Untitled',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w500,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: isCompleted ? Colors.grey : Colors.black,
                                ),
                              ),
                              if (milestone['completedAt'] != null)
                                Text(
                                  'Completed: ${DateFormat('MMM dd, yyyy HH:mm').format(milestone['completedAt'].toDate())}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.green[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHistoryCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Progress History',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 16),
            if (_progressHistory.isEmpty)
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No progress updates yet',
                      style: GoogleFonts.poppins(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: _progressHistory.map((history) {
                  final timestamp = history['timestamp'] as Timestamp;
                  final progress = (history['progress'] ?? 0.0).toDouble();
                  final status = history['status'] ?? 'Unknown';
                  final notes = history['notes'] ?? '';

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(status),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  status,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${progress.toInt()}%',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF006D77),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM dd, yyyy HH:mm').format(timestamp.toDate()),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              notes,
                              style: GoogleFonts.poppins(fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (!widget.isEmployer && !_isCompletionRequested && _currentStatus != 'Completed') ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _showProgressUpdateDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D77),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Update Progress',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_currentProgress >= 80.0 && _currentStatus != 'Completed')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _showCompletionDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Request Completion',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
          if (_isJobCreator && _isCompletionRequested && _currentStatus == 'Pending Review')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _showCompletionResponseDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Review Completion Request',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (_isCompletionRequested && !_isJobCreator)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.pending,
                    color: Colors.orange[700],
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Completion Request Pending',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Waiting for employer approval',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.orange[600],
                    ),
                  ),
                ],
              ),
            ),
          if (_currentStatus == 'Completed')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green[700],
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Task Completed!',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Great job! 100 points have been awarded.',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.green[600],
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
            widget.jobTitle,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadProgressData,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          child: Column(
            children: [
              _buildProgressCard(),
              _buildMilestonesCard(),
              _buildProgressHistoryCard(),
              _buildActionButtons(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}