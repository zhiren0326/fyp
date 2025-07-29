
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fyp/Add%20Job%20Module/JobDetailPage.dart';
import '../Notification Module/NotificationService.dart';
import 'TaskProgressTrackerDetail.dart'; // Ensure this import is correct

class ManageApplicantsPage extends StatefulWidget {
  final String jobId;
  final String jobPosition;

  const ManageApplicantsPage({super.key, required this.jobId, required this.jobPosition});

  @override
  State<ManageApplicantsPage> createState() => _ManageApplicantsPageState();
}

class _ManageApplicantsPageState extends State<ManageApplicantsPage> {
  Map<String, dynamic>? jobData;
  List<Map<String, dynamic>> teamPerformanceData = [];
  double overallProgress = 0.0;

  @override
  void initState() {
    super.initState();
    print('ManageApplicantsPage initialized for job ${widget.jobId} at ${DateTime.now()}');
    _loadJobData();
    _loadTeamPerformanceData();
  }

  Future<void> _loadJobData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .get();

      if (doc.exists) {
        setState(() {
          jobData = doc.data();
          overallProgress = (jobData!['progressPercentage'] ?? 0.0).toDouble();
        });
      }
    } catch (e) {
      print('Error loading job data: $e');
    }
  }

  Future<void> _loadTeamPerformanceData() async {
    try {
      final jobDoc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .get();

      if (!jobDoc.exists) return;

      final data = jobDoc.data()!;
      final acceptedApplicants = data['acceptedApplicants'] as List? ?? [];

      List<Map<String, dynamic>> performanceList = [];

      for (String applicantId in acceptedApplicants) {
        // Get user profile
        final profileDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(applicantId)
            .collection('profiledetails')
            .doc('profile')
            .get();

        // Get task progress for this job
        final progressDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(applicantId)
            .collection('taskProgress')
            .doc(widget.jobId)
            .get();

        String name = 'Unknown User';
        if (profileDoc.exists) {
          name = profileDoc.data()!['name'] ?? 'Unknown User';
        }

        double progress = 0.0;
        String status = 'Not Started';
        if (progressDoc.exists) {
          final progressData = progressDoc.data()!;
          progress = (progressData['currentProgress'] ?? 0.0).toDouble();
          status = progressData['status'] ?? 'Not Started';
        }

        performanceList.add({
          'userId': applicantId,
          'name': name,
          'progress': progress,
          'status': status,
          'efficiency': _calculateEfficiency(progress, status),
        });
      }

      setState(() {
        teamPerformanceData = performanceList;
      });
    } catch (e) {
      print('Error loading team performance: $e');
    }
  }

  double _calculateEfficiency(double progress, String status) {
    // Simple efficiency calculation based on progress and status
    switch (status) {
      case 'Completed': return 100.0;
      case 'In Progress': return progress * 0.8; // Slightly reduce for in-progress
      case 'On Hold': return progress * 0.5; // Significant reduction for on hold
      case 'Not Started': return 0.0;
      default: return progress * 0.7;
    }
  }

  Future<void> _acceptApplicant(String applicantId) async {
    try {
      // Fetch the job document to check acceptedApplicants and requiredPeople
      final jobDoc = await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).get();
      final data = jobDoc.data() as Map<String, dynamic>;
      final acceptedApplicants = data['acceptedApplicants'] as List? ?? [];
      final requiredPeople = data['requiredPeople'] as int? ?? 1;

      // Check if accepting a new applicant would exceed requiredPeople
      if (acceptedApplicants.length >= requiredPeople) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot accept more applicants: Job is already full')),
        );
        return;
      }

      // Proceed with accepting the applicant
      await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
        'acceptedApplicants': FieldValue.arrayUnion([applicantId]),
      });

      // Create initial task progress tracker for the accepted applicant
      await _createTaskProgressForApplicant(applicantId);

      // Send local notification to the accepted applicant
      await NotificationService().notifyTaskStatusChanged(
        taskTitle: widget.jobPosition,
        newStatus: 'Accepted',
        taskId: widget.jobId,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Applicant accepted successfully')),
      );

      setState(() {});
      _loadTeamPerformanceData(); // Reload team performance data
    } catch (e) {
      print('Error accepting applicant: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accepting applicant: $e')),
      );
    }
  }

  Future<void> _createTaskProgressForApplicant(String applicantId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(applicantId)
          .collection('taskProgress')
          .doc(widget.jobId)
          .set({
        'taskId': widget.jobId,
        'taskTitle': widget.jobPosition,
        'currentProgress': 0.0,
        'status': 'Not Started',
        'milestones': [],
        'subTasks': [],
        'notes': '',
        'createdAt': Timestamp.now(),
        'lastUpdated': Timestamp.now(),
      });
    } catch (e) {
      print('Error creating task progress: $e');
    }
  }

  Future<void> _sendAcceptanceNotification(String applicantId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(applicantId)
          .collection('notifications')
          .add({
        'message': 'Congratulations! You have been accepted for "${widget.jobPosition}". You can now track your progress.',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'type': 'acceptance',
        'jobId': widget.jobId,
      });
    } catch (e) {
      print('Error sending acceptance notification: $e');
    }
  }

  Future<void> _rejectApplicant(String applicantId) async {
    String? rejectionReason;
    final frequentReasons = [
      'Lack of required skills',
      'Insufficient experience',
      'Schedule conflict',
      'Application incomplete',
      'Other'
    ];

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        String? selectedReason;
        final TextEditingController customReasonController = TextEditingController();

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Reason for Rejection'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    hint: const Text('Select a reason'),
                    value: selectedReason,
                    items: frequentReasons.map((reason) {
                      return DropdownMenuItem<String>(
                        value: reason,
                        child: Text(reason),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedReason = value;
                        customReasonController.clear();
                      });
                    },
                  ),
                  if (selectedReason == 'Other')
                    TextField(
                      controller: customReasonController,
                      decoration: const InputDecoration(labelText: 'Please specify'),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedReason = value;
                        });
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: selectedReason == null
                      ? null
                      : () async {
                    Navigator.pop(dialogContext);
                    try {
                      await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
                        'applicants': FieldValue.arrayRemove([applicantId]),
                        'rejectedApplicants': FieldValue.arrayUnion([applicantId]),
                      });
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(applicantId)
                          .collection('notifications')
                          .add({
                        'message': 'Your application for "${widget.jobPosition}" was rejected. Reason: $selectedReason',
                        'timestamp': FieldValue.serverTimestamp(),
                        'read': false,
                        'type': 'rejection',
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Applicant rejected successfully')),
                      );
                      setState(() {});
                    } catch (e) {
                      print('Error rejecting applicant: $e');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error rejecting applicant: $e')),
                      );
                    }
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateOverallProgress() async {
    if (teamPerformanceData.isEmpty) return;

    double totalProgress = teamPerformanceData.fold(0.0, (sum, item) => sum + item['progress']);
    double avgProgress = totalProgress / teamPerformanceData.length;

    // Send progress notifications to team members
    for (var member in teamPerformanceData) {
      await NotificationService().notifyProgressUpdate(
        taskTitle: widget.jobPosition,
        progressPercentage: member['progress'],
        taskId: widget.jobId,
      );
    }

    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .update({
        'progressPercentage': avgProgress,
        'lastProgressUpdate': Timestamp.now(),
      });

      setState(() {
        overallProgress = avgProgress;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Overall progress updated to ${avgProgress.toStringAsFixed(1)}%'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating progress: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _viewApplicantProgress(String applicantId, String applicantName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaskProgressTrackerDetail(
          taskId: widget.jobId,
          taskTitle: '${widget.jobPosition} - $applicantName',
        ),
      ),
    );
  }

  Widget _buildOverallProgressCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Overall Job Progress',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF006D77),
                  ),
                ),
                Text(
                  '${overallProgress.toStringAsFixed(1)}%',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF006D77),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            LinearProgressIndicator(
              value: overallProgress / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                overallProgress < 30 ? Colors.red :
                overallProgress < 70 ? Colors.orange : Colors.green,
              ),
              minHeight: 8,
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: _updateOverallProgress,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006D77),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Update Progress',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamPerformanceSection() {
    if (teamPerformanceData.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Team Performance',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77),
              ),
            ),
            const SizedBox(height: 15),
            ...teamPerformanceData.map((member) {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member['name'],
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'Status: ${member['status']}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              '${member['progress'].toStringAsFixed(1)}%',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF006D77),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.analytics, color: Color(0xFF006D77)),
                              onPressed: () => _viewApplicantProgress(
                                member['userId'],
                                member['name'],
                              ),
                              tooltip: 'View Progress',
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: member['progress'] / 100,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        member['progress'] < 30 ? Colors.red :
                        member['progress'] < 70 ? Colors.orange : Colors.green,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Completed': return Colors.green;
      case 'In Progress': return Colors.blue;
      case 'On Hold': return Colors.orange;
      case 'Not Started': return Colors.grey;
      case 'Cancelled': return Colors.red;
      default: return Colors.grey;
    }
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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            'Manage: ${widget.jobPosition}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
          ),
          backgroundColor: Colors.teal,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _loadJobData();
                _loadTeamPerformanceData();
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              _buildOverallProgressCard(),
              _buildTeamPerformanceSection(),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  final applicants = data['applicants'] as List? ?? [];
                  final requiredPeople = data['requiredPeople'] as int? ?? 1;
                  final acceptedApplicants = data['acceptedApplicants'] as List? ?? [];
                  final isJobFull = acceptedApplicants.length >= requiredPeople;

                  if (applicants.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            isJobFull ? Icons.people : Icons.people_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isJobFull ? 'Job is full. No more applicants can be accepted.' : 'No applicants yet.',
                            style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return Card(
                    margin: const EdgeInsets.all(16),
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Applicants (${applicants.length})',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF006D77),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isJobFull ? Colors.red[100] : Colors.green[100],
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isJobFull ? Colors.red : Colors.green,
                                  ),
                                ),
                                child: Text(
                                  '${acceptedApplicants.length}/$requiredPeople',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isJobFull ? Colors.red[700] : Colors.green[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: applicants.length,
                          itemBuilder: (context, index) {
                            final applicantId = applicants[index];
                            return FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(applicantId)
                                  .collection('skills')
                                  .doc('user_skills')
                                  .get(),
                              builder: (context, skillsSnapshot) {
                                String skillTags = 'Not provided';
                                if (skillsSnapshot.hasData && skillsSnapshot.data!.exists) {
                                  final skillsData = skillsSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                                  final skillList = skillsData['skills'] as List? ?? [];
                                  skillTags = skillList.isNotEmpty
                                      ? skillList.map((skillMap) => skillMap['skill'] as String? ?? 'Unknown Skill').join(', ')
                                      : 'Not provided';
                                }
                                return FutureBuilder<DocumentSnapshot>(
                                  future: FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(applicantId)
                                      .collection('profiledetails')
                                      .doc('profile')
                                      .get(),
                                  builder: (context, profileSnapshot) {
                                    if (!profileSnapshot.hasData || !profileSnapshot.data!.exists) {
                                      return const ListTile(title: Text('Loading applicant details...'));
                                    }
                                    final profileData = profileSnapshot.data!.data() as Map<String, dynamic>;
                                    final name = profileData['name'] ?? 'Unknown User';
                                    final phone = profileData['phone'] ?? 'Not provided';
                                    final address = profileData['address'] ?? 'Not provided';
                                    final isAccepted = acceptedApplicants.contains(applicantId);
                                    final isRejected = data['rejectedApplicants']?.contains(applicantId) ?? false;

                                    return Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isAccepted ? Colors.green[50] :
                                        isRejected ? Colors.red[50] : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isAccepted ? Colors.green :
                                          isRejected ? Colors.red : Colors.grey[300]!,
                                        ),
                                      ),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.all(16),
                                        title: Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor: isAccepted ? Colors.green :
                                              isRejected ? Colors.red : Colors.blue,
                                              child: Text(
                                                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                                                  ),
                                                  Text(
                                                    'Phone: $phone',
                                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Address: $address', style: GoogleFonts.poppins(fontSize: 12)),
                                              Text('Skills: $skillTags', style: GoogleFonts.poppins(fontSize: 12)),
                                              const SizedBox(height: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: isAccepted ? Colors.green[100] :
                                                  isRejected ? Colors.red[100] : Colors.orange[100],
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  'Status: ${isAccepted ? 'Accepted' : isRejected ? 'Rejected' : 'Pending'}',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isAccepted ? Colors.green[700] :
                                                    isRejected ? Colors.red[700] : Colors.orange[700],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isAccepted)
                                              IconButton(
                                                icon: const Icon(Icons.analytics, color: Colors.blue),
                                                onPressed: () => _viewApplicantProgress(applicantId, name),
                                                tooltip: 'View Progress',
                                              ),
                                            if (!isAccepted && !isRejected) ...[
                                              IconButton(
                                                icon: const Icon(Icons.check, color: Colors.green),
                                                onPressed: isJobFull
                                                    ? null // Disable button if job is full
                                                    : () => _acceptApplicant(applicantId),
                                                tooltip: isJobFull ? 'Job is full' : 'Accept applicant',
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.close, color: Colors.red),
                                                onPressed: () => _rejectApplicant(applicantId),
                                                tooltip: 'Reject applicant',
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TaskProgressTrackerDetail(
                  taskId: widget.jobId,
                  taskTitle: widget.jobPosition,
                ),
              ),
            );
          },
          backgroundColor: const Color(0xFF006D77),
          child: const Icon(Icons.analytics, color: Colors.white),
        ),
      ),
    );
  }
}
