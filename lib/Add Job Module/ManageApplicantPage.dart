import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fyp/Add%20Job%20Module/JobDetailPage.dart';

class ManageApplicantsPage extends StatefulWidget {
  final String jobId;
  final String jobPosition;

  const ManageApplicantsPage({super.key, required this.jobId, required this.jobPosition});

  @override
  State<ManageApplicantsPage> createState() => _ManageApplicantsPageState();
}

class _ManageApplicantsPageState extends State<ManageApplicantsPage> {
  @override
  void initState() {
    super.initState();
    print('ManageApplicantsPage initialized for job ${widget.jobId} at ${DateTime.now()}');
  }

  Future<void> _acceptApplicant(String applicantId) async {
    try {
      await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
        'acceptedApplicants': FieldValue.arrayUnion([applicantId]),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Applicant accepted successfully')),
      );
      setState(() {});
    } catch (e) {
      print('Error accepting applicant: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accepting applicant: $e')),
      );
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
            'Manage Applicants for ${widget.jobPosition}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
          ),
          backgroundColor: Colors.teal,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final data = snapshot.data!.data() as Map<String, dynamic>;
            final applicants = data['applicants'] as List? ?? [];
            final requiredPeople = data['requiredPeople'] as int? ?? 1;
            final acceptedApplicants = data['acceptedApplicants'] as List? ?? [];
            if (applicants.isEmpty) return const Center(child: Text('No applicants yet.', style: TextStyle(fontSize: 16)));

            return ListView.builder(
              padding: const EdgeInsets.all(16),
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
                        final isAccepted = data['acceptedApplicants']?.contains(applicantId) ?? false;
                        final isRejected = data['rejectedApplicants']?.contains(applicantId) ?? false;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            title: Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Phone: $phone', style: GoogleFonts.poppins()),
                                Text('Address: $address', style: GoogleFonts.poppins()),
                                Text('Skills: $skillTags', style: GoogleFonts.poppins()),
                                Text(
                                  'Status: ${isAccepted ? 'Accepted' : isRejected ? 'Rejected' : 'Pending'}',
                                  style: GoogleFonts.poppins(
                                    color: isAccepted
                                        ? Colors.green
                                        : isRejected
                                        ? Colors.red
                                        : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isAccepted && !isRejected)
                                  IconButton(
                                    icon: const Icon(Icons.check, color: Colors.green),
                                    onPressed: () => _acceptApplicant(applicantId),
                                  ),
                                if (!isAccepted && !isRejected)
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.red),
                                    onPressed: () => _rejectApplicant(applicantId),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
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