import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EditingJobsPage extends StatefulWidget {
  final List<String> userCreatedJobIds;
  final Function(String) onEditJob;

  const EditingJobsPage({super.key, required this.userCreatedJobIds, required this.onEditJob});

  @override
  State<EditingJobsPage> createState() => _EditingJobsPageState();
}

class _EditingJobsPageState extends State<EditingJobsPage> {
  @override
  void initState() {
    super.initState();
    print('EditingJobsPage initialized with ${widget.userCreatedJobIds.length} jobs');
  }

  void _removeJob(String jobId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Are you sure you want to delete this job? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              FirebaseFirestore.instance.collection('jobs').doc(jobId).delete().then((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Job removed successfully')),
                );
                setState(() {
                  widget.userCreatedJobIds.remove(jobId);
                });
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

  @override
  Widget build(BuildContext context) {
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
        appBar: AppBar(
          title: Text(
            'Edit Your Jobs',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 20,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.teal,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
        body: widget.userCreatedJobIds.isEmpty
            ? const Center(
          child: Text(
            'No tasks created.',
            style: TextStyle(fontSize: 16),
          ),
        )
            : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: widget.userCreatedJobIds.length,
          itemBuilder: (context, index) {
            final jobId = widget.userCreatedJobIds[index];
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('jobs').doc(jobId).get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const ListTile(title: Text('Loading...'));
                }
                final data = snapshot.data!.data() as Map<String, dynamic>;
                final jobPosition = data['jobPosition'] ?? 'Untitled Job';
                final isAccepted = data['isAccepted'] ?? false;
                final status = isAccepted ? 'Accepted' : 'Not Accepted';
                return ListTile(
                  title: Text(
                    jobPosition,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Posted: ${data['postedAt']?.toDate().toLocal().toString().split('.')[0] ?? 'N/A'}',
                        style: GoogleFonts.poppins(fontSize: 12),
                      ),
                      Text(
                        'Status: $status',
                        style: GoogleFonts.poppins(fontSize: 12, color: isAccepted ? Colors.green : Colors.orange),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.teal),
                        onPressed: () {
                          widget.onEditJob(jobId);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Job edited successfully')),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          _removeJob(jobId);
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    widget.onEditJob(jobId);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Job edited successfully')),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}