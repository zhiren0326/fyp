import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp/Add%20Job%20Module/AddJobPage.dart';
import 'package:fyp/Login%20Signup/Screen/home_screen.dart';
import 'package:google_fonts/google_fonts.dart';

// Custom dateOnly function
DateTime dateOnly(DateTime dateTime) {
  return DateTime(dateTime.year, dateTime.month, dateTime.day);
}

class JobDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final String jobId;

  const JobDetailPage({super.key, required this.data, required this.jobId});

  Future<void> acceptJob(String jobId, BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser!;
    try {
      // Update job status
      await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
        'isAccepted': true,
        'acceptedBy': user.uid,
      });

      // Determine start and end dates based on task type
      DateTime now = DateTime.now().toLocal(); // Current date: 2025-07-21 02:28 AM +08
      DateTime startDate = data['startDate'] != null
          ? dateOnly(DateTime.parse(data['startDate']).toLocal())
          : dateOnly(now); // Default to today, no past dates
      if (startDate.isBefore(dateOnly(now))) {
        startDate = dateOnly(now); // Enforce no past start dates
      }
      DateTime endDate;
      if (data['isShortTerm'] == true && data['endDate'] != null) {
        endDate = dateOnly(DateTime.parse(data['endDate']).toLocal());
        if (endDate.isBefore(startDate)) {
          endDate = startDate; // Ensure end date is not before start date
        }
      } else {
        // Long-term task: extend to end of year as default
        endDate = DateTime(now.year, 12, 31); // 2025-12-31
      }

      // Parse job start and end times
      TimeOfDay startTime = _parseTimeOfDay(data['startTime'] ?? '12:00 AM');
      TimeOfDay endTime = _parseTimeOfDay(data['endTime'] ?? '${startTime.hour + 1}:00 ${startTime.period == DayPeriod.pm ? 'PM' : 'AM'}');

      // Create task with job details
      final task = {
        'title': data['jobPosition'] ?? 'Accepted Job',
        'isTimeBlocked': false,
        'startTime': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
        'endTime': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
      };

      // Save task for each date in the range
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

      print('Task saved successfully from ${startDate.toIso8601String().split('T')[0]} to ${endDate.toIso8601String().split('T')[0]}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully applied!')),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen(initialIndex: 1)),
      );
    } catch (error) {
      print('Error accepting job or creating task: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to apply for job: $error')),
      );
    }
  }

  // Helper method to parse time string robustly
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
    if (parts.length != 2) {
      throw FormatException('Invalid time format: $timeStr');
    }

    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);

    if (period == 'PM' && hour != 12) {
      hour += 12;
    } else if (period == 'AM' && hour == 12) {
      hour = 0;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  Widget build(BuildContext context) {
    final taskType = data['isShortTerm'] == true ? 'Short-term' : 'Long-term';
    final salary = data['salary'] ?? '-';
    final requiredSkill = data['requiredSkill'] ?? '-';
    final startTime = data['isShortTerm'] == true && data['startTime'] != null ? data['startTime'] : '-';
    final endTime = data['isShortTerm'] == true && data['endTime'] != null ? data['endTime'] : '-';
    final isOwner = data['postedBy'] == FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Job Details',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
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
              decoration: BoxDecoration(
                color: Colors.teal,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Flexible(
                  child: Text(
                    data['jobPosition'] ?? 'Job Title',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
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
                    Text(
                      'Job Details',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const Divider(thickness: 1, color: Colors.grey),
                    _buildDetailRow('Description', data['description'] ?? '-'),
                    _buildDetailRow('Location', data['location'] ?? '-'),
                    _buildDetailRow('Salary', 'RM $salary'),
                    _buildDetailRow('Required Skill', requiredSkill is String ? requiredSkill.split(',').join(', ') : requiredSkill.toString()),
                    _buildDetailRow('Task Type', taskType),
                    _buildDetailRow('Start Date', data['startDate'] ?? '-'),
                    if (data['isShortTerm'] == true) ...[
                      _buildDetailRow('End Date', data['endDate'] ?? '-'),
                      if (startTime != '-') _buildDetailRow('Start Time', startTime),
                      if (endTime != '-') _buildDetailRow('End Time', endTime),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: isOwner
                  ? const Text(
                'You cannot apply to your own job',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              )
                  : ElevatedButton(
                onPressed: () async {
                  await acceptJob(jobId, context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  'Apply Now',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
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
            child: Text(
              '$label:',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}