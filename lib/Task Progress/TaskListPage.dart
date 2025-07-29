/*
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:async/async.dart'; // Add this import for StreamGroup
import 'TaskProgressPage.dart';
import 'TaskProgressService.dart';

class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key});

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Not Started':
        return Colors.grey;
      case 'In Progress':
        return Colors.blue;
      case 'On Hold':
        return Colors.orange;
      case 'Pending Review':
        return Colors.yellow[700]!;
      case 'Completed':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Not Started':
        return Icons.play_circle_outline;
      case 'In Progress':
        return Icons.timelapse;
      case 'On Hold':
        return Icons.pause_circle_outline;
      case 'Pending Review':
        return Icons.pending;
      case 'Completed':
        return Icons.check_circle;
      case 'Rejected':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildTaskCard(Map<String, dynamic> task, bool isEmployerView) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TaskProgressPage(
                taskId: task['id'],
                taskTitle: task['title'],
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      task['title'] ?? 'Unnamed Task',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF006D77),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(task['status']).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _getStatusColor(task['status'])),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getStatusIcon(task['status']),
                          size: 12,
                          color: _getStatusColor(task['status']),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          task['status'],
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _getStatusColor(task['status']),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Progress',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: (task['progress'] ?? 0.0) / 100,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getStatusColor(task['status']),
                          ),
                          minHeight: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${(task['progress'] ?? 0.0).toStringAsFixed(1)}%',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(task['status']),
                    ),
                  ),
                ],
              ),
              if (task['isShortTerm'] == false) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[300]!),
                  ),
                  child: Text(
                    'Long-term Task',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[700],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isEmployerView) ...[
                    Text(
                      'Team Members: ${task['teamSize'] ?? 0}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Last updated: ${_formatLastUpdated(task['lastUpdated'])}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatLastUpdated(dynamic timestamp) {
    if (timestamp == null) return 'Never';

    try {
      DateTime dateTime;
      if (timestamp is Timestamp) {
        dateTime = timestamp.toDate();
      } else {
        return 'Never';
      }

      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      return 'Never';
    }
  }

  Widget _buildSummaryCards() {
    if (_currentUserId == null) return const SizedBox.shrink();

    final createdJobsStream = FirebaseFirestore.instance
        .collection('jobs')
        .where('postedBy', isEqualTo: _currentUserId)
        .snapshots();
    final appliedJobsStream = FirebaseFirestore.instance
        .collection('jobs')
        .where('acceptedApplicants', arrayContains: _currentUserId)
        .snapshots();

    return StreamBuilder<List<QuerySnapshot>>(
      stream: StreamGroup.merge([createdJobsStream, appliedJobsStream]).map((snapshots) {
        // Ensure we have both snapshots; if one is missing, return empty list
        if (snapshots.length < 2) return <QuerySnapshot>[];
        return snapshots.cast<QuerySnapshot>();
      }),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final createdJobs = snapshot.data![0].docs;
        final appliedJobs = snapshot.data![1].docs;

        // Calculate statistics
        int totalCreated = createdJobs.length;
        int totalApplied = appliedJobs.length;

        int completedApplied = 0;
        int inProgressApplied = 0;

        for (var job in appliedJobs) {
          final jobData = job.data() as Map<String, dynamic>;
          final statusList = jobData['submissionStatus'] as List<dynamic>? ?? [];

          for (var status in statusList) {
            if (status is Map<String, dynamic> &&
                status['userId'] == _currentUserId) {
              final statusStr = status['status']?.toString() ?? 'Not Started';
              if (statusStr == 'Completed') {
                completedApplied++;
              } else if (statusStr == 'In Progress') {
                inProgressApplied++;
              }
              break;
            }
          }
        }

        return Container(
          height: 120,
          margin: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Created Jobs',
                  totalCreated.toString(),
                  Icons.work_outline,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Applied Jobs',
                  totalApplied.toString(),
                  Icons.assignment_outlined,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Completed',
                  completedApplied.toString(),
                  Icons.check_circle_outline,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'In Progress',
                  inProgressApplied.toString(),
                  Icons.timelapse,
                  Colors.purple,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCreatedJobsTab() {
    if (_currentUserId == null) {
      return const Center(
        child: Text('Please log in to view your tasks.'),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('postedBy', isEqualTo: _currentUserId)
          .orderBy('lastUpdated', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Error loading tasks',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final jobs = snapshot.data?.docs ?? [];

        if (jobs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.work_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No jobs created yet',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Jobs you create will appear here',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final jobDoc = jobs[index];
            final jobData = jobDoc.data() as Map<String, dynamic>;

            // Calculate average progress for employer view
            final progressList = jobData['progressPercentage'] as List<dynamic>? ?? [];
            double averageProgress = 0.0;
            String overallStatus = 'Not Started';

            if (progressList.isNotEmpty) {
              double totalProgress = 0.0;
              Map<String, int> statusCounts = {};

              for (var progress in progressList) {
                if (progress is Map<String, dynamic>) {
                  totalProgress += (progress['progress'] as num?)?.toDouble() ?? 0.0;
                }
              }

              averageProgress = totalProgress / progressList.length;

              // Determine overall status based on submissionStatus
              final statusList = jobData['submissionStatus'] as List<dynamic>? ?? [];
              for (var status in statusList) {
                if (status is Map<String, dynamic>) {
                  final statusStr = status['status']?.toString() ?? 'Not Started';
                  statusCounts[statusStr] = (statusCounts[statusStr] ?? 0) + 1;
                }
              }

              if (statusCounts['Completed'] == progressList.length) {
                overallStatus = 'Completed';
              } else if (statusCounts['Pending Review'] != null && statusCounts['Pending Review']! > 0) {
                overallStatus = 'Pending Review';
              } else if (statusCounts['In Progress'] != null && statusCounts['In Progress']! > 0) {
                overallStatus = 'In Progress';
              } else if (statusCounts['Rejected'] != null && statusCounts['Rejected']! > 0) {
                overallStatus = 'In Progress';
              }
            }

            final task = {
              'id': jobDoc.id,
              'title': _extractJobTitle(jobData['jobPosition']),
              'progress': averageProgress,
              'status': overallStatus,
              'isShortTerm': jobData['isShortTerm'] ?? true,
              'lastUpdated': jobData['lastUpdated'],
              'teamSize': (jobData['acceptedApplicants'] as List?)?.length ?? 0,
            };

            return _buildTaskCard(task, true);
          },
        );
      },
    );
  }

  Widget _buildAppliedJobsTab() {
    if (_currentUserId == null) {
      return const Center(
        child: Text('Please log in to view your tasks.'),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('acceptedApplicants', arrayContains: _currentUserId)
          .orderBy('lastUpdated', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Error loading tasks',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final jobs = snapshot.data?.docs ?? [];

        if (jobs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No applied jobs yet',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Jobs you\'ve been accepted to will appear here',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final jobDoc = jobs[index];
            final jobData = jobDoc.data() as Map<String, dynamic>;

            // Find current user's progress
            final progressList = jobData['progressPercentage'] as List<dynamic>? ?? [];
            double userProgress = 0.0;
            String userStatus = 'Not Started';

            for (var progress in progressList) {
              if (progress is Map<String, dynamic> &&
                  progress['userId'] == _currentUserId) {
                userProgress = (progress['progress'] as num?)?.toDouble() ?? 0.0;
                break;
              }
            }

            final statusList = jobData['submissionStatus'] as List<dynamic>? ?? [];
            for (var status in statusList) {
              if (status is Map<String, dynamic> &&
                  status['userId'] == _currentUserId) {
                userStatus = status['status']?.toString() ?? 'Not Started';
                break;
              }
            }

            final task = {
              'id': jobDoc.id,
              'title': _extractJobTitle(jobData['jobPosition']),
              'progress': userProgress,
              'status': userStatus,
              'isShortTerm': jobData['isShortTerm'] ?? true,
              'lastUpdated': jobData['lastUpdated'],
            };

            return _buildTaskCard(task, false);
          },
        );
      },
    );
  }

  String _extractJobTitle(dynamic jobPosition) {
    if (jobPosition == null) return 'Unnamed Task';

    if (jobPosition is String) {
      return jobPosition.isNotEmpty ? jobPosition : 'Unnamed Task';
    } else if (jobPosition is List && jobPosition.isNotEmpty) {
      return jobPosition.first?.toString() ?? 'Unnamed Task';
    } else if (jobPosition is Map) {
      return jobPosition['title']?.toString() ??
          jobPosition['name']?.toString() ??
          'Unnamed Task';
    }

    return jobPosition.toString().isNotEmpty ? jobPosition.toString() : 'Unnamed Task';
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
          title: Text(
            'My Tasks',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {}),
              tooltip: 'Refresh',
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                icon: Icon(Icons.work),
                text: 'Created Jobs',
              ),
              Tab(
                icon: Icon(Icons.assignment),
                text: 'Applied Jobs',
              ),
            ],
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.normal),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
          ),
        ),
        body: Column(
          children: [
            _buildSummaryCards(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCreatedJobsTab(),
                  _buildAppliedJobsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
*/
