import 'package:flutter/material.dart';
import 'package:fyp/module/ActivityLog.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'LocationPickerPage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddJobPage extends StatefulWidget {
  final String? jobId;
  final Map<String, dynamic>? initialData;

  const AddJobPage({super.key, this.jobId, this.initialData});

  @override
  State<AddJobPage> createState() => _AddJobPageState();
}

class _AddJobPageState extends State<AddJobPage> {
  bool isShortTerm = true;
  bool isRecurring = false;

  final Map<String, TextEditingController> controllers = {
    'Job position*': TextEditingController(),
    'Type of workplace*': TextEditingController(),
    'Job location*': TextEditingController(),
    'Employer/Company Name*': TextEditingController(),
    'Employment type*': TextEditingController(),
    'Salary (RM)*': TextEditingController(),
    'Description': TextEditingController(),
    'Required Skill*': TextEditingController(),
    'Start date*': TextEditingController(),
    'Start time*': TextEditingController(),
    'End date*': TextEditingController(),
    'End time*': TextEditingController(),
    'Recurring Tasks': TextEditingController(),
  };

  final Set<String> visibleInputs = {};

  final List<String> workplaceOptions = ["On-site", "Remote", "Hybrid"];
  final List<String> employmentOptions = ["Full-time", "Part-time", "Contract", "Temporary", "Internship"];

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      controllers['Job position*']!.text = widget.initialData!['jobPosition'] ?? '';
      controllers['Type of workplace*']!.text = widget.initialData!['workplaceType'] ?? '';
      controllers['Job location*']!.text = widget.initialData!['location'] ?? '';
      controllers['Employer/Company Name*']!.text = widget.initialData!['employerName'] ?? '';
      controllers['Employment type*']!.text = widget.initialData!['employmentType'] ?? '';
      controllers['Salary (RM)*']!.text = widget.initialData!['salary']?.toString() ?? '';
      controllers['Description']!.text = widget.initialData!['description'] ?? '';
      controllers['Required Skill*']!.text = widget.initialData!['requiredSkill']?.toString() ?? '';
      controllers['Start date*']!.text = widget.initialData!['startDate'] ?? '';
      controllers['Start time*']!.text = widget.initialData!['startTime'] ?? '';
      controllers['End date*']!.text = widget.initialData!['endDate'] ?? '';
      controllers['End time*']!.text = widget.initialData!['endTime'] ?? '';
      controllers['Recurring Tasks']!.text = widget.initialData!['recurringTasks'] ?? '';
      isShortTerm = widget.initialData!['isShortTerm'] ?? true;
      isRecurring = widget.initialData!['recurring'] ?? false;
      visibleInputs.addAll(controllers.keys.where((key) => controllers[key]!.text.isNotEmpty));
    }
  }

  @override
  void dispose() {
    controllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _submitJob() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    final startDateTime = _parseDateTime(controllers['Start date*']!.text, controllers['Start time*']!.text);
    if (startDateTime != null && startDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start date and time cannot be in the past.'),
          backgroundColor: Color(0xFF006D77),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (currentUser == null) return;

    if (!_isFormValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill out all required fields with (*) sign.'),
          backgroundColor: Color(0xFF006D77),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Validate start and end date/time for short-term tasks
    if (isShortTerm) {
      final startDateTime = _parseDateTime(controllers['Start date*']!.text, controllers['Start time*']!.text);
      final endDateTime = _parseDateTime(controllers['End date*']!.text, controllers['End time*']!.text);
      if (startDateTime == null || endDateTime == null || startDateTime.isAfter(endDateTime)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Start date and time must be earlier than end date and time.'),
            backgroundColor: Color(0xFF006D77),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    final jobData = <String, dynamic>{
      'jobPosition': controllers['Job position*']!.text,
      'workplaceType': controllers['Type of workplace*']!.text,
      'location': controllers['Job location*']!.text,
      'employerName': controllers['Employer/Company Name*']!.text,
      'employmentType': controllers['Employment type*']!.text,
      'salary': int.tryParse(controllers['Salary (RM)*']!.text) ?? 0,
      'description': controllers['Description']!.text,
      'requiredSkill': controllers['Required Skill*']!.text,
      'startDate': controllers['Start date*']!.text,
      'startTime': isShortTerm ? controllers['Start time*']!.text : null,
      'endDate': isShortTerm ? controllers['End date*']!.text : null,
      'endTime': isShortTerm ? controllers['End time*']!.text : null,
      'recurring': isRecurring,
      'recurringTasks': isRecurring ? controllers['Recurring Tasks']!.text : null,
      'isShortTerm': isShortTerm,
      'postedAt': widget.jobId == null ? Timestamp.now() : FieldValue.serverTimestamp(),
      'postedBy': currentUser.uid,
      'acceptedBy': widget.initialData?['acceptedBy'] ?? null,
    };

    try {
      if (widget.jobId != null) {
        await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update(jobData);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job updated successfully!'), backgroundColor: Color(0xFF006D77)),
        );
      } else {
        await FirebaseFirestore.instance.collection('jobs').add(jobData);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job posted successfully!'), backgroundColor: Color(0xFF006D77)),
        );
      }
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to ${widget.jobId != null ? 'update' : 'post'} job: $e'), backgroundColor: Color(0xFF006D77)),
      );
    }
  }

  // Helper method to parse date and time into DateTime
  DateTime? _parseDateTime(String dateStr, String timeStr) {
    try {
      final dateParts = dateStr.split('-');
      if (dateParts.length != 3) return null;
      final timeParts = timeStr.split(':');
      if (timeParts.length != 2) return null;

      final hour = int.parse(timeParts[0].replaceAll(RegExp(r'[^0-9]'), ''));
      final minute = int.parse(timeParts[1].replaceAll(RegExp(r'[^0-9]'), ''));
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      // Determine AM/PM if present (simplified assumption based on format)
      final period = timeStr.contains('PM') && hour != 12 ? 12 : (timeStr.contains('AM') && hour == 12 ? -12 : 0);
      final adjustedHour = (hour + period) % 24;

      return DateTime(year, month, day, adjustedHour, minute);
    } catch (e) {
      print('Error parsing date-time: $e');
      return null;
    }
  }

  Widget _buildDropdownField(String label, List<String> options) {
    final controller = controllers[label]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: const Color(0xFF006D77),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: controller.text.isNotEmpty ? controller.text : null,
            items: options.map((e) => DropdownMenuItem(value: e, child: Text(e, style: GoogleFonts.poppins(color: const Color(0xFF006D77))))).toList(),
            onChanged: (val) => setState(() => controller.text = val ?? ''),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF9F9F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            dropdownColor: Colors.white,
            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF006D77)),
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimePicker(String label, bool isDate) {
    final controller = controllers[label]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: const Color(0xFF006D77),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            readOnly: true,
            onTap: () async {
              final now = DateTime.now();
              final result = isDate
                  ? await showDatePicker(
                context: context,
                initialDate: controller.text.isNotEmpty ? DateTime.parse(controller.text) : now,
                firstDate: now, // Restrict to today or later
                lastDate: DateTime(2100),
              )
                  : await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (result != null) {
                final formatted = isDate
                    ? (result as DateTime).toLocal().toString().split(" ")[0]
                    : (result as TimeOfDay).format(context);
                setState(() => controller.text = formatted);
              }
            },
            decoration: InputDecoration(
              hintText: 'Pick $label',
              filled: true,
              fillColor: const Color(0xFFF9F9F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFF006D77)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldTile(String label) {
    final controller = controllers[label]!;
    final isVisible = visibleInputs.contains(label);
    final hasText = controller.text.isNotEmpty;
    final isSalaryField = label == 'Salary (RM)*';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: const Color(0xFF006D77),
                ),
              ),
              IconButton(
                icon: Icon(
                  hasText ? Icons.edit : Icons.add,
                  color: const Color(0xFF006D77),
                ),
                onPressed: () async {
                  if (label == 'Job location*') {
                    final selected = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LocationPickerPage()),
                    );
                    if (selected != null && selected is String) {
                      setState(() {
                        controllers[label]!.text = selected;
                        visibleInputs.add(label);
                      });
                    }
                  } else {
                    setState(() => visibleInputs.add(label));
                  }
                },
              ),
            ],
          ),
          if (isVisible) ...[
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: isSalaryField ? TextInputType.number : TextInputType.text,
              inputFormatters: isSalaryField ? [FilteringTextInputFormatter.digitsOnly] : null,
              maxLines: label == 'Description' ? 4 : 1,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Enter $label',
                filled: true,
                fillColor: const Color(0xFFF9F9F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isFormValid() {
    for (var entry in controllers.entries) {
      final isRequired = entry.key.endsWith('*');
      final isTimeField = entry.key == 'Start time*' || entry.key == 'End time*';
      if (!isRequired) continue;
      if (!isShortTerm && (entry.key == 'End date*' || isTimeField)) continue; // Skip for long-term
      if (entry.value.text.trim().isEmpty) {
        print('Missing required field: ${entry.key}');
        return false;
      }
    }
    return true;
  }

  Widget _buildSwitchRow({required String label, required bool value, required Function(bool) onChanged}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF006D77),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF006D77),
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF006D77)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.jobId == null ? 'Add a Job' : 'Edit Job',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF006D77),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _submitJob,
              child: Text(
                widget.jobId == null ? 'Post' : 'Save',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF006D77),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.jobId == null ? 'Add a new job' : 'Edit your job',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF006D77),
                ),
              ),
              const SizedBox(height: 16),
              _buildSwitchRow(
                label: isShortTerm ? 'Job Type: Short-term' : 'Job Type: Long-term',
                value: isShortTerm,
                onChanged: (val) => setState(() => isShortTerm = val),
              ),
              _buildSwitchRow(
                label: 'Recurring task',
                value: isRecurring,
                onChanged: (val) => setState(() => isRecurring = val),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    _buildFieldTile('Job position*'),
                    _buildDropdownField('Type of workplace*', workplaceOptions),
                    _buildFieldTile('Job location*'),
                    _buildFieldTile('Employer/Company Name*'),
                    _buildDropdownField('Employment type*', employmentOptions),
                    _buildFieldTile('Salary (RM)*'),
                    _buildFieldTile('Required Skill*'),
                    _buildFieldTile('Description'),
                    _buildDateTimePicker('Start date*', true),
                    if (isShortTerm) _buildDateTimePicker('Start time*', false),
                    if (isShortTerm) _buildDateTimePicker('End date*', true),
                    if (isShortTerm) _buildDateTimePicker('End time*', false),
                    if (isRecurring) _buildFieldTile('Recurring Tasks'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}