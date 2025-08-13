import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp/Add%20Job%20Module/AddJobPage.dart';
import 'package:fyp/Task%20Progress/TaskProgressPage.dart';
import '../Add Job Module/RecurringTaskScheduler.dart';
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
        _processRecurringTasks(), // Process any pending recurring tasks
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

  Future<void> _processRecurringTasks() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final now = DateTime.now();

      // Get all active recurring tasks
      final recurringTasksSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('recurringTasks')
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in recurringTasksSnapshot.docs) {
        final data = doc.data();
        final nextOccurrence = DateTime.tryParse(data['nextOccurrence'] ?? '');

        if (nextOccurrence != null && now.isAfter(nextOccurrence)) {
          await _generateRecurringTaskInstance(doc.id, data);
        }
      }
    } catch (e) {
      print('Error processing recurring tasks: $e');
    }
  }

  Future<void> _generateRecurringTaskInstance(String recurringTaskId, Map<String, dynamic> recurringData) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final originalJobData = recurringData['originalJobData'] as Map<String, dynamic>?;
      if (originalJobData == null) return;

      final now = DateTime.now();
      final frequency = recurringData['frequency'] ?? 'daily';

      // Calculate new dates
      final newStartDate = now.toIso8601String().split('T')[0];
      final originalEndDate = DateTime.tryParse(originalJobData['endDate'] ?? '');
      final daysDifference = originalEndDate != null
          ? originalEndDate.difference(DateTime.parse(originalJobData['startDate'])).inDays
          : 1;
      final newEndDate = now.add(Duration(days: daysDifference)).toIso8601String().split('T')[0];

      // Create new job instance
      final newJobData = Map<String, dynamic>.from(originalJobData);
      newJobData.update('startDate', (value) => newStartDate);
      newJobData.update('endDate', (value) => newEndDate);
      newJobData['postedAt'] = Timestamp.now();
      newJobData['isCompleted'] = false;
      newJobData['applicants'] = [];
      newJobData['acceptedApplicants'] = [];
      newJobData['progressPercentage'] = 0;
      newJobData['isRecurringInstance'] = true;
      newJobData['parentRecurringId'] = recurringTaskId;
      newJobData['recurring'] = false;

      // Add to jobs collection
      final docRef = await FirebaseFirestore.instance.collection('jobs').add(newJobData);
      await docRef.update({'jobId': docRef.id});

      // Create task progress
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(docRef.id)
          .set({
        'taskId': docRef.id,
        'taskTitle': newJobData['jobPosition'] ?? 'Task',
        'currentProgress': 0,
        'milestones': [],
        'createdAt': Timestamp.now(),
        'lastUpdated': Timestamp.now(),
        'status': 'generated',
        'jobCreator': currentUser.uid,
        'canEditProgress': [currentUser.uid],
        'isRecurringInstance': true,
      });

      // Update next occurrence
      final nextOccurrence = _calculateNextOccurrence(now, frequency, recurringData['time'] ?? '09:00');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('recurringTasks')
          .doc(recurringTaskId)
          .update({
        'nextOccurrence': nextOccurrence.toIso8601String(),
        'lastGenerated': Timestamp.now(),
      });

      print('Generated recurring task instance: ${newJobData['jobPosition']}');
    } catch (e) {
      print('Error generating recurring task instance: $e');
    }
  }

  DateTime _calculateNextOccurrence(DateTime from, String frequency, String time) {
    final timeParts = time.split(':');
    final hour = int.tryParse(timeParts[0]) ?? 9;
    final minute = int.tryParse(timeParts[1]) ?? 0;

    DateTime next = from;

    switch (frequency.toLowerCase()) {
      case 'hourly':
        next = next.add(const Duration(hours: 1));
        break;
      case 'daily':
        next = DateTime(next.year, next.month, next.day + 1, hour, minute);
        break;
      case 'weekly':
        next = DateTime(next.year, next.month, next.day + 7, hour, minute);
        break;
      case 'monthly':
        next = DateTime(next.year, next.month + 1, next.day, hour, minute);
        break;
      case 'yearly':
        next = DateTime(next.year + 1, next.month, next.day, hour, minute);
        break;
      default:
        next = DateTime(next.year, next.month, next.day + 1, hour, minute);
    }

    return next;
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
      throw e;
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

  void _editJob(String jobId, Map<String, dynamic> data) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => AddJobPage(jobId: jobId, initialData: data)
        )
    ).then((_) => _loadInitialData()); // Refresh data after edit
  }

  void _deleteJob(String jobId, String jobTitle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Task',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete "$jobTitle"? This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performDeleteJob(jobId, jobTitle);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      case 'critical':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Future<void> _performDeleteJob(String jobId, String jobTitle) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Delete the job document
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(jobId)
          .delete();

      // Delete associated task progress
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('taskProgress')
          .doc(jobId)
          .delete();

      // Delete recurring task if exists
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('recurringTasks')
          .doc(jobId)
          .delete();

      // Log the deletion activity
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('activityLog')
          .add({
        'action': 'Deleted',
        'taskId': jobId,
        'taskTitle': jobTitle,
        'timestamp': Timestamp.now(),
        'details': {
          'reason': 'Manual deletion by user',
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task "$jobTitle" deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh the data
      _loadInitialData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildQuickActionsSection() {
    final actions = [
      {
        'title': 'Tasks Progress',
        'icon': Icons.task,
        'color': Colors.blue,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TaskProgressPage(),
          ),
        ),
      },
      {
        'title': 'Recurring Tasks',
        'icon': Icons.repeat,
        'color': Colors.purple,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RecurringTaskScheduler()),
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
                      final isOwner = data['postedBy'] == currentUser.uid;
                      final isRecurringInstance = data['isRecurringInstance'] ?? false;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      jobPosition,
                                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
                                    ),
                                  ),
                                  // Add priority badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _getPriorityColor(data['priority'] ?? 'Medium').withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: _getPriorityColor(data['priority'] ?? 'Medium')),
                                    ),
                                    child: Text(
                                      data['priority'] ?? 'Medium',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        color: _getPriorityColor(data['priority'] ?? 'Medium'),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (isRecurringInstance)
                                    Container(
                                      margin: const EdgeInsets.only(left: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.purple),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.repeat, size: 12, color: Colors.purple),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Recurring',
                                            style: GoogleFonts.poppins(
                                              fontSize: 10,
                                              color: Colors.purple,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
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
                            // Edit and Delete buttons for owner's tasks
                            if (isOwner)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _editJob(job.id, data),
                                        icon: const Icon(Icons.edit, size: 16),
                                        label: Text(
                                          'Edit',
                                          style: GoogleFonts.poppins(fontSize: 12),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _deleteJob(job.id, jobPosition),
                                        icon: const Icon(Icons.delete, size: 16),
                                        label: Text(
                                          'Delete',
                                          style: GoogleFonts.poppins(fontSize: 12),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
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
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddJobPage())
            ).then((_) => _loadInitialData()), // Refresh after creating new task
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