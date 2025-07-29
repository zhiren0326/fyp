import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'TaskProgressTrackerDetail.dart';

class TaskProgressTracker extends StatefulWidget {
  const TaskProgressTracker({super.key});

  @override
  State<TaskProgressTracker> createState() => _TaskProgressTrackerState();
}

class _TaskProgressTrackerState extends State<TaskProgressTracker> {
  List<Map<String, dynamic>> appliedJobs = [];
  bool _isLoading = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (_currentUserId != null) {
      _loadAppliedJobs();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAppliedJobs() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('jobs')
          .where('acceptedApplicants', arrayContains: _currentUserId)
          .get();

      setState(() {
        appliedJobs = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'title': data['jobPosition'] ?? 'Unnamed Job',
            'progress': (data['progressPercentage'] ?? 0.0).toDouble(),
            'status': data['submissionStatus'] ?? 'In Progress',
          };
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading applied jobs: $e');
      setState(() => _isLoading = false);
    }
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TaskProgressTrackerDetail(
                taskId: job['id'],
                taskTitle: job['title'],
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      job['title'],
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF006D77),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${job['progress'].toStringAsFixed(1)}%',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(job['status']),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: job['progress'] / 100,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(job['status'])),
                minHeight: 8,
              ),
              const SizedBox(height: 10),
              Text(
                'Status: ${job['status']}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: _getStatusColor(job['status']),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Not Started': return Colors.grey;
      case 'In Progress': return Colors.blue;
      case 'On Hold': return Colors.orange;
      case 'Completed': return Colors.green;
      case 'Pending Review': return Colors.yellow;
      case 'Rejected': return Colors.red;
      case 'Cancelled': return Colors.red;
      default: return Colors.grey;
    }
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
            'My Applied Jobs',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : appliedJobs.isEmpty
            ? const Center(child: Text('No applied jobs found.'))
            : ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: appliedJobs.length,
          itemBuilder: (context, index) {
            return _buildJobCard(appliedJobs[index]);
          },
        ),
      ),
    );
  }
}