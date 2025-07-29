/*

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TaskProgressService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Gets the current user's progress for a specific task
  static Stream<Map<String, dynamic>> getUserTaskProgress(String taskId) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || taskId.isEmpty) {
      return Stream.value({'progress': 0.0, 'status': 'Not Started'});
    }

    return _firestore
        .collection('jobs')
        .doc(taskId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        return {'progress': 0.0, 'status': 'Not Started'};
      }

      final data = snapshot.data() as Map<String, dynamic>;

      // Get user's progress
      final progressList = data['progressPercentage'] as List<dynamic>? ?? [];
      double progress = 0.0;
      String status = 'Not Started';

      for (var item in progressList) {
        if (item is Map<String, dynamic> && item['userId'] == currentUserId) {
          progress = (item['progress'] as num?)?.toDouble() ?? 0.0;
          break;
        }
      }

      final statusList = data['submissionStatus'] as List<dynamic>? ?? [];
      for (var item in statusList) {
        if (item is Map<String, dynamic> && item['userId'] == currentUserId) {
          status = item['status']?.toString() ?? 'Not Started';
          break;
        }
      }

      return {
        'progress': progress,
        'status': status,
        'taskId': taskId,
        'taskTitle': data['jobPosition']?.toString() ?? 'Unknown Task',
        'isShortTerm': data['isShortTerm'] ?? true,
        'employerId': data['postedBy'],
        'acceptedApplicants': data['acceptedApplicants'] ?? [],
        'fileBase64': data['fileBase64'] ?? [],
        'notes': data['notes']?.toString() ?? '',
      };
    });
  }

  /// Updates user's task progress
  static Future<bool> updateTaskProgress({
    required String taskId,
    required double progress,
    required String status,
    String? notes,
    List<String>? fileBase64s,
  }) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return false;

      await _firestore.runTransaction((transaction) async {
        final jobRef = _firestore.collection('jobs').doc(taskId);
        final jobDoc = await transaction.get(jobRef);

        if (!jobDoc.exists) throw Exception('Task not found');

        final data = jobDoc.data() as Map<String, dynamic>;
        List<dynamic> progressList = [];

        // Handle progressPercentage as number or array
        final currentProgressData = data['progressPercentage'];
        if (currentProgressData is num) {
          print('Converting progressPercentage from number to array');
          progressList = [
            {
              'userId': currentUserId,
              'progress': currentProgressData.toDouble(),
              'timestamp': FieldValue.serverTimestamp(),
            }
          ];
        } else if (currentProgressData is List<dynamic>) {
          progressList = List.from(currentProgressData);
        } else {
          progressList = [];
        }

        // Remove existing progress for this user
        progressList.removeWhere(
                (item) => item is Map<String, dynamic> && item['userId'] == currentUserId);

        // Add updated progress
        progressList.add({
          'userId': currentUserId,
          'progress': progress.clamp(0.0, 100.0),
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Update submissionStatus
        List<dynamic> statusList = List.from(data['submissionStatus'] ?? []);
        statusList.removeWhere(
                (item) => item is Map<String, dynamic> && item['userId'] == currentUserId);
        statusList.add({
          'userId': currentUserId,
          'status': status,
          'timestamp': FieldValue.serverTimestamp(),
        });

        transaction.update(jobRef, {
          'progressPercentage': progressList,
          'submissionStatus': statusList,
          'notes': notes ?? '',
          'fileBase64': FieldValue.arrayUnion(fileBase64s ?? []),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      });

      // Update user taskProgress
      await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('taskProgress')
          .doc(taskId)
          .set({
        'currentProgress': progress.clamp(0.0, 100.0),
        'status': status,
        'notes': notes ?? '',
        'fileBase64': FieldValue.arrayUnion(fileBase64s ?? []),
        'lastUpdated': FieldValue.serverTimestamp(),
        'taskId': taskId,
        'taskTitle': (await _firestore.collection('jobs').doc(taskId).get()).data()?['jobPosition'] ?? 'Unknown Task',
        'userId': currentUserId,
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      print('Error updating task progress: $e');
      return false;
    }
  }

  /// Marks task as finished (pending review)
  static Future<bool> markTaskAsFinished({
    required String taskId,
    String? finalNotes,
    List<String>? finalBase64s,
  }) async {
    try {
      final success = await updateTaskProgress(
        taskId: taskId,
        progress: 100.0,
        status: 'Pending Review',
        notes: finalNotes,
        fileBase64s: finalBase64s,
      );

      if (success) {
        // Notify employer
        await _notifyEmployer(taskId);
      }

      return success;
    } catch (e) {
      print('Error marking task as finished: $e');
      return false;
    }
  }

  /// Employer reviews the task (accept/reject)
  static Future<bool> reviewTask({
    required String taskId,
    required String userId,
    required bool isAccepted,
    String? reviewNotes,
  }) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return false;

      // Check if current user is the employer
      final jobDoc = await _firestore.collection('jobs').doc(taskId).get();
      if (!jobDoc.exists) return false;

      final jobData = jobDoc.data() as Map<String, dynamic>;
      if (jobData['postedBy'] != currentUserId) return false;

      await _firestore.runTransaction((transaction) async {
        final jobRef = _firestore.collection('jobs').doc(taskId);
        final jobDoc = await transaction.get(jobRef);

        final data = jobDoc.data() as Map<String, dynamic>;
        List<dynamic> progressList = List.from(data['progressPercentage'] ?? []);

        // Update user's status
        for (int i = 0; i < progressList.length; i++) {
          if (progressList[i] is Map<String, dynamic> &&
              progressList[i]['userId'] == userId) {
            progressList[i] = {
              ...progressList[i],
              'progress': isAccepted ? 100.0 : progressList[i]['progress'],
              'timestamp': FieldValue.serverTimestamp(),
            };
            break;
          }
        }

        // Update submissionStatus
        List<dynamic> statusList = List.from(data['submissionStatus'] ?? []);
        statusList.removeWhere(
                (item) => item is Map<String, dynamic> && item['userId'] == userId);
        statusList.add({
          'userId': userId,
          'status': isAccepted ? 'Completed' : 'Rejected',
          'timestamp': FieldValue.serverTimestamp(),
          'reviewNotes': reviewNotes ?? '',
          'reviewedBy': currentUserId,
        });

        transaction.update(jobRef, {
          'progressPercentage': progressList,
          'submissionStatus': statusList,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      });

      // Update user taskProgress
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('taskProgress')
          .doc(taskId)
          .set({
        'currentProgress': isAccepted ? 100.0 : (jobData['progressPercentage'] as List<dynamic>)
            .firstWhere((item) => item['userId'] == userId, orElse: () => {'progress': 0.0})['progress']
            .toDouble(),
        'status': isAccepted ? 'Completed' : 'Rejected',
        'reviewNotes': reviewNotes ?? '',
        'reviewedBy': currentUserId,
        'reviewedAt': FieldValue.serverTimestamp(),
        'taskId': taskId,
        'taskTitle': jobData['jobPosition'] ?? 'Unknown Task',
        'userId': userId,
      }, SetOptions(merge: true));

      // Notify the employee
      await _notifyEmployee(taskId, userId, isAccepted, reviewNotes);

      return true;
    } catch (e) {
      print('Error reviewing task: $e');
      return false;
    }
  }

  /// Gets all users' progress for a task (employer view)
  static Stream<List<Map<String, dynamic>>> getTaskProgressForEmployer(String taskId) {
    return _firestore
        .collection('jobs')
        .doc(taskId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return [];

      final data = snapshot.data() as Map<String, dynamic>;
      final progressList = data['progressPercentage'] as List<dynamic>? ?? [];
      final statusList = data['submissionStatus'] as List<dynamic>? ?? [];
      final acceptedApplicants = data['acceptedApplicants'] as List<dynamic>? ?? [];
      final fileBase64List = data['fileBase64'] as List<dynamic>? ?? [];

      List<Map<String, dynamic>> result = [];

      for (String userId in acceptedApplicants) {
        Map<String, dynamic> userProgress = {
          'userId': userId,
          'progress': 0.0,
          'status': 'Not Started',
          'notes': '',
          'fileBase64': <String>[],
          'lastUpdated': null,
        };

        // Find user's progress
        for (var item in progressList) {
          if (item is Map<String, dynamic> && item['userId'] == userId) {
            userProgress['progress'] = (item['progress'] as num?)?.toDouble() ?? 0.0;
            userProgress['lastUpdated'] = item['timestamp'];
            break;
          }
        }

        // Find user's status
        for (var item in statusList) {
          if (item is Map<String, dynamic> && item['userId'] == userId) {
            userProgress['status'] = item['status']?.toString() ?? 'Not Started';
            userProgress['reviewNotes'] = item['reviewNotes']?.toString() ?? '';
            break;
          }
        }

        // Use job-level fileBase64 (shared across users)
        userProgress['fileBase64'] = fileBase64List.cast<String>();

        userProgress['notes'] = data['notes']?.toString() ?? '';

        result.add(userProgress);
      }

      return result;
    });
  }

  /// Check if user can edit task progress
  static Future<bool> canUserEditTask(String taskId) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return false;

      final jobDoc = await _firestore.collection('jobs').doc(taskId).get();
      if (!jobDoc.exists) return false;

      final data = jobDoc.data() as Map<String, dynamic>;
      final acceptedApplicants = List<String>.from(data['acceptedApplicants'] ?? []);

      // Check if user is an accepted applicant (not the employer)
      return acceptedApplicants.contains(currentUserId) &&
          data['postedBy'] != currentUserId;
    } catch (e) {
      print('Error checking edit permissions: $e');
      return false;
    }
  }

  /// Check if user is the employer of the task
  static Future<bool> isUserEmployer(String taskId) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return false;

      final jobDoc = await _firestore.collection('jobs').doc(taskId).get();
      if (!jobDoc.exists) return false;

      final data = jobDoc.data() as Map<String, dynamic>;
      return data['postedBy'] == currentUserId;
    } catch (e) {
      print('Error checking employer status: $e');
      return false;
    }
  }

  static Future<void> _notifyEmployer(String taskId) async {
    try {
      final jobDoc = await _firestore.collection('jobs').doc(taskId).get();
      if (!jobDoc.exists) return;

      final data = jobDoc.data() as Map<String, dynamic>;
      final employerId = data['postedBy'];
      final taskTitle = data['jobPosition']?.toString() ?? 'Task';
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      if (employerId != null && currentUserId != null) {
        await _firestore
            .collection('users')
            .doc(employerId)
            .collection('notifications')
            .add({
          'type': 'task_completion',
          'title': 'Task Completed - Review Required',
          'message': 'Task "$taskTitle" has been marked as completed and requires your review.',
          'taskId': taskId,
          'fromUserId': currentUserId,
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });
      }
    } catch (e) {
      print('Error notifying employer: $e');
    }
  }

  static Future<void> _notifyEmployee(
      String taskId,
      String employeeId,
      bool isAccepted,
      String? reviewNotes,
      ) async {
    try {
      final jobDoc = await _firestore.collection('jobs').doc(taskId).get();
      if (!jobDoc.exists) return;

      final data = jobDoc.data() as Map<String, dynamic>;
      final taskTitle = data['jobPosition']?.toString() ?? 'Task';

      await _firestore
          .collection('users')
          .doc(employeeId)
          .collection('notifications')
          .add({
        'type': isAccepted ? 'task_accepted' : 'task_rejected',
        'title': isAccepted ? 'Task Accepted' : 'Task Rejected',
        'message': isAccepted
            ? 'Your task "$taskTitle" has been accepted!'
            : 'Your task "$taskTitle" has been rejected. ${reviewNotes ?? ''}',
        'taskId': taskId,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
    } catch (e) {
      print('Error notifying employee: $e');
    }
  }
}
*/
