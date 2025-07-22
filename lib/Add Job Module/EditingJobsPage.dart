
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp/Add%20Job%20Module/ManageApplicantPage.dart';
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
    FirebaseFirestore.instance.collection('jobs').doc(jobId).get().then((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
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
      }
    });
  }

  void _manageApplicants(String jobId) {
    FirebaseFirestore.instance.collection('jobs').doc(jobId).get().then((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ManageApplicantsPage(jobId: jobId, jobPosition: data['jobPosition'] ?? 'Job'),
          ),
        ).then((_) => setState(() {}));
      }
    });
  }

  void _viewJobDetails(String jobId) {
    FirebaseFirestore.instance.collection('jobs').doc(jobId).get().then((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => JobDetailPage(data: data, jobId: jobId)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please log in.'));

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
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final jobs = snapshot.data!.docs;
                  if (jobs.isEmpty) return const Center(child: Text('No tasks created.', style: TextStyle(fontSize: 16)));
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      final data = jobs[index].data() as Map<String, dynamic>;
                      final jobId = jobs[index].id;
                      final jobPosition = data['jobPosition'] ?? 'Untitled Job';
                      final applicants = data['applicants'] as List? ?? [];
                      final requiredPeople = data['requiredPeople'] as int? ?? 1;
                      final acceptedApplicants = data['acceptedApplicants'] as List? ?? [];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text(jobPosition, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Posted: ${data['postedAt']?.toDate().toString().split('.')[0] ?? 'N/A'}',
                                  style: GoogleFonts.poppins()),
                              Text('Applicants: ${applicants.length}', style: GoogleFonts.poppins()),
                              Text('Accepted: ${acceptedApplicants.length}/${requiredPeople}', style: GoogleFonts.poppins()),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, color: Colors.teal), onPressed: () => _editJob(jobId)),
                              const SizedBox(width: 8),
                              IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _removeJob(jobId)),
                              if (applicants.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.people, color: Colors.blue),
                                  onPressed: () => _manageApplicants(jobId),
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
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final jobs = snapshot.data!.docs;
                  if (jobs.isEmpty) return const Center(child: Text('No applied jobs.', style: TextStyle(fontSize: 16)));
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      final data = jobs[index].data() as Map<String, dynamic>;
                      final jobId = jobs[index].id;
                      final jobPosition = data['jobPosition'] ?? 'Untitled Job';
                      final isAccepted = (data['acceptedApplicants'] as List?)?.contains(currentUser.uid) ?? false;
                      final isRejected = (data['rejectedApplicants'] as List?)?.contains(currentUser.uid) ?? false;
                      final status = isAccepted ? 'Accepted' : isRejected ? 'Rejected' : 'Pending';
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text(jobPosition, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Applied: ${data['postedAt']?.toDate().toString().split('.')[0] ?? 'N/A'}',
                                  style: GoogleFonts.poppins()),
                              Text(
                                'Status: $status',
                                style: GoogleFonts.poppins(
                                  color: isAccepted ? Colors.green : isRejected ? Colors.red : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          trailing: Icon(
                            isAccepted ? Icons.check_circle : isRejected ? Icons.cancel : Icons.hourglass_empty,
                            color: isAccepted ? Colors.green : isRejected ? Colors.red : Colors.orange,
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
