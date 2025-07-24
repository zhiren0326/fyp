import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp/Add%20Job%20Module/AddJobPage.dart';
import 'package:fyp/Add%20Job%20Module/EditingJobsPage.dart';
import 'package:fyp/Login%20Signup/Screen/home_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fyp/module/ChatMessage.dart';

// Custom dateOnly function
DateTime dateOnly(DateTime dateTime) {
  return DateTime(dateTime.year, dateTime.month, dateTime.day);
}

class JobDetailPage extends StatefulWidget {
  final Map<String, dynamic> data;
  final String jobId;

  const JobDetailPage({super.key, required this.data, required this.jobId});

  @override
  State<JobDetailPage> createState() => _JobDetailPageState();
}

class _JobDetailPageState extends State<JobDetailPage> {
  bool _isLoading = false;
  bool _hasApplied = false;
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _checkApplicationStatus();
    _checkOwnership();
  }

  Future<void> _checkApplicationStatus() async {
    final user = FirebaseAuth.instance.currentUser!;
    final jobDoc = await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).get();
    if (jobDoc.exists) {
      final data = jobDoc.data() as Map<String, dynamic>;
      setState(() {
        _hasApplied = (data['applicants'] as List?)?.contains(user.uid) ?? false;
      });
    }
  }

  Future<void> _checkOwnership() async {
    final user = FirebaseAuth.instance.currentUser!;
    print('Checking ownership: postedBy=${widget.data['postedBy']}, userUid=${user.uid}');
    setState(() {
      _isOwner = widget.data['postedBy'] == user.uid;
    });
  }

  Future<bool> _checkProfileCompleteness() async {
    final user = FirebaseAuth.instance.currentUser!;
    try {
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('profiledetails')
          .doc('profile')
          .get();

      // Check if profile document exists and has required fields
      if (!profileDoc.exists) {
        return false;
      }

      final data = profileDoc.data() as Map<String, dynamic>;
      // Define required fields for a complete profile (adjust based on your needs)
      // For example, assume 'name' is mandatory
      return data['name'] != null && data['name'].toString().trim().isNotEmpty;
    } catch (e) {
      print('Error checking profile: $e');
      return false;
    }
  }

  Future<void> _acceptJob() async {
    if (_isLoading || _hasApplied) return;

    final user = FirebaseAuth.instance.currentUser!;
    // Check profile completeness
    final isProfileComplete = await _checkProfileCompleteness();
    if (!isProfileComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please complete your profile before applying for a job.', style: GoogleFonts.poppins()),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
      // Navigate to Profile.dart screen (adjust route name or widget as needed)
      Navigator.pushNamed(context, '/ProfileScreen');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
        'applicants': FieldValue.arrayUnion([user.uid]),
      });

      DateTime now = DateTime.now().toLocal();
      DateTime startDate = widget.data['startDate'] != null
          ? dateOnly(DateTime.parse(widget.data['startDate']).toLocal())
          : dateOnly(now);
      if (startDate.isBefore(dateOnly(now))) startDate = dateOnly(now);
      DateTime endDate = widget.data['isShortTerm'] == true && widget.data['endDate'] != null
          ? dateOnly(DateTime.parse(widget.data['endDate']).toLocal())
          : DateTime(now.year, 12, 31);
      if (endDate.isBefore(startDate)) endDate = startDate;

      TimeOfDay startTime = _parseTimeOfDay(widget.data['startTime'] ?? '12:00 AM');
      TimeOfDay endTime = _parseTimeOfDay(widget.data['endTime'] ?? '${startTime.hour + 1}:00 ${startTime.period == DayPeriod.pm ? 'PM' : 'AM'}');

      final task = {
        'title': widget.data['jobPosition'] ?? 'Accepted Job',
        'isTimeBlocked': false,
        'startTime': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
        'endTime': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
      };

      DateTime currentDate = startDate;
      while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('tasks')
            .doc(currentDate.toIso8601String().split('T')[0])
            .set({
          'tasks': FieldValue.arrayUnion([task]),
        }, SetOptions(merge: true));
        currentDate = currentDate.add(const Duration(days: 1));
      }

      print('Task saved successfully');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully applied!')));
      setState(() => _hasApplied = true);
      await Future.delayed(const Duration(milliseconds: 500));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const EditingJobsPage()),
      );
    } catch (error) {
      print('Error accepting job: $error');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to apply: $error')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _contactEmployer() async {
    final user = FirebaseAuth.instance.currentUser!;
    final ownerUid = widget.data['postedBy'];

    print('Contact Employer: ownerUid=$ownerUid, userUid=${user.uid}');

    if (ownerUid == null || ownerUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: Employer UID not found in job data.', style: GoogleFonts.poppins()),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (ownerUid == user.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You cannot chat with yourself as the employer.', style: GoogleFonts.poppins()),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      // Fetch current user's custom ID
      final currentUserCustomIdDoc = await FirebaseFirestore.instance
          .collection('custom_ids')
          .doc(user.uid)
          .get();
      if (!currentUserCustomIdDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: Your custom ID not found.', style: GoogleFonts.poppins()),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      final currentUserCustomId = currentUserCustomIdDoc['customId'];
      print('Current user custom ID: $currentUserCustomId');

      // Fetch owner's custom ID and profile details
      final ownerCustomIdDoc = await FirebaseFirestore.instance
          .collection('custom_ids')
          .doc(ownerUid)
          .get();
      if (!ownerCustomIdDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: Employer ID not found.', style: GoogleFonts.poppins()),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      final ownerCustomId = ownerCustomIdDoc['customId'];
      print('Owner custom ID: $ownerCustomId');

      final ownerProfileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerUid)
          .collection('profiledetails')
          .doc('profile')
          .get();
      if (!ownerProfileDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: Employer profile not found.', style: GoogleFonts.poppins()),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      final ownerName = ownerProfileDoc['name'] ?? 'Employer';
      final ownerPhotoURL = ownerProfileDoc['photoURL'] ?? 'assets/default_avatar.png';
      print('Owner profile: name=$ownerName, photoURL=$ownerPhotoURL');

      // Add chat to user's chat list
      final chatDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chats')
          .doc('chat_list');
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(chatDocRef);
        List<Map<String, dynamic>> updatedChatList = List<Map<String, dynamic>>.from(doc.data()?['users'] ?? []);
        final chatIndex = updatedChatList.indexWhere((chat) => chat['customId'] == ownerCustomId);
        final chatData = {
          'customId': ownerCustomId,
          'name': ownerName,
          'photoURL': ownerPhotoURL,
          'isGroup': false,
        };
        if (chatIndex == -1) {
          updatedChatList.add(chatData);
        } else {
          updatedChatList[chatIndex] = chatData;
        }
        transaction.set(chatDocRef, {'users': updatedChatList}, SetOptions(merge: true));
      });
      print('Chat added to user chat list');

      // Navigate to ChatMessage page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatMessage(
            currentUserCustomId: currentUserCustomId,
            selectedCustomId: ownerCustomId,
            selectedUserName: ownerName,
            selectedUserPhotoURL: ownerPhotoURL,
          ),
        ),
      );
    } catch (e) {
      print('Error in _contactEmployer: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start chat with employer: $e', style: GoogleFonts.poppins()),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    timeStr = timeStr.trim().toUpperCase().replaceAll(' ', '');
    String period = 'AM';
    String normalizedTime;

    if (timeStr.contains('PM')) {
      period = 'PM';
      normalizedTime = timeStr.replaceAll('PM', '');
    } else if (timeStr.contains('AM')) {
      normalizedTime = timeStr.replaceAll('AM', '');
    } else {
      normalizedTime = timeStr;
    }

    List<String> parts = normalizedTime.split(':');
    if (parts.length != 2) throw FormatException('Invalid time format: $timeStr');

    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);

    if (period == 'PM' && hour != 12) hour += 12;
    else if (period == 'AM' && hour == 12) hour = 0;

    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  Widget build(BuildContext context) {
    final taskType = widget.data['isShortTerm'] == true ? 'Short-term' : 'Long-term';
    final salary = widget.data['salary'] ?? '-';
    final requiredSkill = widget.data['requiredSkill'] ?? '-';
    final startTime = widget.data['isShortTerm'] == true && widget.data['startTime'] != null ? widget.data['startTime'] : '-';
    final endTime = widget.data['isShortTerm'] == true && widget.data['endTime'] != null ? widget.data['endTime'] : '-';

    print('Building UI: isOwner=$_isOwner');

    return Scaffold(
      appBar: AppBar(
        title: Text('Job Details', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 18)),
        backgroundColor: const Color(0xFFB2DFDB),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB2DFDB), Colors.white],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(12)),
              child: Center(
                child: Flexible(
                  child: Text(
                    widget.data['jobPosition'] ?? 'Job Title',
                    style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Job Details', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.black87)),
                    const Divider(thickness: 1, color: Colors.grey),
                    _buildDetailRow('Description', widget.data['description'] ?? '-'),
                    _buildDetailRow('Location', widget.data['location'] ?? '-'),
                    _buildDetailRow('Salary', 'RM $salary'),
                    _buildDetailRow('Required Skill', requiredSkill is String ? requiredSkill.split(',').join(', ') : requiredSkill.toString()),
                    _buildDetailRow('Task Type', taskType),
                    _buildDetailRow('Start Date', widget.data['startDate'] ?? '-'),
                    if (widget.data['isShortTerm'] == true) ...[
                      _buildDetailRow('End Date', widget.data['endDate'] ?? '-'),
                      if (startTime != '-') _buildDetailRow('Start Time', startTime),
                      if (endTime != '-') _buildDetailRow('End Time', endTime),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  if (_isOwner)
                    const Text('You cannot apply to your own job', style: TextStyle(fontSize: 16, color: Colors.grey))
                  else
                    _isLoading
                        ? const CircularProgressIndicator(color: Colors.teal)
                        : ElevatedButton(
                      onPressed: _hasApplied ? null : _acceptJob,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hasApplied ? Colors.grey : Colors.teal,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        _hasApplied ? 'Already Applied' : 'Apply Now',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (!_isOwner)
                    ElevatedButton(
                      onPressed: _contactEmployer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[800],
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        'Contact Employer',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black54)),
          ),
          Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: 16, color: Colors.black87))),
        ],
      ),
    );
  }
}