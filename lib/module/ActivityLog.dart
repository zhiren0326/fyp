import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp/Add%20Job%20Module/AddJobPage.dart';
import '../Add Job Module/JobDetailPage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

final TextEditingController _searchController = TextEditingController();
String _searchQuery = '';

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  static const String _geminiApiKey = 'AIzaSyCFdlu9A8pY0FaZEMVaZ7eL-D9XcveMufo'; // Hardcoded Gemini API key
  bool _isSkillsFilterEnabled = false; // Tracks smart job suggestions filter
  bool _isAIPoweredFilterEnabled = false; // Tracks AI-powered suggestions filter
  String _userSkills = ''; // Stores user's skills as a comma-separated string
  List<String> _relatedSkills = []; // Stores AI-generated related skills

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tap the + button to create a new task',
            style: GoogleFonts.poppins(),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.teal,
        ),
      );
      _fetchUserSkills(); // Fetch user skills on init
    });
  }

  // Fetch user skills from Firestore at users/{uid}/skills/user_skills
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
                .map((item) => (item['skill'] ?? 'Unknown Skill').toString().trim())
                .join(', ');
          });
          print('User skills: $_userSkills'); // Debug log
          // Fetch related skills based on user skills
          if (_userSkills.isNotEmpty) {
            _fetchRelatedSkills();
          }
        }
      }
    } catch (e) {
      print('Error fetching skills: $e'); // Debug log
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error fetching skills: $e',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // Fetch AI-generated related skills using Gemini API
  Future<void> _fetchRelatedSkills() async {
    if (_geminiApiKey.isEmpty) {
      setState(() {
        _relatedSkills = _userSkills.toLowerCase().contains('flutter')
            ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python'] // Fallback for Flutter users
            : [];
      });
      print('API key not configured'); // Debug log
      return;
    }

    // Check if user has Flutter skill for coding-specific prompt
    final isFlutterUser = _userSkills.toLowerCase().contains('flutter');
    final prompt = isFlutterUser
        ? 'For a user with skills: $_userSkills, provide related coding skills (e.g., Dart, Firebase, Android, Java, Kotlin, Python) as a comma-separated list. '
        'Return JSON with key "relatedSkills".'
        : 'For a user with skills: $_userSkills, provide related skills in the same category as a comma-separated list. '
        'Return JSON with key "relatedSkills".';

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$_geminiApiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ]
          }),
        );

        print('Attempt $attempt - API response status: ${response.statusCode}'); // Debug log
        print('Attempt $attempt - API response body: ${response.body}'); // Debug log
        print('Using Flutter-specific prompt: $isFlutterUser'); // Debug log

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final content = data['candidates']?[0]['content']['parts'][0]['text'] as String?;
          if (content == null) {
            setState(() {
              _relatedSkills = isFlutterUser
                  ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python'] // Fallback for Flutter users
                  : [];
            });
            print('Invalid API response: content is null'); // Debug log
            return;
          }
          try {
            final parsed = jsonDecode(content);
            setState(() {
              _relatedSkills = (parsed['relatedSkills'] as String?)?.split(',').map((s) => s.trim()).toList() ??
                  (isFlutterUser ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python'] : []);
            });
            print('Related skills: $_relatedSkills'); // Debug log
            return; // Success, exit retry loop
          } catch (e) {
            setState(() {
              _relatedSkills = isFlutterUser
                  ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python'] // Fallback for Flutter users
                  : [];
            });
            print('Error parsing API response: $e'); // Debug log
            return;
          }
        } else if (response.statusCode == 401) {
          setState(() {
            _relatedSkills = isFlutterUser
                ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python'] // Fallback for Flutter users
                : [];
          });
          print('HTTP 401: Invalid API key'); // Debug log
          return;
        } else if (response.statusCode == 429) {
          print('HTTP 429: Rate limit exceeded, retrying...'); // Debug log
          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: attempt * 2)); // Exponential backoff
            continue;
          }
          setState(() {
            _relatedSkills = isFlutterUser
                ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python'] // Fallback for Flutter users
                : [];
          });
          print('HTTP 429: Rate limit exceeded after $maxRetries attempts'); // Debug log
          return;
        } else {
          setState(() {
            _relatedSkills = isFlutterUser
                ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python'] // Fallback for Flutter users
                : [];
          });
          print('HTTP error: ${response.statusCode}'); // Debug log
          return;
        }
      } catch (e) {
        print('Attempt $attempt - Error fetching related skills: $e'); // Debug log
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2)); // Exponential backoff
          continue;
        }
        setState(() {
          _relatedSkills = isFlutterUser
              ? ['Dart', 'Firebase', 'Android', 'Java', 'Kotlin', 'Python'] // Fallback for Flutter users
              : [];
        });
        print('Error fetching related skills after $maxRetries attempts: $e'); // Debug log
        return;
      }
    }
  }

  void _editJob(String jobId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddJobPage(jobId: jobId, initialData: data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB2DFDB), Colors.white], // Teal to white gradient
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'Activity',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            // User Greeting
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUser!.uid)
                    .collection('profiledetails')
                    .doc('profile')
                    .snapshots(),
                builder: (context, snapshot) {
                  String displayName = "User";
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    if (data['name'] != null && data['name'].toString().isNotEmpty) {
                      displayName = data['name'];
                    }
                  }
                  return Text(
                    'Hello, $displayName',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Display Aktivity

            // Display User Skills
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
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _userSkills.isEmpty
                          ? Row(
                        children: [
                          Text(
                            'No skills added. Go to Skills Tags to add skills.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              Navigator.pushNamed(context, '/SkillTagScreen');
                            },
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
                        children: _userSkills
                            .split(',')
                            .map((skill) => ActionChip(
                          label: Text(
                            skill.trim(),
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          backgroundColor: Colors.teal,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          onPressed: () {
                            Navigator.pushNamed(context, '/SkillTagScreen');
                          },
                        ))
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/SkillTagScreen');
                        },
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
            // Smart Jobs Suggestions Toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  title: Text(
                    'Smart Jobs Suggestions',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    'Show jobs matching all your skills',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  trailing: Switch(
                    value: _isSkillsFilterEnabled,
                    onChanged: (value) {
                      setState(() {
                        _isSkillsFilterEnabled = value;
                      });
                    },
                    activeColor: Colors.teal,
                    activeTrackColor: Colors.teal.withOpacity(0.3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // AI-Powered Suggestions Toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  title: Text(
                    'AI-Powered Suggestions',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
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
                    onChanged: (value) {
                      setState(() {
                        _isAIPoweredFilterEnabled = value;
                      });
                    },
                    activeColor: Colors.teal,
                    activeTrackColor: Colors.teal.withOpacity(0.3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search job title or skill...',
                  prefixIcon: const Icon(Icons.search, color: Colors.teal),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.teal),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    },
                  )
                      : null,
                  hintStyle: GoogleFonts.poppins(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
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
            // Recently Added Jobs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Recently Added Jobs',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 8),
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
                  final isAccepted = data['isAccepted'] == true;
                  final isOwner = data['postedBy'] == currentUser!.uid;
                  if (isAccepted || isOwner) return false; // Exclude accepted jobs and jobs posted by the current user

                  final jobPosition = data['jobPosition']?.toString().toLowerCase() ?? '';
                  List<String> requiredSkills = [];
                  var skillData = data['requiredSkill'];
                  if (skillData != null) {
                    requiredSkills = skillData is String
                        ? skillData.split(',').map((s) => s.trim().toLowerCase()).toList()
                        : (skillData as List).map((e) => e.toString().toLowerCase()).toList();
                  }

                  bool matchesSmartFilter = true;
                  bool matchesAIFilter = true;

                  // Apply smart jobs filter if enabled
                  if (_isSkillsFilterEnabled && _userSkills.isNotEmpty) {
                    final userSkillsList = _userSkills.split(',').map((s) => s.trim().toLowerCase()).toList();
                    matchesSmartFilter = requiredSkills.isNotEmpty && requiredSkills.every((skill) => userSkillsList.contains(skill));
                  }

                  // Apply AI-powered filter if enabled
                  if (_isAIPoweredFilterEnabled && _userSkills.isNotEmpty) {
                    final userSkillsList = _userSkills.split(',').map((s) => s.trim().toLowerCase()).toList();
                    final combinedSkills = [...userSkillsList, ..._relatedSkills.map((s) => s.toLowerCase())];
                    matchesAIFilter = requiredSkills.isEmpty || requiredSkills.any((skill) => combinedSkills.contains(skill));
                  }

                  // Apply search query filter
                  bool matchesSearch = true;
                  if (_searchQuery.isNotEmpty) {
                    final matchesJobPosition = jobPosition.contains(_searchQuery);
                    final matchesSkill = requiredSkills.any((skill) => skill.contains(_searchQuery));
                    matchesSearch = matchesJobPosition || matchesSkill;
                  }

                  // Include job if it matches the enabled filters and search query
                  if (_isSkillsFilterEnabled && _isAIPoweredFilterEnabled) {
                    return matchesSmartFilter && matchesAIFilter && matchesSearch;
                  } else if (_isSkillsFilterEnabled) {
                    return matchesSmartFilter && matchesSearch;
                  } else if (_isAIPoweredFilterEnabled) {
                    return matchesAIFilter && matchesSearch;
                  }
                  return matchesSearch;
                }).toList();

                return Column(
                  children: jobs.map((job) {
                    final data = job.data() as Map<String, dynamic>;
                    if ((data['jobPosition'] == null || data['jobPosition'].toString().trim().isEmpty) &&
                        (data['description'] == null || data['description'].toString().trim().isEmpty)) {
                      return const SizedBox.shrink();
                    }
                    final jobPosition = data['jobPosition'] ?? 'N/A';
                    final taskType = data['isShortTerm'] == true ? 'Short-term' : 'Long-term';
                    final startDate = data['startDate'] ?? '-';
                    final startTime = data['isShortTerm'] == true ? (data['startTime'] ?? '-') : '';
                    final salary = data['salary'] ?? 'Not specified';

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        title: Text(
                          jobPosition,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Task Type: $taskType',
                              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800]),
                            ),
                            Text(
                              'Start Date: $startDate',
                              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800]),
                            ),
                            if (startTime.isNotEmpty)
                              Text(
                                'Start Time: $startTime',
                                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800]),
                              ),
                            Text(
                              'Salary: RM $salary',
                              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800]),
                            ),
                            if (data['requiredSkill'] != null)
                              Text(
                                'Skill Required: ${data['requiredSkill'] is String ? (data['requiredSkill'] as String).split(',').join(', ') : (data['requiredSkill'] as List).join(', ')}',
                                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800]),
                              ),
                          ],
                        ),
                        onTap: () {
                          print('Navigating to JobDetailPage with jobId: ${job.id}');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => JobDetailPage(data: data, jobId: job.id),
                            ),
                          ).then((value) {
                            print('Returned from JobDetailPage');
                          }).catchError((error) {
                            print('Navigation error: $error');
                          });
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: FloatingActionButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AddJobPage()),
              );
            },
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
}