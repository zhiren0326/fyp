import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp/Add%20Job%20Module/AddJobPage.dart';
import '../Add Job Module/JobDetailPage.dart';
import 'package:google_fonts/google_fonts.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

final TextEditingController _searchController = TextEditingController();
String _searchQuery = '';

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tap the + button to create a new task'),
          duration: Duration(seconds: 2),
        ),
      );
    });
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
          padding: const EdgeInsets.only(top: 20, bottom: 80),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
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
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Hello, $displayName',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        color: Colors.black,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search job title or skill...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    },
                  )
                      : null,
                  hintStyle: GoogleFonts.poppins(),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: GoogleFonts.poppins(),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Text(
                'Recently Added Jobs',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('jobs')
                  .orderBy('postedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No jobs available."));
                }
                final jobs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final isAccepted = data['isAccepted'] == true;
                  if (isAccepted) return false; // Exclude accepted jobs
                  final jobPosition = data['jobPosition']?.toString().toLowerCase() ?? '';
                  List<String> requiredSkills = [];
                  var skillData = data['requiredSkill'];
                  if (skillData != null) {
                    if (skillData is String) {
                      requiredSkills = skillData.split(',').map((s) => s.trim().toLowerCase()).toList();
                    } else if (skillData is List) {
                      requiredSkills = (skillData as List<dynamic>).map((e) => e.toString().toLowerCase()).toList();
                    }
                  }
                  if (_searchQuery.isEmpty) {
                    return true;
                  }
                  final matchesJobPosition = jobPosition.contains(_searchQuery);
                  final matchesSkill = requiredSkills.any((skill) => skill.contains(_searchQuery));
                  return matchesJobPosition || matchesSkill;
                }).toList();
                return Column(
                  children: jobs.map((job) {
                    final data = job.data() as Map<String, dynamic>;
                    if ((data['jobPosition'] == null || data['jobPosition'].toString().trim().isEmpty) &&
                        (data['description'] == null || data['description'].toString().trim().isEmpty)) {
                      return const SizedBox.shrink();
                    }
                    final isOwner = data['postedBy'] == currentUser.uid;
                    final jobPosition = data['jobPosition'] ?? 'N/A';
                    final taskType = data['isShortTerm'] == true ? 'Short-term' : 'Long-term';
                    final startDate = data['startDate'] ?? '-';
                    final startTime = data['isShortTerm'] == true ? (data['startTime'] ?? '-') : '';
                    final salary = data['salary'] ?? 'Not specified';

                    return GestureDetector(
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
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        color: Colors.white,
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(10),
                          title: Text(
                            jobPosition,
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Task Type: $taskType', style: GoogleFonts.poppins(fontSize: 14)),
                              Text('Start Date: $startDate', style: GoogleFonts.poppins(fontSize: 14)),
                              if (startTime.isNotEmpty)
                                Text('Start Time: $startTime', style: GoogleFonts.poppins(fontSize: 14)),
                              Text('Salary: RM $salary', style: GoogleFonts.poppins(fontSize: 14)),
                              if (data['requiredSkill'] != null)
                                Text(
                                  'Skill Required: ${data['requiredSkill'] is String ? (data['requiredSkill'] as String).split(',').join(', ') : (data['requiredSkill'] as List).join(', ')}',
                                  style: GoogleFonts.poppins(fontSize: 14),
                                ),
                            ],
                          ),
                          trailing: isOwner
                              ? IconButton(
                            icon: const Icon(Icons.edit, color: Colors.teal),
                            onPressed: () {
                              _editJob(job.id, data); // Navigate to edit page
                            },
                          )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 15.0),
          child: Tooltip(
            message: 'Tap to create a new task',
            waitDuration: const Duration(milliseconds: 500),
            showDuration: const Duration(seconds: 2),
            child: FloatingActionButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AddJobPage()),
                );
              },
              backgroundColor: Colors.teal,
              child: const Icon(Icons.add, size: 30),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      ),
    );
  }
}

