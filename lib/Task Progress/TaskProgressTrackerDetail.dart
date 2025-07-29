import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

import 'ProgressUpdateNotifier.dart';
import 'TaskProgressTracker.dart';

class TaskProgressTrackerDetail extends StatefulWidget {
  final String? taskId;
  final String? taskTitle;
  final ProgressUpdateNotifier? updateNotifier;

  const TaskProgressTrackerDetail({
    super.key,
    this.taskId,
    this.taskTitle,
    this.updateNotifier,
  });

  @override
  State<TaskProgressTrackerDetail> createState() => _TaskProgressTrackerDetailState();
}

class _TaskProgressTrackerDetailState extends State<TaskProgressTrackerDetail> {
  double currentProgress = 0.0;
  List<Map<String, dynamic>> milestones = [];
  List<Map<String, dynamic>> subTasks = [];
  String selectedStatus = 'In Progress';
  List<File> selectedFiles = [];
  List<String> uploadedFileBase64 = [];
  bool isSubmitting = false;
  bool isVerifying = false;

  bool _isShortTermTask = true;
  bool _taskTypeChecked = false;

  final TextEditingController milestoneController = TextEditingController();
  final TextEditingController progressController = TextEditingController();
  final TextEditingController subTaskController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  final List<String> statusOptions = [
    'Not Started',
    'In Progress',
    'On Hold',
    'Pending Review',
    'Completed',
    'Cancelled'
  ];

  bool _isLoading = true;
  bool _canEditProgress = false;
  String? _jobCreatorId;
  String? _currentUserId;
  String? _employerId;
  final ImagePicker _imagePicker = ImagePicker();
  StreamSubscription<DocumentSnapshot>? _progressSubscription;
  StreamSubscription<DocumentSnapshot>? _jobSubscription;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (widget.taskId != null) {
      _checkTaskTypeAndLoadData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _jobSubscription?.cancel();
    milestoneController.dispose();
    progressController.dispose();
    subTaskController.dispose();
    notesController.dispose();
    super.dispose();
  }

  void _setupProgressStream() {
    if (widget.taskId == null || _currentUserId == null) return;

    _progressSubscription = FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.taskId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;

      final data = snapshot.data();
      if (data == null) return;

      final progressList = data['progressPercentage'] as List<dynamic>? ?? [];
      final isEmployer = data['postedBy'] == _currentUserId;

      if (isEmployer) {
        // Employer: calculate average progress
        if (progressList.isNotEmpty) {
          double total = 0.0;
          int count = 0;
          for (var item in progressList) {
            if (item is Map<String, dynamic> && item['progress'] != null) {
              total += (item['progress'] as num).toDouble();
              count++;
            }
          }
          final avgProgress = count > 0 ? total / count : 0.0;
          if (mounted) {
            setState(() {
              currentProgress = avgProgress;
              progressController.text = currentProgress.toStringAsFixed(1);
            });
          }
        }
      } else {
        // Employee: find user's progress
        for (var item in progressList) {
          if (item is Map<String, dynamic> &&
              item['userId'] == _currentUserId &&
              item['progress'] != null) {
            if (mounted) {
              setState(() {
                currentProgress = (item['progress'] as num).toDouble();
                progressController.text = currentProgress.toStringAsFixed(1);
              });
            }
            break;
          }
        }
      }
    });
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

      if (jobDoc.exists && jobDoc.data() != null) {
        _jobCreatorId = jobDoc.data()?['postedBy'];
        final applicants = jobDoc.data()?['acceptedApplicants'] as List<dynamic>?;

        // Only employees (accepted applicants) can edit progress
        _canEditProgress = applicants != null &&
            applicants.contains(_currentUserId) &&
            selectedStatus != 'Completed' &&
            _currentUserId != _jobCreatorId; // Exclude employer
        setState(() {});
      } else {
        _canEditProgress = false;
        setState(() {});
      }
    } catch (e) {
      print('Error checking edit permissions: $e');
      setState(() => _canEditProgress = false);
    }
  }

  Future<void> _loadInitialData() async {
    try {
      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .get();

      if (jobDoc.exists) {
        final jobData = jobDoc.data()!;
        setState(() {
          milestones = List<Map<String, dynamic>>.from(jobData['milestones'] ?? []);
          subTasks = List<Map<String, dynamic>>.from(jobData['subTasks'] ?? []);
          notesController.text = jobData['notes'] ?? '';
          uploadedFileBase64 = List<String>.from(jobData['fileBase64'] ?? []);
        });
      }
    } catch (e) {
      print('Error loading initial data: $e');
    }
  }

  Future<void> _saveProgress() async {
    if (!_canEditProgress) {
      _showErrorDialog('Permission Denied', 'Only assigned employees can edit task progress.');
      return;
    }

    try {
      var newProgress = double.tryParse(progressController.text) ?? currentProgress;
      newProgress = newProgress.clamp(0.0, 100.0);
      final base64Strings = await _convertFilesToBase64();

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final jobRef = FirebaseFirestore.instance.collection('jobs').doc(widget.taskId);
        final jobDoc = await transaction.get(jobRef);

        if (!jobDoc.exists) return;

        final jobData = jobDoc.data()!;
        List<dynamic> progressList = List.from(jobData['progressPercentage'] ?? []);
        List<dynamic> statusList = List.from(jobData['submissionStatus'] ?? []);

        // Remove old progress/status entries
        progressList = progressList.where((item) =>
        !(item is Map<String, dynamic> && item['userId'] == _currentUserId)).toList();

        statusList = statusList.where((item) =>
        !(item is Map<String, dynamic> && item['userId'] == _currentUserId)).toList();

        // Add new entries
        progressList.add({
          'userId': _currentUserId,
          'progress': newProgress,
          'timestamp': FieldValue.serverTimestamp()
        });

        statusList.add({
          'userId': _currentUserId,
          'status': selectedStatus,
          'timestamp': FieldValue.serverTimestamp()
        });

        transaction.update(jobRef, {
          'progressPercentage': progressList,
          'submissionStatus': statusList,
          'milestones': milestones,
          'subTasks': subTasks,
          'notes': notesController.text,
          'fileBase64': FieldValue.arrayUnion(base64Strings),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      });

      // Also update user's taskProgress document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId!)
          .collection('taskProgress')
          .doc(widget.taskId)
          .set({
        'currentProgress': newProgress,
        'status': selectedStatus,
        'milestones': milestones,
        'subTasks': subTasks,
        'notes': notesController.text,
        'fileBase64': FieldValue.arrayUnion(base64Strings),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('Saved progress: $newProgress, status: $selectedStatus, userId: $_currentUserId');
      _showSnackBar('Progress saved successfully!', Colors.green);

      // Notify other screens to update
      widget.updateNotifier?.notifyProgressChanged();

      setState(() {
        currentProgress = newProgress;
        selectedFiles.clear();
      });
    } catch (e) {
      print('Error saving progress: $e');
      _showSnackBar('Error saving progress: $e', Colors.red);
    }
  }

  Future<List<String>> _convertFilesToBase64() async {
    List<String> base64Strings = [];
    if (selectedFiles.isEmpty) return base64Strings;

    try {
      for (int i = 0; i < selectedFiles.length; i++) {
        File fileToConvert = selectedFiles[i];
        List<int> fileBytes = await fileToConvert.readAsBytes();
        String base64String = base64Encode(fileBytes);
        base64Strings.add(base64String);
      }
      if (base64Strings.isNotEmpty) {
        _showSnackBar('Successfully converted ${base64Strings.length}/${selectedFiles.length} file(s)', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error converting files: $e', Colors.red);
    }

    return base64Strings;
  }

  Future<void> _pickFilesOrTakePicture() async {
    if (!_canEditProgress) {
      _showErrorDialog('Permission Denied',
          'Files cannot be uploaded or pictures taken once the task is completed.');
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Upload from Gallery'),
            onTap: () async {
              Navigator.pop(context);
              await _pickFiles();
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Take a Picture'),
            onTap: () async {
              Navigator.pop(context);
              await _takePicture();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
      );

      if (result != null && result.files.isNotEmpty) {
        final validFiles = result.files.where((file) => file.path != null).map((file) => File(file.path!)).toList();
        if (validFiles.isNotEmpty) {
          setState(() {
            selectedFiles.addAll(validFiles);
          });
          _showSnackBar('Selected ${validFiles.length} file(s)', Colors.green);
        }
      }
    } catch (e) {
      _showSnackBar('Error selecting files: $e', Colors.red);
    }
  }

  Future<void> _takePicture() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        setState(() {
          selectedFiles.add(File(photo.path));
        });
        _showSnackBar('Photo captured successfully', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Camera error: $e', Colors.red);
    }
  }

  Future<void> _markAsComplete() async {
    if (!_canEditProgress || selectedStatus != 'In Progress') {
      _showErrorDialog('Permission Denied',
          'Only the assigned employee can mark as complete when status is In Progress.');
      return;
    }

    setState(() => isSubmitting = true);
    try {
      final base64Strings = await _convertFilesToBase64();

      currentProgress = 100.0;
      progressController.text = currentProgress.toStringAsFixed(1);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId!)
          .collection('taskProgress')
          .doc(widget.taskId)
          .update({
        'status': 'Pending Review',
        'currentProgress': currentProgress,
        'fileBase64': [...uploadedFileBase64, ...base64Strings],
        'lastUpdated': Timestamp.now(),
        'userId': _currentUserId,
      });

      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .update({
        'progressPercentage': FieldValue.arrayUnion([
          {'userId': _currentUserId, 'progress': currentProgress}
        ]),
        'submissionStatus': FieldValue.arrayUnion([
          {'userId': _currentUserId, 'status': 'Pending Review'}
        ]),
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

  Future<void> _checkTaskTypeAndLoadData() async {
    try {
      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .get();

      if (jobDoc.exists) {
        final jobData = jobDoc.data()!;
        _isShortTermTask = jobData['isShortTerm'] ?? true;
        _taskTypeChecked = true;

        if (!_isShortTermTask) {
          setState(() {
            _isLoading = false;
          });
          return;
        }

        _employerId = jobData['postedBy'];
        _jobCreatorId = jobData['postedBy'];
        await _checkEditPermissions();
        await _loadInitialData();
        _setupProgressStream();

        // Set initial progress from Firestore
        final progressList = jobData['progressPercentage'] as List<dynamic>? ?? [];
        final isEmployer = jobData['postedBy'] == _currentUserId;

        if (isEmployer) {
          if (progressList.isNotEmpty) {
            double total = 0.0;
            int count = 0;
            for (var item in progressList) {
              if (item is Map<String, dynamic> && item['progress'] != null) {
                total += (item['progress'] as num).toDouble();
                count++;
              }
            }
            setState(() {
              currentProgress = count > 0 ? total / count : 0.0;
              progressController.text = currentProgress.toStringAsFixed(1);
            });
          }
        } else {
          for (var item in progressList) {
            if (item is Map<String, dynamic> &&
                item['userId'] == _currentUserId &&
                item['progress'] != null) {
              setState(() {
                currentProgress = (item['progress'] as num).toDouble();
                progressController.text = currentProgress.toStringAsFixed(1);
              });
              break;
            }
          }
        }

        setState(() => _isLoading = false);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildLongTermTaskMessage() {
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
            'Task Details',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
        ),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 64,
                  color: Colors.orange[600],
                ),
                const SizedBox(height: 16),
                Text(
                  'Long-term Task',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF006D77),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'This is a long-term task. Progress tracking is not available for long-term tasks as they don\'t have specific deadlines.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006D77),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: Text(
                    'Go Back',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        'message': 'A task for "${widget.taskTitle}" by $_currentUserId is ready for review.',
        'taskId': widget.taskId,
        'fromUserId': _currentUserId,
        'timestamp': Timestamp.now(),
        'read': false,
      });
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  Future<void> _verifyTask(String action, String userId) async {
    if (_currentUserId != _jobCreatorId) {
      _showErrorDialog(
          'Permission Denied', 'Only the employer can verify tasks.');
      return;
    }

    setState(() => isVerifying = true);
    try {
      String newStatus = action == 'accept' ? 'Completed' : 'Rejected';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('taskProgress')
          .doc(widget.taskId)
          .update({
        'status': newStatus,
        'lastUpdated': Timestamp.now(),
      });

      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .update({
        'submissionStatus': FieldValue.arrayRemove([
          {'userId': userId, 'status': 'Pending Review'}
        ]),
        'submissionStatus': FieldValue.arrayUnion([
          {'userId': userId, 'status': newStatus}
        ]),
        'lastUpdated': Timestamp.now(),
      });

      if (action == 'accept') {
        await _awardPoints(userId);
        await _updateManageApplicants(userId);
        _showSnackBar(
            'Task accepted and points awarded for $userId!', Colors.green);
      } else {
        await _sendRejectionNotification(userId);
        _showSnackBar(
            'Task rejected for $userId. Employee notified.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error verifying task for $userId: $e', Colors.red);
    } finally {
      setState(() => isVerifying = false);
    }
  }

  Future<void> _awardPoints(String userId) async {
    try {
      final taskDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .get();
      final points = taskDoc.data()?['salary'] ?? 500;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('profiledetails')
          .doc('profile')
          .update({
        'points': FieldValue.increment(points),
        'lastPointsUpdate': Timestamp.now(),
      });
    } catch (e) {
      print('Error awarding points: $e');
    }
  }

  Future<void> _updateManageApplicants(String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .update({
        'acceptedApplicants': FieldValue.arrayRemove([userId]),
      });
    } catch (e) {
      print('Error updating ManageApplicants: $e');
    }
  }

  Future<void> _sendRejectionNotification(String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
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
      progressController.text = currentProgress.toStringAsFixed(1);
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
                  'Only the assigned employee can edit this task. Employers can review and verify.',
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
            if (_canEditProgress)
              Column(
                children: [
                  TextField(
                    controller: progressController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Progress (%)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9]+(\.[0-9]{0,2})?')),
                    ],
                    enabled: _canEditProgress,
                    onChanged: (value) {
                      if (_canEditProgress) {
                        currentProgress = double.tryParse(value) ?? currentProgress;
                        currentProgress = currentProgress.clamp(0.0, 100.0);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButton<String>(
                    value: selectedStatus,
                    items: statusOptions.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: _canEditProgress
                        ? (newValue) {
                      if (newValue != null) {
                        setState(() {
                          selectedStatus = newValue;
                        });
                      }
                    }
                        : null,
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _canEditProgress ? _saveProgress : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canEditProgress ? const Color(0xFF006D77) : Colors.grey,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Save Progress', style: TextStyle(color: _canEditProgress ? Colors.white : Colors.black)),
                  ),
                ],
              ),
            if (_canEditProgress && selectedStatus == 'In Progress')
              ElevatedButton(
                onPressed: isSubmitting || !_canEditProgress
                    ? null
                    : _markAsComplete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D77),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Mark as Complete', style: TextStyle(color: Colors.white)),
              ),
            if (_currentUserId == _jobCreatorId)
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _getApplicantStatuses(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  return Column(
                    children: snapshot.data!.map((statusData) {
                      String userId = statusData['userId'];
                      String status = statusData['status'];
                      return status == 'Pending Review'
                          ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('Applicant $userId: $status'),
                            ),
                            ElevatedButton(
                              onPressed: isVerifying ? null : () => _verifyTask('accept', userId),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: isVerifying
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('Accept'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: isVerifying ? null : () => _verifyTask('reject', userId),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: isVerifying
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('Reject'),
                            ),
                          ],
                        ),
                      )
                          : const SizedBox.shrink();
                    }).toList(),
                  );
                },
              ),
            const SizedBox(height: 10),
            Text('Status: ${selectedStatus} (Your Progress)',
                style: GoogleFonts.poppins(color: _getStatusColor(selectedStatus))),
            if (uploadedFileBase64.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Text('Attached Files:', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  ...uploadedFileBase64.map((base64) => ListTile(
                    leading: Icon(Icons.insert_drive_file),
                    title: Text('File ${uploadedFileBase64.indexOf(base64) + 1}', style: GoogleFonts.poppins()),
                    onTap: () => _displayBase64Image(base64),
                  )).toList(),
                ],
              ),
            if (_canEditProgress)
              Column(
                children: [
                  ElevatedButton(
                    onPressed: _pickFilesOrTakePicture,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF006D77),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Upload Files or Take Picture', style: TextStyle(color: Colors.white)),
                  ),
                  if (selectedFiles.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Text('Selected Files:', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        ...selectedFiles.map((file) => ListTile(
                          leading: Icon(Icons.insert_drive_file),
                          title: Text(file.path.split('/').last, style: GoogleFonts.poppins()),
                        )).toList(),
                      ],
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _displayBase64Image(String base64String) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Image.memory(base64Decode(base64String)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getApplicantStatuses() async {
    final jobDoc = await FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.taskId)
        .get();
    final statuses = jobDoc.data()?['submissionStatus'] as List<dynamic>? ?? [];
    return statuses.map((s) => {'userId': s['userId'], 'status': s['status']}).toList();
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
          if (_canEditProgress)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: milestoneController,
                    decoration: InputDecoration(
                      hintText: 'Add milestone',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    enabled: _canEditProgress,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _canEditProgress ? _addMilestone : null,
                ),
              ],
            ),
          ...milestones.map((milestone) {
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Checkbox(
                  value: milestone['completed'],
                  onChanged: _canEditProgress ? (value) => _toggleMilestone(milestones.indexOf(milestone)) : null,
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
          if (_canEditProgress)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: subTaskController,
                    decoration: InputDecoration(
                      hintText: 'Add sub-task',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    enabled: _canEditProgress,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _canEditProgress ? _addSubTask : null,
                ),
              ],
            ),
          ...subTasks.map((subTask) {
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Checkbox(
                  value: subTask['completed'],
                  onChanged: _canEditProgress ? (value) => _toggleSubTask(subTasks.indexOf(subTask)) : null,
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
              hintText: 'Add notes',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Not Started':
        return Colors.grey;
      case 'In Progress':
        return Colors.blue;
      case 'On Hold':
        return Colors.orange;
      case 'Pending Review':
        return Colors.yellow;
      case 'Completed':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || !_taskTypeChecked) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB2DFDB), Colors.white],
          ),
        ),
        child: const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (!_isShortTermTask) {
      return _buildLongTermTaskMessage();
    }

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
            if (_canEditProgress)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saveProgress,
              ),
          ],
        ),
        body: ListView(
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
