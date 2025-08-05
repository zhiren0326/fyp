import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Translation History Model
class TranslationHistory {
  final String id;
  final String originalText;
  final String translatedText;
  final String fromLanguage;
  final String toLanguage;
  final DateTime timestamp;
  final String userId;

  TranslationHistory({
    required this.id,
    required this.originalText,
    required this.translatedText,
    required this.fromLanguage,
    required this.toLanguage,
    required this.timestamp,
    required this.userId,
  });

  Map<String, dynamic> toMap() {
    return {
      'originalText': originalText,
      'translatedText': translatedText,
      'fromLanguage': fromLanguage,
      'toLanguage': toLanguage,
      'timestamp': Timestamp.fromDate(timestamp),
      'userId': userId,
    };
  }

  factory TranslationHistory.fromMap(String id, Map<String, dynamic> map) {
    return TranslationHistory(
      id: id,
      originalText: map['originalText'] ?? '',
      translatedText: map['translatedText'] ?? '',
      fromLanguage: map['fromLanguage'] ?? '',
      toLanguage: map['toLanguage'] ?? '',
      timestamp: map['timestamp'] != null
          ? (map['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      userId: map['userId'] ?? '',
    );
  }
}

// Updated Translation Statistics Model
class TranslationStats {
  final int todayCount;
  final int weekCount;
  final int monthCount;
  final int totalCount;
  final String todayDate;
  final String currentTime;

  TranslationStats({
    required this.todayCount,
    required this.weekCount,
    required this.monthCount,
    required this.totalCount,
    required this.todayDate,
    required this.currentTime,
  });
}

class TranslatePasteScreen extends StatefulWidget {
  @override
  _TranslatePasteScreenState createState() => _TranslatePasteScreenState();
}

class _TranslatePasteScreenState extends State<TranslatePasteScreen>
    with TickerProviderStateMixin {
  static const String _geminiApiKey = 'AIzaSyCFdlu9A8pY0FaZEMVaZ7eL-D9XcveMufo';
  static const String _geminiApiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  String _selectedFromLanguage = 'Auto-detect';
  String _selectedToLanguage = 'English';
  bool _isTranslating = false;
  bool _isInitialized = false;
  String? _currentUserId;
  TranslationStats _stats = TranslationStats(
    todayCount: 0,
    weekCount: 0,
    monthCount: 0,
    totalCount: 0,
    todayDate: DateFormat('MMM dd, yyyy').format(DateTime.now()),
    currentTime: DateFormat('HH:mm').format(DateTime.now()),
  );

  // Timer for updating time display
  Timer? _timeUpdateTimer;

  final Map<String, String> _languageCodes = {
    'Auto-detect': 'auto',
    'English': 'en',
    'Spanish': 'es',
    'French': 'fr',
    'German': 'de',
    'Italian': 'it',
    'Portuguese': 'pt',
    'Russian': 'ru',
    'Chinese': 'zh',
    'Japanese': 'ja',
    'Korean': 'ko',
    'Arabic': 'ar',
    'Hindi': 'hi',
    'Dutch': 'nl',
    'Swedish': 'sv',
    'Norwegian': 'no'
  };

  final List<String> _languages = [
    'Auto-detect',
    'English',
    'Spanish',
    'French',
    'German',
    'Italian',
    'Portuguese',
    'Russian',
    'Chinese',
    'Japanese',
    'Korean',
    'Arabic',
    'Hindi',
    'Dutch',
    'Swedish',
    'Norwegian'
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeFirebase();

    // Update time every minute
    _timeUpdateTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {
          _stats = TranslationStats(
            todayCount: _stats.todayCount,
            weekCount: _stats.weekCount,
            monthCount: _stats.monthCount,
            totalCount: _stats.totalCount,
            todayDate: DateFormat('MMM dd, yyyy').format(DateTime.now()),
            currentTime: DateFormat('HH:mm').format(DateTime.now()),
          );
        });
      }
    });
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _fadeController.forward();
    _scaleController.forward();
  }

  Future<void> _initializeFirebase() async {
    try {
      print('Initializing Firebase...');

      // Check if user is already signed in
      User? currentUser = _auth.currentUser;

      if (currentUser == null) {
        print('No current user, signing in anonymously...');
        UserCredential userCredential = await _auth.signInAnonymously();
        currentUser = userCredential.user;
        print('Anonymous sign in successful: ${currentUser?.uid}');
      } else {
        print('Current user exists: ${currentUser.uid}');
      }

      if (currentUser != null) {
        setState(() {
          _currentUserId = currentUser!.uid;
          _isInitialized = true;
        });
        print('Firebase initialized successfully with user: $_currentUserId');
        await _loadStats();
      }
    } catch (e) {
      print('Firebase initialization error: $e');
      _showSnackBar('Firebase initialization failed: $e', Colors.red);
      // Still allow the app to work without Firebase
      setState(() {
        _isInitialized = true;
      });
    }
  }

  Future<void> _loadStats() async {
    if (_currentUserId == null) {
      print('No user ID available for loading stats');
      return;
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day); // Start of today (00:00:00)
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59); // End of today (23:59:59)
    final weekStart = now.subtract(Duration(days: 7));
    final monthStart = DateTime(now.year, now.month, 1); // Start of current month

    try {
      print('Loading stats for user: $_currentUserId');

      // Try the optimized query first
      QuerySnapshot querySnapshot;
      try {
        querySnapshot = await _firestore
            .collection('translations')
            .where('userId', isEqualTo: _currentUserId)
            .orderBy('timestamp', descending: true)
            .get();
      } catch (indexError) {
        // Fallback to query without orderBy if index doesn't exist
        print('Index not available, using fallback query: $indexError');
        querySnapshot = await _firestore
            .collection('translations')
            .where('userId', isEqualTo: _currentUserId)
            .get();
      }

      print('Found ${querySnapshot.docs.length} translation records');

      int todayCount = 0;
      int weekCount = 0;
      int monthCount = 0;
      int totalCount = querySnapshot.docs.length;

      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = data['timestamp'] != null
            ? (data['timestamp'] as Timestamp).toDate()
            : DateTime.now();

        // Count for today (between start and end of today)
        if (timestamp.isAfter(todayStart.subtract(Duration(milliseconds: 1))) &&
            timestamp.isBefore(todayEnd.add(Duration(milliseconds: 1)))) {
          todayCount++;
          print('Today translation found: ${DateFormat('HH:mm:ss').format(timestamp)}');
        }

        // Count for this week (last 7 days)
        if (timestamp.isAfter(weekStart)) {
          weekCount++;
        }

        // Count for this month
        if (timestamp.isAfter(monthStart.subtract(Duration(milliseconds: 1)))) {
          monthCount++;
        }
      }

      setState(() {
        _stats = TranslationStats(
          todayCount: todayCount,
          weekCount: weekCount,
          monthCount: monthCount,
          totalCount: totalCount,
          todayDate: DateFormat('MMM dd, yyyy').format(now),
          currentTime: DateFormat('HH:mm').format(now),
        );
      });

      print('Stats loaded: Today: $todayCount, Week: $weekCount, Month: $monthCount, Total: $totalCount');
    } catch (e) {
      print('Error loading stats: $e');
      _showSnackBar('Failed to load statistics', Colors.orange);
    }
  }

  Future<void> _saveTranslationHistory(String originalText, String translatedText) async {
    if (_currentUserId == null) {
      print('No user ID available for saving translation');
      _showSnackBar('Unable to save translation history', Colors.orange);
      return;
    }

    try {
      print('Saving translation history...');

      final history = TranslationHistory(
        id: '',
        originalText: originalText,
        translatedText: translatedText,
        fromLanguage: _selectedFromLanguage,
        toLanguage: _selectedToLanguage,
        timestamp: DateTime.now(), // Use current time
        userId: _currentUserId!,
      );

      DocumentReference docRef = await _firestore
          .collection('translations')
          .add(history.toMap());

      print('Translation saved with ID: ${docRef.id}');

      // Immediately refresh stats to show updated count
      await _loadStats();

      // Force UI update
      setState(() {});

    } catch (e) {
      print('Error saving translation history: $e');
      _showSnackBar('Failed to save translation history: $e', Colors.red);
    }
  }

  @override
  void dispose() {
    _timeUpdateTimer?.cancel();
    _fadeController.dispose();
    _scaleController.dispose();
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      ClipboardData? data = await Clipboard.getData('text/plain');
      if (data != null && data.text != null) {
        setState(() {
          _inputController.text = data.text!;
        });
        _showSnackBar('Text pasted successfully!', Colors.green);
      } else {
        _showSnackBar('No text found in clipboard', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('Failed to paste from clipboard', Colors.red);
    }
  }

  Future<void> _copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      _showSnackBar('Translation copied to clipboard!', Colors.green);
    } catch (e) {
      _showSnackBar('Failed to copy to clipboard', Colors.red);
    }
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

  Future<String> _translateWithGemini(String text, String fromLang, String toLang) async {
    try {
      String prompt;
      if (fromLang == 'auto') {
        prompt = '''Translate the following text to $_selectedToLanguage. Only return the translation, nothing else:

"$text"''';
      } else {
        prompt = '''Translate the following text from $_selectedFromLanguage to $_selectedToLanguage. Only return the translation, nothing else:

"$text"''';
      }

      final response = await http.post(
        Uri.parse('$_geminiApiUrl?key=$_geminiApiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'contents': [{
            'parts': [{
              'text': prompt
            }]
          }],
          'generationConfig': {
            'temperature': 0.1,
            'topK': 1,
            'topP': 1,
            'maxOutputTokens': 2048,
          },
          'safetySettings': [
            {
              'category': 'HARM_CATEGORY_HARASSMENT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_HATE_SPEECH',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          final translatedText = data['candidates'][0]['content']['parts'][0]['text'];
          return translatedText.trim().replaceAll('"', '');
        } else {
          throw Exception('No translation generated');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception('API Error: ${errorData['error']['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      print('Translation error: $e');
      throw Exception('Failed to translate: $e');
    }
  }

  Future<void> _translateText() async {
    if (_inputController.text.trim().isEmpty) {
      _showSnackBar('Please enter text to translate', Colors.orange);
      return;
    }

    setState(() {
      _isTranslating = true;
    });

    try {
      String fromLangCode = _languageCodes[_selectedFromLanguage] ?? 'auto';
      String toLangCode = _languageCodes[_selectedToLanguage] ?? 'en';

      String translatedText = await _translateWithGemini(
        _inputController.text.trim(),
        fromLangCode,
        toLangCode,
      );

      setState(() {
        _outputController.text = translatedText;
        _isTranslating = false;
      });

      // Save to Firebase (only if initialized)
      if (_isInitialized && _currentUserId != null) {
        await _saveTranslationHistory(_inputController.text.trim(), translatedText);
      }

      _showSnackBar('Translation completed!', Colors.green);
    } catch (e) {
      setState(() {
        _isTranslating = false;
      });
      _showSnackBar('Translation failed: ${e.toString()}', Colors.red);
      print('Translation error: $e');
    }
  }

  void _swapLanguages() {
    if (_selectedFromLanguage != 'Auto-detect') {
      setState(() {
        String temp = _selectedFromLanguage;
        _selectedFromLanguage = _selectedToLanguage;
        _selectedToLanguage = temp;

        // Swap text content too
        String tempText = _inputController.text;
        _inputController.text = _outputController.text;
        _outputController.text = tempText;
      });
    }
  }

  void _showHistoryScreen() {
    if (!_isInitialized || _currentUserId == null) {
      _showSnackBar('History not available - Firebase not initialized', Colors.orange);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TranslationHistoryScreen(userId: _currentUserId!),
      ),
    );
  }

  void _showStatsScreen() {
    if (!_isInitialized || _currentUserId == null) {
      _showSnackBar('Statistics not available - Firebase not initialized', Colors.orange);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TranslationStatsScreen(userId: _currentUserId!),
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
                Icons.analytics,
                color: Colors.white,
                size: 20,
              ),
            ),
            onPressed: _showStatsScreen,
          ),
          IconButton(
            icon: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Icon(
                    Icons.history,
                    color: Colors.white,
                    size: 20,
                  ),
                  if (!_isInitialized)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            onPressed: _showHistoryScreen,
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
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                children: [
                  _buildHeader(),
                  _buildStatsBar(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildLanguageSelector(),
                          SizedBox(height: 24),
                          _buildInputSection(),
                          SizedBox(height: 20),
                          _buildTranslateButton(),
                          SizedBox(height: 20),
                          _buildOutputSection(),
                        ],
                      ),
                    ),
                  ),
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
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.translate,
              color: Colors.white,
              size: 28,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Translate Paste',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'Paste and translate instantly',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isInitialized
                            ? Colors.green.withOpacity(0.8)
                            : Colors.orange.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _isInitialized ? 'Live' : 'Offline',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Date and Time Header
          Container(
            padding: EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  _stats.todayDate,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 16),
                Icon(Icons.access_time, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  _stats.currentTime,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Stats Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Today', _stats.todayCount.toString()),
              _buildStatItem('Week', _stats.weekCount.toString()),
              _buildStatItem('Month', _stats.monthCount.toString()),
              _buildStatItem('Total', _stats.totalCount.toString()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageSelector() {
    return Container(
      padding: EdgeInsets.all(4),
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
          Expanded(child: _buildLanguageDropdown(_selectedFromLanguage, true)),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 8),
            child: GestureDetector(
              onTap: _swapLanguages,
              child: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFF667eea).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.swap_horiz,
                  color: Color(0xFF667eea),
                  size: 24,
                ),
              ),
            ),
          ),
          Expanded(child: _buildLanguageDropdown(_selectedToLanguage, false)),
        ],
      ),
    );
  }

  Widget _buildLanguageDropdown(String selectedLanguage, bool isFrom) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedLanguage,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: Color(0xFF667eea)),
          style: TextStyle(
            color: Color(0xFF333333),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          items: _languages.map((String language) {
            if (!isFrom && language == 'Auto-detect') return null;
            return DropdownMenuItem<String>(
              value: language,
              child: Text(language),
            );
          }).where((item) => item != null).cast<DropdownMenuItem<String>>().toList(),
          onChanged: (String? newValue) {
            setState(() {
              if (isFrom) {
                _selectedFromLanguage = newValue!;
              } else {
                _selectedToLanguage = newValue!;
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Container(
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
          Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.edit, color: Color(0xFF667eea)),
                SizedBox(width: 8),
                Text(
                  'Enter text to translate',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                Spacer(),
                GestureDetector(
                  onTap: _pasteFromClipboard,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Color(0xFF667eea).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.paste, size: 16, color: Color(0xFF667eea)),
                        SizedBox(width: 4),
                        Text(
                          'Paste',
                          style: TextStyle(
                            color: Color(0xFF667eea),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: TextField(
              controller: _inputController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Paste or type your text here...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: EdgeInsets.all(16),
              ),
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslateButton() {
    return Container(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isTranslating ? null : _translateText,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF667eea),
          elevation: 8,
          shadowColor: Colors.black.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isTranslating
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
              'Translating...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.translate, size: 20),
            SizedBox(width: 8),
            Text(
              'Translate',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputSection() {
    return Container(
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
          Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.translate, color: Color(0xFF667eea)),
                SizedBox(width: 8),
                Text(
                  'Translation',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                Spacer(),
                if (_outputController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () => _copyToClipboard(_outputController.text),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Color(0xFF667eea).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy, size: 16, color: Color(0xFF667eea)),
                          SizedBox(width: 4),
                          Text(
                            'Copy',
                            style: TextStyle(
                              color: Color(0xFF667eea),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: TextField(
              controller: _outputController,
              maxLines: 5,
              readOnly: true,
              decoration: InputDecoration(
                hintText: 'Translation will appear here...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: EdgeInsets.all(16),
              ),
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// Translation History Screen
class TranslationHistoryScreen extends StatelessWidget {
  final String userId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  TranslationHistoryScreen({required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('Translation History'),
          backgroundColor: Color(0xFF667eea),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: Icon(Icons.delete_sweep),
              onPressed: () => _showClearHistoryDialog(context),
            ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('translations')
              .where('userId', isEqualTo: userId)
          // .orderBy('timestamp', descending: true)  // Comment out temporarily
              .limit(100)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(child: Text('No translation history yet'));
            }

            // Sort the data in Dart instead of Firestore (temporary solution)
            var docs = snapshot.data!.docs.toList();
            docs.sort((a, b) {
              final timestampA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
              final timestampB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;

              if (timestampA == null || timestampB == null) return 0;
              return timestampB.compareTo(timestampA); // Descending order
            });

            return ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;

                try {
                  final history = TranslationHistory.fromMap(doc.id, data);
                  return _buildHistoryCard(context, history, doc.id);
                } catch (e) {
                  return Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Error loading translation', style: TextStyle(color: Colors.red)),
                    ),
                  );
                }
              },
            );
          },
        )
    );
  }

  Widget _buildHistoryCard(BuildContext context, TranslationHistory history, String docId) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.translate, color: Color(0xFF667eea), size: 20),
                SizedBox(width: 8),
                Text(
                  '${history.fromLanguage} → ${history.toLanguage}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF667eea),
                  ),
                ),
                Spacer(),
                Text(
                  DateFormat('MMM dd, HH:mm').format(history.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Original:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    history.originalText,
                    style: TextStyle(fontSize: 14),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Translation:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    history.translatedText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: history.translatedText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Translation copied!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  icon: Icon(Icons.copy, size: 16),
                  label: Text('Copy'),
                  style: TextButton.styleFrom(
                    foregroundColor: Color(0xFF667eea),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _deleteTranslation(context, docId),
                  icon: Icon(Icons.delete, size: 16),
                  label: Text('Delete'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _deleteTranslation(BuildContext context, String docId) async {
    try {
      await _firestore.collection('translations').doc(docId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Translation deleted'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete translation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showClearHistoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Clear History'),
          content: Text('Are you sure you want to delete all translation history? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _clearAllHistory(context);
              },
              child: Text('Clear All', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _clearAllHistory(BuildContext context) async {
    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('translations')
          .where('userId', isEqualTo: userId)
          .get();

      final batch = _firestore.batch();
      for (DocumentSnapshot doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('All history cleared'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to clear history'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Updated Translation Statistics Screen
class TranslationStatsScreen extends StatelessWidget {
  final String userId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  TranslationStatsScreen({required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Translation Statistics'),
        backgroundColor: Color(0xFF667eea),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              // Trigger refresh by rebuilding the widget
              (context as Element).markNeedsBuild();
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('translations')
            .where('userId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF667eea)),
                  SizedBox(height: 16),
                  Text('Loading statistics...'),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    'Error loading statistics',
                    style: TextStyle(fontSize: 18, color: Colors.red),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.analytics,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No translation data yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Start translating to see statistics',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          // Calculate detailed time-based statistics
          final docs = snapshot.data!.docs;
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);
          final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
          final yesterdayStart = DateTime(now.year, now.month, now.day - 1);
          final yesterdayEnd = DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
          final thisWeekStart = now.subtract(Duration(days: 7));
          final thisMonthStart = DateTime(now.year, now.month, 1);
          final thisYearStart = DateTime(now.year, 1, 1);

          int todayCount = 0;
          int yesterdayCount = 0;
          int weekCount = 0;
          int monthCount = 0;
          int yearCount = 0;
          Map<String, int> languagePairs = {};
          Map<String, int> dailyData = {};
          Map<int, int> hourlyData = {}; // Hour of day (0-23) -> count

          // Initialize hourly data
          for (int i = 0; i < 24; i++) {
            hourlyData[i] = 0;
          }

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final timestamp = data['timestamp'] != null
                ? (data['timestamp'] as Timestamp).toDate()
                : DateTime.now();
            final fromLang = data['fromLanguage'] ?? 'Unknown';
            final toLang = data['toLanguage'] ?? 'Unknown';

            // Today's count
            if (timestamp.isAfter(todayStart.subtract(Duration(milliseconds: 1))) &&
                timestamp.isBefore(todayEnd.add(Duration(milliseconds: 1)))) {
              todayCount++;
              // Track hourly distribution for today
              hourlyData[timestamp.hour] = (hourlyData[timestamp.hour] ?? 0) + 1;
            }

            // Yesterday's count
            if (timestamp.isAfter(yesterdayStart.subtract(Duration(milliseconds: 1))) &&
                timestamp.isBefore(yesterdayEnd.add(Duration(milliseconds: 1)))) {
              yesterdayCount++;
            }

            // This week
            if (timestamp.isAfter(thisWeekStart)) {
              weekCount++;
            }

            // This month
            if (timestamp.isAfter(thisMonthStart.subtract(Duration(milliseconds: 1)))) {
              monthCount++;
            }

            // This year
            if (timestamp.isAfter(thisYearStart.subtract(Duration(milliseconds: 1)))) {
              yearCount++;
            }

            // Language pair statistics
            String pair = '$fromLang → $toLang';
            languagePairs[pair] = (languagePairs[pair] ?? 0) + 1;

            // Daily data for the last 7 days
            if (timestamp.isAfter(thisWeekStart)) {
              String dayKey = DateFormat('MMM dd').format(timestamp);
              dailyData[dayKey] = (dailyData[dayKey] ?? 0) + 1;
            }
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current Time Header
                _buildTimeHeader(now),
                SizedBox(height: 24),

                // Today vs Yesterday Comparison
                _buildComparisonCards(todayCount, yesterdayCount),
                SizedBox(height: 24),

                // Time-based Overview Cards
                Row(
                  children: [
                    Expanded(child: _buildStatCard('This Week', weekCount.toString(), Icons.date_range, Colors.green)),
                    SizedBox(width: 12),
                    Expanded(child: _buildStatCard('This Month', monthCount.toString(), Icons.calendar_month, Colors.orange)),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildStatCard('This Year', yearCount.toString(), Icons.calendar_today, Colors.purple)),
                    SizedBox(width: 12),
                    Expanded(child: _buildStatCard('All Time', docs.length.toString(), Icons.all_inclusive, Colors.indigo)),
                  ],
                ),
                SizedBox(height: 24),

                // Today's Hourly Activity
                if (todayCount > 0) ...[
                  Text(
                    'Today\'s Activity by Hour',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 12),
                  _buildHourlyActivityTable(hourlyData),
                  SizedBox(height: 24),
                ],

                // Last 7 Days Activity
                if (dailyData.isNotEmpty) ...[
                  Text(
                    'Last 7 Days Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 12),
                  _buildDailyActivityTable(dailyData),
                  SizedBox(height: 24),
                ],

                // Language Pairs
                if (languagePairs.isNotEmpty) ...[
                  Text(
                    'Most Used Language Pairs',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 12),
                  _buildLanguagePairsTable(languagePairs),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeHeader(DateTime now) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.access_time, color: Colors.white, size: 24),
          SizedBox(width: 12),
          Column(
            children: [
              Text(
                DateFormat('EEEE, MMMM dd, yyyy').format(now),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                DateFormat('HH:mm:ss').format(now),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCards(int todayCount, int yesterdayCount) {
    int difference = todayCount - yesterdayCount;
    bool isPositive = difference >= 0;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              children: [
                Text(
                  'Today',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  todayCount.toString(),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  DateFormat('MMM dd').format(DateTime.now()),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Text(
                  'Yesterday',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  yesterdayCount.toString(),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isPositive ? Icons.trending_up : Icons.trending_down,
                      color: isPositive ? Colors.green : Colors.red,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '${isPositive ? '+' : ''}$difference',
                      style: TextStyle(
                        fontSize: 12,
                        color: isPositive ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHourlyActivityTable(Map<int, int> hourlyData) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Translations by Hour (Today)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
          ),
          Container(
            height: 200,
            padding: EdgeInsets.all(16),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 1.5,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: 24,
              itemBuilder: (context, index) {
                int count = hourlyData[index] ?? 0;
                return Container(
                  decoration: BoxDecoration(
                    color: count > 0 ? Color(0xFF667eea).withOpacity(0.1 + (count * 0.1)) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: count > 0 ? Color(0xFF667eea) : Colors.grey.shade300,
                      width: count > 0 ? 1.5 : 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${index.toString().padLeft(2, '0')}:00',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: count > 0 ? Color(0xFF667eea) : Colors.grey.shade600,
                        ),
                      ),
                      if (count > 0)
                        Text(
                          count.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF667eea),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyActivityTable(Map<String, int> dailyData) {
    final sortedDays = dailyData.entries.toList()
      ..sort((a, b) {
        try {
          final dateA = DateFormat('MMM dd').parse(a.key);
          final dateB = DateFormat('MMM dd').parse(b.key);
          return dateA.compareTo(dateB);
        } catch (e) {
          return 0;
        }
      });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Table(
            columnWidths: {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
            },
            children: [
              _buildTableRow('Day', 'Translations', isHeader: true),
              ...sortedDays.map((entry) => _buildTableRow(entry.key, entry.value.toString())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLanguagePairsTable(Map<String, int> languagePairs) {
    final sortedPairs = languagePairs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topPairs = sortedPairs.take(10).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Table(
            columnWidths: {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
            },
            children: [
              _buildTableRow('Language Pair', 'Count', isHeader: true),
              ...topPairs.map((entry) => _buildTableRow(entry.key, entry.value.toString())),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _buildTableRow(String col1, String col2, {bool isHeader = false, bool isTotal = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: isHeader
            ? Color(0xFF667eea).withOpacity(0.1)
            : isTotal
            ? Colors.grey[100]
            : Colors.transparent,
      ),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            col1,
            style: TextStyle(
              fontWeight: isHeader || isTotal ? FontWeight.bold : FontWeight.normal,
              color: isHeader ? Color(0xFF667eea) : Color(0xFF333333),
              fontSize: isHeader ? 14 : 13,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            col2,
            style: TextStyle(
              fontWeight: isHeader || isTotal ? FontWeight.bold : FontWeight.normal,
              color: isHeader ? Color(0xFF667eea) : Color(0xFF333333),
              fontSize: isHeader ? 14 : 13,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}