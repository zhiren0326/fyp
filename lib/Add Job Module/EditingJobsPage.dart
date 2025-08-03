  import 'package:cloud_firestore/cloud_firestore.dart';
  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:flutter/material.dart';
  import 'package:fyp/Add%20Job%20Module/ManageApplicantPage.dart';
  import 'package:fyp/Task%20Progress/TaskProgressPage.dart';
  import 'package:google_fonts/google_fonts.dart';
  import 'package:fyp/Add%20Job%20Module/AddJobPage.dart';
  import 'package:fyp/Add%20Job%20Module/JobDetailPage.dart';

  class EditingJobsPage extends StatefulWidget {
    const EditingJobsPage({super.key});

    @override
    State<EditingJobsPage> createState() => _EditingJobsPageState();
  }

  class _EditingJobsPageState extends State<EditingJobsPage> {
    @override
    void initState() {
      super.initState();
      print('EditingJobsPage initialized');
    }

    Future<void> _removeJob(String jobId) async {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete this job? This action cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                FirebaseFirestore.instance.collection('jobs').doc(jobId).delete().then((_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Job removed successfully')),
                  );
                  setState(() {});
                }).catchError((e) {
                  print('Error removing job: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error removing job: $e')),
                  );
                });
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }

    void _editJob(String jobId) {
      print('Editing job: $jobId');
      FirebaseFirestore.instance.collection('jobs').doc(jobId).get().then((doc) {
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          print('Job data found: ${data['jobPosition']}');
          if (data['postedBy'] == FirebaseAuth.instance.currentUser!.uid) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => AddJobPage(jobId: jobId, initialData: data)),
            ).then((_) => setState(() {}));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You can only edit jobs you created.')),
            );
          }
        } else {
          print('Job document not found');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Job not found.')),
          );
        }
      }).catchError((e) {
        print('Error fetching job for edit: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading job: $e')),
        );
      });
    }

    void _manageApplicants(String jobId) async {
      print('Managing applicants for job: $jobId');

      try {
        final doc = await FirebaseFirestore.instance.collection('jobs').doc(jobId).get();

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          print('Job found: ${data['jobPosition']}');
          print('Applicants count: ${(data['applicants'] as List?)?.length ?? 0}');
          print('Accepted applicants count: ${(data['acceptedApplicants'] as List?)?.length ?? 0}');

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ManageApplicantsPage(
                  jobId: jobId,
                  jobPosition: data['jobPosition'] ?? 'Job'
              ),
            ),
          ).then((_) {
            print('Returned from ManageApplicantsPage');
            setState(() {});
          });
        } else {
          print('Job document not found for ID: $jobId');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Job not found.')),
          );
        }
      } catch (e) {
        print('Error managing applicants: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading job: $e')),
        );
      }
    }

    void _viewJobDetails(String jobId) {
      print('Viewing job details: $jobId');
      FirebaseFirestore.instance.collection('jobs').doc(jobId).get().then((doc) {
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => JobDetailPage(data: data, jobId: jobId)),
          );
        } else {
          print('Job document not found for details');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Job not found.')),
          );
        }
      }).catchError((e) {
        print('Error fetching job details: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading job details: $e')),
        );
      });
    }

    @override
    Widget build(BuildContext context) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return const Scaffold(
          body: Center(child: Text('Please log in.')),
        );
      }

      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB2DFDB), Colors.white],
          ),
        ),
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Text('Manage Your Jobs', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
              backgroundColor: Colors.teal,
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Created Tasks'),
                  Tab(text: 'Applied Jobs'),
                ],
              ),
              leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
            ),
            body: TabBarView(
              children: [
                // Created Tasks Tab
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('jobs')
                      .where('postedBy', isEqualTo: currentUser.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      print('Error in StreamBuilder: ${snapshot.error}');
                      return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()));
                    }

                    if (!snapshot.hasData) {
                      return const Center(child: Text('No data available.', style: TextStyle(fontSize: 16)));
                    }

                    final jobs = snapshot.data!.docs;
                    print('Found ${jobs.length} created jobs');

                    if (jobs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.work_outline, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No tasks created.', style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600])),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: jobs.length,
                      itemBuilder: (context, index) {
                        final doc = jobs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final jobId = doc.id;
                        final jobPosition = data['jobPosition'] ?? 'Untitled Job';
                        final applicants = data['applicants'] as List? ?? [];
                        final requiredPeople = data['requiredPeople'] as int? ?? 1;
                        final acceptedApplicants = data['acceptedApplicants'] as List? ?? [];
                        final postedAt = data['postedAt'] as Timestamp?;

                        print('Job: $jobPosition, Applicants: ${applicants.length}, Accepted: ${acceptedApplicants.length}');

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(
                                jobPosition,
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16)
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                Text(
                                    'Posted: ${postedAt?.toDate().toString().split('.')[0] ?? 'N/A'}',
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])
                                ),
                                Text(
                                    'Applicants: ${applicants.length}',
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])
                                ),
                                Text(
                                    'Accepted: ${acceptedApplicants.length}/$requiredPeople',
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: applicants.isNotEmpty ? Colors.orange[100] : Colors.grey[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        applicants.isNotEmpty ? 'Has Applicants' : 'No Applicants',
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: applicants.isNotEmpty ? Colors.orange[700] : Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Edit button
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.teal),
                                  onPressed: () => _editJob(jobId),
                                  tooltip: 'Edit Job',
                                ),

                                // Delete button
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _removeJob(jobId),
                                  tooltip: 'Delete Job',
                                ),

                                // Manage applicants button (only show if there are applicants OR accepted applicants)
                                if (applicants.isNotEmpty || acceptedApplicants.isNotEmpty)
                                  IconButton(
                                    icon: Icon(
                                      Icons.people,
                                      color: applicants.isNotEmpty ? Colors.orange : Colors.blue,
                                    ),
                                    onPressed: () {
                                      print('Manage applicants button pressed for job: $jobId');
                                      _manageApplicants(jobId);
                                    },
                                    tooltip: applicants.isNotEmpty ? 'Manage Applicants (${applicants.length} pending)' : 'View Accepted Team',
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                // Applied Jobs Tab
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('jobs')
                      .where('applicants', arrayContains: currentUser.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      print('Error in applied jobs StreamBuilder: ${snapshot.error}');
                      return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()));
                    }

                    if (!snapshot.hasData) {
                      return const Center(child: Text('No data available.', style: TextStyle(fontSize: 16)));
                    }

                    final jobs = snapshot.data!.docs;
                    print('Found ${jobs.length} applied jobs');

                    if (jobs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.work_off_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No applied jobs.', style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600])),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: jobs.length,
                      itemBuilder: (context, index) {
                        final doc = jobs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final jobId = doc.id;
                        final jobPosition = data['jobPosition'] ?? 'Untitled Job';
                        final isAccepted = (data['acceptedApplicants'] as List?)?.contains(currentUser.uid) ?? false;
                        final isRejected = (data['rejectedApplicants'] as List?)?.contains(currentUser.uid) ?? false;
                        final status = isAccepted ? 'Accepted' : isRejected ? 'Rejected' : 'Pending';
                        final postedAt = data['postedAt'] as Timestamp?;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(
                                jobPosition,
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16)
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                Text(
                                    'Applied: ${postedAt?.toDate().toString().split('.')[0] ?? 'N/A'}',
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isAccepted ? Colors.green[100] : isRejected ? Colors.red[100] : Colors.orange[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Status: $status',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isAccepted ? Colors.green[700] : isRejected ? Colors.red[700] : Colors.orange[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isAccepted ? Icons.check_circle : isRejected ? Icons.cancel : Icons.hourglass_empty,
                                  color: isAccepted ? Colors.green : isRejected ? Colors.red : Colors.orange,
                                ),
                                if (isAccepted) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.analytics, color: Colors.blue),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => TaskProgressPage(
                                            taskId: jobId,
                                            taskTitle: jobPosition,
                                          ),
                                        ),
                                      );
                                    },
                                    tooltip: 'View Task Progress',
                                  ),
                                ],
                              ],
                            ),
                            onTap: () => _viewJobDetails(jobId),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }
  }