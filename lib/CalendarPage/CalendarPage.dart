import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:fyp/CalendarPage/DailyPlannerPage.dart';
import 'package:fyp/CalendarPage/TimeBlockingPage.dart';
import 'package:fyp/CalendarPage/PomodoroTimerPage.dart';
import '../models/task.dart';
import '../models/time_block.dart';

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
  Map<DateTime, List<TimeBlock>> _timeBlocks = {};
  bool _showTimeBlocks = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadTasks();
    _loadTimeBlocks();
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
              id: doc.id,
              title: data['jobPosition'] ?? 'Unnamed Job',
              isTimeBlocked: data['isTimeBlocked'] ?? false,
              startTime: _parseTimeOfDay(data['startTime'] ?? '12:00 AM'),
              endTime: _parseTimeOfDay(data['endTime'] ?? '1:00 AM'),
              jobId: doc.id,
              priority: _parsePriority(data['priority']),
              estimatedDuration: data['estimatedDuration'] ?? 60,
              category: data['category'] ?? 'Work',
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

  void _loadTimeBlocks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final now = dateOnly(DateTime.now().toLocal());
        final timeBlockSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('timeBlocks')
            .where('date', isGreaterThanOrEqualTo: now.toIso8601String().split('T')[0])
            .limit(50)
            .get();

        setState(() {
          _timeBlocks = {};
          for (var doc in timeBlockSnapshot.docs) {
            final data = doc.data();
            final date = dateOnly(DateTime.parse(data['date']));
            final timeBlock = TimeBlock.fromMap(data);
            _timeBlocks.putIfAbsent(date, () => []).add(timeBlock);
          }
        });
      } catch (e) {
        print('Error loading time blocks: $e');
      }
    }
  }

  TaskPriority _parsePriority(dynamic priority) {
    if (priority is String) {
      switch (priority.toLowerCase()) {
        case 'high':
          return TaskPriority.high;
        case 'medium':
          return TaskPriority.medium;
        case 'low':
          return TaskPriority.low;
        default:
          return TaskPriority.medium;
      }
    }
    return TaskPriority.medium;
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

  void _navigateToDailyPlanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DailyPlannerPage(selectedDate: _selectedDay!),
      ),
    ).then((_) => _loadTasks());
  }

  void _navigateToTimeBlocking() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TimeBlockingPage(
          selectedDate: _selectedDay!,
          tasks: _tasks[dateOnly(_selectedDay!)] ?? [],
        ),
      ),
    ).then((_) {
      _loadTasks();
      _loadTimeBlocks();
    });
  }

  void _navigateToPomodoroTimer() {
    final dailyTasks = _tasks[dateOnly(_selectedDay!)] ?? [];
    if (dailyTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tasks available for Pomodoro timer')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PomodoroTimerPage(tasks: dailyTasks),
      ),
    );
  }

  Widget _buildTimeManagementActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Time Management Tools',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.teal[800],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  icon: Icons.today,
                  title: 'Daily Planner',
                  onTap: _navigateToDailyPlanner,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionCard(
                  icon: Icons.schedule,
                  title: 'Time Blocking',
                  onTap: _navigateToTimeBlocking,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  icon: Icons.timer,
                  title: 'Pomodoro Timer',
                  onTap: _navigateToPomodoroTimer,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionCard(
                  icon: _showTimeBlocks ? Icons.event : Icons.event_note,
                  title: _showTimeBlocks ? 'Show Tasks' : 'Show Blocks',
                  onTap: () => setState(() => _showTimeBlocks = !_showTimeBlocks),
                  color: Colors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 4),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskList() {
    final selectedDate = dateOnly(_selectedDay!);
    final dailyTasks = _tasks[selectedDate] ?? [];
    final dailyTimeBlocks = _timeBlocks[selectedDate] ?? [];

    if (_showTimeBlocks) {
      return _buildTimeBlockList(dailyTimeBlocks);
    }

    if (dailyTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No tasks for this day',
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _navigateToDailyPlanner,
              icon: const Icon(Icons.add),
              label: const Text('Add tasks'),
            ),
          ],
        ),
      );
    }

    // Sort tasks by priority and time
    dailyTasks.sort((a, b) {
      final priorityComparison = b.priority.index.compareTo(a.priority.index);
      if (priorityComparison != 0) return priorityComparison;

      if (a.isTimeBlocked && b.isTimeBlocked) {
        return a.startTime.hour.compareTo(b.startTime.hour);
      }
      return a.isTimeBlocked ? -1 : 1;
    });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: dailyTasks.length,
      itemBuilder: (context, index) {
        final task = dailyTasks[index];
        return _buildTaskCard(task);
      },
    );
  }

  Widget _buildTaskCard(Task task) {
    Color priorityColor = task.priority == TaskPriority.high
        ? Colors.red
        : task.priority == TaskPriority.medium
        ? Colors.orange
        : Colors.green;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Container(
          width: 4,
          height: double.infinity,
          decoration: BoxDecoration(
            color: priorityColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(
          task.title,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.isTimeBlocked)
              Text(
                '${task.startTime.format(context)} - ${task.endTime.format(context)}',
                style: GoogleFonts.poppins(color: Colors.teal),
              )
            else
              Text(
                'No time block assigned',
                style: GoogleFonts.poppins(color: Colors.grey),
              ),
            Text(
              '${task.category} • ${task.estimatedDuration} min • ${task.priority.name.toUpperCase()}',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'timeBlock':
                _navigateToTimeBlocking();
                break;
              case 'pomodoro':
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => PomodoroTimerPage(tasks: [task]),
                  ),
                );
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'timeBlock',
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 16),
                  SizedBox(width: 8),
                  Text('Time Block'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'pomodoro',
              child: Row(
                children: [
                  Icon(Icons.timer, size: 16),
                  SizedBox(width: 8),
                  Text('Start Pomodoro'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeBlockList(List<TimeBlock> timeBlocks) {
    if (timeBlocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No time blocks for this day',
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _navigateToTimeBlocking,
              icon: const Icon(Icons.add),
              label: const Text('Create time blocks'),
            ),
          ],
        ),
      );
    }

    timeBlocks.sort((a, b) => a.startTime.hour.compareTo(b.startTime.hour));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: timeBlocks.length,
      itemBuilder: (context, index) {
        final timeBlock = timeBlocks[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: timeBlock.color.withOpacity(0.1),
          child: ListTile(
            leading: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: timeBlock.color,
                shape: BoxShape.circle,
              ),
            ),
            title: Text(
              timeBlock.title,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${timeBlock.startTime.format(context)} - ${timeBlock.endTime.format(context)}',
              style: GoogleFonts.poppins(),
            ),
            trailing: timeBlock.taskIds.isNotEmpty
                ? Chip(
              label: Text('${timeBlock.taskIds.length} tasks'),
              backgroundColor: timeBlock.color.withOpacity(0.2),
            )
                : null,
          ),
        );
      },
    );
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
              // Calendar Widget
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
                  _loadTimeBlocks();
                },
                eventLoader: (day) {
                  final date = dateOnly(day);
                  final tasks = _tasks[date] ?? [];
                  final timeBlocks = _timeBlocks[date] ?? [];
                  return [...tasks, ...timeBlocks];
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

              // Time Management Actions
              _buildTimeManagementActions(),

              // Task/Time Block List
              Expanded(child: _buildTaskList()),
            ],
          ),
        ),
      ),
    );
  }
}