// UserDataService.dart - Service to fetch user-specific data safely
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

  // Fetch user-specific money history for a date range
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
            'description': _safeToString(data['description']),
            'taskTitle': _safeToString(data['taskTitle'] ?? data['description'] ?? 'Task Completed'),
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
            'taskTitle': _safeToString(data['taskTitle']),
            'taskId': _safeToString(data['taskId']),
            'source': _safeToString(data['source'] ?? 'task_completion'),
            'timestamp': data['timestamp'] as Timestamp?,
          };

          // Only add if we have valid timestamp
          if (processedData['timestamp'] != null) {
            pointsData.add(processedData);
            print('Added points record: ${processedData['description']} - ${processedData['points']} points');
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

  // Fetch user-specific translations for a date range
  static Future<List<Map<String, dynamic>>> fetchUserTranslations({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      print('Fetching translations for user: $userId from $startDate to $endDate');

      // Note: translations collection is at root level, filter by userId
      final snapshot = await _firestore
          .collection('translations')
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThan: Timestamp.fromDate(endDate))
          .get();

      List<Map<String, dynamic>> translationsData = [];

      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();

          // Safely extract and validate data
          final processedData = {
            'id': doc.id,
            'originalText': _safeToString(data['originalText']),
            'translatedText': _safeToString(data['translatedText']),
            'fromLanguage': _safeToString(data['fromLanguage'] ?? 'Unknown'),
            'toLanguage': _safeToString(data['toLanguage'] ?? 'Unknown'),
            'characters': _safeToString(data['originalText']).length,
            'timestamp': data['timestamp'] as Timestamp?,
            'userId': _safeToString(data['userId']),
          };

          // Only add if we have valid timestamp
          if (processedData['timestamp'] != null) {
            translationsData.add(processedData);
            print('Added translation: ${processedData['fromLanguage']} → ${processedData['toLanguage']}');
          }

        } catch (e) {
          print('Error processing translation document ${doc.id}: $e');
          // Continue processing other documents
        }
      }

      print('Fetched ${translationsData.length} translation records for user $userId');
      return translationsData;

    } catch (e) {
      print('Error fetching user translations: $e');
      return [];
    }
  }

  // Generate daily summary data for a specific user
  static Future<Map<String, dynamic>> generateDailySummaryForUser({
    required String userId,
    required DateTime date,
  }) async {
    try {
      print('Generating daily summary for user: $userId on $date');

      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      // Fetch all user data for the day in parallel
      final results = await Future.wait([
        fetchUserMoneyHistory(userId: userId, startDate: dayStart, endDate: dayEnd),
        fetchUserPointsHistory(userId: userId, startDate: dayStart, endDate: dayEnd),
        fetchUserTranslations(userId: userId, startDate: dayStart, endDate: dayEnd),
      ]);

      final moneyData = results[0] as List<Map<String, dynamic>>;
      final pointsData = results[1] as List<Map<String, dynamic>>;
      final translationsData = results[2] as List<Map<String, dynamic>>;

      // Process money data (tasks)
      double totalEarnings = 0.0;
      int completedTasks = moneyData.length;
      Map<String, int> tasksByCategory = {};
      List<Map<String, dynamic>> taskDetails = [];

      for (var moneyRecord in moneyData) {
        final amount = moneyRecord['amount'] as double;
        final taskTitle = moneyRecord['taskTitle'] as String;
        final timestamp = moneyRecord['timestamp'] as Timestamp?;

        totalEarnings += amount;

        final category = _categorizeTask(taskTitle);
        tasksByCategory[category] = (tasksByCategory[category] ?? 0) + 1;

        taskDetails.add({
          'title': taskTitle,
          'status': 'Completed',
          'progress': 100.0,
          'earnings': amount,
          'time': timestamp?.toDate() ?? DateTime.now(),
          'category': category,
          'source': moneyRecord['source'],
        });
      }

      // Process points data
      int pointsEarned = 0;
      List<Map<String, dynamic>> pointTransactions = [];

      for (var pointRecord in pointsData) {
        final points = pointRecord['points'] as int;
        final description = pointRecord['description'] as String;
        final timestamp = pointRecord['timestamp'] as Timestamp?;

        pointsEarned += points;
        pointTransactions.add({
          'points': points,
          'description': description,
          'timestamp': timestamp?.toDate() ?? DateTime.now(),
        });
      }

      // Process translations data
      int translationsCount = translationsData.length;
      int totalCharacters = 0;
      List<Map<String, dynamic>> translationDetails = [];

      for (var translationRecord in translationsData) {
        final characters = translationRecord['characters'] as int;
        totalCharacters += characters;

        translationDetails.add({
          'originalText': translationRecord['originalText'],
          'translatedText': translationRecord['translatedText'],
          'fromLanguage': translationRecord['fromLanguage'],
          'toLanguage': translationRecord['toLanguage'],
          'characters': characters,
          'timestamp': (translationRecord['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        });
      }

      final summaryData = {
        'date': date.toIso8601String(),
        'userId': userId,
        'totalTasks': completedTasks,
        'completedTasks': completedTasks,
        'inProgressTasks': 0, // All tasks in money history are completed
        'pendingTasks': 0,
        'pointsEarned': pointsEarned,
        'totalEarnings': totalEarnings,
        'translationsCount': translationsCount,
        'totalCharacters': totalCharacters,
        'taskDetails': taskDetails,
        'pointTransactions': pointTransactions,
        'translationDetails': translationDetails,
        'tasksByCategory': tasksByCategory,
        'completionRate': completedTasks > 0 ? 100.0 : 0.0, // All tracked tasks are completed
      };

      print('Generated daily summary for user $userId: ${completedTasks} tasks, ${pointsEarned} points, RM${totalEarnings.toStringAsFixed(2)}');
      return summaryData;

    } catch (e) {
      print('Error generating daily summary for user $userId: $e');
      return {
        'date': date.toIso8601String(),
        'userId': userId,
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
        'translationDetails': <Map<String, dynamic>>[],
        'tasksByCategory': <String, int>{},
        'completionRate': 0.0,
      };
    }
  }

  // Generate weekly summary data for a specific user
  static Future<Map<String, dynamic>> generateWeeklySummaryForUser({
    required String userId,
    required DateTime weekStart,
  }) async {
    try {
      print('Generating weekly summary for user: $userId starting $weekStart');

      final weekEnd = weekStart.add(const Duration(days: 7));

      // Fetch all user data for the week in parallel
      final results = await Future.wait([
        fetchUserMoneyHistory(userId: userId, startDate: weekStart, endDate: weekEnd),
        fetchUserPointsHistory(userId: userId, startDate: weekStart, endDate: weekEnd),
        fetchUserTranslations(userId: userId, startDate: weekStart, endDate: weekEnd),
      ]);

      final moneyData = results[0] as List<Map<String, dynamic>>;
      final pointsData = results[1] as List<Map<String, dynamic>>;
      final translationsData = results[2] as List<Map<String, dynamic>>;

      // Process weekly totals
      int totalTasks = moneyData.length;
      int completedTasks = totalTasks; // All tasks in money history are completed
      double totalEarnings = 0.0;
      Map<String, int> tasksByCategory = {};

      for (var moneyRecord in moneyData) {
        final amount = moneyRecord['amount'] as double;
        final taskTitle = moneyRecord['taskTitle'] as String;

        totalEarnings += amount;

        final category = _categorizeTask(taskTitle);
        tasksByCategory[category] = (tasksByCategory[category] ?? 0) + 1;
      }

      // Process points
      int totalPoints = 0;
      for (var pointRecord in pointsData) {
        final points = pointRecord['points'] as int;
        totalPoints += points;
      }

      // Calculate daily breakdown
      List<Map<String, dynamic>> dailyBreakdown = [];
      for (int i = 0; i < 7; i++) {
        final currentDay = weekStart.add(Duration(days: i));
        final dayStart = DateTime(currentDay.year, currentDay.month, currentDay.day);
        final dayEnd = dayStart.add(const Duration(days: 1));

        final dayTasks = moneyData.where((record) {
          final timestamp = record['timestamp'] as Timestamp?;
          if (timestamp == null) return false;
          final date = timestamp.toDate();
          return date.isAfter(dayStart.subtract(const Duration(seconds: 1))) &&
              date.isBefore(dayEnd);
        }).toList();

        final dayPoints = pointsData.where((record) {
          final timestamp = record['timestamp'] as Timestamp?;
          if (timestamp == null) return false;
          final date = timestamp.toDate();
          return date.isAfter(dayStart.subtract(const Duration(seconds: 1))) &&
              date.isBefore(dayEnd);
        }).fold(0, (sum, record) => sum + (record['points'] as int));

        final dayEarnings = dayTasks.fold(0.0, (sum, record) => sum + (record['amount'] as double));

        final dayTranslations = translationsData.where((record) {
          final timestamp = record['timestamp'] as Timestamp?;
          if (timestamp == null) return false;
          final date = timestamp.toDate();
          return date.isAfter(dayStart.subtract(const Duration(seconds: 1))) &&
              date.isBefore(dayEnd);
        }).length;

        dailyBreakdown.add({
          'date': currentDay,
          'dayName': _getDayName(currentDay.weekday),
          'totalTasks': dayTasks.length,
          'completedTasks': dayTasks.length,
          'points': dayPoints,
          'earnings': dayEarnings,
          'translations': dayTranslations,
          'completionRate': dayTasks.isNotEmpty ? 100.0 : 0.0,
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

      final summaryData = {
        'weekStart': weekStart.toIso8601String(),
        'weekEnd': weekEnd.toIso8601String(),
        'userId': userId,
        'totalTasks': totalTasks,
        'completedTasks': completedTasks,
        'inProgressTasks': 0,
        'pendingTasks': 0,
        'overdueTasks': 0,
        'totalPoints': totalPoints,
        'totalEarnings': totalEarnings,
        'translationsCount': translationsData.length,
        'completionRate': totalTasks > 0 ? (completedTasks / totalTasks) * 100 : 0.0,
        'tasksByCategory': tasksByCategory,
        'averageDailyCompletion': averageDailyCompletion,
        'averageDailyEarnings': averageDailyEarnings,
        'mostProductiveDay': mostProductiveDayIndex >= 0 ? dailyBreakdown[mostProductiveDayIndex]['dayName'] : 'N/A',
        'dailyBreakdown': dailyBreakdown,
      };

      print('Generated weekly summary for user $userId: ${totalTasks} tasks, ${totalPoints} points, RM${totalEarnings.toStringAsFixed(2)}');
      return summaryData;

    } catch (e) {
      print('Error generating weekly summary for user $userId: $e');
      return {
        'weekStart': weekStart.toIso8601String(),
        'weekEnd': weekStart.add(const Duration(days: 7)).toIso8601String(),
        'userId': userId,
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
      // Check if user has any records in any collection
      final moneyCheck = await _firestore
          .collection('users')
          .doc(userId)
          .collection('moneyHistory')
          .limit(1)
          .get();

      final pointsCheck = await _firestore
          .collection('users')
          .doc(userId)
          .collection('pointsHistory')
          .limit(1)
          .get();

      final translationsCheck = await _firestore
          .collection('translations')
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      return moneyCheck.docs.isNotEmpty ||
          pointsCheck.docs.isNotEmpty ||
          translationsCheck.docs.isNotEmpty;
    } catch (e) {
      print('Error checking if user has data: $e');
      return false;
    }
  }

  // Get user profile data
  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }
}