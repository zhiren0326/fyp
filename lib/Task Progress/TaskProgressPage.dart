/*
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// Import the new progress tracker
import 'ProgressTracker.dart';

class TaskProgressPage extends StatefulWidget {
  final String taskId;
  final String taskTitle;

  const TaskProgressPage({
    super.key,
    required this.taskId,
    required this.taskTitle,
  });

  @override
  State<TaskProgressPage> createState() => _TaskProgressPageState();
}

class _TaskProgressPageState extends State<TaskProgressPage> {
  bool _isJobCreator = false;
  bool _isAcceptedApplicant = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Check if user is the job creator
      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.taskId)
          .get();

      if (jobDoc.exists) {
        final jobData = jobDoc.data()!;
        final jobCreatorId = jobData['jobCreator'] ?? jobData['postedBy'] ?? '';
        final acceptedApplicants = jobData['acceptedApplicants'] as List? ?? [];

        setState(() {
          _isJobCreator = currentUser.uid == jobCreatorId;
          _isAcceptedApplicant = acceptedApplicants.contains(currentUser.uid);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error checking user role: $e');
      setState(() => _isLoading = false);
    }
  }

  void _navigateToProgressTracker() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProgressTrackerPage(
          jobId: widget.taskId,
          jobTitle: widget.taskTitle,
          isEmployer: _isJobCreator,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.taskTitle),
          backgroundColor: const Color(0xFF006D77),
        ),
        body: const Center(child: CircularProgressIndicator()),
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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            'Task Progress',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.analytics,
                  size: 80,
                  color: const Color(0xFF006D77),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.taskTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF006D77),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _isJobCreator
                      ? 'Monitor your team\'s progress and review completion requests.'
                      : _isAcceptedApplicant
                      ? 'Track your progress and update milestones.'
                      : 'You don\'t have access to this task\'s progress tracking.',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_isJobCreator || _isAcceptedApplicant) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _navigateToProgressTracker,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006D77),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isJobCreator ? 'View Team Progress' : 'Update My Progress',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Features:',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF006D77),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_isJobCreator) ...[
                          _buildFeatureItem(Icons.visibility, 'Monitor team progress'),
                          _buildFeatureItem(Icons.pending_actions, 'Review completion requests'),
                          _buildFeatureItem(Icons.approval, 'Approve/reject completions'),
                          _buildFeatureItem(Icons.stars, 'Award points to employees'),
                        ] else ...[
                          _buildFeatureItem(Icons.timeline, 'Track your progress'),
                          _buildFeatureItem(Icons.flag, 'Add milestones'),
                          _buildFeatureItem(Icons.history, 'View progress history'),
                          _buildFeatureItem(Icons.check_circle, 'Request completion'),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.block,
                          size: 48,
                          color: Colors.orange[700],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Access Denied',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You need to be either the job creator or an accepted applicant to access progress tracking.',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.orange[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: const Color(0xFF006D77),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}*/
