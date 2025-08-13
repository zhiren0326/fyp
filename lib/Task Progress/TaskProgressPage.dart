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
      print('TaskProgressPage f- User email: ${user.email}');
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

  Future<void> _approveTaskCompletion(String taskId, String employeeId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _showSnackBar('User not authenticated.');
        return;
      }

      // Get job details first to calculate points and money
      final jobDoc = await FirebaseFirestore.instance.collection('jobs').doc(taskId).get();
      if (!jobDoc.exists) {
        _showSnackBar('Job not found.');
        return;
      }

      final jobData = jobDoc.data()!;
      final jobSalary = (jobData['salary'] ?? 0).toDouble();
      final jobTitle = jobData['jobPosition'] ?? 'Task';

      // Calculate points based on job details and duration
      int pointsToAward = _calculatePointsFromJob(jobData);

      // Use batch writes instead of transaction to avoid completion errors
      final batch = FirebaseFirestore.instance.batch();

      // Get employee's current profile data first
      final employeeProfileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('profiledetails')
          .doc('profile')
          .get();

      final currentPoints = (employeeProfileDoc.data()?['points'] ?? 0) as int;
      final currentMoney = (employeeProfileDoc.data()?['totalEarnings'] ?? 0.0) as double;
      final tasksCompleted = (employeeProfileDoc.data()?['tasksCompleted'] ?? 0) as int;

      // Update taskProgress in employee's collection
      final taskProgressRef = FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('taskProgress')
          .doc(taskId);

      batch.update(taskProgressRef, {
        'completionApproved': true,
        'status': 'completed',
        'currentProgress': 100,
        'lastUpdated': Timestamp.now(),
        'approvedBy': currentUser.uid,
        'approvedAt': Timestamp.now(),
        'pointsAwarded': pointsToAward,
        'moneyEarned': jobSalary,
      });

      // Update jobs collection
      final jobRef = FirebaseFirestore.instance.collection('jobs').doc(taskId);
      batch.update(jobRef, {
        'isCompleted': true,
        'completedAt': Timestamp.now(),
        'completedBy': employeeId,
        'pointsAwarded': pointsToAward,
        'salaryPaid': jobSalary,
      });

      // Update employee's profile with points
      final employeeProfileRef = FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('profiledetails')
          .doc('profile');

      batch.update(employeeProfileRef, {
        'points': currentPoints + pointsToAward,
        'totalEarnings': currentMoney + jobSalary,
        'tasksCompleted': tasksCompleted + 1,
        'lastPointsUpdate': Timestamp.now(),
        'lastEarningsUpdate': Timestamp.now(),
      });

      // Add points history
      final pointsHistoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('pointsHistory')
          .doc();

      batch.set(pointsHistoryRef, {
        'points': pointsToAward,
        'source': 'task_completion',
        'taskId': taskId,
        'taskTitle': jobTitle,
        'timestamp': Timestamp.now(),
        'description': 'Completed task: $jobTitle',
      });

      // Add money history
      final moneyHistoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('moneyHistory')
          .doc();

      batch.set(moneyHistoryRef, {
        'amount': jobSalary,
        'source': 'task_completion',
        'taskId': taskId,
        'taskTitle': jobTitle,
        'timestamp': Timestamp.now(),
        'description': 'Payment for completed task: $jobTitle',
        'type': 'earning',
      });

      // Add to task history
      final taskHistoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('taskProgress')
          .doc(taskId)
          .collection('history')
          .doc();

      batch.set(taskHistoryRef, {
        'notes': 'Task completion approved by employer',
        'timestamp': Timestamp.now(),
        'action': 'completion_approved',
        'approvedBy': currentUser.uid,
        'pointsAwarded': pointsToAward,
        'moneyEarned': jobSalary,
      });

      // Commit all changes
      await batch.commit();

      // Check and award badges
      await _checkAndAwardBadges(employeeId);

      // Create notification in Firestore (for app notification history)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('notifications')
          .add({
        'message': 'Task "$jobTitle" completed! Earned $pointsToAward points and RM${jobSalary.toStringAsFixed(2)}',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'type': 'completion_approved',
        'taskId': taskId,
        'approvedBy': currentUser.uid,
        'pointsAwarded': pointsToAward,
        'moneyEarned': jobSalary,
      });

      // Send real-time notification to employee
      await NotificationService().sendRealTimeNotification(
        userId: employeeId,
        title: '🎉 Task Completed & Approved!',
        body: 'Congratulations! You earned $pointsToAward points and RM${jobSalary.toStringAsFixed(2)} for completing "$jobTitle"',
        data: {
          'type': 'completion_approved',
          'taskId': taskId,
          'taskTitle': jobTitle,
          'pointsAwarded': pointsToAward,
          'moneyEarned': jobSalary,
          'timestamp': DateTime.now().toIso8601String(),
        },
        priority: NotificationPriority.high,
      );

      _showSnackBar('Task completion approved! Employee notification sent. Employee earned $pointsToAward points and RM${jobSalary.toStringAsFixed(2)}');
      print('Task approval notification sent to employee: $employeeId');
    } catch (e) {
      print('Error approving completion: $e');
      _showSnackBar('Error approving completion: $e');
    }
  }

  int _calculatePointsFromJob(Map<String, dynamic> jobData) {
    // Get task details
    final estimatedDuration = (jobData['estimatedDuration'] ?? 1).toDouble(); // in hours
    final priority = jobData['priority'] ?? 'Medium';
    final isShortTerm = jobData['isShortTerm'] ?? false;
    final employmentType = jobData['employmentType'] ?? 'Contract';
    final requiredSkills = jobData['requiredSkill'] as List? ?? [];
    final salary = (jobData['salary'] ?? 0).toDouble();

    // Base points: 50 points per hour of estimated duration
    int basePoints = (estimatedDuration * 50).round();

    // Priority multipliers
    Map<String, double> priorityMultipliers = {
      'low': 0.8,
      'medium': 1.0,
      'high': 1.3,
      'critical': 1.6,
    };

    double priorityMultiplier = priorityMultipliers[priority.toLowerCase()] ?? 1.0;

    // Employment type multipliers
    Map<String, double> employmentMultipliers = {
      'contract': 1.0,
      'part-time': 0.9,
      'full-time': 1.1,
      'freelance': 1.2,
      'internship': 0.7,
    };

    double employmentMultiplier = employmentMultipliers[employmentType.toLowerCase()] ?? 1.0;

    // Skill complexity bonus (5 points per required skill)
    int skillBonus = requiredSkills.length * 5;

    // Short-term task bonus (encourages quick task completion)
    int shortTermBonus = isShortTerm ? 20 : 0;

    // Salary tier bonus (additional points for higher-paying tasks)
    int salaryBonus = 0;
    if (salary >= 100) salaryBonus = 30;
    else if (salary >= 50) salaryBonus = 20;
    else if (salary >= 20) salaryBonus = 10;

    // Calculate final points
    int finalPoints = ((basePoints * priorityMultiplier * employmentMultiplier).round()
        + skillBonus + shortTermBonus + salaryBonus);

    // Minimum and maximum bounds
    if (finalPoints < 20) finalPoints = 20; // Minimum 20 points
    if (finalPoints > 500) finalPoints = 500; // Maximum 500 points per task

    return finalPoints;
  }

  Future<void> _checkAndAwardBadges(String employeeId) async {
    try {
      // Get employee's current stats
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('profiledetails')
          .doc('profile')
          .get();

      if (!profileDoc.exists) return;

      final profileData = profileDoc.data()!;
      final tasksCompleted = (profileData['tasksCompleted'] ?? 0) as int;
      final totalEarnings = (profileData['totalEarnings'] ?? 0.0) as double;
      final points = (profileData['points'] ?? 0) as int;

      // Get current badges
      final badgesDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('badges')
          .doc('achievements')
          .get();

      List<String> currentBadges = [];
      if (badgesDoc.exists) {
        currentBadges = List<String>.from(badgesDoc.data()?['earnedBadges'] ?? []);
      }

      List<String> newBadges = [];

      // Check for task completion badges
      if (tasksCompleted >= 1 && !currentBadges.contains('first_task')) {
        newBadges.add('first_task');
      }
      if (tasksCompleted >= 5 && !currentBadges.contains('task_warrior')) {
        newBadges.add('task_warrior');
      }
      if (tasksCompleted >= 10 && !currentBadges.contains('dedicated_worker')) {
        newBadges.add('dedicated_worker');
      }
      if (tasksCompleted >= 25 && !currentBadges.contains('task_master')) {
        newBadges.add('task_master');
      }
      if (tasksCompleted >= 50 && !currentBadges.contains('legend')) {
        newBadges.add('legend');
      }

      // Check for earnings badges
      if (totalEarnings >= 100 && !currentBadges.contains('first_earnings')) {
        newBadges.add('first_earnings');
      }
      if (totalEarnings >= 1000 && !currentBadges.contains('money_maker')) {
        newBadges.add('money_maker');
      }
      if (totalEarnings >= 5000 && !currentBadges.contains('high_earner')) {
        newBadges.add('high_earner');
      }

      // Check for points badges
      if (points >= 500 && !currentBadges.contains('point_collector')) {
        newBadges.add('point_collector');
      }
      if (points >= 2000 && !currentBadges.contains('point_master')) {
        newBadges.add('point_master');
      }

      // Award new badges
      if (newBadges.isNotEmpty) {
        final updatedBadges = [...currentBadges, ...newBadges];

        await FirebaseFirestore.instance
            .collection('users')
            .doc(employeeId)
            .collection('badges')
            .doc('achievements')
            .set({
          'earnedBadges': updatedBadges,
          'lastUpdated': Timestamp.now(),
          'totalBadges': updatedBadges.length,
        }, SetOptions(merge: true));

        // Send notification for new badges
        for (String badge in newBadges) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(employeeId)
              .collection('notifications')
              .add({
            'message': 'New badge earned: ${_getBadgeName(badge)}!',
            'timestamp': FieldValue.serverTimestamp(),
            'read': false,
            'type': 'badge_earned',
            'badgeId': badge,
          });
        }
      }
    } catch (e) {
      print('Error checking badges: $e');
    }
  }

  String _getBadgeName(String badgeId) {
    Map<String, String> badgeNames = {
      'first_task': 'First Task Completed',
      'task_warrior': 'Task Warrior',
      'dedicated_worker': 'Dedicated Worker',
      'task_master': 'Task Master',
      'legend': 'Legend',
      'first_earnings': 'First Earnings',
      'money_maker': 'Money Maker',
      'high_earner': 'High Earner',
      'point_collector': 'Point Collector',
      'point_master': 'Point Master',
    };
    return badgeNames[badgeId] ?? badgeId;
  }

  Future<void> _updateJobProgressFromIndividualProgress(String taskId) async {
    try {
      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(taskId)
          .get();

      if (!jobDoc.exists) return;

      final data = jobDoc.data()!;
      final acceptedApplicants = List<String>.from(data['acceptedApplicants'] ?? []);

      if (acceptedApplicants.isEmpty) {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(taskId)
            .update({
          'overallProgress': 0.0,
          'progressPercentage': 0.0,
        });
        return;
      }

      List<double> allProgressValues = [];
      int completedCount = 0;
      int totalMembers = acceptedApplicants.length;

      for (String applicantId in acceptedApplicants) {
        try {
          final progressDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(applicantId)
              .collection('taskProgress')
              .doc(taskId)
              .get();

          double progress = 0.0;
          bool completionApproved = false;

          if (progressDoc.exists) {
            final progressData = progressDoc.data()!;
            progress = (progressData['currentProgress'] ?? 0.0).toDouble();
            completionApproved = progressData['completionApproved'] ?? false;

            if (completionApproved && progress >= 100) {
              completedCount++;
            }
          }

          // Always include all team members in the calculation (including those with 0% progress)
          allProgressValues.add(progress);

          print('Progress for applicant $applicantId: $progress%');
        } catch (e) {
          print('Error getting progress for $applicantId: $e');
          allProgressValues.add(0.0);
        }
      }

      // Calculate simple average of ALL team members' progress
      final avgProgress = allProgressValues.isNotEmpty
          ? allProgressValues.reduce((a, b) => a + b) / allProgressValues.length
          : 0.0;

      // Determine if job is completed (all members have completed their tasks)
      final isJobCompleted = completedCount == totalMembers && totalMembers > 0;

      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(taskId)
          .update({
        'overallProgress': double.parse(avgProgress.toStringAsFixed(2)),
        'progressPercentage': double.parse(avgProgress.toStringAsFixed(2)),
        'isCompleted': isJobCompleted,
        'completedMembers': completedCount,
        'totalMembers': totalMembers,
        'lastProgressUpdate': FieldValue.serverTimestamp(),
      });

      print('Job progress updated: ${avgProgress.toStringAsFixed(2)}% (${completedCount}/${totalMembers} completed)');
      print('Individual progress values: $allProgressValues');
      print('Average calculation: ${allProgressValues.reduce((a, b) => a + b)} / ${allProgressValues.length} = ${avgProgress.toStringAsFixed(2)}%');
    } catch (e) {
      print('Error updating job progress: $e');
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

      // Update overall job progress (CRITICAL FIX)
      await _updateJobProgressFromIndividualProgress(taskId);

      // Update jobs collection with the new calculated progress
      final jobDoc = await FirebaseFirestore.instance.collection('jobs').doc(taskId).get();
      if (jobDoc.exists) {
        // Enhanced notification for completion review
        if (newProgress == 100) {
          final jobData = jobDoc.data()!;
          final jobCreatorId = jobData['jobCreator'] ?? jobData['postedBy'];
          final taskTitle = jobData['jobPosition'] ?? 'Task';

          // Get current user's name
          final userProfileDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .collection('profiledetails')
              .doc('profile')
              .get();

          String userName;
          if (userProfileDoc.exists) {
            final data = userProfileDoc.data() as Map<String, dynamic>?;
            userName = data?['name'] as String? ?? 'Unknown User';
          } else {
            userName = 'Unknown User';
          }

          // Create notification in Firestore (for app notification history)
          await FirebaseFirestore.instance
              .collection('users')
              .doc(jobCreatorId)
              .collection('notifications')
              .add({
            'message': 'Task "$taskTitle" completion requested by $userName. Please review.',
            'timestamp': FieldValue.serverTimestamp(),
            'read': false,
            'type': 'completion_request',
            'taskId': taskId,
            'employeeId': currentUser.uid,
            'completionNotes': completionNotes ?? '',
          });

          // Send real-time notification using NotificationService
          await NotificationService().sendCompletionRequestNotification(
            employerId: jobCreatorId,
            employeeId: currentUser.uid,
            employeeName: userName,
            taskId: taskId,
            taskTitle: taskTitle,
            completionNotes: completionNotes ?? '',
          );

          print('Enhanced completion request notification sent to employer: $jobCreatorId');
        }
      }

      _showSnackBar(newProgress == 100 ? 'Completion requested! Employer will be notified immediately.' : 'Progress updated successfully!');
    } catch (e) {
      print('Error updating progress: $e');
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

      if (newStatus == 'blocked') {
        final jobDoc = await FirebaseFirestore.instance
            .collection('jobs')
            .doc(taskId)
            .get();

        if (jobDoc.exists) {
          final jobCreatorId = jobDoc.data()!['jobCreator'];
          await NotificationService().sendRealTimeNotification(
            userId: jobCreatorId,
            title: '⚠️ Task Blocked',
            body: 'Task "${taskData['taskTitle']}" has been blocked and needs attention',
            data: {
              'type': 'status_changed',
              'taskId': taskId,
              'newStatus': 'blocked',
            },
            priority: NotificationPriority.high,
          );
        }
      }

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

  Future<void> _rejectTaskCompletion(String taskId, String employeeId, String rejectionReason) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _showSnackBar('User not authenticated.');
        return;
      }

      // Get task title for notification
      final jobDoc = await FirebaseFirestore.instance.collection('jobs').doc(taskId).get();
      final taskTitle = jobDoc.exists
          ? ((jobDoc.data() as Map<String, dynamic>?)?['jobPosition'] ?? 'Task')
          : 'Task';
      // Update taskProgress in employee's collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('taskProgress')
          .doc(taskId)
          .update({
        'completionRequested': false,
        'completionApproved': false,
        'status': 'inProgress',
        'lastUpdated': Timestamp.now(),
        'rejectedBy': currentUser.uid,
        'rejectedAt': Timestamp.now(),
        'rejectionReason': rejectionReason,
      });

      // Add to history
      await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('taskProgress')
          .doc(taskId)
          .collection('history')
          .add({
        'notes': 'Task completion rejected: $rejectionReason',
        'timestamp': Timestamp.now(),
        'action': 'completion_rejected',
        'rejectedBy': currentUser.uid,
        'rejectionReason': rejectionReason,
      });

      // Create notification in Firestore (for app notification history)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('notifications')
          .add({
        'message': 'Task completion rejected. Reason: $rejectionReason',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'type': 'completion_rejected',
        'taskId': taskId,
        'rejectedBy': currentUser.uid,
        'rejectionReason': rejectionReason,
      });

      // Send real-time notification to employee
      await NotificationService().sendRealTimeNotification(
        userId: employeeId,
        title: '❌ Task Completion Rejected',
        body: 'Your completion request for "$taskTitle" was rejected. Reason: $rejectionReason',
        data: {
          'type': 'completion_rejected',
          'taskId': taskId,
          'taskTitle': taskTitle,
          'rejectionReason': rejectionReason,
          'timestamp': DateTime.now().toIso8601String(),
        },
        priority: NotificationPriority.high,
      );

      _showSnackBar('Task completion rejected. Employee notification sent.');
      print('Task rejection notification sent to employee: $employeeId');
    } catch (e) {
      print('Error rejecting completion: $e');
      _showSnackBar('Error rejecting completion: $e');
    }
  }

  void _showCompletionReviewDialog(String taskId, String employeeId, String employeeName, String completionNotes) {
    final rejectionReasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Review Task Completion', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Employee: $employeeName', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              if (completionNotes.isNotEmpty) ...[
                Text('Completion Notes:', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(completionNotes, style: GoogleFonts.poppins()),
                ),
                const SizedBox(height: 16),
              ],
              Text('Rejection Reason (if rejecting):', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              TextField(
                controller: rejectionReasonController,
                decoration: InputDecoration(
                  hintText: 'Enter reason for rejection...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                maxLines: 3,
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
              final rejectionReason = rejectionReasonController.text.trim();
              if (rejectionReason.isEmpty) {
                _showSnackBar('Please provide a rejection reason.');
                return;
              }
              Navigator.pop(context);
              _rejectTaskCompletion(taskId, employeeId, rejectionReason);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Reject', style: GoogleFonts.poppins(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _approveTaskCompletion(taskId, employeeId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Approve', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
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
          .orderBy('postedAt', descending: true) // Add this line
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
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(employeeId)
                            .collection('profiledetails')
                            .doc('profile')
                            .get(),
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
                                    // Show completion request status
                                    if (taskData?['completionRequested'] == true && taskData?['completionApproved'] != true) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange[100],
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'PENDING REVIEW',
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
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (taskData?['completionRequested'] == true && taskData?['completionApproved'] != true)
                                      IconButton(
                                        icon: const Icon(Icons.rate_review, color: Colors.orange, size: 20),
                                        onPressed: () => _showCompletionReviewDialog(
                                          jobId,
                                          employeeId,
                                          employeeName,
                                          taskData?['completionNotes'] ?? '',
                                        ),
                                        tooltip: 'Review Completion',
                                      )
                                    else ...[
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
          .orderBy('createdAt', descending: true) // Add this line
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

        // Filter tasks to exclude those created by the current user
        return FutureBuilder<List<QueryDocumentSnapshot>>(
          future: _filterNonCreatedTasks(snapshot.data!.docs, currentUser.uid),
          builder: (context, filteredSnapshot) {
            if (filteredSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (filteredSnapshot.hasError) {
              print('Error filtering tasks: ${filteredSnapshot.error}');
              return Center(child: Text('Error: ${filteredSnapshot.error}', style: GoogleFonts.poppins()));
            }

            final tasks = filteredSnapshot.data ?? [];

            if (tasks.isEmpty) {
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

            // Apply status filter
            var filteredTasks = tasks;
            if (selectedFilter != 'all') {
              filteredTasks = tasks.where((doc) {
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
                    itemCount: filteredTasks.length,
                    itemBuilder: (context, index) {
                      final taskDoc = filteredTasks[index];
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
      },
    );
  }

  Future<List<QueryDocumentSnapshot>> _filterNonCreatedTasks(
      List<QueryDocumentSnapshot> taskDocs, String currentUserId) async {
    final filteredTasks = <QueryDocumentSnapshot>[];

    for (var taskDoc in taskDocs) {
      final taskId = taskDoc.id;
      // Fetch the corresponding job document
      final jobDoc = await FirebaseFirestore.instance.collection('jobs').doc(taskId).get();
      if (jobDoc.exists) {
        final jobData = jobDoc.data() as Map<String, dynamic>;
        final postedBy = jobData['postedBy'] ?? '';
        // Only include tasks where the current user is not the creator
        if (postedBy != currentUserId) {
          filteredTasks.add(taskDoc);
        }
      }
    }

    return filteredTasks;
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