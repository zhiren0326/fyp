import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp/Add%20Job%20Module/AddJobPage.dart';

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
      appBar: AppBar(
      ),
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
              final isOwner = data['postedBy'] == currentUser!.uid;
              final isAccepted = data['isAccepted'] == true;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(data['title'] ?? ''),
                  subtitle: Text(data['description'] ?? ''),
                  trailing: isOwner
                      ? IconButton(
                    icon: const Icon(Icons.edit, color: Colors.orange),
                    onPressed: () {
                      // Navigate to edit page (to implement)
                    },
                  )
                      : isAccepted
                      ? const Text("Taken", style: TextStyle(color: Colors.grey))
                      : ElevatedButton(
                    onPressed: () => acceptJob(job.id),
                    child: const Text("Accept"),
                  ),
                ),
              );
            },
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
