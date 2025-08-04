import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../Notification Module/NotificationService.dart';
import '../Task Progress/TaskProgressPage.dart';

class ManageApplicantsPage extends StatefulWidget {
  final String jobId;
  final String jobPosition;

  const ManageApplicantsPage({super.key, required this.jobId, required this.jobPosition});

  @override
  State<ManageApplicantsPage> createState() => _ManageApplicantsPageState();
}

class _ManageApplicantsPageState extends State<ManageApplicantsPage> {
  List<Map<String, dynamic>> teamPerformanceData = [];
  double overallProgress = 0.0;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    print('ManageApplicantsPage initialized for job ${widget.jobId} at ${DateTime.now()}');
    _loadTeamPerformanceData();
  }

  Future<void> _loadTeamPerformanceData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      print('Loading team performance data for job: ${widget.jobId}');

      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .get();

      if (!jobDoc.exists) {
        setState(() {
          errorMessage = 'Job not found';
          isLoading = false;
        });
        return;
      }

      final data = jobDoc.data()!;
      final acceptedApplicants = List<String>.from(data['acceptedApplicants'] ?? []);
      final progressValues = <double>[];

      print('Found ${acceptedApplicants.length} accepted applicants');

      List<Map<String, dynamic>> performanceList = [];

      for (String applicantId in acceptedApplicants) {
        try {
          // Get profile data
          final profileDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(applicantId)
              .collection('profiledetails')
              .doc('profile')
              .get();

          // Get progress data
          final progressDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(applicantId)
              .collection('taskProgress')
              .doc(widget.jobId)
              .get();

          String name = 'Unknown User';
          if (profileDoc.exists && profileDoc.data() != null) {
            name = profileDoc.data()!['name'] ?? 'Unknown User';
          }

          double progress = 0.0;
          String status = 'Not Started';
          bool completionRequested = false;
          bool completionApproved = false;
          String completionNotes = '';

          if (progressDoc.exists && progressDoc.data() != null) {
            final progressData = progressDoc.data()!;
            progress = (progressData['currentProgress'] ?? 0.0).toDouble();
            status = progressData['status'] ?? 'Not Started';
            completionRequested = progressData['completionRequested'] ?? false;
            completionApproved = progressData['completionApproved'] ?? false;
            completionNotes = progressData['completionNotes'] ?? '';
            progressValues.add(progress);
          }

          performanceList.add({
            'userId': applicantId,
            'name': name,
            'progress': progress,
            'status': status,
            'efficiency': _calculateEfficiency(progress, status),
            'completionRequested': completionRequested,
            'completionApproved': completionApproved,
            'completionNotes': completionNotes,
          });

          print('Added performance data for user $name: $progress%');
        } catch (e) {
          print('Error loading data for applicant $applicantId: $e');
          // Add user with default data if there's an error
          performanceList.add({
            'userId': applicantId,
            'name': 'Error Loading User',
            'progress': 0.0,
            'status': 'Error',
            'efficiency': 0.0,
            'completionRequested': false,
            'completionApproved': false,
            'completionNotes': '',
          });
        }
      }

      final avgProgress = progressValues.isNotEmpty
          ? progressValues.reduce((a, b) => a + b) / progressValues.length
          : 0.0;

      setState(() {
        teamPerformanceData = performanceList;
        overallProgress = avgProgress;
        isLoading = false;
      });

      print('Team performance loaded successfully. Overall progress: $avgProgress%');

      // Update overall progress in jobs collection
      try {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(widget.jobId)
            .update({'overallProgress': avgProgress});
      } catch (e) {
        print('Error updating overall progress: $e');
      }
    } catch (e) {
      print('Error loading team performance: $e');
      setState(() {
        errorMessage = 'Error loading data: $e';
        isLoading = false;
      });
    }
  }

  double _calculateEfficiency(double progress, String status) {
    switch (status.toLowerCase()) {
      case 'completed': return 100.0;
      case 'inprogress': return progress * 0.8;
      case 'pendingreview': return progress * 0.9;
      case 'paused': return progress * 0.5;
      case 'blocked': return progress * 0.4;
      case 'not started': return 0.0;
      default: return progress * 0.7;
    }
  }

  Future<void> _acceptApplicant(String applicantId) async {
    try {
      print('Accepting applicant: $applicantId');

      final jobDocRef = FirebaseFirestore.instance.collection('jobs').doc(widget.jobId);
      final jobDoc = await jobDocRef.get();

      if (!jobDoc.exists) {
        _showSnackBar('Job not found.');
        return;
      }

      final data = jobDoc.data()!;
      final acceptedApplicants = List<String>.from(data['acceptedApplicants'] ?? []);
      final applicants = List<String>.from(data['applicants'] ?? []);
      final requiredPeople = data['requiredPeople'] as int? ?? 1;

      // Check if applicant is in the applicants list
      if (!applicants.contains(applicantId)) {
        _showSnackBar('Applicant not found in applicants list.');
        return;
      }

      if (acceptedApplicants.length >= requiredPeople) {
        _showSnackBar('Cannot accept more applicants: Job is full.');
        return;
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Accepting applicant and setting up notifications...',
                    style: GoogleFonts.poppins(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Update the job document
      await jobDocRef.update({
        'applicants': FieldValue.arrayRemove([applicantId]),
        'acceptedApplicants': FieldValue.arrayUnion([applicantId]),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Create task progress for the accepted applicant
      await _createTaskProgressForApplicant(applicantId);

      // Send assignment notification to the employee
      await NotificationService().sendRealTimeNotification(
        userId: applicantId,
        title: '🎉 Job Assignment Confirmed!',
        body: 'Congratulations! You have been assigned to "${widget.jobPosition}". Please check your tasks for details and deadline information.',
        data: {
          'type': NotificationService.typeTaskAssigned,
          'jobId': widget.jobId,
          'jobTitle': widget.jobPosition,
          'timestamp': DateTime.now().toIso8601String(),
        },
        priority: NotificationPriority.high,
      );

      // Set up deadline notifications for the employee (NEW FEATURE)
      await _setupDeadlineNotificationsForEmployee(applicantId, data);

      // Close loading dialog
      Navigator.of(context).pop();

      _showSnackBar('Applicant accepted successfully. Notifications and deadline reminders have been set up.');
      await _loadTeamPerformanceData(); // Reload data

      print('Applicant $applicantId accepted successfully with deadline notifications');

    } catch (e) {
      // Close loading dialog if it's open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      print('Error accepting applicant: $e');
      _showSnackBar('Error accepting applicant: $e');
    }
  }

  // NEW METHOD: Set up deadline notifications for the accepted employee
  Future<void> _setupDeadlineNotificationsForEmployee(String employeeId, Map<String, dynamic> jobData) async {
    try {
      final isShortTerm = jobData['isShortTerm'] ?? false;

      // Only set up deadline notifications for short-term jobs
      if (!isShortTerm) {
        print('Job is long-term, no deadline notifications needed');
        return;
      }

      final endDateStr = jobData['endDate'] as String?;
      final endTimeStr = jobData['endTime'] as String?;

      if (endDateStr == null || endTimeStr == null) {
        print('No deadline information found in job data');
        return;
      }

      final deadline = _parseDateTime(endDateStr, endTimeStr);
      if (deadline == null || deadline.isBefore(DateTime.now())) {
        print('Invalid or past deadline, skipping notification setup');
        return;
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      final employerUserId = currentUser?.uid;

      print('Setting up deadline notifications for employee $employeeId with deadline: $deadline');

      // Use the new notification service method to schedule deadline reminders
      // This will automatically fetch the user's preferences from Firestore
      await NotificationService().scheduleDeadlineRemindersForEmployees(
        taskId: widget.jobId,
        taskTitle: widget.jobPosition,
        deadline: deadline,
        employeeIds: [employeeId], // Only this employee
        employerUserId: employerUserId, // Employer won't get notifications
      );

      print('Deadline notifications scheduled successfully for employee $employeeId');

    } catch (e) {
      print('Error setting up deadline notifications: $e');
      // Don't show error to user since the main acceptance was successful
      // Just log the error for debugging
    }
  }

  Future<void> _createTaskProgressForApplicant(String applicantId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      print('Creating task progress for applicant: $applicantId');

      final taskProgressRef = FirebaseFirestore.instance
          .collection('users')
          .doc(applicantId)
          .collection('taskProgress')
          .doc(widget.jobId);

      await taskProgressRef.set({
        'taskId': widget.jobId,
        'taskTitle': widget.jobPosition,
        'currentProgress': 0.0,
        'status': 'assigned', // Changed from 'created' to 'assigned'
        'milestones': [],
        'subTasks': [],
        'notes': 'Task assigned by employer. Deadline notifications have been set up based on your preferences.',
        'createdAt': Timestamp.now(),
        'lastUpdated': Timestamp.now(),
        'jobCreator': currentUser.uid,
        'canEditProgress': [applicantId], // Only employee can edit
        'completionRequested': false,
        'completionApproved': false,
        'completionNotes': '',
        'dependencies': [],
        'isBlocked': false,
        'deadlineNotificationsEnabled': true, // Track that deadline notifications are active
      });

      // Add to history
      await taskProgressRef.collection('history').add({
        'progress': 0.0,
        'status': 'assigned',
        'notes': 'Task assigned by employer. Deadline notifications configured based on user preferences.',
        'timestamp': Timestamp.now(),
        'action': 'task_assigned',
        'performedBy': currentUser.uid,
      });

      print('Task progress created successfully for $applicantId');
    } catch (e) {
      print('Error creating task progress: $e');
      rethrow; // Re-throw so the calling method knows there was an error
    }
  }

  DateTime? _parseDateTime(String dateStr, String timeStr) {
    try {
      if (dateStr.isEmpty || timeStr.isEmpty) return null;

      final dateParts = dateStr.split('-');
      if (dateParts.length != 3) return null;
      final timeParts = timeStr.split(':');
      if (timeParts.length != 2) return null;

      final hour = int.parse(timeParts[0].replaceAll(RegExp(r'[^0-9]'), ''));
      final minute = int.parse(timeParts[1].replaceAll(RegExp(r'[^0-9]'), ''));
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      final period = timeStr.contains('PM') && hour != 12 ? 12 : (timeStr.contains('AM') && hour == 12 ? -12 : 0);
      final adjustedHour = (hour + period) % 24;

      return DateTime(year, month, day, adjustedHour, minute);
    } catch (e) {
      print('Error parsing date-time: $e');
      return null;
    }
  }

  Future<void> _acceptMultipleApplicants(List<String> applicantIds) async {
    if (applicantIds.isEmpty) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Accepting ${applicantIds.length} applicants and setting up notifications...',
                    style: GoogleFonts.poppins(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final jobDocRef = FirebaseFirestore.instance.collection('jobs').doc(widget.jobId);
      final jobDoc = await jobDocRef.get();

      if (!jobDoc.exists) {
        Navigator.of(context).pop();
        _showSnackBar('Job not found.');
        return;
      }

      final data = jobDoc.data()!;
      final acceptedApplicants = List<String>.from(data['acceptedApplicants'] ?? []);
      final requiredPeople = data['requiredPeople'] as int? ?? 1;

      // Filter applicants that can actually be accepted
      final canAccept = requiredPeople - acceptedApplicants.length;
      final toAccept = applicantIds.take(canAccept).toList();

      if (toAccept.isEmpty) {
        Navigator.of(context).pop();
        _showSnackBar('Cannot accept any more applicants: Job is full.');
        return;
      }

      // Update job document
      await jobDocRef.update({
        'applicants': FieldValue.arrayRemove(toAccept),
        'acceptedApplicants': FieldValue.arrayUnion(toAccept),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Process each accepted applicant
      for (String applicantId in toAccept) {
        // Create task progress
        await _createTaskProgressForApplicant(applicantId);

        // Send assignment notification
        await NotificationService().sendRealTimeNotification(
          userId: applicantId,
          title: '🎉 Job Assignment Confirmed!',
          body: 'Congratulations! You have been assigned to "${widget.jobPosition}". Please check your tasks for details.',
          data: {
            'type': NotificationService.typeTaskAssigned,
            'jobId': widget.jobId,
            'jobTitle': widget.jobPosition,
            'timestamp': DateTime.now().toIso8601String(),
          },
          priority: NotificationPriority.high,
        );

        // Set up deadline notifications
        await _setupDeadlineNotificationsForEmployee(applicantId, data);
      }

      Navigator.of(context).pop(); // Close loading dialog

      final message = toAccept.length == applicantIds.length
          ? '${toAccept.length} applicants accepted successfully.'
          : '${toAccept.length} of ${applicantIds.length} applicants accepted (job capacity reached).';

      _showSnackBar(message);
      await _loadTeamPerformanceData();

    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      print('Error accepting multiple applicants: $e');
      _showSnackBar('Error accepting applicants: $e');
    }
  }

  Future<void> _updateJobDeadlineForAllEmployees(DateTime newDeadline) async {
    try {
      final jobDocRef = FirebaseFirestore.instance.collection('jobs').doc(widget.jobId);
      final jobDoc = await jobDocRef.get();

      if (!jobDoc.exists) {
        _showSnackBar('Job not found.');
        return;
      }

      final data = jobDoc.data()!;
      final acceptedApplicants = List<String>.from(data['acceptedApplicants'] ?? []);

      // Update the deadline in the job document
      final newEndDate = newDeadline.toLocal().toString().split(' ')[0];
      final newEndTime = '${newDeadline.hour.toString().padLeft(2, '0')}:${newDeadline.minute.toString().padLeft(2, '0')}';

      await jobDocRef.update({
        'endDate': newEndDate,
        'endTime': newEndTime,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Reschedule deadline notifications for all accepted employees
      if (acceptedApplicants.isNotEmpty && newDeadline.isAfter(DateTime.now())) {
        print('Rescheduling deadline notifications for ${acceptedApplicants.length} employees');

        final currentUser = FirebaseAuth.instance.currentUser;
        await NotificationService().scheduleDeadlineRemindersForEmployees(
          taskId: widget.jobId,
          taskTitle: widget.jobPosition,
          deadline: newDeadline,
          employeeIds: acceptedApplicants,
          employerUserId: currentUser?.uid,
        );

        // Notify employees about the deadline change
        for (String employeeId in acceptedApplicants) {
          await NotificationService().sendRealTimeNotification(
            userId: employeeId,
            title: '📅 Deadline Updated',
            body: 'The deadline for "${widget.jobPosition}" has been updated to ${newDeadline.toLocal().toString().split('.')[0]}',
            data: {
              'type': NotificationService.typeStatusChanged,
              'jobId': widget.jobId,
              'jobTitle': widget.jobPosition,
              'action': 'deadline_updated',
              'newDeadline': newDeadline.toIso8601String(),
              'timestamp': DateTime.now().toIso8601String(),
            },
            priority: NotificationPriority.high,
          );
        }
      }

      _showSnackBar('Deadline updated and notifications rescheduled for all employees.');
      print('Job deadline updated and notifications rescheduled');

    } catch (e) {
      print('Error updating job deadline: $e');
      _showSnackBar('Error updating deadline: $e');
    }
  }

  Future<void> _rejectApplicant(String applicantId) async {
    final frequentReasons = [
      'Lack of required skills',
      'Insufficient experience',
      'Schedule conflict',
      'Application incomplete',
      'Other'
    ];

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        String? selectedReason;
        final TextEditingController customReasonController = TextEditingController();

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text('Reason for Rejection', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    hint: Text('Select a reason', style: GoogleFonts.poppins()),
                    value: selectedReason,
                    isExpanded: true,
                    items: frequentReasons.map((reason) {
                      return DropdownMenuItem<String>(
                        value: reason,
                        child: Text(reason, style: GoogleFonts.poppins()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedReason = value;
                        if (value != 'Other') {
                          customReasonController.clear();
                        }
                      });
                    },
                  ),
                  if (selectedReason == 'Other') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: customReasonController,
                      decoration: InputDecoration(
                        labelText: 'Please specify',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      style: GoogleFonts.poppins(),
                      onChanged: (value) {
                        setDialogState(() {});
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Cancel', style: GoogleFonts.poppins()),
                ),
                ElevatedButton(
                  onPressed: () {
                    final isValidReason = selectedReason != null &&
                        (selectedReason != 'Other' || customReasonController.text.trim().isNotEmpty);

                    if (!isValidReason) {
                      _showSnackBar('Please select or specify a reason.');
                      return;
                    }

                    Navigator.pop(dialogContext);
                    _performRejectApplicant(applicantId, selectedReason!, customReasonController.text.trim());
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006D77)),
                  child: Text('Submit', style: GoogleFonts.poppins(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _performRejectApplicant(String applicantId, String selectedReason, String customReason) async {
    try {
      print('Rejecting applicant: $applicantId, Reason: $selectedReason');

      final rejectionReason = selectedReason == 'Other' ? customReason : selectedReason;

      await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
        'applicants': FieldValue.arrayRemove([applicantId]),
        'rejectedApplicants': FieldValue.arrayUnion([applicantId]),
      });

      // Send notification to rejected applicant
      await FirebaseFirestore.instance
          .collection('users')
          .doc(applicantId)
          .collection('notifications')
          .add({
        'message': 'Your application for "${widget.jobPosition}" was rejected. Reason: $rejectionReason',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'type': 'rejection',
        'jobId': widget.jobId,
      });

      _showSnackBar('Applicant rejected successfully.');
      setState(() {}); // Refresh the UI

      print('Applicant $applicantId rejected successfully');
    } catch (e) {
      print('Error rejecting applicant: $e');
      _showSnackBar('Error rejecting applicant: $e');
    }
  }

  Future<void> _reviewCompletionRequest(String applicantId, String applicantName, bool approve, String? notes) async {
    try {
      final taskProgressRef = FirebaseFirestore.instance
          .collection('users')
          .doc(applicantId)
          .collection('taskProgress')
          .doc(widget.jobId);

      final updateData = {
        'completionApproved': approve,
        'lastUpdated': Timestamp.now(),
        'status': approve ? 'completed' : 'inProgress',
      };
      if (notes != null && notes.isNotEmpty) {
        updateData['completionNotes'] = notes;
      }

      await taskProgressRef.update(updateData);

      // Update history
      await taskProgressRef.collection('history').add({
        'status': approve ? 'completed' : 'inProgress',
        'notes': approve ? 'Completion approved by employer' : 'Completion rejected: $notes',
        'timestamp': Timestamp.now(),
        'action': approve ? 'completion_approved' : 'completion_rejected',
      });

      // Update jobs collection
      if (approve) {
        await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
          'progressPercentage': 100.0,
          'isCompleted': true,
        });

        // Award points
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final profileRef = FirebaseFirestore.instance
              .collection('users')
              .doc(applicantId)
              .collection('profiledetails')
              .doc('profile');

          final profileDoc = await transaction.get(profileRef);
          final currentPoints = (profileDoc.data()?['points'] ?? 0) as int;

          transaction.update(profileRef, {
            'points': currentPoints + 100,
            'lastPointsUpdate': Timestamp.now(),
          });

          final pointsHistoryRef = FirebaseFirestore.instance
              .collection('users')
              .doc(applicantId)
              .collection('pointsHistory')
              .doc();

          transaction.set(pointsHistoryRef, {
            'points': 100,
            'source': 'task_completion',
            'itemName': widget.jobPosition,
            'timestamp': Timestamp.now(),
            'description': 'Completed task: ${widget.jobPosition}',
          });
        });
      }

      // Notify employee
      await FirebaseFirestore.instance
          .collection('users')
          .doc(applicantId)
          .collection('notifications')
          .add({
        'message': approve
            ? 'Your task "${widget.jobPosition}" has been approved as complete! You earned 100 points.'
            : 'Your completion request for "${widget.jobPosition}" was rejected. Reason: ${notes ?? 'No reason provided'}',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'type': approve ? 'completion_approved' : 'completion_rejected',
      });

      _showSnackBar(approve ? 'Task completion approved and points awarded.' : 'Completion request rejected.');
      _loadTeamPerformanceData();
    } catch (e) {
      print('Error reviewing completion request: $e');
      _showSnackBar('Error reviewing completion request: $e');
    }
  }

  void _viewApplicantProgress(String applicantId, String applicantName, String completionNotes) {
    if (teamPerformanceData.any((member) => member['userId'] == applicantId && member['completionRequested'] && !member['completionApproved'])) {
      _showCompletionReviewDialog(applicantId, applicantName, completionNotes);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TaskProgressPage(
            taskId: widget.jobId,
            taskTitle: '${widget.jobPosition} - $applicantName',
            isEmployer: true,
            applicantId: applicantId, // Add this line
          ),
        ),
      );
    }
  }

  void _showCompletionReviewDialog(String applicantId, String applicantName, String completionNotes) {
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Review Completion Request', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Employee: $applicantName', style: GoogleFonts.poppins()),
            const SizedBox(height: 8),
            Text('Completion Notes: ${completionNotes.isEmpty ? 'None' : completionNotes}', style: GoogleFonts.poppins()),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: 'Review Notes (Optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              maxLines: 3,
              style: GoogleFonts.poppins(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _reviewCompletionRequest(applicantId, applicantName, false, notesController.text.trim());
            },
            child: Text('Reject', style: GoogleFonts.poppins(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _reviewCompletionRequest(applicantId, applicantName, true, notesController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006D77)),
            child: Text('Approve', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF006D77),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildOverallProgressCard(double progress) {
    return Card(
      margin: const EdgeInsets.all(16),
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
                  'Overall Job Progress',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF006D77),
                  ),
                ),
                Text(
                  '${progress.toStringAsFixed(1)}%',
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
              value: progress / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                progress < 30 ? Colors.red : progress < 70 ? Colors.orange : Colors.green,
              ),
              minHeight: 8,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamPerformanceSection() {
    if (teamPerformanceData.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Team Performance',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 15),
            ...teamPerformanceData.map((member) {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member['name'],
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    'Status: ${member['status']}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (member['completionRequested'] && !member['completionApproved']) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Completion Requested',
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange[700],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              '${member['progress'].toStringAsFixed(1)}%',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF006D77),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                member['completionRequested'] && !member['completionApproved']
                                    ? Icons.pending_actions
                                    : Icons.analytics,
                                color: member['completionRequested'] && !member['completionApproved']
                                    ? Colors.orange
                                    : const Color(0xFF006D77),
                              ),
                              onPressed: () => _viewApplicantProgress(
                                member['userId'],
                                member['name'],
                                member['completionNotes'],
                              ),
                              tooltip: member['completionRequested'] && !member['completionApproved']
                                  ? 'Review Completion Request'
                                  : 'View Progress',
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: member['progress'] / 100,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        member['progress'] < 30 ? Colors.red : member['progress'] < 70 ? Colors.orange : Colors.green,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _getApplicantData(String applicantId) async {
    try {
      // Get profile data
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(applicantId)
          .collection('profiledetails')
          .doc('profile')
          .get();

      // Get skills data
      final skillsDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(applicantId)
          .collection('skills')
          .doc('user_skills')
          .get();

      String name = 'Unknown User';
      String phone = 'Not provided';
      String address = 'Not provided';
      String skills = 'Not provided';

      if (profileDoc.exists && profileDoc.data() != null) {
        final profileData = profileDoc.data()!;
        name = profileData['name'] ?? 'Unknown User';
        phone = profileData['phone'] ?? 'Not provided';
        address = profileData['address'] ?? 'Not provided';
      }

      if (skillsDoc.exists && skillsDoc.data() != null) {
        final skillsData = skillsDoc.data()!;
        final skillList = skillsData['skills'] as List? ?? [];
        skills = skillList.isNotEmpty
            ? skillList.map((skillMap) => skillMap['skill'] as String? ?? 'Unknown Skill').join(', ')
            : 'Not provided';
      }

      return {
        'name': name,
        'phone': phone,
        'address': address,
        'skills': skills,
      };
    } catch (e) {
      print('Error getting applicant data for $applicantId: $e');
      return {
        'name': 'Error Loading User',
        'phone': 'Error',
        'address': 'Error',
        'skills': 'Error',
      };
    }
  }

  void _showSelectTeamMemberDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Team Member', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: teamPerformanceData.map((member) {
            return ListTile(
              title: Text(member['name'], style: GoogleFonts.poppins()),
              subtitle: Text('Progress: ${member['progress'].toStringAsFixed(1)}%', style: GoogleFonts.poppins()),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TaskProgressPage(
                      taskId: widget.jobId,
                      taskTitle: '${widget.jobPosition} - ${member['name']}',
                      isEmployer: true,
                      applicantId: member['userId'],
                    ),
                  ),
                );
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

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return Scaffold(
        body: Center(
          child: Text('Please log in.', style: GoogleFonts.poppins()),
        ),
      );
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
            'Manage: ${widget.jobPosition}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
          ),
          backgroundColor: const Color(0xFF006D77),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadTeamPerformanceData,
            ),
          ],
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Error: $errorMessage',
                style: GoogleFonts.poppins(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadTeamPerformanceData,
                child: const Text('Retry'),
              ),
            ],
          ),
        )
            : StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            final overallProgress = (data['overallProgress'] ?? 0.0).toDouble();
            final applicants = List<String>.from(data['applicants'] ?? []);
            final acceptedApplicants = List<String>.from(data['acceptedApplicants'] ?? []);
            final rejectedApplicants = List<String>.from(data['rejectedApplicants'] ?? []);
            final requiredPeople = data['requiredPeople'] as int? ?? 1;
            final isJobFull = acceptedApplicants.length >= requiredPeople;

            print('Current applicants: ${applicants.length}, Accepted: ${acceptedApplicants.length}, Rejected: ${rejectedApplicants.length}');

            return SingleChildScrollView(
              child: Column(
                children: [
                  _buildOverallProgressCard(overallProgress),
                  _buildTeamPerformanceSection(),

                  // Applicants section
                  Card(
                    margin: const EdgeInsets.all(16),
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Pending Applicants (${applicants.length})',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF006D77),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isJobFull ? Colors.red[100] : Colors.green[100],
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isJobFull ? Colors.red : Colors.green,
                                  ),
                                ),
                                child: Text(
                                  '${acceptedApplicants.length}/$requiredPeople Filled',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isJobFull ? Colors.red[700] : Colors.green[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (applicants.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(
                                  isJobFull ? Icons.people : Icons.people_outline,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  isJobFull
                                      ? 'Job is full. No more applicants can be accepted.'
                                      : 'No pending applicants.',
                                  style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: applicants.length,
                            itemBuilder: (context, index) {
                              final applicantId = applicants[index];
                              return FutureBuilder<Map<String, dynamic>>(
                                future: _getApplicantData(applicantId),
                                builder: (context, applicantSnapshot) {
                                  if (applicantSnapshot.connectionState == ConnectionState.waiting) {
                                    return const ListTile(
                                      title: Text('Loading applicant details...'),
                                      leading: CircularProgressIndicator(),
                                    );
                                  }

                                  if (applicantSnapshot.hasError) {
                                    return ListTile(
                                      title: Text('Error loading applicant', style: GoogleFonts.poppins()),
                                      subtitle: Text('Error: ${applicantSnapshot.error}', style: GoogleFonts.poppins()),
                                      leading: const Icon(Icons.error, color: Colors.red),
                                    );
                                  }

                                  final applicantData = applicantSnapshot.data ?? {};
                                  final name = applicantData['name'] ?? 'Unknown User';
                                  final phone = applicantData['phone'] ?? 'Not provided';
                                  final address = applicantData['address'] ?? 'Not provided';
                                  final skills = applicantData['skills'] ?? 'Not provided';

                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey[300]!),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withOpacity(0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(16),
                                      title: Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: Colors.blue,
                                            child: Text(
                                              name.isNotEmpty ? name[0].toUpperCase() : 'U',
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
                                                  name,
                                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                                                ),
                                                Text(
                                                  'Phone: $phone',
                                                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Address: $address', style: GoogleFonts.poppins(fontSize: 12)),
                                            const SizedBox(height: 4),
                                            Text('Skills: $skills', style: GoogleFonts.poppins(fontSize: 12)),
                                            const SizedBox(height: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.orange[100],
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'Status: Pending',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.orange[700],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.check, color: Colors.green),
                                            onPressed: isJobFull ? null : () => _acceptApplicant(applicantId),
                                            tooltip: isJobFull ? 'Job is full' : 'Accept applicant',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close, color: Colors.red),
                                            onPressed: () => _rejectApplicant(applicantId),
                                            tooltip: 'Reject applicant',
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                      ],
                    ),
                  ),

                  // Accepted applicants section
                  if (acceptedApplicants.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.all(16),
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Accepted Applicants (${acceptedApplicants.length})',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF006D77),
                              ),
                            ),
                          ),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: acceptedApplicants.length,
                            itemBuilder: (context, index) {
                              final applicantId = acceptedApplicants[index];
                              return FutureBuilder<Map<String, dynamic>>(
                                future: _getApplicantData(applicantId),
                                builder: (context, applicantSnapshot) {
                                  if (applicantSnapshot.connectionState == ConnectionState.waiting) {
                                    return const ListTile(
                                      title: Text('Loading applicant details...'),
                                      leading: CircularProgressIndicator(),
                                    );
                                  }

                                  final applicantData = applicantSnapshot.data ?? {};
                                  final name = applicantData['name'] ?? 'Unknown User';
                                  final phone = applicantData['phone'] ?? 'Not provided';
                                  final skills = applicantData['skills'] ?? 'Not provided';

                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.green[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(16),
                                      title: Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: Colors.green,
                                            child: Text(
                                              name.isNotEmpty ? name[0].toUpperCase() : 'U',
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
                                                  name,
                                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                                                ),
                                                Text(
                                                  'Phone: $phone',
                                                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                                                ),
                                                Text(
                                                  'Skills: $skills',
                                                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.green[100],
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            'Status: Accepted',
                                            style: GoogleFonts.poppins(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green[700],
                                            ),
                                          ),
                                        ),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.analytics, color: Colors.blue),
                                        onPressed: () {
                                          final member = teamPerformanceData.firstWhere(
                                                (m) => m['userId'] == applicantId,
                                            orElse: () => {'completionNotes': ''},
                                          );
                                          _viewApplicantProgress(applicantId, name, member['completionNotes']);
                                        },
                                        tooltip: 'View Progress',
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // Show a dialog to select which team member's progress to view
            if (teamPerformanceData.isNotEmpty) {
              _showSelectTeamMemberDialog();
            } else {
              _showSnackBar('No team members to view progress for.');
            }
          },
          backgroundColor: const Color(0xFF006D77),
          child: const Icon(Icons.analytics, color: Colors.white),
        ),
      ),
    );
  }
}