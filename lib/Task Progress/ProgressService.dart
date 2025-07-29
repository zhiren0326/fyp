import 'package:cloud_firestore/cloud_firestore.dart';

/// Service class for handling task progress operations
class ProgressService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Gets a stream of task progress for a specific user
  /// Returns progress as a double between 0.0 and 100.0
  static Stream<double> getTaskProgressStream(String taskId, String userId) {
    if (taskId.isEmpty || userId.isEmpty) {
      return Stream.value(0.0);
    }

    return _firestore
        .collection('jobs')
        .doc(taskId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return 0.0;

      final data = snapshot.data();
      if (data == null) return 0.0;

      final progressList = data['progressPercentage'] as List<dynamic>? ?? [];

      // Find the user's specific progress
      for (var item in progressList) {
        if (item is Map<String, dynamic> &&
            item['userId'] == userId &&
            item['progress'] != null) {
          return (item['progress'] as num).toDouble();
        }
      }

      return 0.0;
    }).handleError((error) {
      print('Error getting task progress: $error');
      return 0.0;
    });
  }

  /// Gets a stream of average progress for all employees (employer view)
  /// Returns average progress as a double between 0.0 and 100.0
  static Stream<double> getEmployerProgressStream(String taskId) {
    if (taskId.isEmpty) {
      return Stream.value(0.0);
    }

    return _firestore
        .collection('jobs')
        .doc(taskId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return 0.0;

      final data = snapshot.data();
      if (data == null) return 0.0;

      final progressList = data['progressPercentage'] as List<dynamic>? ?? [];
      if (progressList.isEmpty) return 0.0;

      double total = 0.0;
      int count = 0;

      for (var item in progressList) {
        if (item is Map<String, dynamic> && item['progress'] != null) {
          total += (item['progress'] as num).toDouble();
          count++;
        }
      }

      return count > 0 ? total / count : 0.0;
    }).handleError((error) {
      print('Error getting employer progress: $error');
      return 0.0;
    });
  }

  /// Gets the current status of a task for a specific user
  static Stream<String> getTaskStatusStream(String taskId, String userId) {
    if (taskId.isEmpty || userId.isEmpty) {
      return Stream.value('Not Started');
    }

    return _firestore
        .collection('jobs')
        .doc(taskId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return 'Not Started';

      final data = snapshot.data();
      if (data == null) return 'Not Started';

      final statusList = data['submissionStatus'] as List<dynamic>? ?? [];

      // Find the user's specific status
      for (var item in statusList) {
        if (item is Map<String, dynamic> &&
            item['userId'] == userId &&
            item['status'] != null) {
          return item['status'].toString();
        }
      }

      return 'Not Started';
    }).handleError((error) {
      print('Error getting task status: $error');
      return 'Not Started';
    });
  }

  /// Gets a combined stream of progress and status
  static Stream<Map<String, dynamic>> getTaskProgressAndStatusStream(
      String taskId, String userId) {
    if (taskId.isEmpty || userId.isEmpty) {
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

      final data = snapshot.data();
      if (data == null) {
        return {'progress': 0.0, 'status': 'Not Started'};
      }

      double progress = 0.0;
      String status = 'Not Started';

      // Get progress
      final progressList = data['progressPercentage'] as List<dynamic>? ?? [];
      for (var item in progressList) {
        if (item is Map<String, dynamic> &&
            item['userId'] == userId &&
            item['progress'] != null) {
          progress = (item['progress'] as num).toDouble();
          break;
        }
      }

      // Get status
      final statusList = data['submissionStatus'] as List<dynamic>? ?? [];
      for (var item in statusList) {
        if (item is Map<String, dynamic> &&
            item['userId'] == userId &&
            item['status'] != null) {
          status = item['status'].toString();
          break;
        }
      }

      return {'progress': progress, 'status': status};
    }).handleError((error) {
      print('Error getting task progress and status: $error');
      return {'progress': 0.0, 'status': 'Not Started'};
    });
  }

  /// Checks if a task is a short-term task (supports progress tracking)
  static Future<bool> isShortTermTask(String taskId) async {
    try {
      final doc = await _firestore.collection('jobs').doc(taskId).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['isShortTerm'] ?? true;
      }
      return true; // Default to short-term
    } catch (e) {
      print('Error checking task type: $e');
      return true;
    }
  }

  /// Gets all tasks for a user with their progress
  static Stream<List<Map<String, dynamic>>> getUserTasksWithProgress(
      String userId, {bool isEmployer = false}) {
    if (userId.isEmpty) {
      return Stream.value([]);
    }

    Query query;
    if (isEmployer) {
      query = _firestore
          .collection('jobs')
          .where('postedBy', isEqualTo: userId)
          .where('isShortTerm', isEqualTo: true);
    } else {
      query = _firestore
          .collection('jobs')
          .where('acceptedApplicants', arrayContains: userId)
          .where('isShortTerm', isEqualTo: true);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;

        // Extract title safely
        String title = 'Unnamed Task';
        if (data['jobPosition'] != null) {
          if (data['jobPosition'] is String) {
            title = data['jobPosition'];
          } else if (data['jobPosition'] is List &&
              (data['jobPosition'] as List).isNotEmpty) {
            title = (data['jobPosition'] as List).first.toString();
          }
        }

        // Get progress and status
        double progress = 0.0;
        String status = 'Not Started';

        if (isEmployer) {
          // For employers, calculate average progress
          final progressList = data['progressPercentage'] as List<dynamic>? ?? [];
          if (progressList.isNotEmpty) {
            double total = 0.0;
            int count = 0;
            for (var item in progressList) {
              if (item is Map<String, dynamic> && item['progress'] != null) {
                total += (item['progress'] as num).toDouble();
                count++;
              }
            }
            progress = count > 0 ? total / count : 0.0;
          }

          // Get general status
          final statusList = data['submissionStatus'] as List<dynamic>? ?? [];
          if (statusList.isNotEmpty && statusList.first is Map) {
            status = (statusList.first as Map)['status']?.toString() ?? 'Not Started';
          }
        } else {
          // For employees, get their specific progress and status
          final progressList = data['progressPercentage'] as List<dynamic>? ?? [];
          for (var item in progressList) {
            if (item is Map<String, dynamic> &&
                item['userId'] == userId &&
                item['progress'] != null) {
              progress = (item['progress'] as num).toDouble();
              break;
            }
          }

          final statusList = data['submissionStatus'] as List<dynamic>? ?? [];
          for (var item in statusList) {
            if (item is Map<String, dynamic> &&
                item['userId'] == userId &&
                item['status'] != null) {
              status = item['status'].toString();
              break;
            }
          }
        }

        return {
          'id': doc.id,
          'title': title,
          'progress': progress,
          'status': status,
          'isShortTerm': data['isShortTerm'] ?? true,
        };
      }).toList();
    }).handleError((error) {
      print('Error getting user tasks: $error');
      return <Map<String, dynamic>>[];
    });
  }
}