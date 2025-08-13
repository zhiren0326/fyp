import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../models/time_block.dart';

class TimeBlockingPage extends StatefulWidget {
  final DateTime selectedDate;
  final List<Task> tasks;

  const TimeBlockingPage({
    super.key,
    required this.selectedDate,
    required this.tasks,
  });

  @override
  State<TimeBlockingPage> createState() => _TimeBlockingPageState();
}

class _TimeBlockingPageState extends State<TimeBlockingPage> {
  List<TimeBlock> _timeBlocks = [];
  List<Task> _unscheduledTasks = [];
  List<Task> _completedTasks = [];
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  // Time slot configuration
  static const int _startHour = 6; // 6 AM
  static const int _endHour = 23; // 11 PM
  static const int _slotDuration = 30; // 30 minutes per slot

  final List<Color> _blockColors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.indigo,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    _separateTasksByCompletion();
    _loadTimeBlocks();
  }

  void _separateTasksByCompletion() {
    _unscheduledTasks = widget.tasks.where((task) => !task.isCompleted).toList();
    _completedTasks = widget.tasks.where((task) => task.isCompleted).toList();
  }

  Future<void> _loadTimeBlocks() async {
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('timeBlocks')
            .where('date', isEqualTo: dateStr)
            .get();

        setState(() {
          _timeBlocks = snapshot.docs
              .map((doc) => TimeBlock.fromMap(doc.data()))
              .toList();

          // Remove tasks that are already scheduled from unscheduled list (but not completed)
          _unscheduledTasks.removeWhere((task) =>
              _timeBlocks.any((block) => block.taskIds.contains(task.id)));

          _isLoading = false;
        });
      } catch (e) {
        print('Error loading time blocks: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveTimeBlocks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
        final batch = FirebaseFirestore.instance.batch();

        // Delete existing time blocks for this date
        final existingBlocks = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('timeBlocks')
            .where('date', isEqualTo: dateStr)
            .get();

        for (var doc in existingBlocks.docs) {
          batch.delete(doc.reference);
        }

        // Add new time blocks
        for (var block in _timeBlocks) {
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('timeBlocks')
              .doc();
          batch.set(docRef, block.toMap());
        }

        await batch.commit();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Time blocks saved successfully')),
        );
      } catch (e) {
        print('Error saving time blocks: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  List<TimeSlot> _generateTimeSlots() {
    List<TimeSlot> slots = [];
    for (int hour = _startHour; hour < _endHour; hour++) {
      for (int minute = 0; minute < 60; minute += _slotDuration) {
        slots.add(TimeSlot(
          startTime: TimeOfDay(hour: hour, minute: minute),
          endTime: TimeOfDay(
            hour: minute + _slotDuration >= 60 ? hour + 1 : hour,
            minute: (minute + _slotDuration) % 60,
          ),
        ));
      }
    }
    return slots;
  }

  bool _isSlotOccupied(TimeSlot slot) {
    return _timeBlocks.any((block) =>
        _timesOverlap(slot.startTime, slot.endTime, block.startTime, block.endTime));
  }

  bool _timesOverlap(TimeOfDay start1, TimeOfDay end1, TimeOfDay start2, TimeOfDay end2) {
    final start1Minutes = start1.hour * 60 + start1.minute;
    final end1Minutes = end1.hour * 60 + end1.minute;
    final start2Minutes = start2.hour * 60 + start2.minute;
    final end2Minutes = end2.hour * 60 + end2.minute;

    return start1Minutes < end2Minutes && end1Minutes > start2Minutes;
  }

  void _createTimeBlock(TimeSlot slot) {
    showDialog(
      context: context,
      builder: (context) => _TimeBlockDialog(
        initialStartTime: slot.startTime,
        initialEndTime: slot.endTime,
        availableTasks: _unscheduledTasks, // Only non-completed tasks
        colors: _blockColors,
        selectedDate: widget.selectedDate,
        onSave: (timeBlock) {
          setState(() {
            _timeBlocks.add(timeBlock);
            // Remove scheduled tasks from unscheduled list
            _unscheduledTasks.removeWhere((task) =>
                timeBlock.taskIds.contains(task.id));
          });
          _saveTimeBlocks();
        },
      ),
    );
  }

  void _editTimeBlock(TimeBlock block) {
    showDialog(
      context: context,
      builder: (context) => _TimeBlockDialog(
        initialStartTime: block.startTime,
        initialEndTime: block.endTime,
        initialTitle: block.title,
        initialColor: block.color,
        initialTaskIds: block.taskIds,
        availableTasks: [..._unscheduledTasks, ...widget.tasks.where((task) =>
        block.taskIds.contains(task.id) && !task.isCompleted)], // Exclude completed tasks
        colors: _blockColors,
        selectedDate: widget.selectedDate,
        onSave: (updatedBlock) {
          setState(() {
            final index = _timeBlocks.indexOf(block);
            _timeBlocks[index] = updatedBlock;

            // Recalculate unscheduled tasks (exclude completed ones)
            _unscheduledTasks = widget.tasks.where((task) =>
            !task.isCompleted && !_timeBlocks.any((b) => b.taskIds.contains(task.id))).toList();
          });
          _saveTimeBlocks();
        },
      ),
    );
  }

  void _deleteTimeBlock(TimeBlock block) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Time Block'),
        content: Text('Are you sure you want to delete "${block.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _timeBlocks.remove(block);
                // Add non-completed tasks back to unscheduled list
                for (String taskId in block.taskIds) {
                  final task = widget.tasks.firstWhere(
                        (t) => t.id == taskId,
                    orElse: () => Task(
                      id: taskId,
                      title: 'Unknown Task',
                      startTime: const TimeOfDay(hour: 9, minute: 0),
                      endTime: const TimeOfDay(hour: 10, minute: 0),
                    ),
                  );
                  if (!task.isCompleted && !_unscheduledTasks.contains(task)) {
                    _unscheduledTasks.add(task);
                  }
                }
              });
              _saveTimeBlocks();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Handle task drop on time slot (only for non-completed tasks)
  void _onTaskDropped(Task task, TimeSlot slot) {
    if (task.isCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot schedule completed tasks'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isSlotOccupied(slot)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Time slot is already occupied')),
      );
      return;
    }

    final timeBlock = TimeBlock(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: task.title,
      date: widget.selectedDate,
      startTime: slot.startTime,
      endTime: slot.endTime,
      color: _blockColors[_timeBlocks.length % _blockColors.length],
      taskIds: [task.id],
    );

    setState(() {
      _timeBlocks.add(timeBlock);
      _unscheduledTasks.remove(task);
    });

    _saveTimeBlocks();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${task.title} scheduled successfully')),
    );
  }

  Widget _buildTimeSlotGrid() {
    final timeSlots = _generateTimeSlots();

    return ListView.builder(
      controller: _scrollController,
      itemCount: timeSlots.length,
      itemBuilder: (context, index) {
        final slot = timeSlots[index];
        final isOccupied = _isSlotOccupied(slot);
        final timeBlock = _timeBlocks.firstWhere(
              (block) => _timesOverlap(slot.startTime, slot.endTime, block.startTime, block.endTime),
          orElse: () => TimeBlock(
            id: '',
            title: '',
            date: widget.selectedDate,
            startTime: slot.startTime,
            endTime: slot.endTime,
            color: Colors.grey,
          ),
        );

        return Container(
          height: 60,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            children: [
              // Time label
              SizedBox(
                width: 80,
                child: Text(
                  slot.startTime.format(context),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Time block or empty slot with drag target
              Expanded(
                child: DragTarget<Task>(
                  onWillAccept: (task) => task != null && !task.isCompleted,
                  onAccept: (task) => _onTaskDropped(task, slot),
                  builder: (context, candidateData, rejectedData) {
                    final isDraggedOver = candidateData.isNotEmpty;
                    return GestureDetector(
                      onTap: isOccupied ? () => _editTimeBlock(timeBlock) : () => _createTimeBlock(slot),
                      onLongPress: isOccupied ? () => _deleteTimeBlock(timeBlock) : null,
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: isDraggedOver
                              ? Colors.green.withOpacity(0.3)
                              : isOccupied
                              ? timeBlock.color.withOpacity(0.3)
                              : Colors.grey[100],
                          border: Border.all(
                            color: isDraggedOver
                                ? Colors.green
                                : isOccupied
                                ? timeBlock.color
                                : Colors.grey[300]!,
                            width: isDraggedOver || isOccupied ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: isOccupied
                              ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                timeBlock.title,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: timeBlock.color,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (timeBlock.taskIds.isNotEmpty)
                                Text(
                                  '${timeBlock.taskIds.length} task${timeBlock.taskIds.length > 1 ? 's' : ''}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: timeBlock.color.withOpacity(0.7),
                                  ),
                                ),
                            ],
                          )
                              : isDraggedOver
                              ? const Icon(
                            Icons.schedule,
                            color: Colors.green,
                            size: 20,
                          )
                              : Icon(
                            Icons.add,
                            color: Colors.grey[400],
                            size: 20,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUnscheduledTasks() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unscheduled Tasks Section
          if (_unscheduledTasks.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Unscheduled Tasks (${_unscheduledTasks.length})',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[700],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Drag to schedule',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.orange[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _unscheduledTasks.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) {
                    newIndex -= 1;
                  }
                  final Task item = _unscheduledTasks.removeAt(oldIndex);
                  _unscheduledTasks.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final task = _unscheduledTasks[index];
                return _buildDraggableTaskTile(task, index);
              },
            ),
          ],

          // Completed Tasks Section
          if (_completedTasks.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: _unscheduledTasks.isEmpty
                    ? const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                )
                    : BorderRadius.zero,
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Completed Tasks (${_completedTasks.length})',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Cannot be scheduled',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.green[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _completedTasks.length,
              itemBuilder: (context, index) {
                final task = _completedTasks[index];
                return _buildCompletedTaskTile(task);
              },
            ),
          ],

          if (_unscheduledTasks.isEmpty && _completedTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.task_alt, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text(
                    'All tasks are scheduled or completed',
                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDraggableTaskTile(Task task, int index) {
    final isJobTask = task.id.startsWith('job_');

    return Draggable<Task>(
      key: Key(task.id),
      data: task,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.title,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        color: Colors.blue[700],
                      ),
                    ),
                    Text(
                      '${task.category} • ${task.estimatedDuration} min',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.blue[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: ListTile(
          leading: Icon(
            Icons.drag_indicator,
            color: Colors.grey[400],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
              ),
              if (isJobTask)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'JOB',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Text(
            '${task.category} • ${task.estimatedDuration} min',
            style: GoogleFonts.poppins(fontSize: 12),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.schedule),
            onPressed: () => _quickScheduleTask(task),
          ),
        ),
      ),
      child: ListTile(
        key: Key(task.id),
        leading: Icon(
          Icons.drag_indicator,
          color: Colors.grey[600],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                task.title,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
            ),
            if (isJobTask)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'JOB',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${task.category} • ${task.estimatedDuration} min',
          style: GoogleFonts.poppins(fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.schedule),
          onPressed: () => _quickScheduleTask(task),
        ),
      ),
    );
  }

  Widget _buildCompletedTaskTile(Task task) {
    final isJobTask = task.id.startsWith('job_');

    return ListTile(
      leading: Icon(
        Icons.check_circle,
        color: Colors.green[600],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              task.title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.lineThrough,
                color: Colors.grey[600],
              ),
            ),
          ),
          if (isJobTask)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'JOB',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'COMPLETED',
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        '${task.category} • ${task.estimatedDuration} min',
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  void _quickScheduleTask(Task task) {
    if (task.isCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot schedule completed tasks'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final slots = _generateTimeSlots();
    final availableSlots = slots.where((slot) => !_isSlotOccupied(slot)).toList();

    if (availableSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No available time slots')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Schedule "${task.title}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select a time slot:'),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: availableSlots.take(10).length,
                itemBuilder: (context, index) {
                  final slot = availableSlots[index];
                  return ListTile(
                    title: Text(
                      '${slot.startTime.format(context)} - ${slot.endTime.format(context)}',
                    ),
                    onTap: () {
                      final timeBlock = TimeBlock(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: task.title,
                        date: widget.selectedDate,
                        startTime: slot.startTime,
                        endTime: slot.endTime,
                        color: _blockColors[_timeBlocks.length % _blockColors.length],
                        taskIds: [task.id],
                      );

                      setState(() {
                        _timeBlocks.add(timeBlock);
                        _unscheduledTasks.remove(task);
                      });

                      _saveTimeBlocks();
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Time Blocking',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.teal[800]),
              ),
              Text(
                DateFormat('EEEE, MMMM d, y').format(widget.selectedDate),
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.teal[600]),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Time Blocking Tips'),
                    content: const Text(
                      '• Tap empty slots to create time blocks\n'
                          '• Tap existing blocks to edit them\n'
                          '• Long press blocks to delete them\n'
                          '• Drag tasks from the list to time slots\n'
                          '• Reorder tasks by dragging within the list\n'
                          '• Use different colors for different activities\n'
                          '• Completed tasks cannot be scheduled',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.help_outline, color: Colors.teal),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            _buildUnscheduledTasks(),
            Expanded(child: _buildTimeSlotGrid()),
          ],
        ),
      ),
    );
  }
}

class _TimeBlockDialog extends StatefulWidget {
  final TimeOfDay initialStartTime;
  final TimeOfDay initialEndTime;
  final String? initialTitle;
  final Color? initialColor;
  final List<String> initialTaskIds;
  final List<Task> availableTasks;
  final List<Color> colors;
  final DateTime selectedDate;
  final Function(TimeBlock) onSave;

  const _TimeBlockDialog({
    required this.initialStartTime,
    required this.initialEndTime,
    this.initialTitle,
    this.initialColor,
    this.initialTaskIds = const [],
    required this.availableTasks,
    required this.colors,
    required this.selectedDate,
    required this.onSave,
  });

  @override
  State<_TimeBlockDialog> createState() => _TimeBlockDialogState();
}

class _TimeBlockDialogState extends State<_TimeBlockDialog> {
  late TextEditingController _titleController;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late Color _selectedColor;
  late List<String> _selectedTaskIds;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _startTime = widget.initialStartTime;
    _endTime = widget.initialEndTime;
    _selectedColor = widget.initialColor ?? widget.colors[0];
    _selectedTaskIds = List.from(widget.initialTaskIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initialTitle != null ? 'Edit Time Block' : 'Create Time Block',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Block Title',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: const Text('Start Time'),
                    subtitle: Text(_startTime.format(context)),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _startTime,
                      );
                      if (time != null) {
                        setState(() => _startTime = time);
                      }
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: const Text('End Time'),
                    subtitle: Text(_endTime.format(context)),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _endTime,
                      );
                      if (time != null) {
                        setState(() => _endTime = time);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Color', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: widget.colors.map((color) {
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: _selectedColor == color
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (widget.availableTasks.isNotEmpty) ...[
              Text('Assign Tasks', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: widget.availableTasks.length,
                  itemBuilder: (context, index) {
                    final task = widget.availableTasks[index];
                    final isSelected = _selectedTaskIds.contains(task.id);
                    final isJobTask = task.id.startsWith('job_');

                    return CheckboxListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(task.title),
                          ),
                          if (isJobTask)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'JOB',
                                style: GoogleFonts.poppins(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text('${task.category} • ${task.estimatedDuration} min'),
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedTaskIds.add(task.id);
                          } else {
                            _selectedTaskIds.remove(task.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_titleController.text.trim().isNotEmpty) {
              final timeBlock = TimeBlock(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: _titleController.text.trim(),
                date: widget.selectedDate,
                startTime: _startTime,
                endTime: _endTime,
                color: _selectedColor,
                taskIds: _selectedTaskIds,
              );

              widget.onSave(timeBlock);
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class TimeSlot {
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  TimeSlot({required this.startTime, required this.endTime});
}