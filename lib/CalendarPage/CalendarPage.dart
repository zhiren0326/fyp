import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

import 'DailyPlannerPage.dart';

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
  DateTime _focusedDay = DateTime.now().toLocal();
  DateTime? _selectedDay;
  Map<DateTime, List<Task>> _tasks = {};

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
            .where('date', isGreaterThanOrEqualTo: now.toIso8601String().split('T')[0])
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

            if (!isShortTerm) {
              _tasks.putIfAbsent(startDate, () => []).add(task);
            } else {
              DateTime currentDate = startDate;
              while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
                if (!currentDate.isBefore(now)) {
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
            }
          }

          print('Loaded ${jobSnapshot.docs.length} jobs and ${taskSnapshot.docs.length} tasks for user ${user.uid}');
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
              TableCalendar(
                firstDay: now,
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
                  _loadTasks();
                },
                eventLoader: (day) {
                  final date = dateOnly(day);
                  return _tasks[date] ?? [];
                },
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                  selectedDecoration: BoxDecoration(color: Colors.teal[700], shape: BoxShape.circle),
                  todayTextStyle: GoogleFonts.poppins(color: Colors.white),
                  selectedTextStyle: GoogleFonts.poppins(color: Colors.white),
                  defaultTextStyle: GoogleFonts.poppins(color: Colors.black87),
                  markersAlignment: Alignment.bottomRight,
                  markerDecoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                ),
                headerStyle: HeaderStyle(
                  formatButtonDecoration: BoxDecoration(
                    color: Colors.teal,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  formatButtonTextStyle: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
                  titleTextStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.teal),
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
                  padding: const EdgeInsets.all(16),
                  itemCount: _tasks[dateOnly(_selectedDay!)]!.length,
                  itemBuilder: (context, index) {
                    final task = _tasks[dateOnly(_selectedDay!)]![index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        title: Text(
                          task.title,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                        subtitle: task.isTimeBlocked
                            ? Text(
                          '${task.startTime.format(context)} - ${task.endTime.format(context)}',
                          style: GoogleFonts.poppins(),
                        )
                            : Text(
                          'No time block assigned',
                          style: GoogleFonts.poppins(color: Colors.grey),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
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