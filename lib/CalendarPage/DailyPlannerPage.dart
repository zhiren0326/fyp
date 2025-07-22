/*
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_draggable_gridview/flutter_draggable_gridview.dart';
import 'package:fyp/main.dart' show flutterLocalNotificationsPlugin;
import 'package:table_calendar/table_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

DateTime dateOnly(DateTime dateTime) {
  return DateTime(dateTime.year, dateTime.month, dateTime.day);
}

Future<void> scheduleNotification(String title, DateTime scheduledTime) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
    'time_block_channel',
    'Time Block Reminders',
    importance: Importance.max,
    priority: Priority.high,
  );
  const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
  await flutterLocalNotificationsPlugin.zonedSchedule(
    title.hashCode,
    '$title starts now!',
    'Time to focus on your task.',
    tz.TZDateTime.from(scheduledTime, tz.local),
    platformChannelSpecifics,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

class DailyPlannerPage extends StatefulWidget {
  final DateTime initialDate;

  const DailyPlannerPage({super.key, required this.initialDate});

  @override
  State<DailyPlannerPage> createState() => _DailyPlannerPageState();
}

class _DailyPlannerPageState extends State<DailyPlannerPage> {
  late DateTime _selectedDay;
  Map<DateTime, List<Task>> _tasks = {};
  List<TimeSlot> _timeSlots = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = dateOnly(widget.initialDate);
    _initializeTimeSlots();
    _loadTasks();
  }

  void _initializeTimeSlots() {
    _timeSlots = List.generate(9, (index) {
      final hour = 9 + index; // 9 AM to 5 PM
      return TimeSlot(
        startTime: TimeOfDay(hour: hour, minute: 0),
        endTime: TimeOfDay(hour: hour + 1, minute: 0),
      );
    });
  }

  void _loadTasks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final now = dateOnly(DateTime.now().toLocal());
        final jobSnapshot = await FirebaseFirestore.instance
            .collection('jobs')
            .where('acceptedApplicants', arrayContains: user.uid)
            .where('startDate', isGreaterThanOrEqualTo: now.toIso8601String().split('T')[0])
            .limit(50)
            .get();

        final taskSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('tasks')
            .where('date', isEqualTo: dateOnly(_selectedDay).toIso8601String().split('T')[0])
            .limit(50)
            .get();

        setState(() {
          _tasks = {};
          for (var doc in jobSnapshot.docs) {
            final data = doc.data();
            final startDate = data['startDate'] != null
                ? dateOnly(DateTime.parse(data['startDate']).toLocal())
                : now;
            final isShortTerm = data['isShortTerm'] == true;
            final endDate = isShortTerm && data['endDate'] != null
                ? dateOnly(DateTime.parse(data['endDate']).toLocal())
                : startDate;

            final task = Task(
              title: data['jobPosition'] ?? 'Unnamed Job',
              isTimeBlocked: false,
              startTime: _parseTimeOfDay(data['startTime'] ?? '12:00 AM'),
              endTime: _parseTimeOfDay(data['endTime'] ?? '1:00 AM'),
              jobId: doc.id,
            );

            if (!isShortTerm && isSameDay(startDate, _selectedDay)) {
              _tasks.putIfAbsent(startDate, () => []).add(task);
            } else if (isShortTerm) {
              DateTime currentDate = startDate;
              while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
                if (isSameDay(currentDate, _selectedDay) && !currentDate.isBefore(now)) {
                  _tasks.putIfAbsent(currentDate, () => []).add(task);
                }
                currentDate = currentDate.add(const Duration(days: 1));
              }
            }
          }

          for (var doc in taskSnapshot.docs) {
            final data = doc.data();
            final date = dateOnly(DateTime.parse(data['date']));
            final tasksData = data['tasks'] as List<dynamic>? ?? [];
            for (var taskData in tasksData) {
              final task = Task.fromMap(taskData);
              _tasks.putIfAbsent(date, () => []).add(task);
              if (task.isTimeBlocked && date.isAtSameMomentAs(dateOnly(_selectedDay))) {
                final scheduledTime = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  task.startTime.hour,
                  task.startTime.minute,
                );
                if (scheduledTime.isAfter(DateTime.now())) {
                  scheduleNotification(task.title, scheduledTime);
                }
              }
            }
          }

          print('Loaded ${jobSnapshot.docs.length} jobs and ${taskSnapshot.docs.length} tasks for user ${user.uid} on ${_selectedDay.toIso8601String()}');
        });
      } catch (e) {
        print('Error loading tasks: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load tasks: $e')),
        );
      }
    }
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    try {
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
    } catch (e) {
      print('Error parsing time: $timeStr, $e');
      return TimeOfDay(hour: 0, minute: 0);
    }
  }

  Future<void> _saveTask(DateTime date, Task task) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('tasks')
            .doc(date.toIso8601String().split('T')[0])
            .set({
          'date': date.toIso8601String().split('T')[0],
          'tasks': FieldValue.arrayUnion([task.toMap()]),
        }, SetOptions(merge: true));
        print('Task saved for date: ${date.toIso8601String().split('T')[0]}');

        if (task.isTimeBlocked) {
          final scheduledTime = DateTime(
            date.year,
            date.month,
            date.day,
            task.startTime.hour,
            task.startTime.minute,
          );
          if (scheduledTime.isAfter(DateTime.now())) {
            await scheduleNotification(task.title, scheduledTime);
          }
        }
      } catch (e) {
        print('Error saving task: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save task: $e')),
        );
      }
    }
  }

  bool _checkForOverlap(Task newTask, DateTime date, List<Task> existingTasks) {
    for (var task in existingTasks) {
      if (task.isTimeBlocked && task != newTask) {
        final existingStart = DateTime(date.year, date.month, date.day, task.startTime.hour, task.startTime.minute);
        final existingEnd = DateTime(date.year, date.month, date.day, task.endTime.hour, task.endTime.minute);
        final newStart = DateTime(date.year, date.month, date.day, newTask.startTime.hour, newTask.startTime.minute);
        final newEnd = DateTime(date.year, date.month, date.day, newTask.endTime.hour, newTask.endTime.minute);

        if (newStart.isBefore(existingEnd) && newEnd.isAfter(existingStart)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final now = dateOnly(DateTime.now().toLocal());
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
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Daily Planner - ${dateOnly(_selectedDay).toString().split(' ')[0]}',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.teal),
                    ),
                    IconButton(
                      icon: const Icon(Icons.calendar_today, color: Colors.teal),
                      onPressed: () async {
                        final selectedDate = await showDatePicker(
                          context: context,
                          initialDate: _selectedDay,
                          firstDate: now,
                          lastDate: DateTime.utc(2030, 12, 31),
                        );
                        if (selectedDate != null) {
                          setState(() {
                            _selectedDay = selectedDate;
                            _loadTasks();
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: (_tasks[dateOnly(_selectedDay)]?.isEmpty ?? true)
                    ? Center(
                  child: Text(
                    'No tasks for this day',
                    style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
                  ),
                )
                    : Column(
                  children: [
                    Expanded(
                      child: DraggableGridViewBuilder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 1,
                          childAspectRatio: 4,
                        ),
                        children: _tasks[dateOnly(_selectedDay)]!
                            .asMap()
                            .entries
                            .map((entry) => DraggableGridItem(
                          child: Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: ListTile(
                              title: Text(
                                entry.value.title,
                                style: GoogleFonts.poppins(fontSize: 16),
                              ),
                              subtitle: Text(
                                entry.value.isTimeBlocked
                                    ? '${entry.value.startTime.format(context)} - ${entry.value.endTime.format(context)}'
                                    : 'Drag to a time slot',
                                style: GoogleFonts.poppins(fontSize: 14),
                              ),
                            ),
                          ),
                          isDraggable: !entry.value.isTimeBlocked,
                          index: entry.key,
                        ))
                            .toList(),
                        dragCompletion: (List<DraggableGridItem> list, int before, int after) {
                          setState(() {
                            final draggedTask = _tasks[dateOnly(_selectedDay)]!.removeAt(before);
                            _tasks[dateOnly(_selectedDay)]!.insert(after, draggedTask);
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _timeSlots.length,
                        itemBuilder: (context, index) {
                          final slot = _timeSlots[index];
                          final tasksInSlot = (_tasks[dateOnly(_selectedDay)] ?? [])
                              .where((task) =>
                          task.isTimeBlocked &&
                              task.startTime.hour == slot.startTime.hour &&
                              task.startTime.minute == slot.startTime.minute)
                              .toList();
                          return DragTarget<Task>(
                            builder: (context, candidateData, rejectedData) {
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                color: candidateData.isNotEmpty ? Colors.teal.withOpacity(0.2) : null,
                                child: ListTile(
                                  title: Text(
                                    '${slot.startTime.format(context)} - ${slot.endTime.format(context)}',
                                    style: GoogleFonts.poppins(fontSize: 16),
                                  ),
                                  subtitle: tasksInSlot.isEmpty
                                      ? Text('Empty', style: GoogleFonts.poppins(color: Colors.grey))
                                      : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: tasksInSlot
                                        .map((task) => Text(
                                      task.title,
                                      style: GoogleFonts.poppins(fontSize: 14),
                                    ))
                                        .toList(),
                                  ),
                                ),
                              );
                            },
                            onAccept: (task) {
                              if (_checkForOverlap(
                                  task.copyWith(startTime: slot.startTime, endTime: slot.endTime),
                                  dateOnly(_selectedDay),
                                  _tasks[dateOnly(_selectedDay)]!)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Time slot overlaps with another task')),
                                );
                              } else {
                                setState(() {
                                  task.isTimeBlocked = true;
                                  task.startTime = slot.startTime;
                                  task.endTime = slot.endTime;
                                });
                                _saveTask(dateOnly(_selectedDay), task);
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            final result = await showDialog<Task>(
              context: context,
              builder: (context) => AddTaskDialog(),
            );
            if (result != null) {
              setState(() {
                _tasks.putIfAbsent(dateOnly(_selectedDay), () => []).add(result);
              });
              _saveTask(dateOnly(_selectedDay), result);
            }
          },
          backgroundColor: Colors.teal,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class AddTaskDialog extends StatefulWidget {
  @override
  _AddTaskDialogState createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<AddTaskDialog> {
  final _titleController = TextEditingController();
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay _endTime = TimeOfDay.now();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Task', style: GoogleFonts.poppins()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: InputDecoration(labelText: 'Task Title'),
          ),
          TextButton(
            onPressed: () async {
              final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
              if (time != null) setState(() => _startTime = time);
            },
            child: Text('Start Time: ${_startTime.format(context)}'),
          ),
          TextButton(
            onPressed: () async {
              final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
              if (time != null) setState(() => _endTime = time);
            },
            child: Text('End Time: ${_endTime.format(context)}'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_titleController.text.isNotEmpty) {
              Navigator.pop(
                context,
                Task(
                  title: _titleController.text,
                  isTimeBlocked: false,
                  startTime: _startTime,
                  endTime: _endTime,
                ),
              );
            }
          },
          child: Text('Add'),
        ),
      ],
    );
  }
}

class Task {
  final String title;
  bool isTimeBlocked;
  TimeOfDay startTime;
  TimeOfDay endTime;
  final String? jobId;

  Task({
    required this.title,
    this.isTimeBlocked = false,
    required this.startTime,
    required this.endTime,
    this.jobId,
  });

  Task copyWith({TimeOfDay? startTime, TimeOfDay? endTime, bool? isTimeBlocked}) {
    return Task(
      title: title,
      isTimeBlocked: isTimeBlocked ?? this.isTimeBlocked,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      jobId: jobId,
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'isTimeBlocked': isTimeBlocked,
    'startTime': '${startTime.hour}:${startTime.minute}',
    'endTime': '${endTime.hour}:${endTime.minute}',
    'jobId': jobId,
  };

  factory Task.fromMap(Map<String, dynamic> map) {
    final startParts = (map['startTime'] as String).split(':');
    final endParts = (map['endTime'] as String).split(':');
    final startTime = TimeOfDay(
      hour: int.parse(startParts[0]),
      minute: int.parse(startParts[1]),
    );
    final endTime = TimeOfDay(
      hour: int.parse(endParts[0]),
      minute: int.parse(endParts[1]),
    );
    return Task(
      title: map['title'] as String,
      isTimeBlocked: map['isTimeBlocked'] as bool? ?? false,
      startTime: startTime,
      endTime: endTime,
      jobId: map['jobId'] as String?,
    );
  }
}

class TimeSlot {
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  TimeSlot({required this.startTime, required this.endTime});
}*/
