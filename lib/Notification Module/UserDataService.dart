// Fixed UserDataService.dart - Corrected task counting logic
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

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

      if (userId.isEmpty) {
        print('Error: Empty userId provided');
        return [];
      }

      if (endDate.isBefore(startDate)) {
        print('Error: End date is before start date');
        return [];
      }

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

          if (data.isEmpty) {
            print('Warning: Empty document found: ${doc.id}');
            continue;
          }

          final processedData = {
            'id': doc.id,
            'points': _safeToInt(data['points']),
            'description': _safeToString(data['description']).isNotEmpty
                ? _safeToString(data['description'])
                : 'Points earned',
            'taskTitle': _safeToString(data['taskTitle']).isNotEmpty
                ? _safeToString(data['taskTitle'])
                : (_safeToString(data['description']).isNotEmpty
                ? _safeToString(data['description'])
                : 'Task Completed'),
            'taskId': _safeToString(data['taskId']),
            'source': _safeToString(data['source']).isNotEmpty
                ? _safeToString(data['source'])
                : 'task_completion',
            'type': _safeToString(data['type']).isNotEmpty
                ? _safeToString(data['type'])
                : 'earning',
            'category': _safeToString(data['category']).isNotEmpty
                ? _safeToString(data['category'])
                : 'General',
            'timestamp': data['timestamp'] as Timestamp?,
          };

          if (processedData['timestamp'] != null) {
            final timestamp = (processedData['timestamp'] as Timestamp).toDate();
            if (timestamp.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
                timestamp.isBefore(endDate)) {
              pointsData.add(processedData);
              print('Added points record: ${processedData['taskTitle']} - ${processedData['points']} points at $timestamp');
            } else {
              print('Skipped points record outside date range: ${processedData['taskTitle']} at $timestamp');
            }
          } else {
            print('Warning: Skipped points record with null timestamp: ${doc.id}');
          }

        } catch (e) {
          print('Error processing points history document ${doc.id}: $e');
        }
      }

      print('Successfully fetched ${pointsData.length} points history records for user $userId');
      return pointsData;

    } catch (e) {
      print('Error fetching user points history: $e');
      return [];
    }
  }

  // Fetch user-specific money history for a date range
  static Future<List<Map<String, dynamic>>> fetchUserMoneyHistory({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      print('Fetching money history for user: $userId from $startDate to $endDate');

      if (userId.isEmpty) {
        print('Error: Empty userId provided');
        return [];
      }

      if (endDate.isBefore(startDate)) {
        print('Error: End date is before start date');
        return [];
      }

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

          if (data.isEmpty) {
            print('Warning: Empty document found: ${doc.id}');
            continue;
          }

          final processedData = {
            'id': doc.id,
            'amount': _safeToDouble(data['amount']),
            'description': _safeToString(data['description']).isNotEmpty
                ? _safeToString(data['description'])
                : 'Money transaction',
            'taskTitle': _safeToString(data['taskTitle']).isNotEmpty
                ? _safeToString(data['taskTitle'])
                : (_safeToString(data['description']).isNotEmpty
                ? _safeToString(data['description'])
                : 'Transaction'),
            'taskId': _safeToString(data['taskId']),
            'source': _safeToString(data['source']).isNotEmpty
                ? _safeToString(data['source'])
                : 'task_completion',
            'type': _safeToString(data['type']).isNotEmpty
                ? _safeToString(data['type'])
                : 'earning',
            'timestamp': data['timestamp'] as Timestamp?,
          };

          if (processedData['timestamp'] != null) {
            final timestamp = (processedData['timestamp'] as Timestamp).toDate();
            if (timestamp.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
                timestamp.isBefore(endDate)) {
              moneyData.add(processedData);
              print('Added money record: ${processedData['taskTitle']} - RM${processedData['amount']} at $timestamp');
            } else {
              print('Skipped money record outside date range: ${processedData['taskTitle']} at $timestamp');
            }
          } else {
            print('Warning: Skipped money record with null timestamp: ${doc.id}');
          }

        } catch (e) {
          print('Error processing money history document ${doc.id}: $e');
        }
      }

      print('Successfully fetched ${moneyData.length} money history records for user $userId');
      return moneyData;

    } catch (e) {
      print('Error fetching user money history: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> getUserDataSummary(String userId) async {
    try {
      print('Getting data summary for user: $userId');

      final pointsCount = await _firestore
          .collection('users')
          .doc(userId)
          .collection('pointsHistory')
          .count()
          .get();

      final moneyCount = await _firestore
          .collection('users')
          .doc(userId)
          .collection('moneyHistory')
          .count()
          .get();

      final profileExists = await _firestore
          .collection('users')
          .doc(userId)
          .collection('profiledetails')
          .doc('profile')
          .get();

      DateTime? earliestPointsDate;
      DateTime? latestPointsDate;
      DateTime? earliestMoneyDate;
      DateTime? latestMoneyDate;

      if (pointsCount.count! > 0) {
        final earliestPoints = await _firestore
            .collection('users')
            .doc(userId)
            .collection('pointsHistory')
            .orderBy('timestamp', descending: false)
            .limit(1)
            .get();

        final latestPoints = await _firestore
            .collection('users')
            .doc(userId)
            .collection('pointsHistory')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();

        if (earliestPoints.docs.isNotEmpty) {
          earliestPointsDate = (earliestPoints.docs.first.data()['timestamp'] as Timestamp?)?.toDate();
        }
        if (latestPoints.docs.isNotEmpty) {
          latestPointsDate = (latestPoints.docs.first.data()['timestamp'] as Timestamp?)?.toDate();
        }
      }

      if (moneyCount.count! > 0) {
        final earliestMoney = await _firestore
            .collection('users')
            .doc(userId)
            .collection('moneyHistory')
            .orderBy('timestamp', descending: false)
            .limit(1)
            .get();

        final latestMoney = await _firestore
            .collection('users')
            .doc(userId)
            .collection('moneyHistory')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();

        if (earliestMoney.docs.isNotEmpty) {
          earliestMoneyDate = (earliestMoney.docs.first.data()['timestamp'] as Timestamp?)?.toDate();
        }
        if (latestMoney.docs.isNotEmpty) {
          latestMoneyDate = (latestMoney.docs.first.data()['timestamp'] as Timestamp?)?.toDate();
        }
      }

      return {
        'userId': userId,
        'pointsHistoryCount': pointsCount.count ?? 0,
        'moneyHistoryCount': moneyCount.count ?? 0,
        'hasProfile': profileExists.exists,
        'earliestPointsDate': earliestPointsDate,
        'latestPointsDate': latestPointsDate,
        'earliestMoneyDate': earliestMoneyDate,
        'latestMoneyDate': latestMoneyDate,
        'totalRecords': (pointsCount.count ?? 0) + (moneyCount.count ?? 0),
        'dataAvailable': (pointsCount.count ?? 0) > 0 || (moneyCount.count ?? 0) > 0 || profileExists.exists,
      };

    } catch (e) {
      print('Error getting user data summary: $e');
      return {
        'userId': userId,
        'pointsHistoryCount': 0,
        'moneyHistoryCount': 0,
        'hasProfile': false,
        'earliestPointsDate': null,
        'latestPointsDate': null,
        'earliestMoneyDate': null,
        'latestMoneyDate': null,
        'totalRecords': 0,
        'dataAvailable': false,
        'error': e.toString(),
      };
    }
  }

  // Fetch user profile details
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

  // FIXED: Generate daily summary with correct task counting
  static Future<Map<String, dynamic>> generateDailySummaryForUser({
    required String userId,
    required DateTime date,
  }) async {
    try {
      print('Generating daily summary for user: $userId on $date');

      if (userId.isEmpty) {
        throw ArgumentError('User ID cannot be empty');
      }

      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      print('Date range: $dayStart to $dayEnd');

      final hasData = await userHasData(userId);
      if (!hasData) {
        print('User $userId has no data available');
        return _getEmptyDailySummary(userId, date, 'No user data found');
      }

      final results = await Future.wait([
        fetchUserPointsHistory(userId: userId, startDate: dayStart, endDate: dayEnd),
        fetchUserMoneyHistory(userId: userId, startDate: dayStart, endDate: dayEnd),
        fetchUserProfileDetails(userId: userId),
      ]).timeout(const Duration(seconds: 30), onTimeout: () {
        print('Timeout while fetching user data for $userId');
        throw TimeoutException('Data fetch timeout', const Duration(seconds: 30));
      });

      final pointsData = results[0] as List<Map<String, dynamic>>;
      final moneyData = results[1] as List<Map<String, dynamic>>;
      final profileData = results[2] as Map<String, dynamic>?;

      print('Fetched data: ${pointsData.length} points records, ${moneyData.length} money records');

      // FIXED: Create a unified task tracking system
      // Use taskId to avoid double counting the same task
      Set<String> uniqueTaskIds = {};
      Map<String, Map<String, dynamic>> tasksByTaskId = {};

      // Process points data and track unique tasks
      int pointsEarned = 0;
      Map<String, int> tasksByCategory = {};
      List<Map<String, dynamic>> pointTransactions = [];

      for (var pointRecord in pointsData) {
        try {
          final points = pointRecord['points'] as int;
          final taskTitle = pointRecord['taskTitle'] as String;
          final taskId = pointRecord['taskId'] as String;
          final category = pointRecord['category'] as String;
          final timestamp = pointRecord['timestamp'] as Timestamp?;
          final description = pointRecord['description'] as String;

          pointsEarned += points;

          // Track unique tasks by taskId (or taskTitle if no taskId)
          final uniqueId = taskId.isNotEmpty ? taskId : taskTitle;
          if (uniqueId.isNotEmpty) {
            uniqueTaskIds.add(uniqueId);

            // Store task info for later use
            tasksByTaskId[uniqueId] = {
              'taskId': taskId,
              'taskTitle': taskTitle,
              'points': points,
              'category': category.isNotEmpty ? category : _categorizeTask(taskTitle),
              'timestamp': timestamp?.toDate() ?? DateTime.now(),
              'status': points > 0 ? 'Completed' : 'Deducted',
              'progress': points > 0 ? 100.0 : 0.0,
              'source': pointRecord['source'],
              'type': pointRecord['type'],
            };
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
        } catch (e) {
          print('Error processing point record: $e');
        }
      }

      // Process money data and enhance task info
      double totalEarnings = 0.0;
      List<Map<String, dynamic>> moneyTransactions = [];

      for (var moneyRecord in moneyData) {
        try {
          final amount = moneyRecord['amount'] as double;
          final taskTitle = moneyRecord['taskTitle'] as String;
          final taskId = moneyRecord['taskId'] as String;
          final timestamp = moneyRecord['timestamp'] as Timestamp?;
          final description = moneyRecord['description'] as String;

          totalEarnings += amount;

          // Add earnings info to existing task if it exists
          final uniqueId = taskId.isNotEmpty ? taskId : taskTitle;
          if (uniqueId.isNotEmpty && tasksByTaskId.containsKey(uniqueId)) {
            tasksByTaskId[uniqueId]!['earnings'] = amount;
          } else if (uniqueId.isNotEmpty) {
            // This is a money-only transaction (no corresponding points)
            uniqueTaskIds.add(uniqueId);
            tasksByTaskId[uniqueId] = {
              'taskId': taskId,
              'taskTitle': taskTitle,
              'points': 0,
              'earnings': amount,
              'category': _categorizeTask(taskTitle),
              'timestamp': timestamp?.toDate() ?? DateTime.now(),
              'status': amount > 0 ? 'Completed' : 'Deducted',
              'progress': amount > 0 ? 100.0 : 0.0,
              'source': moneyRecord['source'],
              'type': moneyRecord['type'],
            };
          }

          moneyTransactions.add({
            'id': moneyRecord['id'],
            'amount': amount,
            'description': description,
            'taskTitle': taskTitle,
            'timestamp': timestamp?.toDate() ?? DateTime.now(),
            'source': moneyRecord['source'],
          });
        } catch (e) {
          print('Error processing money record: $e');
        }
      }

      // FIXED: Create task details and categories from unique tasks
      List<Map<String, dynamic>> taskDetails = [];

      for (var entry in tasksByTaskId.entries) {
        final taskInfo = entry.value;
        final category = taskInfo['category'] as String;

        // Count task by category
        tasksByCategory[category] = (tasksByCategory[category] ?? 0) + 1;

        // Add to task details
        taskDetails.add({
          'id': entry.key,
          'title': taskInfo['taskTitle'],
          'status': taskInfo['status'],
          'progress': taskInfo['progress'],
          'points': taskInfo['points'],
          'earnings': taskInfo['earnings'] ?? 0.0,
          'time': taskInfo['timestamp'],
          'category': category,
          'source': taskInfo['source'],
          'type': taskInfo['type'],
        });
      }

      // FIXED: Calculate correct counts
      final totalTasks = uniqueTaskIds.length; // This is the correct count!
      final completedTasks = taskDetails.where((task) => task['status'] == 'Completed').length;

      // Get user info from profile
      final userName = profileData?['name'] ?? 'User';
      final userTotalPoints = profileData?['totalPoints'] ?? 0;
      final userTotalEarnings = profileData?['totalEarnings'] ?? 0.0;

      // Calculate completion rate
      double completionRate = totalTasks > 0 ? (completedTasks / totalTasks) * 100 : 0.0;

      final summaryData = {
        'date': date.toIso8601String(),
        'userId': userId,
        'userName': userName,
        'userTotalPoints': userTotalPoints,
        'userTotalEarnings': userTotalEarnings,
        'totalTasks': totalTasks, // FIXED: Now shows correct count
        'completedTasks': completedTasks,
        'inProgressTasks': 0,
        'pendingTasks': 0,
        'pointsEarned': pointsEarned,
        'totalEarnings': totalEarnings,
        'translationsCount': 0,
        'totalCharacters': 0,
        'taskDetails': taskDetails,
        'pointTransactions': pointTransactions,
        'moneyTransactions': moneyTransactions,
        'translationDetails': <Map<String, dynamic>>[],
        'tasksByCategory': tasksByCategory,
        'completionRate': completionRate,
        'profileData': profileData,
        'dataFetched': DateTime.now().toIso8601String(),
        'dataQuality': {
          'pointsRecords': pointsData.length,
          'moneyRecords': moneyData.length,
          'uniqueTasks': totalTasks, // ADDED: Show unique task count
          'hasProfile': profileData != null,
          'dateRange': '${dayStart.toIso8601String()} - ${dayEnd.toIso8601String()}',
        },
      };

      print('Generated daily summary for user $userId ($userName):');
      print('  - Unique Tasks: $totalTasks (FIXED)'); // Updated log
      print('  - Points Records: ${pointsData.length}');
      print('  - Money Records: ${moneyData.length}');
      print('  - Points: $pointsEarned');
      print('  - Earnings: RM${totalEarnings.toStringAsFixed(2)}');
      print('  - Completion: ${completionRate.toStringAsFixed(1)}%');

      return summaryData;

    } catch (e) {
      print('Error generating daily summary for user $userId: $e');
      return _getEmptyDailySummary(userId, date, e.toString());
    }
  }

  static Map<String, dynamic> _getEmptyDailySummary(String userId, DateTime date, String reason) {
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
      'dataFetched': DateTime.now().toIso8601String(),
      'error': reason,
      'dataQuality': {
        'pointsRecords': 0,
        'moneyRecords': 0,
        'uniqueTasks': 0,
        'hasProfile': false,
        'dateRange': '${date.toIso8601String()} - ${date.add(const Duration(days: 1)).toIso8601String()}',
      },
    };
  }

  // FIXED: Generate weekly summary with correct task counting
  static Future<Map<String, dynamic>> generateWeeklySummaryForUser({
    required String userId,
    required DateTime weekStart,
  }) async {
    try {
      print('Generating weekly summary for user: $userId starting $weekStart');

      final weekEnd = weekStart.add(const Duration(days: 7));

      final results = await Future.wait([
        fetchUserPointsHistory(userId: userId, startDate: weekStart, endDate: weekEnd),
        fetchUserMoneyHistory(userId: userId, startDate: weekStart, endDate: weekEnd),
        fetchUserProfileDetails(userId: userId),
      ]);

      final pointsData = results[0] as List<Map<String, dynamic>>;
      final moneyData = results[1] as List<Map<String, dynamic>>;
      final profileData = results[2] as Map<String, dynamic>?;

      // FIXED: Use same unified task tracking for weekly summary
      Set<String> uniqueTaskIds = {};
      Map<String, Map<String, dynamic>> tasksByTaskId = {};

      int totalPoints = 0;
      double totalEarnings = 0.0;
      Map<String, int> tasksByCategory = {};

      // Process points data
      for (var pointRecord in pointsData) {
        final points = pointRecord['points'] as int;
        final taskTitle = pointRecord['taskTitle'] as String;
        final taskId = pointRecord['taskId'] as String;
        final category = pointRecord['category'] as String;
        final timestamp = pointRecord['timestamp'] as Timestamp?;

        totalPoints += points;

        final uniqueId = taskId.isNotEmpty ? taskId : taskTitle;
        if (uniqueId.isNotEmpty && points > 0) {
          uniqueTaskIds.add(uniqueId);

          tasksByTaskId[uniqueId] = {
            'taskId': taskId,
            'taskTitle': taskTitle,
            'points': points,
            'category': category.isNotEmpty ? category : _categorizeTask(taskTitle),
            'timestamp': timestamp?.toDate() ?? DateTime.now(),
          };
        }
      }

      // Process money data
      for (var moneyRecord in moneyData) {
        final amount = moneyRecord['amount'] as double;
        final taskTitle = moneyRecord['taskTitle'] as String;
        final taskId = moneyRecord['taskId'] as String;
        final timestamp = moneyRecord['timestamp'] as Timestamp?;

        totalEarnings += amount;

        final uniqueId = taskId.isNotEmpty ? taskId : taskTitle;
        if (uniqueId.isNotEmpty && amount > 0) {
          if (tasksByTaskId.containsKey(uniqueId)) {
            tasksByTaskId[uniqueId]!['earnings'] = amount;
          } else {
            uniqueTaskIds.add(uniqueId);
            tasksByTaskId[uniqueId] = {
              'taskId': taskId,
              'taskTitle': taskTitle,
              'points': 0,
              'earnings': amount,
              'category': _categorizeTask(taskTitle),
              'timestamp': timestamp?.toDate() ?? DateTime.now(),
            };
          }
        }
      }

      // Count tasks by category
      for (var taskInfo in tasksByTaskId.values) {
        final category = taskInfo['category'] as String;
        tasksByCategory[category] = (tasksByCategory[category] ?? 0) + 1;
      }

      // FIXED: Use correct task counts
      final totalTasks = uniqueTaskIds.length;
      final completedTasks = totalTasks; // Since we only count tasks with positive values

      double completionRate = totalTasks > 0 ? (completedTasks / totalTasks) * 100 : 0;

      // Calculate daily breakdown
      List<Map<String, dynamic>> dailyBreakdown = [];
      for (int i = 0; i < 7; i++) {
        final currentDay = weekStart.add(Duration(days: i));
        final dayStart = DateTime(currentDay.year, currentDay.month, currentDay.day);
        final dayEnd = dayStart.add(const Duration(days: 1));

        // Get daily data using the fixed method
        final dailySummary = await generateDailySummaryForUser(
          userId: userId,
          date: currentDay,
        );

        final dayTasks = dailySummary['totalTasks'] as int? ?? 0;
        final dayPoints = dailySummary['pointsEarned'] as int? ?? 0;
        final dayEarnings = dailySummary['totalEarnings'] as double? ?? 0.0;
        final dayCompletionRate = dailySummary['completionRate'] as double? ?? 0.0;

        dailyBreakdown.add({
          'date': currentDay,
          'dayName': _getDayName(currentDay.weekday),
          'totalTasks': dayTasks,
          'completedTasks': dayTasks, // All fetched tasks are considered completed
          'points': dayPoints,
          'earnings': dayEarnings,
          'translations': 0,
          'completionRate': dayCompletionRate,
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

      final userName = profileData?['name'] ?? 'User';

      final summaryData = {
        'weekStart': weekStart.toIso8601String(),
        'weekEnd': weekEnd.toIso8601String(),
        'userId': userId,
        'userName': userName,
        'totalTasks': totalTasks, // FIXED: Now using correct unique task count
        'completedTasks': completedTasks,
        'inProgressTasks': 0,
        'pendingTasks': 0,
        'overdueTasks': 0,
        'totalPoints': totalPoints,
        'totalEarnings': totalEarnings,
        'translationsCount': 0,
        'completionRate': completionRate,
        'tasksByCategory': tasksByCategory,
        'averageDailyCompletion': averageDailyCompletion,
        'averageDailyEarnings': averageDailyEarnings,
        'mostProductiveDay': mostProductiveDayIndex >= 0 ? dailyBreakdown[mostProductiveDayIndex]['dayName'] : 'N/A',
        'dailyBreakdown': dailyBreakdown,
        'profileData': profileData,
      };

      print('Generated weekly summary for user $userId ($userName): ${totalTasks} unique tasks, ${totalPoints} points, RM${totalEarnings.toStringAsFixed(2)}');
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
      print('Checking if user $userId has data...');

      final summary = await getUserDataSummary(userId);

      final hasData = summary['dataAvailable'] as bool;
      final pointsCount = summary['pointsHistoryCount'] as int;
      final moneyCount = summary['moneyHistoryCount'] as int;
      final hasProfile = summary['hasProfile'] as bool;

      print('User $userId data check result:');
      print('  - Points history records: $pointsCount');
      print('  - Money history records: $moneyCount');
      print('  - Has profile: $hasProfile');
      print('  - Data available: $hasData');

      if (hasData) {
        final earliestDate = summary['earliestPointsDate'] ?? summary['earliestMoneyDate'];
        final latestDate = summary['latestPointsDate'] ?? summary['latestMoneyDate'];
        if (earliestDate != null && latestDate != null) {
          print('  - Date range: $earliestDate to $latestDate');
        }
      }

      return hasData;
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

  // Update user profile data
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

  // Add money transaction
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