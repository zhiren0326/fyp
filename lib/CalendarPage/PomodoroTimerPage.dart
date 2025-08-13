import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/task.dart';

enum PomodoroState { work, shortBreak, longBreak, paused, stopped }

class PomodoroTimerPage extends StatefulWidget {
  final List<Task> tasks;

  const PomodoroTimerPage({super.key, required this.tasks});

  @override
  State<PomodoroTimerPage> createState() => _PomodoroTimerPageState();
}

class _PomodoroTimerPageState extends State<PomodoroTimerPage>
    with TickerProviderStateMixin {
  Timer? _timer;
  PomodoroState _currentState = PomodoroState.stopped;
  int _currentTaskIndex = 0;
  int _completedPomodoros = 0;
  int _totalPomodoros = 0;

  // Timer settings (in seconds)
  int _workDuration = 25 * 60; // 25 minutes
  int _shortBreakDuration = 5 * 60; // 5 minutes
  int _longBreakDuration = 15 * 60; // 15 minutes
  int _pomodorosUntilLongBreak = 4;

  // Current timer state
  int _remainingTime = 25 * 60;
  bool _isRunning = false;

  // Animation controllers
  late AnimationController _progressController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Statistics
  Map<String, int> _dailyStats = {
    'completedPomodoros': 0,
    'totalFocusTime': 0,
    'completedTasks': 0,
  };

  // Separated task lists
  List<Task> _activeTasks = [];
  List<Task> _completedTasks = [];

  @override
  void initState() {
    super.initState();
    _separateTasksByCompletion();
    _initializeAnimations();
    _loadDailyStats();
    _calculateTotalPomodoros();
    _remainingTime = _workDuration;
    _findNextActiveTask();
  }

  void _separateTasksByCompletion() {
    _activeTasks = widget.tasks.where((task) => !task.isCompleted).toList();
    _completedTasks = widget.tasks.where((task) => task.isCompleted).toList();
  }

  void _findNextActiveTask() {
    // Find the first non-completed task as the current task
    for (int i = 0; i < _activeTasks.length; i++) {
      if (!_activeTasks[i].isCompleted) {
        _currentTaskIndex = i;
        break;
      }
    }
  }

  void _initializeAnimations() {
    _progressController = AnimationController(
      duration: Duration(seconds: _workDuration),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _pulseController.repeat(reverse: true);
  }

  void _calculateTotalPomodoros() {
    _totalPomodoros = _activeTasks.fold(0, (sum, task) {
      return sum + (task.estimatedDuration / 25).ceil();
    });
  }

  Future<void> _loadDailyStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final today = DateTime.now().toIso8601String().split('T')[0];
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('pomodoroStats')
            .doc(today)
            .get();

        if (doc.exists) {
          setState(() {
            _dailyStats = Map<String, int>.from(doc.data() ?? {});
          });
        }
      } catch (e) {
        print('Error loading daily stats: $e');
      }
    }
  }

  Future<void> _saveDailyStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final today = DateTime.now().toIso8601String().split('T')[0];
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('pomodoroStats')
            .doc(today)
            .set({
          ..._dailyStats,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        print('Error saving daily stats: $e');
      }
    }
  }

  void _startTimer() {
    if (_currentState == PomodoroState.stopped) {
      _currentState = PomodoroState.work;
      _remainingTime = _workDuration;
      _progressController.duration = Duration(seconds: _workDuration);
    }

    setState(() => _isRunning = true);

    _progressController.forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingTime > 0) {
          _remainingTime--;
        } else {
          _onTimerComplete();
        }
      });
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    _progressController.stop();
    setState(() {
      _isRunning = false;
      _currentState = PomodoroState.paused;
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    _progressController.reset();
    setState(() {
      _isRunning = false;
      _currentState = PomodoroState.stopped;
      _remainingTime = _workDuration;
    });
  }

  void _onTimerComplete() {
    _timer?.cancel();
    _progressController.reset();

    // Haptic feedback
    HapticFeedback.heavyImpact();

    switch (_currentState) {
      case PomodoroState.work:
        _completedPomodoros++;
        _dailyStats['completedPomodoros'] = (_dailyStats['completedPomodoros'] ?? 0) + 1;
        _dailyStats['totalFocusTime'] = (_dailyStats['totalFocusTime'] ?? 0) + 25;

        // Check if it's time for a long break
        if (_completedPomodoros % _pomodorosUntilLongBreak == 0) {
          _currentState = PomodoroState.longBreak;
          _remainingTime = _longBreakDuration;
          _progressController.duration = Duration(seconds: _longBreakDuration);
        } else {
          _currentState = PomodoroState.shortBreak;
          _remainingTime = _shortBreakDuration;
          _progressController.duration = Duration(seconds: _shortBreakDuration);
        }
        _showCompletionDialog('Work Session Complete!',
            'Great job! Time for a ${_currentState == PomodoroState.longBreak ? 'long' : 'short'} break.');
        break;

      case PomodoroState.shortBreak:
      case PomodoroState.longBreak:
        _currentState = PomodoroState.work;
        _remainingTime = _workDuration;
        _progressController.duration = Duration(seconds: _workDuration);
        _showCompletionDialog('Break Complete!', 'Ready to focus again?');
        break;

      default:
        break;
    }

    _saveDailyStats();
    setState(() => _isRunning = false);
  }

  void _showCompletionDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _currentState == PomodoroState.work ? Icons.work : Icons.coffee,
              size: 48,
              color: _currentState == PomodoroState.work ? Colors.green : Colors.orange,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetTimer();
            },
            child: const Text('Stop'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startTimer();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _skipCurrentSession() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip Session'),
        content: const Text('Are you sure you want to skip the current session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _onTimerComplete();
            },
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Color _getCurrentStateColor() {
    switch (_currentState) {
      case PomodoroState.work:
        return Colors.red;
      case PomodoroState.shortBreak:
        return Colors.green;
      case PomodoroState.longBreak:
        return Colors.blue;
      case PomodoroState.paused:
        return Colors.orange;
      case PomodoroState.stopped:
        return Colors.grey;
    }
  }

  String _getCurrentStateText() {
    switch (_currentState) {
      case PomodoroState.work:
        return 'Focus Time';
      case PomodoroState.shortBreak:
        return 'Short Break';
      case PomodoroState.longBreak:
        return 'Long Break';
      case PomodoroState.paused:
        return 'Paused';
      case PomodoroState.stopped:
        return 'Ready to Start';
    }
  }

  Widget _buildTimerDisplay() {
    final progress = _currentState == PomodoroState.work
        ? 1.0 - (_remainingTime / _workDuration)
        : _currentState == PomodoroState.shortBreak
        ? 1.0 - (_remainingTime / _shortBreakDuration)
        : 1.0 - (_remainingTime / _longBreakDuration);

    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),

          // Progress indicator
          SizedBox(
            width: 280,
            height: 280,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 8,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(_getCurrentStateColor()),
            ),
          ),

          // Timer content
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _isRunning ? _pulseAnimation.value : 1.0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _formatTime(_remainingTime),
                      style: GoogleFonts.poppins(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: _getCurrentStateColor(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getCurrentStateText(),
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (_activeTasks.isNotEmpty && _currentTaskIndex < _activeTasks.length)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _activeTasks[_currentTaskIndex].title,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Reset button
        FloatingActionButton(
          onPressed: _isRunning ? null : _resetTimer,
          backgroundColor: Colors.grey,
          child: const Icon(Icons.refresh),
        ),

        // Main control button
        FloatingActionButton.extended(
          onPressed: _isRunning ? _pauseTimer : _startTimer,
          backgroundColor: _getCurrentStateColor(),
          icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
          label: Text(
            _isRunning ? 'Pause' : 'Start',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),

        // Skip button
        FloatingActionButton(
          onPressed: _isRunning ? _skipCurrentSession : null,
          backgroundColor: Colors.orange,
          child: const Icon(Icons.skip_next),
        ),
      ],
    );
  }

  Widget _buildProgressSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session Progress',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _totalPomodoros > 0 ? _completedPomodoros / _totalPomodoros : 0,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
            ),
            const SizedBox(height: 8),
            Text(
              '$_completedPomodoros / $_totalPomodoros Pomodoros completed',
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Today\'s Pomodoros',
                    '${_dailyStats['completedPomodoros'] ?? 0}',
                    Icons.timer,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Focus Time',
                    '${_dailyStats['totalFocusTime'] ?? 0}m',
                    Icons.access_time,
                    Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active Tasks Section
          if (_activeTasks.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Text(
                'Active Tasks (${_activeTasks.length})',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[700],
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _activeTasks.length,
              itemBuilder: (context, index) {
                final task = _activeTasks[index];
                final isCurrentTask = index == _currentTaskIndex;
                final estimatedPomodoros = (task.estimatedDuration / 25).ceil();
                final isJobTask = task.id.startsWith('job_');

                return Container(
                  decoration: BoxDecoration(
                    color: isCurrentTask ? Colors.blue[50] : null,
                    border: isCurrentTask
                        ? Border.all(color: Colors.blue[300]!, width: 2)
                        : null,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isCurrentTask ? Colors.blue : Colors.grey[300],
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isCurrentTask ? Colors.white : Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: GoogleFonts.poppins(
                              fontWeight: isCurrentTask ? FontWeight.w600 : FontWeight.normal,
                            ),
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
                      '${task.category} • $estimatedPomodoros Pomodoro${estimatedPomodoros > 1 ? 's' : ''}',
                      style: GoogleFonts.poppins(fontSize: 12),
                    ),
                    trailing: isCurrentTask
                        ? const Icon(Icons.play_circle_filled, color: Colors.blue)
                        : null,
                    onTap: () {
                      if (!_isRunning) {
                        setState(() => _currentTaskIndex = index);
                      }
                    },
                  ),
                );
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
                borderRadius: _activeTasks.isEmpty
                    ? const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                )
                    : BorderRadius.zero,
              ),
              child: Text(
                'Completed Tasks (${_completedTasks.length})',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.green[700],
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _completedTasks.length,
              itemBuilder: (context, index) {
                final task = _completedTasks[index];
                final estimatedPomodoros = (task.estimatedDuration / 25).ceil();
                final isJobTask = task.id.startsWith('job_');

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green[300],
                    child: const Icon(Icons.check, color: Colors.white),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.normal,
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
                    '${task.category} • $estimatedPomodoros Pomodoro${estimatedPomodoros > 1 ? 's' : ''}',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
                  ),
                );
              },
            ),
          ],

          if (_activeTasks.isEmpty && _completedTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.task_alt, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text(
                    'No tasks available',
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

  Widget _buildSettingsSection() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.settings),
        title: Text(
          'Timer Settings',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildSettingSlider(
                  'Work Duration',
                  _workDuration ~/ 60,
                  10,
                  60,
                      (value) {
                    if (!_isRunning) {
                      setState(() {
                        _workDuration = value * 60;
                        if (_currentState == PomodoroState.stopped) {
                          _remainingTime = _workDuration;
                        }
                      });
                    }
                  },
                ),
                _buildSettingSlider(
                  'Short Break',
                  _shortBreakDuration ~/ 60,
                  3,
                  15,
                      (value) {
                    if (!_isRunning) {
                      setState(() => _shortBreakDuration = value * 60);
                    }
                  },
                ),
                _buildSettingSlider(
                  'Long Break',
                  _longBreakDuration ~/ 60,
                  10,
                  30,
                      (value) {
                    if (!_isRunning) {
                      setState(() => _longBreakDuration = value * 60);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSlider(
      String label,
      int value,
      int min,
      int max,
      Function(int) onChanged,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            Text('$value min', style: GoogleFonts.poppins(color: Colors.grey[600])),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: _isRunning ? null : (newValue) => onChanged(newValue.toInt()),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progressController.dispose();
    _pulseController.dispose();
    super.dispose();
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
          title: Text(
            'Pomodoro Timer',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.teal[800]),
          ),
          actions: [
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Pomodoro Technique'),
                    content: const Text(
                      'The Pomodoro Technique:\n\n'
                          '1. Work for 25 minutes\n'
                          '2. Take a 5-minute break\n'
                          '3. After 4 pomodoros, take a 15-30 minute break\n\n'
                          'This helps maintain focus and prevents burnout.\n\n'
                          'Note: Only active (non-completed) tasks are available for Pomodoro sessions.',
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
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Timer display
              _buildTimerDisplay(),

              const SizedBox(height: 32),

              // Control buttons
              _buildControlButtons(),

              const SizedBox(height: 32),

              // Progress section
              _buildProgressSection(),

              const SizedBox(height: 16),

              // Task list
              _buildTaskList(),

              const SizedBox(height: 16),

              // Settings
              _buildSettingsSection(),
            ],
          ),
        ),
      ),
    );
  }
}