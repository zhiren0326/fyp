import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp/Add%20Job%20Module/AddJobPage.dart';

import '../Add Job Module/JobDetailPage.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  @override
  void initState() {
    super.initState();

    // Show snackbar after frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tap the + button to create a new task'),
          duration: Duration(seconds: 3),
        ),
      );
    });
  }

  void acceptJob(String jobId) {
    FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
      'isAccepted': true,
      'acceptedBy': FirebaseAuth.instance.currentUser!.uid,
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
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

          final jobs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: jobs.length,
              itemBuilder: (context, index) {
                final job = jobs[index];
                final data = job.data() as Map<String, dynamic>;

                if ((data['jobPosition'] == null || data['jobPosition'].toString().trim().isEmpty) &&
                    (data['description'] == null || data['description'].toString().trim().isEmpty)) {
                  return const SizedBox.shrink();
                }

                final isOwner = data['postedBy'] == currentUser!.uid;
                final isAccepted = data['isAccepted'] == true;
                final jobPosition = data['jobPosition'] ?? 'N/A';
                final taskType = data['isShortTerm'] == true ? 'Short-term' : 'Long-term';
                final startDate = data['startDate'] ?? '-';
                final startTime = data['isShortTerm'] == true ? (data['startTime'] ?? '-') : '';
                final salary = data['salary'] ?? 'Not specified';

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => JobDetailPage(data: data),
                          ),
                        );
                      },
                      child: ListTile(
                        title: Text(jobPosition),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Task Type: $taskType'),
                            Text('Start Date: $startDate'),
                            if (startTime.isNotEmpty) Text('Start Time: $startTime'),
                            Text('Salary: RM $salary'),
                            if (data['requiredSkill'] != null)
                              Text('Skill Required: ${data['requiredSkill']}'),
                          ],
                        ),
                        trailing: isOwner
                            ? IconButton(
                          icon: const Icon(Icons.edit, color: Colors.orange),
                          onPressed: () {
                            // Edit logic
                          },
                        )
                            : isAccepted
                            ? const Text("Taken", style: TextStyle(color: Colors.grey))
                            : ElevatedButton(
                          onPressed: () => acceptJob(job.id),
                          child: const Text("Accept"),
                        ),
                      ),
                    )
                );
              }
          );
        },
      ),
      floatingActionButton: Tooltip(
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
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }
}
