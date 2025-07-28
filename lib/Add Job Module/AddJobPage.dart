import 'package:flutter/material.dart';
import 'package:fyp/module/ActivityLog.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../Notification Module/NotificationService.dart';
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
  bool isTimeBlocked = false;

  // Task Management additions
  String selectedPriority = 'Medium';
  List<String> taskDependencies = [];
  List<String> availableTasks = [];

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
    'Required People*': TextEditingController(),
    'Task Notes': TextEditingController(),
  };

  final Set<String> visibleInputs = {};

  final List<String> workplaceOptions = ["On-site", "Remote", "Hybrid"];
  final List<String> employmentOptions = [
    "Full-time",
    "Part-time",
    "Contract",
    "Temporary",
    "Internship"
  ];
  final List<String> priorityLevels = ["Low", "Medium", "High", "Critical"];

  @override
  void initState() {
    super.initState();
    _loadAvailableTasks();
    if (widget.initialData != null) {
      _populateFromInitialData();
    }
  }

  void _populateFromInitialData() {
    final data = widget.initialData!;
    controllers['Job position*']?.text = data['jobPosition'] ?? '';
    controllers['Type of workplace*']?.text = data['workplaceType'] ?? '';
    controllers['Job location*']?.text = data['location'] ?? '';
    controllers['Employer/Company Name*']?.text = data['employerName'] ?? '';
    controllers['Employment type*']?.text = data['employmentType'] ?? '';
    controllers['Salary (RM)*']?.text = data['salary']?.toString() ?? '';
    controllers['Description']?.text = data['description'] ?? '';
    controllers['Required Skill*']?.text = data['requiredSkill']?.toString() ?? '';
    controllers['Start date*']?.text = data['startDate'] ?? '';
    controllers['Start time*']?.text = data['startTime'] ?? '';
    controllers['End date*']?.text = data['endDate'] ?? '';
    controllers['End time*']?.text = data['endTime'] ?? '';
    controllers['Recurring Tasks']?.text = data['recurringTasks'] ?? '';
    controllers['Required People*']?.text = data['requiredPeople']?.toString() ?? '1';
    controllers['Task Notes']?.text = data['taskNotes'] ?? '';

    // Task management fields
    isShortTerm = data['isShortTerm'] ?? true;
    isRecurring = data['recurring'] ?? false;
    selectedPriority = data['priority'] ?? 'Medium';
    taskDependencies = List<String>.from(data['dependencies'] ?? []);
    isTimeBlocked = data['isTimeBlocked'] ?? false;

    visibleInputs.addAll(
        controllers.keys.where((key) => (controllers[key]?.text ?? '').isNotEmpty));
  }

  Future<void> _loadAvailableTasks() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final tasksSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('tasks')
          .get();

      List<String> tasks = [];
      for (var doc in tasksSnapshot.docs) {
        final data = doc.data();
        if (data['tasks'] != null) {
          for (var task in data['tasks']) {
            if (task['title'] != null && !tasks.contains(task['title'])) {
              tasks.add(task['title']);
            }
          }
        }
      }

      setState(() {
        availableTasks = tasks;
      });
    } catch (e) {
      print('Error loading available tasks: $e');
    }
  }

  @override
  void dispose() {
    controllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _submitJob() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      _showSnackBar('User not authenticated.');
      return;
    }

    // Validate deadlines
    if (!_validateDeadlines()) return;

    if (!_isFormValid()) {
      _showSnackBar('Please fill out all required fields with (*) sign.');
      return;
    }

    final startDateTime = _parseDateTime(
        controllers['Start date*']?.text ?? '', controllers['Start time*']?.text ?? '');
    if (startDateTime != null && startDateTime.isBefore(DateTime.now())) {
      _showSnackBar('Start date and time cannot be in the past.');
      return;
    }

    if (isShortTerm) {
      final endDateTime = _parseDateTime(
          controllers['End date*']?.text ?? '', controllers['End time*']?.text ?? '');
      if (startDateTime == null || endDateTime == null ||
          startDateTime.isAfter(endDateTime)) {
        _showSnackBar(
            'Start date and time must be earlier than end date and time.');
        return;
      }
    }

    final requiredPeople = int.tryParse(
        controllers['Required People*']?.text ?? '1') ?? 1;
    if (requiredPeople < 1) {
      _showSnackBar('Required people must be at least 1.');
      return;
    }

    final jobData = _buildJobData(currentUser.uid, requiredPeople);

    try {
      DocumentReference docRef;
      if (widget.jobId != null) {
        docRef =
            FirebaseFirestore.instance.collection('jobs').doc(widget.jobId);
        await docRef.update(jobData);
        _showSnackBar('Job updated successfully!');

        // Update task progress tracking
        await _updateTaskProgress(docRef.id, true);
      } else {
        docRef =
        await FirebaseFirestore.instance.collection('jobs').add(jobData);
        await docRef.update({'jobId': docRef.id});
        _showSnackBar('Job posted successfully!');

        // Create task progress tracking
        await _createTaskProgress(docRef.id);

        // Schedule deadline reminders if it's a short-term job
        if (isShortTerm) {
          final endDateTime = _parseDateTime(
              controllers['End date*']?.text ?? '', controllers['End time*']?.text ?? '');
          if (endDateTime != null) {
            await NotificationService().scheduleDeadlineReminders(
              taskId: docRef.id,
              taskTitle: controllers['Job position*']?.text ?? 'Task',
              deadline: endDateTime,
            );
          }
        }
      }

      // Log activity
      await _logActivity(
          widget.jobId != null ? 'Updated' : 'Created', docRef.id);

      Navigator.pop(context, docRef.id);
    } catch (e) {
      _showSnackBar(
          'Failed to ${widget.jobId != null ? 'update' : 'post'} job: $e');
    }
  }

  Map<String, dynamic> _buildJobData(String userId, int requiredPeople) {
    return {
      'jobPosition': controllers['Job position*']?.text ?? '',
      'workplaceType': controllers['Type of workplace*']?.text ?? '',
      'location': controllers['Job location*']?.text ?? '',
      'employerName': controllers['Employer/Company Name*']?.text ?? '',
      'employmentType': controllers['Employment type*']?.text ?? '',
      'salary': int.tryParse(controllers['Salary (RM)*']?.text ?? '0') ?? 0,
      'description': controllers['Description']?.text ?? '',
      'requiredSkill': (controllers['Required Skill*']?.text ?? '').split(',').map((s) => s.trim()).toList(),
      'startDate': controllers['Start date*']?.text ?? '',
      'startTime': isShortTerm ? controllers['Start time*']?.text : null,
      'endDate': isShortTerm ? controllers['End date*']?.text : null,
      'endTime': isShortTerm ? controllers['End time*']?.text : null,
      'recurring': isRecurring,
      'recurringTasks': isRecurring ? controllers['Recurring Tasks']?.text : null,
      'isShortTerm': isShortTerm,
      'requiredPeople': requiredPeople,
      'applicants': [],
      'acceptedApplicants': [],
      'isCompleted': false,
      'postedAt': widget.jobId == null ? Timestamp.now() : FieldValue.serverTimestamp(),
      'postedBy': userId,

      // Task Management additions
      'priority': selectedPriority,
      'dependencies': taskDependencies,
      'isTimeBlocked': isTimeBlocked,
      'taskNotes': controllers['Task Notes']?.text ?? '',
      'progressPercentage': 0,
      'milestones': [],
      'estimatedDuration': _calculateEstimatedDuration(),
      'actualDuration': null,
      'deadlineReminders': _createDeadlineReminders(),
    };
  }

  bool _validateDeadlines() {
    if ((controllers['Start date*']?.text ?? '').isEmpty) {
      _showSnackBar('Start date is required.');
      return false;
    }

    final startDate = DateTime.tryParse(controllers['Start date*']?.text ?? '');
    if (startDate == null) {
      _showSnackBar('Invalid start date format.');
      return false;
    }

    if (isShortTerm && (controllers['End date*']?.text ?? '').isNotEmpty) {
      final endDate = DateTime.tryParse(controllers['End date*']?.text ?? '');
      if (endDate == null) {
        _showSnackBar('Invalid end date format.');
        return false;
      }
      if (endDate.isBefore(startDate)) {
        _showSnackBar('End date must be after start date.');
        return false;
      }
    }

    return true;
  }

  int _calculateEstimatedDuration() {
    if (!isShortTerm) return 0;

    final startDate = DateTime.tryParse(controllers['Start date*']?.text ?? '');
    final endDate = DateTime.tryParse(controllers['End date*']?.text ?? '');

    if (startDate != null && endDate != null) {
      return endDate.difference(startDate).inDays;
    }
    return 0;
  }

  List<Map<String, dynamic>> _createDeadlineReminders() {
    List<Map<String, dynamic>> reminders = [];

    if ((controllers['Start date*']?.text ?? '').isNotEmpty) {
      final startDate = DateTime.tryParse(controllers['Start date*']?.text ?? '');
      if (startDate != null) {
        // Add reminder 1 day before start
        reminders.add({
          'type': 'start_reminder',
          'reminderDate': startDate.subtract(const Duration(days: 1)).toIso8601String(),
          'message': 'Task "${controllers['Job position*']?.text ?? 'Task'}" starts tomorrow',
          'sent': false,
        });
      }
    }

    if (isShortTerm && (controllers['End date*']?.text ?? '').isNotEmpty) {
      final endDate = DateTime.tryParse(controllers['End date*']?.text ?? '');
      if (endDate != null) {
        // Add reminder 1 day before deadline
        reminders.add({
          'type': 'deadline_reminder',
          'reminderDate': endDate.subtract(const Duration(days: 1)).toIso8601String(),
          'message': 'Task "${controllers['Job position*']?.text ?? 'Task'}" deadline is tomorrow',
          'sent': false,
        });
      }
    }

    return reminders;
  }

  Future<void> _createTaskProgress(String jobId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('taskProgress')
          .doc(jobId)
          .set({
        'taskId': jobId,
        'taskTitle': controllers['Job position*']?.text ?? 'Task',
        'currentProgress': 0,
        'milestones': [],
        'createdAt': Timestamp.now(),
        'lastUpdated': Timestamp.now(),
        'status': 'created',
      });
    } catch (e) {
      print('Error creating task progress: $e');
    }
  }

  Future<void> _updateTaskProgress(String jobId, bool isUpdate) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('taskProgress')
          .doc(jobId)
          .update({
        'taskTitle': controllers['Job position*']?.text ?? 'Task',
        'lastUpdated': Timestamp.now(),
        'status': 'updated',
      });
    } catch (e) {
      print('Error updating task progress: $e');
    }
  }

  Future<void> _logActivity(String action, String taskId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('activityLog')
          .add({
        'action': action,
        'taskId': taskId,
        'taskTitle': controllers['Job position*']?.text ?? 'Task',
        'timestamp': Timestamp.now(),
        'details': {
          'priority': selectedPriority,
          'isRecurring': isRecurring,
          'isTimeBlocked': isTimeBlocked,
        }
      });
    } catch (e) {
      print('Error logging activity: $e');
    }
  }

  DateTime? _parseDateTime(String dateStr, String timeStr) {
    try {
      if (dateStr.isEmpty || timeStr.isEmpty) return null;

      final dateParts = dateStr.split('-');
      if (dateParts.length != 3) return null;
      final timeParts = timeStr.split(':');
      if (timeParts.length != 2) return null;

      final hour = int.parse(timeParts[0].replaceAll(RegExp(r'[^0-9]'), ''));
      final minute = int.parse(timeParts[1].replaceAll(RegExp(r'[^0-9]'), ''));
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      final period = timeStr.contains('PM') && hour != 12 ? 12 : (timeStr.contains('AM') && hour == 12 ? -12 : 0);
      final adjustedHour = (hour + period) % 24;

      return DateTime(year, month, day, adjustedHour, minute);
    } catch (e) {
      print('Error parsing date-time: $e');
      return null;
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF006D77),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildPrioritySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Task Priority', style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: const Color(0xFF006D77))),
          const SizedBox(height: 8),
          Row(
            children: priorityLevels.map((priority) {
              final isSelected = selectedPriority == priority;
              Color priorityColor = _getPriorityColor(priority);

              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => selectedPriority = priority),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? priorityColor : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: priorityColor, width: isSelected ? 2 : 1),
                    ),
                    child: Text(
                      priority,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: isSelected ? Colors.white : priorityColor,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'Low':
        return Colors.green;
      case 'Medium':
        return Colors.orange;
      case 'High':
        return Colors.red;
      case 'Critical':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Widget _buildDependenciesSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Task Dependencies', style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: const Color(0xFF006D77))),
              IconButton(
                icon: const Icon(Icons.add, color: Color(0xFF006D77)),
                onPressed: _showDependencySelector,
              ),
            ],
          ),
          if (taskDependencies.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: taskDependencies.map((dependency) {
                return Chip(
                  label: Text(dependency, style: GoogleFonts.poppins(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => setState(() => taskDependencies.remove(dependency)),
                  backgroundColor: const Color(0xFFB2DFDB),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _showDependencySelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Dependencies'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: availableTasks.map((task) {
              final isSelected = taskDependencies.contains(task);
              return CheckboxListTile(
                title: Text(task),
                value: isSelected,
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true && !taskDependencies.contains(task)) {
                      taskDependencies.add(task);
                    } else if (value == false) {
                      taskDependencies.remove(task);
                    }
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField(String label, List<String> options) {
    final controller = controllers[label];
    if (controller == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600,
              fontSize: 14,
              color: const Color(0xFF006D77))),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: controller.text.isNotEmpty ? controller.text : null,
            items: options.map((e) => DropdownMenuItem(value: e,
                child: Text(e, style: GoogleFonts.poppins(
                    color: const Color(0xFF006D77))))).toList(),
            onChanged: (val) => setState(() => controller.text = val ?? ''),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF9F9F9),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
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
    final controller = controllers[label];
    if (controller == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600,
              fontSize: 14,
              color: const Color(0xFF006D77))),
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
                firstDate: now,
                lastDate: DateTime(2100),
              )
                  : await showTimePicker(context: context, initialTime: TimeOfDay.now());
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
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFF006D77)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldTile(String label) {
    final controller = controllers[label];
    if (controller == null) return const SizedBox.shrink();

    final isVisible = visibleInputs.contains(label);
    final hasText = controller.text.isNotEmpty;
    final isSalaryField = label == 'Salary (RM)*';
    final isRequiredPeopleField = label == 'Required People*';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))
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
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: const Color(0xFF006D77)),
              ),
              IconButton(
                icon: Icon(hasText ? Icons.edit : Icons.add, color: const Color(0xFF006D77)),
                onPressed: () async {
                  if (label == 'Job location*') {
                    final selected = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LocationPickerPage()),
                    );
                    if (selected != null && selected is String) {
                      setState(() {
                        controller.text = selected;
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
              keyboardType: isSalaryField || isRequiredPeopleField
                  ? TextInputType.number
                  : TextInputType.text,
              inputFormatters: isSalaryField || isRequiredPeopleField ? [
                FilteringTextInputFormatter.digitsOnly
              ] : null,
              maxLines: label == 'Description' || label == 'Recurring Tasks' ||
                  label == 'Task Notes' ? 4 : 1,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Enter $label',
                filled: true,
                fillColor: const Color(0xFFF9F9F9),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
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
      if (!isShortTerm && (entry.key == 'End date*' || isTimeField)) continue;
      if ((entry.value.text).trim().isEmpty) {
        print('Missing required field: ${entry.key}');
        return false;
      }
    }
    return true;
  }

  Widget _buildSwitchRow(
      {required String label, required bool value, required Function(bool) onChanged}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF006D77))),
          Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFF006D77)),
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
            style: GoogleFonts.poppins(fontSize: 24,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF006D77)),
          ),
          actions: [
            TextButton(
              onPressed: _submitJob,
              child: Text(
                widget.jobId == null ? 'Post' : 'Save',
                style: GoogleFonts.poppins(color: const Color(0xFF006D77),
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
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
                style: GoogleFonts.poppins(fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF006D77)),
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
                    _buildSwitchRow(
                      label: isShortTerm ? 'Job Type: Short-term' : 'Job Type: Long-term',
                      value: isShortTerm,
                      onChanged: (val) => setState(() => isShortTerm = val),
                    ),
                    _buildSwitchRow(
                      label: 'Recurring Task',
                      value: isRecurring,
                      onChanged: (val) => setState(() => isRecurring = val),
                    ),
                    _buildSwitchRow(
                      label: 'Time Blocking',
                      value: isTimeBlocked,
                      onChanged: (val) => setState(() => isTimeBlocked = val),
                    ),
                    _buildPrioritySelector(),
                    _buildDependenciesSelector(),
                    _buildDateTimePicker('Start date*', true),
                    if (isShortTerm) _buildDateTimePicker('Start time*', false),
                    if (isShortTerm) _buildDateTimePicker('End date*', true),
                    if (isShortTerm) _buildDateTimePicker('End time*', false),
                    if (isRecurring) _buildFieldTile('Recurring Tasks'),
                    _buildFieldTile('Task Notes'),
                    _buildFieldTile('Required People*'),
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