// UserDataService.dart - Fixed to fetch from both pointsHistory and moneyHistory
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserDataService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Helper methods for safe type conversion
  static int _safeToInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  static double _safeToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    return 0.0;
  }

  static String _safeToString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  // Fetch user-specific points history for a date range
  static Future<List<Map<String, dynamic>>> fetchUserPointsHistory({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      print('Fetching points history for user: $userId from $startDate to $endDate');

      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('pointsHistory')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThan: Timestamp.fromDate(endDate))
          .orderBy('timestamp', descending: false)
          .get();

      List<Map<String, dynamic>> pointsData = [];

      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();

          // Safely extract and validate data
          final processedData = {
            'id': doc.id,
            'points': _safeToInt(data['points']),
            'description': _safeToString(data['description'] ?? 'Points earned'),
            'taskTitle': _safeToString(data['taskTitle'] ?? data['description'] ?? 'Task Completed'),
            'taskId': _safeToString(data['taskId']),
            'source': _safeToString(data['source'] ?? 'task_completion'),
            'type': _safeToString(data['type'] ?? 'earning'),
            'category': _safeToString(data['category'] ?? 'General'),
            'timestamp': data['timestamp'] as Timestamp?,
          };

          // Only add if we have valid timestamp
          if (processedData['timestamp'] != null) {
            pointsData.add(processedData);
            print('Added points record: ${processedData['taskTitle']} - ${processedData['points']} points');
          }

        } catch (e) {
          print('Error processing points history document ${doc.id}: $e');
          // Continue processing other documents
        }
      }

      print('Fetched ${pointsData.length} points history records for user $userId');
      return pointsData;

    } catch (e) {
      print('Error fetching user points history: $e');
      return [];
    }
  }

  // NEW: Fetch user-specific money history for a date range
  static Future<List<Map<String, dynamic>>> fetchUserMoneyHistory({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      print('Fetching money history for user: $userId from $startDate to $endDate');

      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('moneyHistory')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThan: Timestamp.fromDate(endDate))
          .orderBy('timestamp', descending: false)
          .get();

      List<Map<String, dynamic>> moneyData = [];

      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();

          // Safely extract and validate data
          final processedData = {
            'id': doc.id,
            'amount': _safeToDouble(data['amount']),
            'description': _safeToString(data['description'] ?? 'Money transaction'),
            'taskTitle': _safeToString(data['taskTitle'] ?? data['description'] ?? 'Transaction'),
            'taskId': _safeToString(data['taskId']),
            'source': _safeToString(data['source'] ?? 'task_completion'),
            'type': _safeToString(data['type'] ?? 'earning'),
            'timestamp': data['timestamp'] as Timestamp?,
          };

          // Only add if we have valid timestamp
          if (processedData['timestamp'] != null) {
            moneyData.add(processedData);
            print('Added money record: ${processedData['taskTitle']} - RM${processedData['amount']}');
          }

        } catch (e) {
          print('Error processing money history document ${doc.id}: $e');
          // Continue processing other documents
        }
      }

      print('Fetched ${moneyData.length} money history records for user $userId');
      return moneyData;

    } catch (e) {
      print('Error fetching user money history: $e');
      return [];
    }
  }

  // Fetch user profile details (removed level references)
  static Future<Map<String, dynamic>?> fetchUserProfileDetails({
    required String userId,
  }) async {
    try {
      print('Fetching profile details for user: $userId');

      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('profiledetails')
          .doc('profile')
          .get();

      if (snapshot.exists) {
        final data = snapshot.data()!;

        // Safely extract profile data (removed level references)
        final profileData = {
          'id': snapshot.id,
          'name': _safeToString(data['name'] ?? data['displayName'] ?? 'User'),
          'email': _safeToString(data['email']),
          'totalEarnings': _safeToDouble(data['totalEarnings'] ?? 0.0),
          'totalPoints': _safeToInt(data['totalPoints'] ?? 0),
          'completedTasks': _safeToInt(data['completedTasks'] ?? 0),
          'experience': _safeToInt(data['experience'] ?? 0),
          'joinDate': data['joinDate'] as Timestamp?,
          'lastActive': data['lastActive'] as Timestamp?,
          'achievements': data['achievements'] as List? ?? [],
          'skills': data['skills'] as List? ?? [],
          'preferences': data['preferences'] as Map<String, dynamic>? ?? {},
        };

        print('Fetched profile for: ${profileData['name']} - ${profileData['totalPoints']} points, RM${profileData['totalEarnings']}');
        return profileData;
      } else {
        print('No profile details found for user $userId');
        return null;
      }

    } catch (e) {
      print('Error fetching user profile details: $e');
      return null;
    }
  }

  // Generate daily summary data for a specific user using correct data sources
  static Future<Map<String, dynamic>> generateDailySummaryForUser({
    required String userId,
    required DateTime date,
  }) async {
    try {
      print('Generating daily summary for user: $userId on $date');

      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      // Fetch user data in parallel from BOTH collections
      final results = await Future.wait([
        fetchUserPointsHistory(userId: userId, startDate: dayStart, endDate: dayEnd),
        fetchUserMoneyHistory(userId: userId, startDate: dayStart, endDate: dayEnd),
        fetchUserProfileDetails(userId: userId),
      ]);

      final pointsData = results[0] as List<Map<String, dynamic>>;
      final moneyData = results[1] as List<Map<String, dynamic>>;
      final profileData = results[2] as Map<String, dynamic>?;

      // Process points data
      int pointsEarned = 0;
      Map<String, int> tasksByCategory = {};
      List<Map<String, dynamic>> taskDetails = [];
      List<Map<String, dynamic>> pointTransactions = [];

      for (var pointRecord in pointsData) {
        final points = pointRecord['points'] as int;
        final taskTitle = pointRecord['taskTitle'] as String;
        final category = pointRecord['category'] as String;
        final timestamp = pointRecord['timestamp'] as Timestamp?;
        final description = pointRecord['description'] as String;

        pointsEarned += points;

        // Count as completed task if it has points
        if (points > 0) {
          // Categorize task
          final taskCategory = category.isNotEmpty ? category : _categorizeTask(taskTitle);
          tasksByCategory[taskCategory] = (tasksByCategory[taskCategory] ?? 0) + 1;

          // Add to task details
          taskDetails.add({
            'id': pointRecord['id'],
            'title': taskTitle,
            'status': 'Completed',
            'progress': 100.0,
            'points': points,
            'time': timestamp?.toDate() ?? DateTime.now(),
            'category': taskCategory,
            'source': pointRecord['source'],
            'type': pointRecord['type'],
          });
        }

        // Add to point transactions
        pointTransactions.add({
          'id': pointRecord['id'],
          'points': points,
          'description': description,
          'taskTitle': taskTitle,
          'timestamp': timestamp?.toDate() ?? DateTime.now(),
          'source': pointRecord['source'],
        });
      }

      // Process money data (FIXED: Use actual money data)
      double totalEarnings = 0.0;
      int completedTasksCount = 0;
      List<Map<String, dynamic>> moneyTransactions = [];

      for (var moneyRecord in moneyData) {
        final amount = moneyRecord['amount'] as double;
        final taskTitle = moneyRecord['taskTitle'] as String;
        final timestamp = moneyRecord['timestamp'] as Timestamp?;
        final description = moneyRecord['description'] as String;

        totalEarnings += amount;

        if (amount > 0) {
          completedTasksCount++;
        }

        // Add to money transactions
        moneyTransactions.add({
          'id': moneyRecord['id'],
          'amount': amount,
          'description': description,
          'taskTitle': taskTitle,
          'timestamp': timestamp?.toDate() ?? DateTime.now(),
          'source': moneyRecord['source'],
        });
      }

      // Get user info from profile (removed level references)
      final userName = profileData?['name'] ?? 'User';
      final userTotalPoints = profileData?['totalPoints'] ?? 0;
      final userTotalEarnings = profileData?['totalEarnings'] ?? 0.0;

      final summaryData = {
        'date': date.toIso8601String(),
        'userId': userId,
        'userName': userName,
        'userTotalPoints': userTotalPoints,
        'userTotalEarnings': userTotalEarnings,
        'totalTasks': completedTasksCount,
        'completedTasks': completedTasksCount,
        'inProgressTasks': 0,
        'pendingTasks': 0,
        'pointsEarned': pointsEarned,
        'totalEarnings': totalEarnings, // FIXED: Now using actual money data
        'translationsCount': 0,
        'totalCharacters': 0,
        'taskDetails': taskDetails,
        'pointTransactions': pointTransactions,
        'moneyTransactions': moneyTransactions, // NEW: Added money transactions
        'translationDetails': <Map<String, dynamic>>[],
        'tasksByCategory': tasksByCategory,
        'completionRate': completedTasksCount > 0 ? 100.0 : 0.0,
        'profileData': profileData,
      };

      print('Generated daily summary for user $userId ($userName): ${completedTasksCount} tasks, ${pointsEarned} points, RM${totalEarnings.toStringAsFixed(2)}');
      return summaryData;

    } catch (e) {
      print('Error generating daily summary for user $userId: $e');
      return {
        'date': date.toIso8601String(),
        'userId': userId,
        'userName': 'User',
        'userTotalPoints': 0,
        'userTotalEarnings': 0.0,
        'totalTasks': 0,
        'completedTasks': 0,
        'inProgressTasks': 0,
        'pendingTasks': 0,
        'pointsEarned': 0,
        'totalEarnings': 0.0,
        'translationsCount': 0,
        'totalCharacters': 0,
        'taskDetails': <Map<String, dynamic>>[],
        'pointTransactions': <Map<String, dynamic>>[],
        'moneyTransactions': <Map<String, dynamic>>[],
        'translationDetails': <Map<String, dynamic>>[],
        'tasksByCategory': <String, int>{},
        'completionRate': 0.0,
        'profileData': null,
      };
    }
  }

  // Generate weekly summary data for a specific user using correct data sources
  static Future<Map<String, dynamic>> generateWeeklySummaryForUser({
    required String userId,
    required DateTime weekStart,
  }) async {
    try {
      print('Generating weekly summary for user: $userId starting $weekStart');

      final weekEnd = weekStart.add(const Duration(days: 7));

      // Fetch user data for the week in parallel from BOTH collections
      final results = await Future.wait([
        fetchUserPointsHistory(userId: userId, startDate: weekStart, endDate: weekEnd),
        fetchUserMoneyHistory(userId: userId, startDate: weekStart, endDate: weekEnd),
        fetchUserProfileDetails(userId: userId),
      ]);

      final pointsData = results[0] as List<Map<String, dynamic>>;
      final moneyData = results[1] as List<Map<String, dynamic>>;
      final profileData = results[2] as Map<String, dynamic>?;

      // Process weekly totals
      int totalTasks = 0;
      int completedTasks = 0;
      int totalPoints = 0;
      double totalEarnings = 0.0;
      Map<String, int> tasksByCategory = {};

      // Process points data
      for (var pointRecord in pointsData) {
        final points = pointRecord['points'] as int;
        final taskTitle = pointRecord['taskTitle'] as String;
        final category = pointRecord['category'] as String;

        totalPoints += points;

        if (points > 0) {
          final taskCategory = category.isNotEmpty ? category : _categorizeTask(taskTitle);
          tasksByCategory[taskCategory] = (tasksByCategory[taskCategory] ?? 0) + 1;
        }
      }

      // Process money data (FIXED: Use actual money data)
      for (var moneyRecord in moneyData) {
        final amount = moneyRecord['amount'] as double;
        totalEarnings += amount;

        if (amount > 0) {
          totalTasks++;
          completedTasks++;
        }
      }

      double completionRate = totalTasks > 0 ? (completedTasks / totalTasks) * 100 : 0;

      // Calculate daily breakdown
      List<Map<String, dynamic>> dailyBreakdown = [];
      for (int i = 0; i < 7; i++) {
        final currentDay = weekStart.add(Duration(days: i));
        final dayStart = DateTime(currentDay.year, currentDay.month, currentDay.day);
        final dayEnd = dayStart.add(const Duration(days: 1));

        // Get points for this day
        final dayPointsRecords = pointsData.where((record) {
          final timestamp = record['timestamp'] as Timestamp?;
          if (timestamp == null) return false;
          final date = timestamp.toDate();
          return date.isAfter(dayStart.subtract(const Duration(seconds: 1))) &&
              date.isBefore(dayEnd);
        }).toList();

        // Get money for this day
        final dayMoneyRecords = moneyData.where((record) {
          final timestamp = record['timestamp'] as Timestamp?;
          if (timestamp == null) return false;
          final date = timestamp.toDate();
          return date.isAfter(dayStart.subtract(const Duration(seconds: 1))) &&
              date.isBefore(dayEnd);
        }).toList();

        int dayTasks = 0;
        int dayPoints = 0;
        double dayEarnings = 0.0;

        // Count points
        for (var record in dayPointsRecords) {
          final points = record['points'] as int;
          dayPoints += points;
        }

        // Count money and tasks
        for (var record in dayMoneyRecords) {
          final amount = record['amount'] as double;
          if (amount > 0) {
            dayTasks++;
          }
          dayEarnings += amount;
        }

        dailyBreakdown.add({
          'date': currentDay,
          'dayName': _getDayName(currentDay.weekday),
          'totalTasks': dayTasks,
          'completedTasks': dayTasks,
          'points': dayPoints,
          'earnings': dayEarnings,
          'translations': 0,
          'completionRate': dayTasks > 0 ? 100.0 : 0.0,
        });
      }

      // Calculate averages
      double averageDailyCompletion = dailyBreakdown.isNotEmpty
          ? dailyBreakdown.map((day) => day['completionRate'] as double).reduce((a, b) => a + b) / 7
          : 0.0;

      double averageDailyEarnings = dailyBreakdown.isNotEmpty
          ? dailyBreakdown.map((day) => day['earnings'] as double).reduce((a, b) => a + b) / 7
          : 0.0;

      int mostProductiveDayIndex = -1;
      if (dailyBreakdown.isNotEmpty) {
        double maxRate = dailyBreakdown.map((d) => d['completionRate'] as double).reduce((a, b) => a > b ? a : b);
        mostProductiveDayIndex = dailyBreakdown.indexWhere((day) => day['completionRate'] == maxRate);
      }

      // Get user info from profile (removed level references)
      final userName = profileData?['name'] ?? 'User';

      final summaryData = {
        'weekStart': weekStart.toIso8601String(),
        'weekEnd': weekEnd.toIso8601String(),
        'userId': userId,
        'userName': userName,
        'totalTasks': totalTasks,
        'completedTasks': completedTasks,
        'inProgressTasks': 0,
        'pendingTasks': 0,
        'overdueTasks': 0,
        'totalPoints': totalPoints,
        'totalEarnings': totalEarnings, // FIXED: Now using actual money data
        'translationsCount': 0,
        'completionRate': completionRate,
        'tasksByCategory': tasksByCategory,
        'averageDailyCompletion': averageDailyCompletion,
        'averageDailyEarnings': averageDailyEarnings,
        'mostProductiveDay': mostProductiveDayIndex >= 0 ? dailyBreakdown[mostProductiveDayIndex]['dayName'] : 'N/A',
        'dailyBreakdown': dailyBreakdown,
        'profileData': profileData,
      };

      print('Generated weekly summary for user $userId ($userName): ${totalTasks} tasks, ${totalPoints} points, RM${totalEarnings.toStringAsFixed(2)}');
      return summaryData;

    } catch (e) {
      print('Error generating weekly summary for user $userId: $e');
      return {
        'weekStart': weekStart.toIso8601String(),
        'weekEnd': weekStart.add(const Duration(days: 7)).toIso8601String(),
        'userId': userId,
        'userName': 'User',
        'totalTasks': 0,
        'completedTasks': 0,
        'inProgressTasks': 0,
        'pendingTasks': 0,
        'overdueTasks': 0,
        'totalPoints': 0,
        'totalEarnings': 0.0,
        'translationsCount': 0,
        'completionRate': 0.0,
        'tasksByCategory': <String, int>{},
        'averageDailyCompletion': 0.0,
        'averageDailyEarnings': 0.0,
        'mostProductiveDay': 'N/A',
        'dailyBreakdown': <Map<String, dynamic>>[],
        'profileData': null,
      };
    }
  }

  // Helper method to categorize tasks
  static String _categorizeTask(String taskTitle) {
    taskTitle = taskTitle.toLowerCase();
    if (taskTitle.contains('translation') || taskTitle.contains('translate')) {
      return 'Translation';
    } else if (taskTitle.contains('coding') || taskTitle.contains('programming') ||
        taskTitle.contains('development')) {
      return 'Development';
    } else if (taskTitle.contains('design') || taskTitle.contains('creative')) {
      return 'Design';
    } else if (taskTitle.contains('research') || taskTitle.contains('analysis')) {
      return 'Research';
    } else if (taskTitle.contains('writing') || taskTitle.contains('content')) {
      return 'Writing';
    }
    return 'General';
  }

  // Helper method to get day name
  static String _getDayName(int weekday) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[(weekday - 1) % 7];
  }

  // Get current authenticated user ID
  static String? getCurrentUserId() {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  // Check if user has any data
  static Future<bool> userHasData(String userId) async {
    try {
      // Check if user has any records in pointsHistory or moneyHistory
      final pointsCheck = await _firestore
          .collection('users')
          .doc(userId)
          .collection('pointsHistory')
          .limit(1)
          .get();

      final moneyCheck = await _firestore
          .collection('users')
          .doc(userId)
          .collection('moneyHistory')
          .limit(1)
          .get();

      // Check if user has profile details
      final profileCheck = await _firestore
          .collection('users')
          .doc(userId)
          .collection('profiledetails')
          .doc('profile')
          .get();

      return pointsCheck.docs.isNotEmpty || moneyCheck.docs.isNotEmpty || profileCheck.exists;
    } catch (e) {
      print('Error checking if user has data: $e');
      return false;
    }
  }

  // Get user profile data
  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      return await fetchUserProfileDetails(userId: userId);
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  // Update user profile data (removed level references)
  static Future<void> updateUserProfile(String userId, Map<String, dynamic> updates) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('profiledetails')
          .doc('profile')
          .set(updates, SetOptions(merge: true));

      print('Updated profile for user $userId');
    } catch (e) {
      print('Error updating user profile: $e');
      throw e;
    }
  }

  // Add points transaction
  static Future<void> addPointsTransaction({
    required String userId,
    required int points,
    required String description,
    required String taskTitle,
    String? taskId,
    String source = 'task_completion',
    String type = 'earning',
    String category = 'General',
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('pointsHistory')
          .add({
        'points': points,
        'description': description,
        'taskTitle': taskTitle,
        'taskId': taskId,
        'source': source,
        'type': type,
        'category': category,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update user profile totals
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('profiledetails')
          .doc('profile')
          .set({
        'totalPoints': FieldValue.increment(points),
        'completedTasks': FieldValue.increment(1),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('Added points transaction for user $userId: $points points');
    } catch (e) {
      print('Error adding points transaction: $e');
      throw e;
    }
  }

  // NEW: Add money transaction
  static Future<void> addMoneyTransaction({
    required String userId,
    required double amount,
    required String description,
    required String taskTitle,
    String? taskId,
    String source = 'task_completion',
    String type = 'earning',
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('moneyHistory')
          .add({
        'amount': amount,
        'description': description,
        'taskTitle': taskTitle,
        'taskId': taskId,
        'source': source,
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update user profile totals
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('profiledetails')
          .doc('profile')
          .set({
        'totalEarnings': FieldValue.increment(amount),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('Added money transaction for user $userId: RM$amount');
    } catch (e) {
      print('Error adding money transaction: $e');
      throw e;
    }
  }
}