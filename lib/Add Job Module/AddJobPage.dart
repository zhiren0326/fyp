import 'package:flutter/material.dart';
import 'package:fyp/module/ActivityLog.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'LocationPickerPage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddJobPage extends StatefulWidget {
  const AddJobPage({super.key});

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
    'Company name*': TextEditingController(),
    'Employment type*': TextEditingController(),
    'Salary (RM)*': TextEditingController(),
    'Description': TextEditingController(),
    'Start date*': TextEditingController(),
    'Start time*': TextEditingController(),
    'End date*': TextEditingController(),
    'End time*': TextEditingController(),
    'Recurring Tasks': TextEditingController(),
  };

  final Set<String> visibleInputs = {};

  final List<String> workplaceOptions = ["On-site", "Remote", "Hybrid"];
  final List<String> employmentOptions = ["Full-time", "Part-time", "Contract", "Temporary", "Internship"];

  Future<void> _submitJob() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    if (!_isFormValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill out all required fields.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return; // Prevent submission
    }

    final jobData = <String, dynamic>{
      'jobPosition': controllers['Job position*']!.text,
      'workplaceType': controllers['Type of workplace*']!.text,
      'location': controllers['Job location*']!.text,
      'companyName': controllers['Company name*']!.text,
      'employmentType': controllers['Employment type*']!.text,
      'salary': int.tryParse(controllers['Salary (RM)*']!.text) ?? 0,
      'description': controllers['Description']!.text,
      'startDate': controllers['Start date*']!.text,
      'startTime': isShortTerm ? controllers['Start time*']!.text : null,
      'endDate': controllers['End date*']!.text,
      'endTime': isShortTerm ? controllers['End time*']!.text : null,
      'recurring': isRecurring,
      'recurringTasks': isRecurring ? controllers['Recurring Tasks']!.text : null,
      'isShortTerm': isShortTerm,
      'postedAt': Timestamp.now(),
      'postedBy': currentUser.uid,
      'acceptedBy': null,
    };

    try {
      await FirebaseFirestore.instance.collection('jobs').add(jobData);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Success'),
          content: const Text('Job posted successfully!'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                controllers.forEach((key, controller) => controller.clear());
                setState(() {
                  visibleInputs.clear();
                  isRecurring = false;
                  isShortTerm = true;
                });
              },
              child: const Text('Add Another'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to post job: $e')));
    }
  }

  Widget _buildDropdownField(String label, List<String> options) {
    final controller = controllers[label]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: const Color(0xFF1A1053),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: controller.text.isEmpty ? null : controller.text,
            items: options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (val) => setState(() => controller.text = val ?? ""),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimePicker(String label, bool isDate) {
    final controller = controllers[label]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: const Color(0xFF1A1053),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            readOnly: true,
            onTap: () async {
              final result = isDate
                  ? await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100))
                  : await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now());
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
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(12),
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
                  color: const Color(0xFF1A1053),
                ),
              ),
              IconButton(
                icon: Icon(
                  hasText ? Icons.edit : Icons.add,
                  color: const Color(0xFFFF8A00),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  bool _isFormValid() {
    return controllers.entries
        .where((entry) {
      final isRequired = entry.key.endsWith('*');
      final isTimeField = entry.key == 'Start time*' || entry.key == 'End time*';
      if (!isRequired) return false;
      if (!isShortTerm && isTimeField) return false;
      return true;
    })
        .every((entry) => entry.value.text.trim().isNotEmpty);
  }

  Widget _buildSwitchRow({required String label, required bool value, required Function(bool) onChanged}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1053),
            ),
          ),
          Switch(value: value, onChanged: onChanged)
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _submitJob,
            child: const Text(
              'Post',
              style: TextStyle(
                color: Color(0xFFFF8A00),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add a job',
              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  _buildFieldTile('Job position*'),
                  _buildDropdownField('Type of workplace*', workplaceOptions),
                  _buildFieldTile('Job location*'),
                  _buildFieldTile('Company name*'),
                  _buildDropdownField('Employment type*', employmentOptions),
                  _buildFieldTile('Salary (RM)*'),
                  _buildFieldTile('Description'),
                  _buildDateTimePicker('Start date*', true),
                  if (isShortTerm) _buildDateTimePicker('Start time*', false),
                  _buildDateTimePicker('End date*', true),
                  if (isShortTerm) _buildDateTimePicker('End time*', false),
                  if (isRecurring) _buildFieldTile('Recurring Tasks'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
