import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

// Enhanced Comprehensive Report Screen with More Graphs
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _isGenerating = false;
  bool _isLoading = true;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _currentUserId;
  ReportData? _reportData;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _fadeController.forward();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    try {
      User? currentUser = _auth.currentUser;

      if (currentUser == null) {
        UserCredential userCredential = await _auth.signInAnonymously();
        currentUser = userCredential.user;
      }

      if (currentUser != null) {
        setState(() {
          _currentUserId = currentUser!.uid;
        });
        _loadReportData();
      } else {
        _showSnackBar('No user logged in. Please sign in first.', Colors.red);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error initializing user: $e');
      _showSnackBar('Failed to initialize user: $e', Colors.red);
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadReportData() async {
    if (_currentUserId == null) {
      _showSnackBar('No user ID available', Colors.red);
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        _loadTranslationData(),
        _loadSkillsData(),
        _loadMoneyData(),
        _loadTaskData(),
        _loadPointsData(),
      ]);

      setState(() {
        _reportData = ReportData(
          translationStats: results[0] as TranslationStats,
          userSkills: results[1] as UserSkills,
          moneyData: results[2] as MoneyData,
          taskData: results[3] as TaskData,
          pointsData: results[4] as PointsData,
        );
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading report data: $e');
      _showSnackBar('Failed to load report data: $e', Colors.red);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<TranslationStats> _loadTranslationData() async {
    try {
      final translationsSnapshot = await _firestore
          .collection('translations')
          .where('userId', isEqualTo: _currentUserId)
          .get();

      final translations = translationsSnapshot.docs.map((doc) {
        final data = doc.data();
        return TranslationData(
          date: (data['timestamp'] as Timestamp).toDate(),
          sourceLanguage: data['fromLanguage'] ?? 'Unknown',
          targetLanguage: data['toLanguage'] ?? 'Unknown',
          sourceText: data['originalText'] ?? '',
          translatedText: data['translatedText'] ?? '',
          charactersCount: (data['originalText'] ?? '').length,
        );
      }).toList();

      // Calculate language usage
      Map<String, int> languageUsage = {};
      Map<String, int> dailyTranslations = {};

      for (var translation in translations) {
        languageUsage[translation.sourceLanguage] =
            (languageUsage[translation.sourceLanguage] ?? 0) + 1;
        languageUsage[translation.targetLanguage] =
            (languageUsage[translation.targetLanguage] ?? 0) + 1;

        // Daily translations
        String dateKey = DateFormat('yyyy-MM-dd').format(translation.date);
        dailyTranslations[dateKey] = (dailyTranslations[dateKey] ?? 0) + 1;
      }

      return TranslationStats(
        totalTranslations: translations.length,
        totalCharacters: translations.fold(0, (sum, t) => sum + t.charactersCount),
        recentTranslations: translations.take(10).toList(),
        languageUsage: languageUsage,
        dailyTranslations: dailyTranslations,
        weeklyAverage: _calculateWeeklyAverage(dailyTranslations),
      );
    } catch (e) {
      print('Error loading translation data: $e');
      return TranslationStats(
        totalTranslations: 0,
        totalCharacters: 0,
        recentTranslations: [],
        languageUsage: {},
        dailyTranslations: {},
        weeklyAverage: 0.0,
      );
    }
  }

  Future<UserSkills> _loadSkillsData() async {
    try {
      final skillsDoc = await _firestore
          .doc('/users/$_currentUserId/skills/user_skills')
          .get();

      List<SkillItem> skillsList = [];
      Map<String, int> skillsMap = {};
      Map<String, int> skillCategories = {};
      int verifiedCount = 0;
      int unverifiedCount = 0;

      if (skillsDoc.exists) {
        final data = skillsDoc.data() as Map<String, dynamic>;
        final skillsArray = data['skills'] as List<dynamic>? ?? [];

        for (var skillData in skillsArray) {
          if (skillData is Map<String, dynamic>) {
            final skillName = skillData['skill'] ?? 'Unknown';
            final iconName = skillData['iconName'] ?? 'star';
            final verified = skillData['verified'] ?? false;
            final timestamp = skillData['timestamp'];
            final category = _categorizeSkill(skillName);

            skillsList.add(SkillItem(
              name: skillName,
              iconName: iconName,
              verified: verified,
              timestamp: timestamp is num
                  ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt())
                  : DateTime.now(),
              category: category,
            ));

            skillsMap[skillName] = (skillsMap[skillName] ?? 0) + 1;
            skillCategories[category] = (skillCategories[category] ?? 0) + 1;

            if (verified) {
              verifiedCount++;
            } else {
              unverifiedCount++;
            }
          }
        }
      }

      return UserSkills(
        skills: skillsMap,
        totalSkills: skillsList.length,
        skillsList: skillsList,
        verifiedCount: verifiedCount,
        unverifiedCount: unverifiedCount,
        skillCategories: skillCategories,
        lastUpdated: skillsList.isNotEmpty
            ? skillsList.map((s) => s.timestamp).reduce((a, b) => a.isAfter(b) ? a : b)
            : DateTime.now(),
      );
    } catch (e) {
      print('Error loading skills data: $e');
      return UserSkills(
        skills: {},
        totalSkills: 0,
        skillsList: [],
        verifiedCount: 0,
        unverifiedCount: 0,
        skillCategories: {},
        lastUpdated: DateTime.now(),
      );
    }
  }

  Future<MoneyData> _loadMoneyData() async {
    try {
      final moneySnapshot = await _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('moneyHistory')
          .orderBy('timestamp', descending: true)
          .get();

      double totalAmount = 0.0;
      int totalTransactions = 0;
      DateTime? lastTransaction;
      String currency = 'RM';
      List<MoneyTransaction> transactions = [];
      Map<String, double> dailyEarnings = {};
      Map<String, double> monthlyEarnings = {};

      for (var doc in moneySnapshot.docs) {
        final data = doc.data();
        final amount = ((data['amount'] ?? 0) as num).toDouble();
        final type = data['type'] ?? 'earning';
        final timestamp = data['timestamp'] as Timestamp?;
        final description = data['description'] ?? '';
        final source = data['source'] ?? '';

        final transactionDate = timestamp?.toDate() ?? DateTime.now();

        transactions.add(MoneyTransaction(
          amount: amount,
          type: type,
          timestamp: transactionDate,
          description: description,
          source: source,
        ));

        if (type == 'earning') {
          totalAmount += amount;

          // Daily earnings
          String dateKey = DateFormat('yyyy-MM-dd').format(transactionDate);
          dailyEarnings[dateKey] = (dailyEarnings[dateKey] ?? 0) + amount;

          // Monthly earnings
          String monthKey = DateFormat('yyyy-MM').format(transactionDate);
          monthlyEarnings[monthKey] = (monthlyEarnings[monthKey] ?? 0) + amount;
        }

        totalTransactions++;

        if (lastTransaction == null || transactionDate.isAfter(lastTransaction)) {
          lastTransaction = transactionDate;
        }
      }

      return MoneyData(
        totalAmount: totalAmount,
        currency: currency,
        lastTransaction: lastTransaction ?? DateTime.now(),
        transactionType: totalTransactions > 0 ? 'earning' : 'none',
        totalTransactions: totalTransactions,
        transactions: transactions,
        dailyEarnings: dailyEarnings,
        monthlyEarnings: monthlyEarnings,
        averageDailyEarning: _calculateAverageDailyEarning(dailyEarnings),
      );
    } catch (e) {
      print('Error loading money data: $e');
      return MoneyData(
        totalAmount: 0.0,
        currency: 'USD',
        lastTransaction: DateTime.now(),
        transactionType: 'none',
        totalTransactions: 0,
        transactions: [],
        dailyEarnings: {},
        monthlyEarnings: {},
        averageDailyEarning: 0.0,
      );
    }
  }

  Future<TaskData> _loadTaskData() async {
    try {
      final moneySnapshot = await _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('moneyHistory')
          .orderBy('timestamp', descending: true)
          .get();

      int totalTasks = 0;
      int completedTasks = 0;
      int inProgressTasks = 0;
      DateTime? lastUpdated;
      List<TaskItem> tasks = [];
      Map<String, int> tasksByCategory = {};
      Map<String, int> taskCompletionTrend = {};

      for (var doc in moneySnapshot.docs) {
        final data = doc.data();
        final taskId = data['taskId'] ?? doc.id;
        final taskTitle = data['taskTitle'] ?? data['description'] ?? 'Untitled Task';
        final amount = ((data['amount'] ?? 0) as num).toDouble();
        final timestamp = data['timestamp'] as Timestamp?;
        final source = data['source'] ?? 'task_completion';
        final category = _categorizeTask(taskTitle);

        final taskDate = timestamp?.toDate() ?? DateTime.now();

        tasks.add(TaskItem(
          taskId: taskId,
          title: taskTitle,
          status: 'Completed',
          progress: 100,
          lastUpdated: taskDate,
          action: 'Task Completed - Earned \$${amount.toStringAsFixed(2)}',
          category: category,
          earnings: amount,
        ));

        totalTasks++;
        completedTasks++;

        tasksByCategory[category] = (tasksByCategory[category] ?? 0) + 1;

        String dateKey = DateFormat('yyyy-MM-dd').format(taskDate);
        taskCompletionTrend[dateKey] = (taskCompletionTrend[dateKey] ?? 0) + 1;

        if (lastUpdated == null || taskDate.isAfter(lastUpdated)) {
          lastUpdated = taskDate;
        }
      }

      return TaskData(
        totalTasks: totalTasks,
        completedTasks: completedTasks,
        inProgressTasks: inProgressTasks,
        lastUpdated: lastUpdated ?? DateTime.now(),
        tasks: tasks,
        tasksByCategory: tasksByCategory,
        taskCompletionTrend: taskCompletionTrend,
        averageTasksPerDay: _calculateAverageTasksPerDay(taskCompletionTrend),
      );
    } catch (e) {
      print('Error loading task data: $e');
      return TaskData(
        totalTasks: 0,
        completedTasks: 0,
        inProgressTasks: 0,
        lastUpdated: DateTime.now(),
        tasks: [],
        tasksByCategory: {},
        taskCompletionTrend: {},
        averageTasksPerDay: 0.0,
      );
    }
  }

  Future<PointsData> _loadPointsData() async {
    try {
      final pointsSnapshot = await _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('pointsHistory')
          .orderBy('timestamp', descending: true)
          .get();

      int totalTaskCompletionPoints = 0;
      List<PointTransaction> recentTransactions = [];
      List<PointTransaction> taskCompletionTransactions = [];
      Map<String, int> dailyPoints = {};
      Map<String, int> pointsBySource = {};

      for (var doc in pointsSnapshot.docs) {
        final data = doc.data();
        final points = ((data['points'] ?? 0) as num).toInt();
        final description = data['description'] ?? '';
        final source = data['source'] ?? '';
        final taskId = data['taskId'] ?? '';
        final taskTitle = data['taskTitle'] ?? '';
        final timestamp = data['timestamp'] != null
            ? (data['timestamp'] as Timestamp).toDate()
            : DateTime.now();

        final transaction = PointTransaction(
          amount: points,
          reason: description,
          timestamp: timestamp,
          type: 'earned',
          source: source,
        );

        if (description.contains('Completed task:') && source == 'task_completion') {
          totalTaskCompletionPoints += points;
          taskCompletionTransactions.add(transaction);
        }

        recentTransactions.add(transaction);

        // Daily points
        String dateKey = DateFormat('yyyy-MM-dd').format(timestamp);
        dailyPoints[dateKey] = (dailyPoints[dateKey] ?? 0) + points;

        // Points by source
        pointsBySource[source] = (pointsBySource[source] ?? 0) + points;
      }

      return PointsData(
        totalPoints: totalTaskCompletionPoints,
        recentTransactions: recentTransactions,
        dailyPoints: dailyPoints,
        pointsBySource: pointsBySource,
        averagePointsPerDay: _calculateAveragePointsPerDay(dailyPoints),
      );
    } catch (e) {
      print('Error loading points data: $e');
      return PointsData(
        totalPoints: 0,
        recentTransactions: [],
        dailyPoints: {},
        pointsBySource: {},
        averagePointsPerDay: 0.0,
      );
    }
  }

  // Helper methods for calculations
  double _calculateWeeklyAverage(Map<String, int> dailyData) {
    if (dailyData.isEmpty) return 0.0;
    int totalTranslations = dailyData.values.fold(0, (sum, count) => sum + count);
    int days = dailyData.keys.length;
    return totalTranslations / (days / 7.0);
  }

  double _calculateAverageDailyEarning(Map<String, double> dailyEarnings) {
    if (dailyEarnings.isEmpty) return 0.0;
    double total = dailyEarnings.values.fold(0.0, (sum, amount) => sum + amount);
    return total / dailyEarnings.keys.length;
  }

  double _calculateAverageTasksPerDay(Map<String, int> taskTrend) {
    if (taskTrend.isEmpty) return 0.0;
    int totalTasks = taskTrend.values.fold(0, (sum, count) => sum + count);
    return totalTasks / taskTrend.keys.length;
  }

  double _calculateAveragePointsPerDay(Map<String, int> dailyPoints) {
    if (dailyPoints.isEmpty) return 0.0;
    int totalPoints = dailyPoints.values.fold(0, (sum, points) => sum + points);
    return totalPoints / dailyPoints.keys.length;
  }

  String _categorizeSkill(String skillName) {
    skillName = skillName.toLowerCase();
    if (skillName.contains('programming') || skillName.contains('coding') ||
        skillName.contains('development') || skillName.contains('software')) {
      return 'Technical';
    } else if (skillName.contains('language') || skillName.contains('translation') ||
        skillName.contains('communication')) {
      return 'Language';
    } else if (skillName.contains('design') || skillName.contains('creative') ||
        skillName.contains('art')) {
      return 'Creative';
    } else if (skillName.contains('management') || skillName.contains('leadership') ||
        skillName.contains('business')) {
      return 'Business';
    }
    return 'Other';
  }

  String _categorizeTask(String taskTitle) {
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
    }
    return 'General';
  }

  // Enhanced PDF Generation
  Future<void> _generatePdfReport() async {
    if (_reportData == null) {
      _showSnackBar('No data available to generate report', Colors.red);
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final pdf = pw.Document();

      // Cover Page
      pdf.addPage(_buildCoverPage());

      // Summary Page
      pdf.addPage(_buildSummaryPage());

      // Detailed Analytics Pages
      pdf.addPage(_buildTranslationAnalyticsPage());
      pdf.addPage(_buildTaskAnalyticsPage());
      pdf.addPage(_buildFinancialAnalyticsPage());
      pdf.addPage(_buildSkillsAnalyticsPage());

      // Recommendations Page
      pdf.addPage(_buildRecommendationsPage());

      // Save and share PDF
      final Uint8List pdfBytes = await pdf.save();
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String fileName = 'Comprehensive_Report_${DateFormat('yyyy_MM_dd_HH_mm').format(DateTime.now())}.pdf';
      final File file = File('${appDocDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Comprehensive User Report - ${DateFormat('MMM dd, yyyy').format(DateTime.now())}',
        text: 'Here is your comprehensive performance report generated on ${DateFormat('MMMM dd, yyyy HH:mm').format(DateTime.now())}',
      );

      _showSnackBar('PDF report generated and shared successfully!', Colors.green);
    } catch (e) {
      print('Error generating PDF: $e');
      _showSnackBar('Failed to generate PDF: $e', Colors.red);
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  // PDF Page Builders
  pw.Page _buildCoverPage() {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(40),
      build: (pw.Context context) {
        return pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Container(
                width: 150,
                height: 150,
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue100,
                  borderRadius: pw.BorderRadius.circular(75),
                  border: pw.Border.all(color: PdfColors.blue, width: 3),
                ),
                child: pw.Center(
                  child: pw.Text(
                    'REPORT',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 40),
              pw.Text(
                'Comprehensive Performance Report',
                style: pw.TextStyle(
                  fontSize: 32,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'User ID: ${_currentUserId ?? 'Unknown'}',
                style: pw.TextStyle(fontSize: 16, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Generated on ${DateFormat('MMMM dd, yyyy HH:mm').format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 14, color: PdfColors.grey500),
              ),
              pw.SizedBox(height: 60),
              pw.Container(
                padding: pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Report Overview',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 15),
                    pw.Text('• Translation & Learning Analytics', style: pw.TextStyle(fontSize: 12)),
                    pw.Text('• Task Management & Productivity', style: pw.TextStyle(fontSize: 12)),
                    pw.Text('• Financial Performance Overview', style: pw.TextStyle(fontSize: 12)),
                    pw.Text('• Skills Development Tracking', style: pw.TextStyle(fontSize: 12)),
                    pw.Text('• Performance Recommendations', style: pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  pw.Page _buildSummaryPage() {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(40),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildPdfHeader(),
            pw.SizedBox(height: 30),
            pw.Text(
              'EXECUTIVE SUMMARY',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue,
              ),
            ),
            pw.SizedBox(height: 20),
            _buildPdfSummaryStats(),
            pw.SizedBox(height: 30),
            _buildPdfKeyMetrics(),
            pw.SizedBox(height: 30),
            _buildPdfPerformanceInsights(),
          ],
        );
      },
    );
  }

  pw.Page _buildTranslationAnalyticsPage() {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(40),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'TRANSLATION ANALYTICS',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue,
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              children: [
                _buildPdfStatCard('Total Translations', _reportData!.translationStats.totalTranslations.toString()),
                pw.SizedBox(width: 20),
                _buildPdfStatCard('Total Characters', _reportData!.translationStats.totalCharacters.toString()),
                pw.SizedBox(width: 20),
                _buildPdfStatCard('Weekly Average', _reportData!.translationStats.weeklyAverage.toStringAsFixed(1)),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.Text(
              'Language Usage Distribution',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 15),
            ..._buildLanguageUsageTable(),
          ],
        );
      },
    );
  }

  pw.Page _buildTaskAnalyticsPage() {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(40),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'TASK & PRODUCTIVITY ANALYTICS',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.purple,
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              children: [
                _buildPdfStatCard('Completed Tasks', _reportData!.taskData.completedTasks.toString()),
                pw.SizedBox(width: 20),
                _buildPdfStatCard('Avg Tasks/Day', _reportData!.taskData.averageTasksPerDay.toStringAsFixed(1)),
                pw.SizedBox(width: 20),
                _buildPdfStatCard('Completion Rate', '100%'),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.Text(
              'Task Categories Breakdown',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 15),
            ..._buildTaskCategoriesTable(),
          ],
        );
      },
    );
  }

  pw.Page _buildFinancialAnalyticsPage() {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(40),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'FINANCIAL PERFORMANCE',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green,
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              children: [
                _buildPdfStatCard('Total Earnings', '${_reportData!.moneyData.currency} ${_reportData!.moneyData.totalAmount.toStringAsFixed(2)}'),
                pw.SizedBox(width: 20),
                _buildPdfStatCard('Avg Daily Earning', '${_reportData!.moneyData.currency} ${_reportData!.moneyData.averageDailyEarning.toStringAsFixed(2)}'),
                pw.SizedBox(width: 20),
                _buildPdfStatCard('Total Transactions', _reportData!.moneyData.totalTransactions.toString()),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.Text(
              'Monthly Earnings Breakdown',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 15),
            ..._buildMonthlyEarningsTable(),
          ],
        );
      },
    );
  }

  pw.Page _buildSkillsAnalyticsPage() {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(40),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'SKILLS DEVELOPMENT',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.orange,
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              children: [
                _buildPdfStatCard('Total Skills', _reportData!.userSkills.totalSkills.toString()),
                pw.SizedBox(width: 20),
                _buildPdfStatCard('Verified Skills', _reportData!.userSkills.verifiedCount.toString()),
                pw.SizedBox(width: 20),
                _buildPdfStatCard('Skill Categories', _reportData!.userSkills.skillCategories.keys.length.toString()),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.Text(
              'Skills by Category',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 15),
            ..._buildSkillsCategoriesTable(),
          ],
        );
      },
    );
  }

  pw.Page _buildRecommendationsPage() {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(40),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'RECOMMENDATIONS & INSIGHTS',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.deepPurple,
              ),
            ),
            pw.SizedBox(height: 20),
            ..._buildRecommendationsList(),
            pw.SizedBox(height: 30),
            pw.Text(
              'Performance Trends',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 15),
            ..._buildPerformanceTrends(),
          ],
        );
      },
    );
  }

  // PDF Helper Methods
  pw.Widget _buildPdfHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Comprehensive User Report',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Generated on ${DateFormat('MMMM dd, yyyy HH:mm').format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 14, color: PdfColors.grey600),
                ),
                pw.Text(
                  'User ID: ${_currentUserId ?? 'Unknown'}',
                  style: pw.TextStyle(fontSize: 12, color: PdfColors.grey500),
                ),
              ],
            ),
            pw.Container(
              width: 80,
              height: 80,
              decoration: pw.BoxDecoration(
                color: PdfColors.blue100,
                borderRadius: pw.BorderRadius.circular(40),
              ),
              child: pw.Center(
                child: pw.Text(
                  'REPORT',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Container(
          height: 3,
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [PdfColors.blue, PdfColors.purple],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPdfSummaryStats() {
    return pw.Row(
      children: [
        _buildPdfStatCard('Overall Score', '${_calculateOverallScore().toStringAsFixed(1)}/100'),
        pw.SizedBox(width: 15),
        _buildPdfStatCard('Active Days', '${_calculateActiveDays()}'),
        pw.SizedBox(width: 15),
        _buildPdfStatCard('Productivity', '${_calculateProductivityScore().toStringAsFixed(1)}%'),
        pw.SizedBox(width: 15),
        _buildPdfStatCard('Growth Rate', '${_calculateGrowthRate().toStringAsFixed(1)}%'),
      ],
    );
  }

  pw.Widget _buildPdfKeyMetrics() {
    return pw.Container(
      padding: pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Key Performance Indicators',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 15),
          _buildPdfMetricRow('Task Completion Rate', '${_reportData!.taskData.totalTasks > 0 ? "100.0" : "0"}%'),
          pw.SizedBox(height: 8),
          _buildPdfMetricRow('Average Earnings per Task', '${_reportData!.taskData.completedTasks > 0 ? (_reportData!.moneyData.totalAmount / _reportData!.taskData.completedTasks).toStringAsFixed(2) : "0"} ${_reportData!.moneyData.currency}'),
          pw.SizedBox(height: 8),
          _buildPdfMetricRow('Skills Verification Rate', '${_reportData!.userSkills.totalSkills > 0 ? ((_reportData!.userSkills.verifiedCount / _reportData!.userSkills.totalSkills) * 100).toStringAsFixed(1) : "0"}%'),
          pw.SizedBox(height: 8),
          _buildPdfMetricRow('Average Translation Length', '${_reportData!.translationStats.totalTranslations > 0 ? (_reportData!.translationStats.totalCharacters / _reportData!.translationStats.totalTranslations).round() : 0} chars'),
          pw.SizedBox(height: 8),
          _buildPdfMetricRow('Points per Task', '${_reportData!.taskData.completedTasks > 0 ? (_reportData!.pointsData.totalPoints / _reportData!.taskData.completedTasks).toStringAsFixed(1) : "0"}'),
        ],
      ),
    );
  }

  pw.Widget _buildPdfPerformanceInsights() {
    return pw.Container(
      padding: pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Performance Insights',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('• Strong task completion consistency with 100% completion rate', style: pw.TextStyle(fontSize: 11)),
          pw.Text('• ${_getTopPerformingCategory()} tasks show highest engagement', style: pw.TextStyle(fontSize: 11)),
          pw.Text('• Skills development focused on ${_getTopSkillCategory()} area', style: pw.TextStyle(fontSize: 11)),
          pw.Text('• Average daily productivity: ${_reportData!.taskData.averageTasksPerDay.toStringAsFixed(1)} tasks', style: pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  List<pw.Widget> _buildLanguageUsageTable() {
    final languages = _reportData!.translationStats.languageUsage.entries.toList();
    languages.sort((a, b) => b.value.compareTo(a.value));

    return [
      pw.Table(
        border: pw.TableBorder.all(),
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Language', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Usage Count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Percentage', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          ...languages.take(10).map((entry) {
            final percentage = (entry.value / languages.fold<int>(0, (sum, e) => sum + e.value) * 100);
            return pw.TableRow(
              children: [
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text(entry.key),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text(entry.value.toString()),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text('${percentage.toStringAsFixed(1)}%'),
                ),
              ],
            );
          }).toList(),
        ],
      ),
    ];
  }

  List<pw.Widget> _buildTaskCategoriesTable() {
    final categories = _reportData!.taskData.tasksByCategory.entries.toList();
    categories.sort((a, b) => b.value.compareTo(a.value));

    return [
      pw.Table(
        border: pw.TableBorder.all(),
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Category', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Tasks Count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Percentage', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          ...categories.map((entry) {
            final percentage = (entry.value / _reportData!.taskData.totalTasks * 100);
            return pw.TableRow(
              children: [
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text(entry.key),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text(entry.value.toString()),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text('${percentage.toStringAsFixed(1)}%'),
                ),
              ],
            );
          }).toList(),
        ],
      ),
    ];
  }

  List<pw.Widget> _buildMonthlyEarningsTable() {
    final months = _reportData!.moneyData.monthlyEarnings.entries.toList();
    months.sort((a, b) => b.key.compareTo(a.key));

    return [
      pw.Table(
        border: pw.TableBorder.all(),
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Month', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Earnings', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Growth', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          ...months.take(12).map((entry) {
            return pw.TableRow(
              children: [
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text(DateFormat('MMM yyyy').format(DateTime.parse('${entry.key}-01'))),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text('${_reportData!.moneyData.currency} ${entry.value.toStringAsFixed(2)}'),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text('--'),
                ),
              ],
            );
          }).toList(),
        ],
      ),
    ];
  }

  List<pw.Widget> _buildSkillsCategoriesTable() {
    final categories = _reportData!.userSkills.skillCategories.entries.toList();
    categories.sort((a, b) => b.value.compareTo(a.value));

    return [
      pw.Table(
        border: pw.TableBorder.all(),
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Category', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Skills Count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text('Percentage', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          ...categories.map((entry) {
            final percentage = (entry.value / _reportData!.userSkills.totalSkills * 100);
            return pw.TableRow(
              children: [
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text(entry.key),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text(entry.value.toString()),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(8),
                  child: pw.Text('${percentage.toStringAsFixed(1)}%'),
                ),
              ],
            );
          }).toList(),
        ],
      ),
    ];
  }

  List<pw.Widget> _buildRecommendationsList() {
    List<String> recommendations = _generateRecommendations();

    return [
      pw.Container(
        padding: pw.EdgeInsets.all(15),
        decoration: pw.BoxDecoration(
          color: PdfColors.green50,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: PdfColors.green200),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Actionable Recommendations',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green800),
            ),
            pw.SizedBox(height: 10),
            ...recommendations.map((rec) => pw.Padding(
              padding: pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text('• $rec', style: pw.TextStyle(fontSize: 11)),
            )).toList(),
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> _buildPerformanceTrends() {
    return [
      pw.Container(
        padding: pw.EdgeInsets.all(15),
        decoration: pw.BoxDecoration(
          color: PdfColors.orange50,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: PdfColors.orange200),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Observed Trends',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800),
            ),
            pw.SizedBox(height: 10),
            pw.Text('• Task completion maintains consistent 100% success rate', style: pw.TextStyle(fontSize: 11)),
            pw.Text('• Translation activity shows ${_reportData!.translationStats.weeklyAverage > 10 ? "high" : "moderate"} weekly engagement', style: pw.TextStyle(fontSize: 11)),
            pw.Text('• Skills verification rate at ${(_reportData!.userSkills.verifiedCount / (_reportData!.userSkills.totalSkills > 0 ? _reportData!.userSkills.totalSkills : 1) * 100).toStringAsFixed(1)}%', style: pw.TextStyle(fontSize: 11)),
            pw.Text('• Average earnings per task: ${(_reportData!.moneyData.totalAmount / (_reportData!.taskData.completedTasks > 0 ? _reportData!.taskData.completedTasks : 1)).toStringAsFixed(2)} ${_reportData!.moneyData.currency}', style: pw.TextStyle(fontSize: 11)),
          ],
        ),
      ),
    ];
  }

  pw.Widget _buildPdfStatCard(String title, String value) {
    return pw.Expanded(
      child: pw.Container(
        padding: pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(8),
          color: PdfColors.white,
        ),
        child: pw.Column(
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildPdfMetricRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 12)),
        pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
      ],
    );
  }

  // Calculation methods
  int _calculateActiveDays() {
    Set<String> activeDays = {};

    // Add days from translations
    for (var translation in _reportData!.translationStats.recentTranslations) {
      activeDays.add(DateFormat('yyyy-MM-dd').format(translation.date));
    }

    // Add days from tasks
    for (var task in _reportData!.taskData.tasks) {
      activeDays.add(DateFormat('yyyy-MM-dd').format(task.lastUpdated));
    }

    return activeDays.length;
  }

  double _calculateProductivityScore() {
    double score = 0.0;

    // Task completion rate (40 points)
    if (_reportData!.taskData.totalTasks > 0) {
      score += 40.0;
    }

    // Translation activity (30 points)
    if (_reportData!.translationStats.totalTranslations > 0) {
      score += 30.0;
    }

    // Skills development (20 points)
    if (_reportData!.userSkills.totalSkills > 0) {
      score += 20.0;
    }

    // Consistency (10 points)
    if (_calculateActiveDays() > 5) {
      score += 10.0;
    }

    return score;
  }

  double _calculateGrowthRate() {
    // Simple growth calculation based on recent activity
    int recentTasks = _reportData!.taskData.tasks.where((task) =>
    DateTime.now().difference(task.lastUpdated).inDays <= 30
    ).length;

    int totalTasks = _reportData!.taskData.totalTasks;

    if (totalTasks == 0) return 0.0;

    return (recentTasks / totalTasks) * 100;
  }

  String _getTopPerformingCategory() {
    if (_reportData!.taskData.tasksByCategory.isEmpty) return 'General';

    var sorted = _reportData!.taskData.tasksByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.first.key;
  }

  String _getTopSkillCategory() {
    if (_reportData!.userSkills.skillCategories.isEmpty) return 'General';

    var sorted = _reportData!.userSkills.skillCategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.first.key;
  }

  List<String> _generateRecommendations() {
    List<String> recommendations = [];

    // Task-based recommendations
    if (_reportData!.taskData.averageTasksPerDay < 2) {
      recommendations.add('Consider increasing daily task completion to 2+ tasks for improved productivity');
    }

    // Skills-based recommendations
    double verificationRate = _reportData!.userSkills.totalSkills > 0
        ? _reportData!.userSkills.verifiedCount / _reportData!.userSkills.totalSkills
        : 0;
    if (verificationRate < 0.5) {
      recommendations.add('Focus on verifying existing skills to improve credibility and earning potential');
    }

    // Translation-based recommendations
    if (_reportData!.translationStats.weeklyAverage < 5) {
      recommendations.add('Increase translation activity to boost language skills and earnings');
    }

    // Financial recommendations
    if (_reportData!.moneyData.averageDailyEarning < 10) {
      recommendations.add('Explore higher-value tasks to increase daily earning potential');
    }

    // General recommendations
    if (_calculateActiveDays() < 10) {
      recommendations.add('Maintain consistent daily activity to build momentum and improve results');
    }

    return recommendations;
  }

  double _calculateOverallScore() {
    if (_reportData == null) return 0.0;

    double translationScore = _reportData!.translationStats.totalTranslations * 2.0;
    double taskScore = _reportData!.taskData.completedTasks * 10.0;
    double skillScore = _reportData!.userSkills.totalSkills * 5.0;
    double verifiedSkillScore = _reportData!.userSkills.verifiedCount * 3.0;
    double pointScore = _reportData!.pointsData.totalPoints * 0.1;
    double moneyScore = _reportData!.moneyData.totalAmount * 0.5;

    double totalScore = translationScore + taskScore + skillScore + verifiedSkillScore + pointScore + moneyScore;

    return (totalScore).clamp(0.0, 100.0);
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.refresh,
                color: Colors.white,
                size: 20,
              ),
            ),
            onPressed: () {
              if (_currentUserId != null) {
                _loadReportData();
              } else {
                _initializeUser();
              }
            },
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF667eea),
                Color(0xFF764ba2),
              ],
            ),
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Loading comprehensive analytics...',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          )
              : FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  SizedBox(height: 30),
                  _buildPart1(),
                  SizedBox(height: 30),
                  _buildPart2(),
                  SizedBox(height: 30),
                  _buildEnhancedGraphsSection(),
                  SizedBox(height: 30),
                  _buildGeneratePdfButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFF667eea).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.assessment,
              color: Color(0xFF667eea),
              size: 32,
            ),
          ),
          SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enhanced Analytics Report',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Complete analysis with advanced visualizations',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Generated: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPart1() {
    if (_reportData == null) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school, color: Color(0xFF667eea)),
              SizedBox(width: 8),
              Text(
                'PART 1: Translation & Learning Analytics',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF667eea),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),

          // Translation Stats
          _buildSectionHeader('Translation Statistics', Icons.translate),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('Translations', _reportData!.translationStats.totalTranslations.toString(), Icons.translate)),
              SizedBox(width: 12),
              Expanded(child: _buildStatCard('Characters', _reportData!.translationStats.totalCharacters.toString(), Icons.text_fields)),
              SizedBox(width: 12),
              Expanded(child: _buildStatCard('Weekly Avg', _reportData!.translationStats.weeklyAverage.toStringAsFixed(1), Icons.trending_up)),
            ],
          ),

          SizedBox(height: 20),

          // Skills Stats
          _buildSectionHeader('Skills Overview', Icons.star),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('Total Skills', _reportData!.userSkills.totalSkills.toString(), Icons.star)),
              SizedBox(width: 8),
              Expanded(child: _buildStatCard('Categories', _reportData!.userSkills.skillCategories.keys.length.toString(), Icons.category)),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('Verified', _reportData!.userSkills.verifiedCount.toString(), Icons.verified)),
              SizedBox(width: 8),
              Expanded(child: _buildStatCard('Unverified', _reportData!.userSkills.unverifiedCount.toString(), Icons.pending)),
            ],
          ),

          SizedBox(height: 20),

          // Money Stats
          _buildSectionHeader('Financial Overview', Icons.attach_money),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('Total Earnings', '${_reportData!.moneyData.currency} ${_reportData!.moneyData.totalAmount.toStringAsFixed(2)}', Icons.account_balance_wallet)),
              SizedBox(width: 8),
              Expanded(child: _buildStatCard('Avg Daily', '${_reportData!.moneyData.currency} ${_reportData!.moneyData.averageDailyEarning.toStringAsFixed(2)}', Icons.trending_up)),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('Transactions', _reportData!.moneyData.totalTransactions.toString(), Icons.receipt)),
              SizedBox(width: 8),
              Expanded(child: _buildStatCard('Last Earn', DateFormat('MMM dd').format(_reportData!.moneyData.lastTransaction), Icons.history)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPart2() {
    if (_reportData == null) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, color: Color(0xFF764ba2)),
              SizedBox(width: 8),
              Text(
                'PART 2: Productivity & Achievements',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF764ba2),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),

          // Task Stats
          _buildSectionHeader('Task Management', Icons.task),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('Total Tasks', _reportData!.taskData.totalTasks.toString(), Icons.assignment)),
              SizedBox(width: 8),
              Expanded(child: _buildStatCard('Completed', _reportData!.taskData.completedTasks.toString(), Icons.check_circle)),
              SizedBox(width: 8),
              Expanded(child: _buildStatCard('Avg/Day', _reportData!.taskData.averageTasksPerDay.toStringAsFixed(1), Icons.today)),
            ],
          ),

          SizedBox(height: 20),

          // Points Stats
          _buildSectionHeader('Points & Rewards', Icons.emoji_events),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('Total Points', _reportData!.pointsData.totalPoints.toString(), Icons.stars)),
              SizedBox(width: 8),
              Expanded(child: _buildStatCard('Avg/Day', _reportData!.pointsData.averagePointsPerDay.toStringAsFixed(1), Icons.trending_up)),
              SizedBox(width: 8),
              Expanded(child: _buildStatCard('Transactions', _reportData!.pointsData.recentTransactions.length.toString(), Icons.receipt)),
            ],
          ),

          SizedBox(height: 20),

          // Performance Metrics
          _buildSectionHeader('Performance Metrics', Icons.analytics),
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildMetricRow('Task Completion Rate', '${_reportData!.taskData.totalTasks > 0 ? "100.0" : "0"}%'),
                Divider(),
                _buildMetricRow('Points per Task', '${_reportData!.taskData.completedTasks > 0 ? (_reportData!.pointsData.totalPoints / _reportData!.taskData.completedTasks).toStringAsFixed(1) : "0"}'),
                Divider(),
                _buildMetricRow('Earnings per Task', '${_reportData!.taskData.completedTasks > 0 ? (_reportData!.moneyData.totalAmount / _reportData!.taskData.completedTasks).toStringAsFixed(2) : "0"} ${_reportData!.moneyData.currency}'),
                Divider(),
                _buildMetricRow('Overall Score', '${_calculateOverallScore().toStringAsFixed(1)}/100'),
                Divider(),
                _buildMetricRow('Active Days', '${_calculateActiveDays()}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedGraphsSection() {
    if (_reportData == null) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics, color: Color(0xFF667eea)),
              SizedBox(width: 8),
              Text(
                'Enhanced Data Visualizations',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF667eea),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),

          // Skills Distribution Pie Chart
          if (_reportData!.userSkills.verifiedCount > 0 || _reportData!.userSkills.unverifiedCount > 0) ...[
            _buildSectionHeader('Skills Verification Status', Icons.pie_chart),
            SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(
                      color: Color(0xFF667eea),
                      value: _reportData!.userSkills.verifiedCount.toDouble(),
                      title: 'Verified\n${_reportData!.userSkills.verifiedCount}',
                      radius: 80,
                      titleStyle: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      color: Color(0xFF764ba2),
                      value: _reportData!.userSkills.unverifiedCount.toDouble(),
                      title: 'Unverified\n${_reportData!.userSkills.unverifiedCount}',
                      radius: 80,
                      titleStyle: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  centerSpaceRadius: 50,
                  sectionsSpace: 3,
                ),
              ),
            ),
            SizedBox(height: 30),
          ],

          // Task Categories Pie Chart
          if (_reportData!.taskData.tasksByCategory.isNotEmpty) ...[
            _buildSectionHeader('Task Categories Distribution', Icons.donut_small),
            SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: PieChart(
                PieChartData(
                  sections: _getTaskCategoriesPieData(),
                  centerSpaceRadius: 50,
                  sectionsSpace: 2,
                ),
              ),
            ),
            SizedBox(height: 30),
          ],

          // Skills Categories Bar Chart
          if (_reportData!.userSkills.skillCategories.isNotEmpty) ...[
            _buildSectionHeader('Skills by Category', Icons.bar_chart),
            SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _reportData!.userSkills.skillCategories.values
                      .reduce((a, b) => a > b ? a : b)
                      .toDouble() * 1.2,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          final categories = _reportData!.userSkills.skillCategories.keys.toList();
                          if (value.toInt() < categories.length) {
                            return Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                categories[value.toInt()],
                                style: TextStyle(fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: _getSkillCategoriesBarGroups(),
                ),
              ),
            ),
            SizedBox(height: 30),
          ],

          // Earnings Over Time Line Chart
          if (_reportData!.moneyData.transactions.isNotEmpty) ...[
            _buildSectionHeader('Cumulative Earnings Trend', Icons.trending_up),
            SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${_reportData!.moneyData.currency}${value.toInt()}',
                            style: TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final transactions = _reportData!.moneyData.transactions.reversed.toList();
                          if (value.toInt() < transactions.length) {
                            final transaction = transactions[value.toInt()];
                            return Text(
                              DateFormat('MMM dd').format(transaction.timestamp),
                              style: TextStyle(fontSize: 8),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _getEarningsSpots(),
                      isCurved: true,
                      color: Color(0xFF667eea),
                      barWidth: 4,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Color(0xFF667eea).withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 30),
          ],

          // Points Accumulation Chart
          if (_reportData!.pointsData.recentTransactions.isNotEmpty) ...[
            _buildSectionHeader('Points Accumulation', Icons.stars),
            SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}',
                            style: TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final transactions = _reportData!.pointsData.recentTransactions.reversed.toList();
                          if (value.toInt() < transactions.length) {
                            final transaction = transactions[value.toInt()];
                            return Text(
                              DateFormat('MMM dd').format(transaction.timestamp),
                              style: TextStyle(fontSize: 8),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _getPointsSpots(),
                      isCurved: true,
                      color: Color(0xFF764ba2),
                      barWidth: 4,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Color(0xFF764ba2).withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 30),
          ],

          // Language Usage Bar Chart
          if (_reportData!.translationStats.languageUsage.isNotEmpty) ...[
            _buildSectionHeader('Top Languages Used', Icons.language),
            SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _reportData!.translationStats.languageUsage.values
                      .reduce((a, b) => a > b ? a : b)
                      .toDouble() * 1.2,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          final languages = _reportData!.translationStats.languageUsage.keys.toList();
                          if (value.toInt() < languages.length) {
                            return Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                languages[value.toInt()].length > 4
                                    ? languages[value.toInt()].substring(0, 4)
                                    : languages[value.toInt()],
                                style: TextStyle(fontSize: 9),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: _getLanguageBarGroups(),
                ),
              ),
            ),
            SizedBox(height: 30),
          ],

          // Monthly Earnings Bar Chart
          if (_reportData!.moneyData.monthlyEarnings.isNotEmpty) ...[
            _buildSectionHeader('Monthly Earnings Breakdown', Icons.calendar_month),
            SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _reportData!.moneyData.monthlyEarnings.values
                      .reduce((a, b) => a > b ? a : b) * 1.2,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${_reportData!.moneyData.currency}${value.toInt()}',
                            style: TextStyle(fontSize: 9),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final months = _reportData!.moneyData.monthlyEarnings.keys.toList()
                            ..sort((a, b) => a.compareTo(b));
                          if (value.toInt() < months.length) {
                            return Text(
                              DateFormat('MMM').format(DateTime.parse('${months[value.toInt()]}-01')),
                              style: TextStyle(fontSize: 9),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: _getMonthlyEarningsBarGroups(),
                ),
              ),
            ),
            SizedBox(height: 30),
          ],

          // Performance Radar Chart Alternative (using circular indicators)
          _buildSectionHeader('Performance Overview', Icons.radar),
          SizedBox(height: 12),
          Container(
            height: 200,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF667eea).withOpacity(0.1), Color(0xFF764ba2).withOpacity(0.1)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPerformanceIndicator('Tasks', _reportData!.taskData.completedTasks.toDouble(), 50),
                _buildPerformanceIndicator('Skills', _reportData!.userSkills.totalSkills.toDouble(), 100),
                _buildPerformanceIndicator('Translations', _reportData!.translationStats.totalTranslations.toDouble(), 200),
                _buildPerformanceIndicator('Points', _reportData!.pointsData.totalPoints.toDouble(), 2000),
                _buildPerformanceIndicator('Earnings', _reportData!.moneyData.totalAmount, 500),
              ],
            ),
          ),
          SizedBox(height: 30),

          // Daily Activity Heatmap Alternative
          _buildSectionHeader('Activity Patterns', Icons.grid_view),
          SizedBox(height: 12),
          _buildActivityGrid(),
        ],
      ),
    );
  }

  // Enhanced Chart Helper Methods
  List<PieChartSectionData> _getTaskCategoriesPieData() {
    final categories = _reportData!.taskData.tasksByCategory.entries.toList();
    final colors = [
      Color(0xFF667eea),
      Color(0xFF764ba2),
      Color(0xFF4ecdc4),
      Color(0xFF45b7d1),
      Color(0xFFf9ca24),
      Color(0xFFf0932b),
    ];

    return categories.asMap().entries.map((entry) {
      final index = entry.key;
      final category = entry.value;

      return PieChartSectionData(
        color: colors[index % colors.length],
        value: category.value.toDouble(),
        title: '${category.key}\n${category.value}',
        radius: 70,
        titleStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  List<BarChartGroupData> _getSkillCategoriesBarGroups() {
    final categories = _reportData!.userSkills.skillCategories.entries.toList();
    categories.sort((a, b) => b.value.compareTo(a.value));

    return categories.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value.value.toDouble(),
            color: Color(0xFF667eea),
            width: 25,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();
  }

  List<BarChartGroupData> _getLanguageBarGroups() {
    final languages = _reportData!.translationStats.languageUsage.entries.toList();
    languages.sort((a, b) => b.value.compareTo(a.value));

    return languages.take(8).toList().asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value.value.toDouble(),
            color: Color(0xFF764ba2),
            width: 20,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();
  }

  List<BarChartGroupData> _getMonthlyEarningsBarGroups() {
    final months = _reportData!.moneyData.monthlyEarnings.entries.toList();
    months.sort((a, b) => a.key.compareTo(b.key));

    return months.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value.value,
            color: Color(0xFF4ecdc4),
            width: 25,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();
  }

  List<FlSpot> _getEarningsSpots() {
    final transactions = _reportData!.moneyData.transactions.reversed.toList();
    double cumulativeEarnings = 0;

    return transactions.asMap().entries.map((entry) {
      cumulativeEarnings += entry.value.amount;
      return FlSpot(entry.key.toDouble(), cumulativeEarnings);
    }).toList();
  }

  List<FlSpot> _getPointsSpots() {
    final transactions = _reportData!.pointsData.recentTransactions.reversed.toList();
    double cumulativePoints = 0;

    return transactions.asMap().entries.map((entry) {
      cumulativePoints += entry.value.amount;
      return FlSpot(entry.key.toDouble(), cumulativePoints);
    }).toList();
  }

  Widget _buildPerformanceIndicator(String label, double value, double maxValue) {
    final percentage = (value / maxValue).clamp(0.0, 1.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 60,
          height: 60,
          child: CircularProgressIndicator(
            value: percentage,
            strokeWidth: 6,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              percentage > 0.7 ? Colors.green : percentage > 0.4 ? Colors.orange : Colors.red,
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        Text(
          value.toInt().toString(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF667eea),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityGrid() {
    // Create a 7x8 grid representing activity pattern (simplified heatmap)
    return Container(
      height: 150,
      child: GridView.builder(
        physics: NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: 35, // 5 weeks
        itemBuilder: (context, index) {
          // Random activity intensity for demo (in real app, use actual data)
          final intensity = math.Random().nextDouble();
          return Container(
            decoration: BoxDecoration(
              color: Color(0xFF667eea).withOpacity(intensity * 0.8 + 0.1),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Color(0xFF667eea), size: 18),
        SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF667eea).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF667eea).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Color(0xFF667eea), size: 24),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF667eea),
            ),
          ),
          SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF667eea),
          ),
        ),
      ],
    );
  }

  Widget _buildGeneratePdfButton() {
    return Container(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: (_isGenerating || _reportData == null) ? null : _generatePdfReport,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF667eea),
          elevation: 8,
          shadowColor: Colors.black.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isGenerating
            ? Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Generating Enhanced PDF Report...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.picture_as_pdf, size: 24),
            SizedBox(width: 12),
            Text(
              'Generate Enhanced PDF Report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// Enhanced Data Models
class ReportData {
  final TranslationStats translationStats;
  final UserSkills userSkills;
  final MoneyData moneyData;
  final TaskData taskData;
  final PointsData pointsData;

  ReportData({
    required this.translationStats,
    required this.userSkills,
    required this.moneyData,
    required this.taskData,
    required this.pointsData,
  });
}

class TranslationStats {
  final int totalTranslations;
  final int totalCharacters;
  final List<TranslationData> recentTranslations;
  final Map<String, int> languageUsage;
  final Map<String, int> dailyTranslations;
  final double weeklyAverage;

  TranslationStats({
    required this.totalTranslations,
    required this.totalCharacters,
    required this.recentTranslations,
    required this.languageUsage,
    required this.dailyTranslations,
    required this.weeklyAverage,
  });
}

class UserSkills {
  final Map<String, int> skills;
  final int totalSkills;
  final DateTime lastUpdated;
  final List<SkillItem> skillsList;
  final int verifiedCount;
  final int unverifiedCount;
  final Map<String, int> skillCategories;

  UserSkills({
    required this.skills,
    required this.totalSkills,
    required this.lastUpdated,
    required this.skillsList,
    required this.verifiedCount,
    required this.unverifiedCount,
    required this.skillCategories,
  });
}

class SkillItem {
  final String name;
  final String iconName;
  final bool verified;
  final DateTime timestamp;
  final String category;

  SkillItem({
    required this.name,
    required this.iconName,
    required this.verified,
    required this.timestamp,
    required this.category,
  });
}

class MoneyData {
  final double totalAmount;
  final String currency;
  final DateTime lastTransaction;
  final String transactionType;
  final int totalTransactions;
  final List<MoneyTransaction> transactions;
  final Map<String, double> dailyEarnings;
  final Map<String, double> monthlyEarnings;
  final double averageDailyEarning;

  MoneyData({
    required this.totalAmount,
    required this.currency,
    required this.lastTransaction,
    required this.transactionType,
    required this.totalTransactions,
    required this.transactions,
    required this.dailyEarnings,
    required this.monthlyEarnings,
    required this.averageDailyEarning,
  });
}

class MoneyTransaction {
  final double amount;
  final String type;
  final DateTime timestamp;
  final String description;
  final String source;

  MoneyTransaction({
    required this.amount,
    required this.type,
    required this.timestamp,
    required this.description,
    required this.source,
  });
}

class TaskData {
  final int totalTasks;
  final int completedTasks;
  final int inProgressTasks;
  final DateTime lastUpdated;
  final List<TaskItem> tasks;
  final Map<String, int> tasksByCategory;
  final Map<String, int> taskCompletionTrend;
  final double averageTasksPerDay;

  TaskData({
    required this.totalTasks,
    required this.completedTasks,
    required this.inProgressTasks,
    required this.lastUpdated,
    required this.tasks,
    required this.tasksByCategory,
    required this.taskCompletionTrend,
    required this.averageTasksPerDay,
  });
}

class TaskItem {
  final String taskId;
  final String title;
  final String status;
  final int progress;
  final DateTime lastUpdated;
  final String action;
  final String category;
  final double earnings;

  TaskItem({
    required this.taskId,
    required this.title,
    required this.status,
    required this.progress,
    required this.lastUpdated,
    required this.action,
    required this.category,
    required this.earnings,
  });
}

class PointsData {
  final int totalPoints;
  final List<PointTransaction> recentTransactions;
  final Map<String, int> dailyPoints;
  final Map<String, int> pointsBySource;
  final double averagePointsPerDay;

  PointsData({
    required this.totalPoints,
    required this.recentTransactions,
    required this.dailyPoints,
    required this.pointsBySource,
    required this.averagePointsPerDay,
  });
}

class PointTransaction {
  final int amount;
  final String reason;
  final DateTime timestamp;
  final String type;
  final String source;

  PointTransaction({
    required this.amount,
    required this.reason,
    required this.timestamp,
    required this.type,
    required this.source,
  });
}

class TranslationData {
  final DateTime date;
  final String sourceLanguage;
  final String targetLanguage;
  final String sourceText;
  final String translatedText;
  final int charactersCount;

  TranslationData({
    required this.date,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.sourceText,
    required this.translatedText,
    required this.charactersCount,
  });
}