import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../module/ChatMessage.dart';

class EmployerReviewPage extends StatefulWidget {
  final String jobId;
  final Map<String, dynamic> submissionData;

  const EmployerReviewPage({
    super.key,
    required this.jobId,
    required this.submissionData,
  });

  @override
  State<EmployerReviewPage> createState() => _EmployerReviewPageState();
}

class _EmployerReviewPageState extends State<EmployerReviewPage> {
  final TextEditingController _reviewNotesController = TextEditingController();
  bool _isProcessing = false;
  Map<String, dynamic>? _employeeProfile;
  String? _employeeCustomId;

  @override
  void initState() {
    super.initState();
    _loadEmployeeProfile();
  }

  @override
  void dispose() {
    _reviewNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployeeProfile() async {
    try {
      final employeeId = widget.submissionData['employeeId'];

      // Get employee profile
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('profiledetails')
          .doc('profile')
          .get();

      // Get employee custom ID
      final customIdDoc = await FirebaseFirestore.instance
          .collection('custom_ids')
          .doc(employeeId)
          .get();

      if (profileDoc.exists && customIdDoc.exists) {
        setState(() {
          _employeeProfile = profileDoc.data();
          _employeeCustomId = customIdDoc.data()?['customId'];
        });
      }
    } catch (e) {
      print('Error loading employee profile: $e');
    }
  }

  Future<void> _approveSubmission() async {
    setState(() => _isProcessing = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser!;
      final employeeId = widget.submissionData['employeeId'];

      // Calculate points based on job complexity and salary
      final salary = widget.submissionData['jobData']['salary'] ?? 0;
      final priority = widget.submissionData['jobData']['priority'] ?? 'Medium';

      int pointsToAward = _calculatePoints(salary, priority);

      // Update submission status
      await FirebaseFirestore.instance
          .collection('jobSubmissions')
          .doc(widget.jobId)
          .update({
        'status': 'approved',
        'reviewedAt': Timestamp.now(),
        'reviewedBy': currentUser.uid,
        'reviewNotes': _reviewNotesController.text.trim(),
        'pointsAwarded': pointsToAward,
      });

      // Update job status
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .update({
        'isCompleted': true,
        'submissionStatus': 'approved',
        'completedAt': Timestamp.now(),
        'lastUpdated': Timestamp.now(),
      });

      // Award points to employee
      await _awardPointsToEmployee(employeeId, pointsToAward);

      // Update task progress to completed
      await _updateTaskProgress();

      // Send notification to employee
      await _sendNotificationToEmployee('approved', pointsToAward);

      // Log activity for employer
      await _logEmployerActivity('Job Completion Approved');

      _showSnackBar('Job completion approved and points awarded!');
      Navigator.pop(context);

    } catch (e) {
      _showSnackBar('Error approving submission: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectSubmission() async {
    if (_reviewNotesController.text.trim().isEmpty) {
      _showSnackBar('Please provide feedback for rejection');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser!;
      final employeeId = widget.submissionData['employeeId'];

      // Update submission status
      await FirebaseFirestore.instance
          .collection('jobSubmissions')
          .doc(widget.jobId)
          .update({
        'status': 'rejected',
        'reviewedAt': Timestamp.now(),
        'reviewedBy': currentUser.uid,
        'reviewNotes': _reviewNotesController.text.trim(),
      });

      // Update job status
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .update({
        'submissionStatus': 'rejected',
      });

      // Send notification to employee
      await _sendNotificationToEmployee('rejected', 0);

      // Log activity for employer
      await _logEmployerActivity('Job Completion Rejected');

      _showSnackBar('Job completion rejected with feedback');
      Navigator.pop(context);

    } catch (e) {
      _showSnackBar('Error rejecting submission: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _sendNotificationToEmployee(String status, int points) async {
    try {
      final employeeId = widget.submissionData['employeeId'];
      final title = status == 'approved' ? 'Job Completion Approved!' : 'Job Completion Rejected';
      final message = status == 'approved'
          ? 'Your job completion has been approved! You earned $points points.'
          : 'Your job completion was rejected. Please check the feedback.';

      await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('notifications')
          .add({
        'type': 'job_completion_$status',
        'title': title,
        'message': message,
        'jobId': widget.jobId,
        'pointsAwarded': points,
        'fromUserId': FirebaseAuth.instance.currentUser!.uid,
        'timestamp': Timestamp.now(),
        'read': false,
      });
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  Future<void> _logEmployerActivity(String action) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('activityLog')
          .add({
        'action': action,
        'taskId': widget.jobId,
        'taskTitle': widget.submissionData['jobTitle'],
        'timestamp': Timestamp.now(),
        'details': {
          'employeeId': widget.submissionData['employeeId'],
          'reviewNotes': _reviewNotesController.text.trim(),
        }
      });
    } catch (e) {
      print('Error logging activity: $e');
    }
  }

  Future<void> _contactEmployee() async {
    if (_employeeCustomId == null) {
      _showSnackBar('Unable to contact employee');
      return;
    }

    try {
      final currentUser = FirebaseAuth.instance.currentUser!;

      // Get current user's custom ID
      final currentUserCustomIdDoc = await FirebaseFirestore.instance
          .collection('custom_ids')
          .doc(currentUser.uid)
          .get();

      if (!currentUserCustomIdDoc.exists) {
        _showSnackBar('Error: Your custom ID not found');
        return;
      }

      final currentUserCustomId = currentUserCustomIdDoc['customId'];

      // Add chat to employer's chat list
      final chatDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('chats')
          .doc('chat_list');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(chatDocRef);
        List<Map<String, dynamic>> updatedChatList = List<Map<String, dynamic>>.from(doc.data()?['users'] ?? []);
        final chatIndex = updatedChatList.indexWhere((chat) => chat['customId'] == _employeeCustomId);
        final chatData = {
          'customId': _employeeCustomId!,
          'name': _employeeProfile!['name'] ?? 'Employee',
          'photoURL': _employeeProfile!['photoURL'] ?? 'assets/default_avatar.png',
          'isGroup': false,
        };
        if (chatIndex == -1) {
          updatedChatList.add(chatData);
        } else {
          updatedChatList[chatIndex] = chatData;
        }
        transaction.set(chatDocRef, {'users': updatedChatList}, SetOptions(merge: true));
      });

      // Navigate to chat
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatMessage(
            currentUserCustomId: currentUserCustomId,
            selectedCustomId: _employeeCustomId!,
            selectedUserName: _employeeProfile!['name'] ?? 'Employee',
            selectedUserPhotoURL: _employeeProfile!['photoURL'] ?? 'assets/default_avatar.png',
          ),
        ),
      );
    } catch (e) {
      _showSnackBar('Failed to start chat: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF006D77),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openFile(String url, String fileName) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showSnackBar('Cannot open file');
      }
    } catch (e) {
      _showSnackBar('Error opening file: $e');
    }
  }

  Widget _buildSubmissionInfo() {
    final submittedAt = (widget.submissionData['submittedAt'] as Timestamp).toDate();

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Job Submission',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF006D77),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange),
                ),
                child: Text(
                  'Pending Review',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.submissionData['jobTitle'] ?? 'Job Title',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                'Submitted: ${submittedAt.day}/${submittedAt.month}/${submittedAt.year} at ${submittedAt.hour}:${submittedAt.minute.toString().padLeft(2, '0')}',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          if (_employeeProfile != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundImage: _employeeProfile!['photoURL'] != null
                      ? NetworkImage(_employeeProfile!['photoURL'])
                      : const AssetImage('assets/default_avatar.png') as ImageProvider,
                ),
                const SizedBox(width: 8),
                Text(
                  'Submitted by: ${_employeeProfile!['name'] ?? 'Employee'}',
                  style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletionDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
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
            'Completion Details',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF006D77),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'Completion Notes:',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.submissionData['completionNotes'] ?? 'No completion notes provided',
            style: GoogleFonts.poppins(fontSize: 14),
          ),

          if (widget.submissionData['additionalInfo'] != null &&
              widget.submissionData['additionalInfo'].toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Additional Information:',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.submissionData['additionalInfo'],
              style: GoogleFonts.poppins(fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttachments() {
    final imageUrls = List<String>.from(widget.submissionData['imageUrls'] ?? []);
    final fileUrls = List<String>.from(widget.submissionData['fileUrls'] ?? []);

    if (imageUrls.isEmpty && fileUrls.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
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
            'Attachments',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF006D77),
            ),
          ),
          const SizedBox(height: 12),

          // Images
          if (imageUrls.isNotEmpty) ...[
            Text(
              'Images (${imageUrls.length})',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrls[index],
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(child: CircularProgressIndicator());
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.error, color: Colors.red),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // Files
          if (fileUrls.isNotEmpty) ...[
            if (imageUrls.isNotEmpty) const SizedBox(height: 16),
            Text(
              'Files (${fileUrls.length})',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...fileUrls.asMap().entries.map((entry) {
              final index = entry.key;
              final url = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _openFile(url, 'File ${index + 1}'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file, color: Color(0xFF006D77)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'File ${index + 1}',
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                        ),
                        const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
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
            'Review & Feedback',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF006D77),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reviewNotesController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Provide feedback or comments about the job completion...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),

          // Points calculation display
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.stars, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Points to be awarded: ${_calculatePoints(
                      widget.submissionData['jobData']['salary'] ?? 0,
                      widget.submissionData['jobData']['priority'] ?? 'Medium'
                  )}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _approveSubmission,
                icon: _isProcessing
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.check_circle),
                label: Text(_isProcessing ? 'Processing...' : 'Approve'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _rejectSubmission,
                icon: const Icon(Icons.cancel),
                label: const Text('Reject'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _contactEmployee,
            icon: const Icon(Icons.message),
            label: const Text('Contact Employee'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006D77),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
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
            'Review Job Completion',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSubmissionInfo(),
            _buildCompletionDetails(),
            _buildAttachments(),
            _buildReviewSection(),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  int _calculatePoints(int salary, String priority) {
    // Base points calculation
    int basePoints = (salary / 100).round(); // 1 point per RM 100

    // Priority multiplier
    double multiplier = 1.0;
    switch (priority) {
      case 'Low':
        multiplier = 0.8;
        break;
      case 'Medium':
        multiplier = 1.0;
        break;
      case 'High':
        multiplier = 1.5;
        break;
      case 'Critical':
        multiplier = 2.0;
        break;
    }

    // Minimum 10 points, maximum 500 points per job
    return (basePoints * multiplier).round().clamp(10, 500);
  }

  Future<void> _awardPointsToEmployee(String employeeId, int points) async {
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final profileRef = FirebaseFirestore.instance
            .collection('users')
            .doc(employeeId)
            .collection('profiledetails')
            .doc('profile');

        final profileDoc = await transaction.get(profileRef);
        final currentPoints = (profileDoc.data()?['points'] ?? 0) as int;

        transaction.update(profileRef, {
          'points': currentPoints + points,
          'lastPointsUpdate': Timestamp.now(),
        });

        // Add to points history
        final pointsHistoryRef = FirebaseFirestore.instance
            .collection('users')
            .doc(employeeId)
            .collection('pointsHistory')
            .doc();

        transaction.set(pointsHistoryRef, {
          'points': points,
          'source': 'job_completion',
          'jobId': widget.jobId,
          'jobTitle': widget.submissionData['jobTitle'],
          'timestamp': Timestamp.now(),
          'description': 'Job completion reward',
        });
      });
    } catch (e) {
      print('Error awarding points: $e');
    }
  }

  Future<void> _updateTaskProgress() async {
    try {
      final employeeId = widget.submissionData['employeeId'];
      await FirebaseFirestore.instance
          .collection('users')
          .doc(employeeId)
          .collection('taskProgress')
          .doc(widget.jobId)
          .update({
        'currentProgress': 100.0,
        'status': 'Completed',
        'completedAt': Timestamp.now(),
        'lastUpdated': Timestamp.now(),
      });
    } catch (e) {
      print('Error updating task progress: $e');
    }
  }
}