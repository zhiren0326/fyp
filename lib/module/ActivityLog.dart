import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp/Add%20Job%20Module/AddJobPage.dart';
import '../Add Job Module/RecurringTasksManager.dart';
import '../Add Job Module/TaskDependenciesManager.dart';
import '../Add Job Module/TaskProgressTracker.dart';
import '../Add%20Job%20Module/JobDetailPage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  static const String _geminiApiKey = 'AIzaSyCFdlu9A8pY0FaZEMVaZ7eL-D9XcveMufo';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSkillsFilterEnabled = false;
  bool _isAIPoweredFilterEnabled = false;
  String _userSkills = '';
  List<String> _relatedSkills = [];
  bool isLoading = true;

  // Dashboard stats
  Map<String, dynamic> dashboardStats = {
    'totalTasks': 0,
    'completedTasks': 0,
    'inProgressTasks': 0,
    'overdueTasks': 0,
    'highPriorityTasks': 0,
    'recurringTasks': 0,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tap the + button to create a new task', style: GoogleFonts.poppins()),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.teal,
        ),
      );
      _loadInitialData();
    });
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _fetchUserSkills(),
        _loadTaskStats(),
      ]);
    } catch (e) {
      print('Error loading initial data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e', style: GoogleFonts.poppins()), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchUserSkills() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      DocumentSnapshot skillsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('skills')
          .doc('user_skills')
          .get();

      if (skillsSnapshot.exists) {
        final data = skillsSnapshot.data() as Map<String, dynamic>;
        if (data['skills'] != null) {
          setState(() {
            _userSkills = (data['skills'] as List)
                .map((item) => (item['skill'] ?? 'Unknown Skill').trim())
                .join(', ');
          });
          print('User skills: $_userSkills');
          if (_userSkills.isNotEmpty) await _fetchRelatedSkills();
        }
      }
    } catch (e) {
      print('Error fetching skills: $e');
      throw e; // Propagate error to be caught in _loadInitialData
    }
  }

  Future<void> _fetchRelatedSkills() async {
    if (_geminiApiKey.isEmpty) {
      setState(() => _relatedSkills = _userSkills.toLowerCase().contains('flutter')
          ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python']
          : []);
      print('API key not configured');
      return;
    }

    final isFlutterUser = _userSkills.toLowerCase().contains('flutter');
    final prompt = isFlutterUser
        ? 'For skills: $_userSkills, suggest related coding skills (e.g., Dart, Firebase) as a comma-separated list. Return JSON with "relatedSkills".'
        : 'For skills: $_userSkills, suggest related skills as a comma-separated list. Return JSON with "relatedSkills".';

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$_geminiApiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'contents': [{'parts': [{'text': prompt}]}]}),
        );

        print('Attempt $attempt - Status: ${response.statusCode}, Body: ${response.body}, FlutterUser: $isFlutterUser');
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final content = data['candidates']?[0]['content']['parts'][0]['text'] as String?;
          if (content == null) {
            setState(() => _relatedSkills = isFlutterUser
                ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python']
                : []);
            print('Invalid API response: content null');
            return;
          }
          try {
            final parsed = jsonDecode(content);
            setState(() => _relatedSkills = (parsed['relatedSkills'] as String?)?.split(',').map((s) => s.trim()).toList() ??
                (isFlutterUser ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python'] : []));
            print('Related skills: $_relatedSkills');
            return;
          } catch (e) {
            setState(() => _relatedSkills = isFlutterUser
                ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python']
                : []);
            print('Parse error: $e');
            return;
          }
        } else if (response.statusCode == 401) {
          setState(() => _relatedSkills = isFlutterUser
              ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python']
              : []);
          print('HTTP 401: Invalid API key');
          return;
        } else if (response.statusCode == 429) {
          print('HTTP 429: Rate limit, retrying...');
          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: attempt * 2));
            continue;
          }
          setState(() => _relatedSkills = isFlutterUser
              ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python']
              : []);
          print('Rate limit exceeded after $maxRetries attempts');
          return;
        } else {
          setState(() => _relatedSkills = isFlutterUser
              ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python']
              : []);
          print('HTTP error: ${response.statusCode}');
          return;
        }
      } catch (e) {
        print('Attempt $attempt - Error: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        }
        setState(() => _relatedSkills = isFlutterUser
            ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python']
            : []);
        print('Error after $maxRetries attempts: $e');
        return;
      }
    }
  }

  Future<void> _loadTaskStats() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final jobsSnapshot = await FirebaseFirestore.instance
          .collection('jobs')
          .where('postedBy', isEqualTo: currentUser.uid)
          .get();

      final appliedJobsSnapshot = await FirebaseFirestore.instance
          .collection('jobs')
          .where('applicants', arrayContains: currentUser.uid)
          .get();

      final tasksSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('tasks')
          .get();

      final recurringTasksSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('recurringTasks')
          .get();

      int totalTasks = 0;
      int completedTasks = 0;
      int inProgressTasks = 0;
      int overdueTasks = 0;
      int highPriorityTasks = 0;

      for (var doc in jobsSnapshot.docs) {
        final data = doc.data();
        totalTasks++;
        if (data['isCompleted'] == true) {
          completedTasks++;
        } else {
          inProgressTasks++;
        }
        if (data['priority'] == 'High' || data['priority'] == 'Critical') {
          highPriorityTasks++;
        }
        if (data['endDate'] != null) {
          final endDate = DateTime.tryParse(data['endDate']);
          if (endDate != null && endDate.isBefore(DateTime.now()) && data['isCompleted'] != true) {
            overdueTasks++;
          }
        }
      }

      for (var doc in appliedJobsSnapshot.docs) {
        final data = doc.data();
        final isAccepted = (data['acceptedApplicants'] as List?)?.contains(currentUser.uid) ?? false;
        if (isAccepted) {
          totalTasks++;
          if (data['isCompleted'] == true) {
            completedTasks++;
          } else {
            inProgressTasks++;
          }
          if (data['priority'] == 'High' || data['priority'] == 'Critical') {
            highPriorityTasks++;
          }
          if (data['endDate'] != null) {
            final endDate = DateTime.tryParse(data['endDate']);
            if (endDate != null && endDate.isBefore(DateTime.now()) && data['isCompleted'] != true) {
              overdueTasks++;
            }
          }
        }
      }

      for (var doc in tasksSnapshot.docs) {
        final data = doc.data();
        if (data['tasks'] != null) {
          for (var task in data['tasks']) {
            totalTasks++;
            if (task['completed'] == true) {
              completedTasks++;
            } else {
              inProgressTasks++;
            }
            if (task['priority'] == 'High' || task['priority'] == 'Critical') {
              highPriorityTasks++;
            }
          }
        }
      }

      setState(() {
        dashboardStats = {
          'totalTasks': totalTasks,
          'completedTasks': completedTasks,
          'inProgressTasks': inProgressTasks,
          'overdueTasks': overdueTasks,
          'highPriorityTasks': highPriorityTasks,
          'recurringTasks': recurringTasksSnapshot.docs.length,
        };
      });
    } catch (e) {
      print('Error loading task stats: $e');
      throw e; // Propagate error to be caught in _loadInitialData
    }
  }

  void _editJob(String jobId, Map<String, dynamic> data) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => AddJobPage(jobId: jobId, initialData: data)));
  }

  Widget _buildStatsGrid() {
    final stats = [
      {
        'title': 'Total Tasks',
        'value': '${dashboardStats['totalTasks']}',
        'color': Colors.blue,
        'icon': Icons.assignment,
      },
      {
        'title': 'Completed',
        'value': '${dashboardStats['completedTasks']}',
        'color': Colors.green,
        'icon': Icons.check_circle,
      },
      {
        'title': 'In Progress',
        'value': '${dashboardStats['inProgressTasks']}',
        'color': Colors.orange,
        'icon': Icons.pending,
      },
      {
        'title': 'Overdue',
        'value': '${dashboardStats['overdueTasks']}',
        'color': Colors.red,
        'icon': Icons.warning,
      },
      {
        'title': 'High Priority',
        'value': '${dashboardStats['highPriorityTasks']}',
        'color': Colors.purple,
        'icon': Icons.priority_high,
      },
      {
        'title': 'Recurring',
        'value': '${dashboardStats['recurringTasks']}',
        'color': Colors.teal,
        'icon': Icons.repeat,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final stat = stats[index];
        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  (stat['color'] as Color).withOpacity(0.1),
                  Colors.white,
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  stat['icon'] as IconData,
                  size: 32,
                  color: stat['color'] as Color,
                ),
                const SizedBox(height: 8),
                Text(
                  stat['value'] as String,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: stat['color'] as Color,
                  ),
                ),
                Text(
                  stat['title'] as String,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActionsSection() {
    final actions = [
      {
        'title': 'Progress Tracker',
        'icon': Icons.analytics,
        'color': Colors.blue,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TaskProgressTracker()),
        ),
      },
      {
        'title': 'Dependencies',
        'icon': Icons.account_tree,
        'color': Colors.green,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TaskDependenciesManager()),
        ),
      },
      {
        'title': 'Recurring Tasks',
        'icon': Icons.repeat,
        'color': Colors.purple,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RecurringTasksManager()),
        ),
      },
      {
        'title': 'Refresh Data',
        'icon': Icons.refresh,
        'color': Colors.orange,
        'onTap': _loadInitialData,
      },
    ];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: actions.length,
              itemBuilder: (context, index) {
                final action = actions[index];
                return InkWell(
                  onTap: action['onTap'] as VoidCallback,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (action['color'] as Color).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: action['color'] as Color),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          action['icon'] as IconData,
                          color: action['color'] as Color,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            action['title'] as String,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: action['color'] as Color,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBox({required String title, required int count, required IconData icon, bool isLoading = false, bool error = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading)
            const CircularProgressIndicator(color: Colors.teal, strokeWidth: 2)
          else if (error)
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 24)
          else
            Icon(icon, color: Colors.teal, size: 24),
          const SizedBox(height: 8),
          Text(
            error ? 'Error' : '$count',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: error ? Colors.redAccent : Colors.teal,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please log in.'));

    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

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
        body: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.teal))
            : RefreshIndicator(
          onRefresh: _loadInitialData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back!',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF006D77),
                      ),
                    ),
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(currentUser.uid)
                          .collection('profiledetails')
                          .doc('profile')
                          .snapshots(),
                      builder: (context, snapshot) {
                        String displayName = "User";
                        if (snapshot.hasData && snapshot.data!.exists) {
                          final data = snapshot.data!.data() as Map<String, dynamic>;
                          if (data['name'] != null && data['name'].isNotEmpty) displayName = data['name'];
                        }
                        return Text(
                          'Hello, $displayName',
                          style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.black87),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildStatsGrid(),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildQuickActionsSection(),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.teal, width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Skills',
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.teal),
                        ),
                        const SizedBox(height: 8),
                        _userSkills.isEmpty
                            ? Row(
                          children: [
                            Text(
                              'No skills added. Go to Skills Tags to add skills.',
                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => Navigator.pushNamed(context, '/SkillTagScreen'),
                              child: Text(
                                'Add skills',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.teal,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        )
                            : Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: _userSkills.split(',').map((skill) => ActionChip(
                            label: Text(
                              skill.trim(),
                              style: GoogleFonts.poppins(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                            backgroundColor: Colors.teal,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            onPressed: () => Navigator.pushNamed(context, '/SkillTagScreen'),
                          )).toList(),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/SkillTagScreen'),
                          child: Text(
                            'Manage Skills',
                            style: GoogleFonts.poppins(
                              color: Colors.teal,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    title: Text(
                      'Smart Jobs Suggestions',
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    subtitle: Text(
                      'Show jobs matching all your skills',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: Switch(
                      value: _isSkillsFilterEnabled,
                      onChanged: (value) => setState(() => _isSkillsFilterEnabled = value),
                      activeColor: Colors.teal,
                      activeTrackColor: Colors.teal.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    title: Text(
                      'AI-Powered Suggestions',
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    subtitle: Text(
                      _relatedSkills.isEmpty && _isAIPoweredFilterEnabled
                          ? 'No related skills available. Try adding more skills.'
                          : 'Show jobs matching your skills or related categories',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: _relatedSkills.isEmpty && _isAIPoweredFilterEnabled ? Colors.redAccent : Colors.grey[600],
                      ),
                    ),
                    trailing: Switch(
                      value: _isAIPoweredFilterEnabled,
                      onChanged: (value) => setState(() => _isAIPoweredFilterEnabled = value),
                      activeColor: Colors.teal,
                      activeTrackColor: Colors.teal.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search job title or skill...',
                    prefixIcon: const Icon(Icons.search, color: Colors.teal),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.teal),
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                      }),
                    )
                        : null,
                    hintStyle: GoogleFonts.poppins(color: Colors.grey[600]),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.teal, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.teal, width: 2),
                    ),
                  ),
                  style: GoogleFonts.poppins(color: Colors.black87),
                ),
              ),
             
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('jobs')
                    .orderBy('postedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.teal));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        'No jobs available.',
                        style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
                      ),
                    );
                  }

                  final jobs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final isOwner = data['postedBy'] == currentUser.uid;
                    if (isOwner) return false;
                    final isAccepted = data['acceptedApplicants']?.contains(currentUser.uid) ?? false;
                    final acceptedCount = (data['acceptedApplicants'] as List?)?.length ?? 0;
                    final requiredPeople = data['requiredPeople'] as int? ?? 1;

                    if (acceptedCount >= requiredPeople) return false;

                    final isFull = data['isFull'] ?? false;
                    if (!isFull && !isAccepted) {
                      final jobPosition = data['jobPosition']?.toLowerCase() ?? '';
                      List<String> requiredSkills = [];
                      var skillData = data['requiredSkill'];
                      if (skillData != null) {
                        requiredSkills = skillData is String
                            ? skillData.split(',').map((s) => s.trim().toLowerCase()).toList()
                            : (skillData as List).map((e) => e.toString().toLowerCase()).toList();
                      }

                      bool matchesSmartFilter = true;
                      bool matchesAIFilter = true;

                      if (_isSkillsFilterEnabled && _userSkills.isNotEmpty) {
                        final userSkillsList = _userSkills.split(',').map((s) => s.trim().toLowerCase()).toList();
                        matchesSmartFilter = requiredSkills.isNotEmpty &&
                            requiredSkills.every((skill) => userSkillsList.contains(skill));
                      }

                      if (_isAIPoweredFilterEnabled && _userSkills.isNotEmpty) {
                        final userSkillsList = _userSkills.split(',').map((s) => s.trim().toLowerCase()).toList();
                        final combinedSkills = [...userSkillsList, ..._relatedSkills.map((s) => s.toLowerCase())];
                        matchesAIFilter = requiredSkills.isEmpty || requiredSkills.any((skill) => combinedSkills.contains(skill));
                      }

                      bool matchesSearch = true;
                      if (_searchQuery.isNotEmpty) {
                        final matchesJobPosition = jobPosition.contains(_searchQuery);
                        final matchesSkill = requiredSkills.any((skill) => skill.contains(_searchQuery));
                        matchesSearch = matchesJobPosition || matchesSkill;
                      }

                      if (_isSkillsFilterEnabled && _isAIPoweredFilterEnabled) {
                        return matchesSmartFilter && matchesAIFilter && matchesSearch;
                      } else if (_isSkillsFilterEnabled) {
                        return matchesSmartFilter && matchesSearch;
                      } else if (_isAIPoweredFilterEnabled) {
                        return matchesAIFilter && matchesSearch;
                      }
                      return matchesSearch;
                    }
                    return false;
                  }).toList();

                  if (jobs.isEmpty) {
                    return Center(
                      child: Text(
                        'No jobs available.',
                        style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
                      ),
                    );
                  }

                  return Column(
                    children: jobs.map((job) {
                      final data = job.data() as Map<String, dynamic>;
                      if ((data['jobPosition']?.trim().isEmpty ?? true) && (data['description']?.trim().isEmpty ?? true)) {
                        return const SizedBox.shrink();
                      }
                      final jobPosition = data['jobPosition'] ?? 'N/A';
                      final taskType = data['isShortTerm'] == true ? 'Short-term' : 'Long-term';
                      final startDate = data['startDate'] ?? '-';
                      final startTime = data['isShortTerm'] == true ? (data['startTime'] ?? '-') : '';
                      final salary = data['salary'] ?? 'Not specified';
                      final applicants = data['applicants'] as List? ?? [];
                      final requiredPeople = data['requiredPeople'] ?? 1;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          title: Text(
                            jobPosition,
                            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Task Type: $taskType', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800])),
                              Text('Start Date: $startDate', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800])),
                              if (startTime.isNotEmpty) Text('Start Time: $startTime', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800])),
                              Text('Salary: RM $salary', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800])),
                              if (data['requiredSkill'] != null)
                                Text(
                                  'Skill Required: ${data['requiredSkill'] is String ? (data['requiredSkill'] as String).split(',').join(', ') : (data['requiredSkill'] as List).join(', ')}',
                                  style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800]),
                                ),
                              Text('Applicants: ${applicants.length}/$requiredPeople', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800])),
                            ],
                          ),
                          trailing: applicants.contains(currentUser.uid)
                              ? const Icon(Icons.check_circle, color: Colors.teal)
                              : null,
                          onTap: () {
                            print('Navigating to JobDetailPage with jobId: ${job.id}');
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => JobDetailPage(data: data, jobId: job.id)),
                            ).then((value) => print('Returned from JobDetailPage')).catchError((error) => print('Navigation error: $error'));
                          },
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 100), // Extra space for FAB
            ],
          ),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: FloatingActionButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddJobPage())),
            backgroundColor: Colors.teal,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.add, size: 30),
            tooltip: 'Create a new task',
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}