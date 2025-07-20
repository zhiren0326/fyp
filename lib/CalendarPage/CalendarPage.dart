import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

// Custom dateOnly function
DateTime dateOnly(DateTime dateTime) {
  return DateTime(dateTime.year, dateTime.month, dateTime.day);
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now().toLocal(); // Start with current date: 2025-07-21
  DateTime? _selectedDay;
  Map<DateTime, List<Task>> _tasks = {};
  final TextEditingController _taskController = TextEditingController();
  bool _isPomodoroRunning = false;
  int _pomodoroMinutes = 25;
  int _breakMinutes = 5;
  Timer? _timer;
  int _remainingSeconds = 0;
  bool _isBreak = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadTasks();
  }

  void _loadTasks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final now = dateOnly(DateTime.now().toLocal()); // Current date: 2025-07-21
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('tasks')
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: now.toIso8601String().split('T')[0])
            .get();
        setState(() {
          _tasks = {
            for (var doc in snapshot.docs)
              dateOnly(DateTime.parse(doc.id)): // Use custom dateOnly
              (doc.data()['tasks'] as List<dynamic>? ?? [])
                  .map((t) => Task.fromMap(t as Map<String, dynamic>))
                  .toList()
          };
          print('Loaded tasks for user ${user.uid}: $_tasks');
        });
      } catch (e) {
        print('Error loading tasks: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load tasks: $e')),
        );
      }
    } else {
      print('No user logged in');
    }
  }

  void _addTask() {
    if (_taskController.text.isNotEmpty) {
      final task = Task(
        title: _taskController.text,
        isTimeBlocked: false,
        startTime: TimeOfDay.now(),
        endTime: TimeOfDay.now().replacing(hour: TimeOfDay.now().hour + 1),
      );
      final taskDate = dateOnly(_selectedDay!);
      if (taskDate.isBefore(dateOnly(DateTime.now().toLocal()))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot add tasks for past dates.')),
        );
        return;
      }
      setState(() {
        _tasks.putIfAbsent(taskDate, () => []).add(task);
      });
      _saveTask(taskDate, task);
      _taskController.clear();
    }
  }

  void _saveTask(DateTime date, Task task) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .doc(date.toIso8601String().split('T')[0])
          .set({
        'tasks': FieldValue.arrayUnion([task.toMap()]),
      }, SetOptions(merge: true));
    }
  }

  void _startPomodoro() {
    if (!_isPomodoroRunning) {
      setState(() {
        _isPomodoroRunning = true;
        _remainingSeconds = _pomodoroMinutes * 60;
        _isBreak = false;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            _isBreak = !_isBreak;
            _remainingSeconds = _isBreak ? _breakMinutes * 60 : _pomodoroMinutes * 60;
            if (_remainingSeconds == 0) {
              _stopPomodoro();
            }
          }
        });
      });
    }
  }

  void _stopPomodoro() {
    _timer?.cancel();
    setState(() {
      _isPomodoroRunning = false;
      _remainingSeconds = 0;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = dateOnly(DateTime.now().toLocal()); // 2025-07-21
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
        body: Column(
          children: [
            TableCalendar(
              firstDay: now, // Restrict to today onward: 2025-07-21
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onFormatChanged: (format) {
                if (_calendarFormat != format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                }
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
                _loadTasks(); // Reload tasks when page changes
              },
              eventLoader: (day) {
                final date = dateOnly(day);
                return _tasks[date] ?? [];
              },
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Colors.teal,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Colors.teal[700],
                  shape: BoxShape.circle,
                ),
                todayTextStyle: GoogleFonts.poppins(color: Colors.white),
                selectedTextStyle: GoogleFonts.poppins(color: Colors.white),
                defaultTextStyle: GoogleFonts.poppins(color: Colors.black87),
                markersAlignment: Alignment.bottomRight,
                markerDecoration: BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
              headerStyle: HeaderStyle(
                formatButtonDecoration: BoxDecoration(
                  color: Colors.teal,
                  borderRadius: BorderRadius.circular(12),
                ),
                formatButtonTextStyle: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                titleTextStyle: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _taskController,
                      decoration: InputDecoration(
                        hintText: 'Add task...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _addTask,
                        ),
                      ),
                      style: GoogleFonts.poppins(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isPomodoroRunning ? _stopPomodoro : _startPomodoro,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    child: Text(
                      _isPomodoroRunning ? 'Stop Pomodoro' : 'Start Pomodoro',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            if (_isPomodoroRunning)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  '${(_remainingSeconds / 60).floor()}:${(_remainingSeconds % 60).toString().padLeft(2, '0')} ${_isBreak ? 'Break' : 'Work'}',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            Expanded(
              child: (_tasks[dateOnly(_selectedDay!)]?.isEmpty ?? true)
                  ? Center(
                child: Text(
                  'No tasks for this day',
                  style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
                ),
              )
                  : ListView.builder(
                itemCount: _tasks[dateOnly(_selectedDay!)]?.length ?? 0,
                itemBuilder: (context, index) {
                  final task = _tasks[dateOnly(_selectedDay!)]![index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: ListTile(
                      title: Text(task.title, style: GoogleFonts.poppins(fontSize: 16)),
                      subtitle: Text(
                        '${task.startTime.format(context)} - ${task.endTime.format(context)} ${task.isTimeBlocked ? '(Deep Work)' : ''}',
                        style: GoogleFonts.poppins(fontSize: 14),
                      ),
                      trailing: Checkbox(
                        value: task.isTimeBlocked,
                        onChanged: (value) {
                          setState(() {
                            task.isTimeBlocked = value ?? false;
                            _saveTask(dateOnly(_selectedDay!), task);
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Task {
  final String title;
  bool isTimeBlocked;
  final TimeOfDay startTime;
  TimeOfDay endTime;

  Task({
    required this.title,
    this.isTimeBlocked = false,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'isTimeBlocked': isTimeBlocked,
    'startTime': '${startTime.hour}:${startTime.minute}',
    'endTime': '${endTime.hour}:${endTime.minute}',
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
    );
  }
}