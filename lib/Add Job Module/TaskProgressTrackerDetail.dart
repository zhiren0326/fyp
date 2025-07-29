
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class TaskProgressTrackerDetail extends StatefulWidget {
  final String? taskId;
  final String? taskTitle;

  const TaskProgressTrackerDetail({super.key, this.taskId, this.taskTitle});

  @override
  State<TaskProgressTrackerDetail> createState() => _TaskProgressTrackerDetailState();
}

class _TaskProgressTrackerDetailState extends State<TaskProgressTrackerDetail> {
  double currentProgress = 0.0;
  List<Map<String, dynamic>> milestones = [];
  List<Map<String, dynamic>> subTasks = [];
  String selectedStatus = 'In Progress';
  List<File> selectedFiles = [];
  List<String> uploadedFileUrls = [];
  bool isSubmitting = false;
  bool isVerifying = false;

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
  bool _canEditProgress = false;
  String? _jobCreatorId;
  String? _currentUserId;
  String? _employerId;
  final ImagePicker _imagePicker = ImagePicker();

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
      await _checkEditPermissions();
      await _loadTaskProgress();
      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .get();
      if (jobDoc.exists) {
        _employerId = jobDoc.data()?['postedBy'];
      }
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

      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .get();

      if (jobDoc.exists) {
        _jobCreatorId = jobDoc.data()?['postedBy'];
        _canEditProgress = _currentUserId == _jobCreatorId || _currentUserId == _employerId;
      }

      final taskProgressDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId!)
          .collection('taskProgress')
          .doc(widget.taskId)
          .get();

      if (taskProgressDoc.exists) {
        final canEditProgressList = List<String>.from(taskProgressDoc.data()?['canEditProgress'] ?? []);
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
          .doc(_currentUserId!)
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
          uploadedFileUrls = List<String>.from(data['fileUrls'] ?? []);
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
      _showErrorDialog('Permission Denied', 'You do not have permission to edit this task progress.');
      return;
    }

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final imageUrls = await _uploadFiles();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(widget.taskId)
          .set({
        'taskId': widget.taskId,
        'taskTitle': widget.taskTitle,
        'currentProgress': currentProgress,
        'milestones': milestones,
        'subTasks': subTasks,
        'status': selectedStatus,
        'notes': notesController.text,
        'fileUrls': [...uploadedFileUrls, ...imageUrls],
        'lastUpdated': Timestamp.now(),
        'jobCreator': _jobCreatorId,
        'canEditProgress': [_jobCreatorId],
        'lastUpdatedBy': _currentUserId,
      }, SetOptions(merge: true));

      await _logProgressActivity();
      _showSnackBar('Progress saved successfully!', Colors.green);
      setState(() => selectedFiles.clear());
    } catch (e) {
      _showSnackBar('Error saving progress: $e', Colors.red);
    }
  }

  Future<List<String>> _uploadFiles() async {
    List<String> urls = [];
    for (int i = 0; i < selectedFiles.length; i++) {
      try {
        final fileName = 'task_progress/${widget.taskId}/files/${DateTime.now().millisecondsSinceEpoch}_$i${selectedFiles[i].path.split('.').last}';
        final ref = FirebaseStorage.instance.ref().child(fileName);
        await ref.putFile(selectedFiles[i]);
        final url = await ref.getDownloadURL();
        urls.add(url);
      } catch (e) {
        print('Error uploading file $i: $e');
      }
    }
    return urls;
  }

  Future<void> _pickFiles() async {
    if (!_canEditProgress) {
      _showErrorDialog('Permission Denied', 'You do not have permission to upload files.');
      return;
    }
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (result != null) {
        setState(() {
          selectedFiles = result.paths.map((path) => File(path!)).toList();
        });
      }
    } catch (e) {
      _showSnackBar('Error picking files: $e', Colors.red);
    }
  }

  Future<void> _markAsComplete() async {
    if (!_canEditProgress || selectedStatus != 'Completed') {
      _showErrorDialog('Permission Denied', 'You can only mark as complete if you have permission and status is set to Completed.');
      return;
    }

    setState(() => isSubmitting = true);
    try {
      final imageUrls = await _uploadFiles();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId!)
          .collection('taskProgress')
          .doc(widget.taskId)
          .update({
        'status': 'Pending Review',
        'fileUrls': [...uploadedFileUrls, ...imageUrls],
        'lastUpdated': Timestamp.now(),
      });

      await _notifyEmployer();
      _showSnackBar('Submission sent for employer review!', Colors.green);
      setState(() {
        selectedFiles.clear();
        selectedStatus = 'Pending Review';
      });
    } catch (e) {
      _showSnackBar('Error marking as complete: $e', Colors.red);
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  Future<void> _notifyEmployer() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_employerId)
          .collection('notifications')
          .add({
        'type': 'task_completion',
        'title': 'Task Completion Submitted',
        'message': 'A task for "${widget.taskTitle}" is ready for review.',
        'taskId': widget.taskId,
        'fromUserId': _currentUserId,
        'timestamp': Timestamp.now(),
        'read': false,
      });
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  Future<void> _verifyTask(String action) async {
    if (_currentUserId != _jobCreatorId) {
      _showErrorDialog('Permission Denied', 'Only the job creator can verify tasks.');
      return;
    }

    setState(() => isVerifying = true);
    try {
      if (action == 'accept') {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId!)
            .collection('taskProgress')
            .doc(widget.taskId)
            .update({
          'status': 'Completed',
          'lastUpdated': Timestamp.now(),
        });

        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(widget.taskId)
            .update({
          'completionSubmitted': true,
          'submissionStatus': 'Completed',
          'lastUpdated': Timestamp.now(),
        });

        await _awardPoints();
        await _updateManageApplicants();
        _showSnackBar('Task accepted and points awarded!', Colors.green);
      } else if (action == 'reject') {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId!)
            .collection('taskProgress')
            .doc(widget.taskId)
            .update({
          'status': 'Rejected',
          'lastUpdated': Timestamp.now(),
        });

        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(widget.taskId)
            .update({
          'submissionStatus': 'Rejected',
          'lastUpdated': Timestamp.now(),
        });

        await _sendRejectionNotification();
        _showSnackBar('Task rejected. Employee notified.', Colors.red);
      }
      // Removed _loadAppliedJobs() as it’s not defined here
    } catch (e) {
      _showSnackBar('Error verifying task: $e', Colors.red);
    } finally {
      setState(() => isVerifying = false);
    }
  }

  Future<void> _awardPoints() async {
    try {
      final taskDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .get();
      final points = taskDoc.data()?['salary'] ?? 500;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('profiledetails')
          .doc('profile')
          .update({
        'points': FieldValue.increment(points),
        'lastPointsUpdate': Timestamp.now(),
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('pointsHistory')
          .add({
        'points': points,
        'source': 'task_completion',
        'taskTitle': widget.taskTitle,
        'timestamp': Timestamp.now(),
        'description': 'Completed task "${widget.taskTitle}"',
      });
    } catch (e) {
      print('Error awarding points: $e');
    }
  }

  Future<void> _updateManageApplicants() async {
    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .update({
        'acceptedApplicants': FieldValue.arrayRemove([_currentUserId]),
      });
    } catch (e) {
      print('Error updating ManageApplicants: $e');
    }
  }

  Future<void> _sendRejectionNotification() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('notifications')
          .add({
        'type': 'task_rejected',
        'title': 'Task Rejected',
        'message': 'Your task "${widget.taskTitle}" was rejected. Please review and resubmit.',
        'taskId': widget.taskId,
        'timestamp': Timestamp.now(),
        'read': false,
      });
    } catch (e) {
      print('Error sending rejection notification: $e');
    }
  }

  Future<void> _logProgressActivity() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId!)
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
    if (!_canEditProgress || milestoneController.text.isEmpty) return;
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

  void _toggleMilestone(int index) {
    if (!_canEditProgress) return;
    setState(() {
      milestones[index]['completed'] = !milestones[index]['completed'];
      milestones[index]['lastUpdatedBy'] = _currentUserId;
      milestones[index]['lastUpdated'] = DateTime.now().toIso8601String();
      _updateProgressFromMilestones();
    });
  }

  void _addSubTask() {
    if (!_canEditProgress || subTaskController.text.isEmpty) return;
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

  void _toggleSubTask(int index) {
    if (!_canEditProgress) return;
    setState(() {
      subTasks[index]['completed'] = !subTasks[index]['completed'];
      subTasks[index]['lastUpdatedBy'] = _currentUserId;
      subTasks[index]['lastUpdated'] = DateTime.now().toIso8601String();
      _updateProgressFromMilestones();
    });
  }

  void _updateProgressFromMilestones() {
    int completedMilestones = milestones.where((m) => m['completed'] == true).length;
    double milestonesProgress = milestones.isEmpty ? 0 : (completedMilestones / milestones.length) * 100;

    int completedSubTasks = subTasks.where((s) => s['completed'] == true).length;
    double subTasksProgress = subTasks.isEmpty ? 0 : (completedSubTasks / subTasks.length) * 100;

    setState(() {
      currentProgress = ((milestonesProgress + subTasksProgress) / 2).clamp(0.0, 100.0);
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
        content: Text(message, style: GoogleFonts.poppins()),
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
                  'You can view this task progress but cannot make changes.',
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

  Widget _buildTaskCard() {
    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.taskTitle ?? 'Task',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF006D77),
                  ),
                ),
                Text(
                  '${currentProgress.toStringAsFixed(1)}%',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(selectedStatus),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: currentProgress / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(selectedStatus)),
              minHeight: 8,
            ),
            const SizedBox(height: 10),
            if (_canEditProgress && selectedStatus != 'Pending Review')
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Update'),
                  ),
                ],
              ),
            if (_canEditProgress && selectedStatus == 'In Progress')
              ElevatedButton(
                onPressed: isSubmitting ? null : _markAsComplete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D77),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Mark as Complete'),
              ),
            if (selectedStatus == 'Pending Review' && _currentUserId == _jobCreatorId)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isVerifying ? null : () => _verifyTask('accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: isVerifying
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isVerifying ? null : () => _verifyTask('reject'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: isVerifying
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Reject'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Text('Status: ${selectedStatus}', style: GoogleFonts.poppins(color: _getStatusColor(selectedStatus))),
            if (uploadedFileUrls.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Text('Attached Files:', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  ...uploadedFileUrls.map((url) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(url.split('/').last, style: GoogleFonts.poppins()),
                  )).toList(),
                ],
              ),
            if (_canEditProgress && selectedStatus != 'Pending Review')
              ElevatedButton(
                onPressed: _pickFiles,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D77),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Upload Files'),
              ),
            const SizedBox(height: 10),
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
                        decoration: BoxDecoration(color: _getStatusColor(status), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Text(status, style: GoogleFonts.poppins()),
                    ],
                  ),
                );
              }).toList(),
              onChanged: _canEditProgress ? (value) => setState(() => selectedStatus = value ?? 'In Progress') : null,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                enabled: _canEditProgress,
              ),
              hint: const Text('Select Status', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                    decoration: milestone['completed'] ? TextDecoration.lineThrough : TextDecoration.none,
                  ),
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
                  enabled: _canEditProgress,
                  decoration: InputDecoration(
                    hintText: _canEditProgress ? 'Add new sub-task' : 'View-only mode',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                    decoration: subTask['completed'] ? TextDecoration.lineThrough : TextDecoration.none,
                  ),
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
            enabled: _canEditProgress,
            decoration: InputDecoration(
              hintText: _canEditProgress ? 'Add notes about your progress...' : 'View-only mode',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
              enabled: _canEditProgress,
            ),
          ),
        ],
      ),
    );
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
            widget.taskTitle ?? 'Task Progress',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          actions: [
            if (_canEditProgress && !isVerifying && selectedStatus != 'Pending Review')
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
            _buildTaskCard(),
            const SizedBox(height: 20),
            _buildMilestonesSection(),
            const SizedBox(height: 20),
            _buildSubTasksSection(),
            const SizedBox(height: 20),
            _buildNotesSection(),
          ],
        ),
      ),
    );
  }
}