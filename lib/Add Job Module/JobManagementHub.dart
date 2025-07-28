import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class JobManagementHub extends StatefulWidget {
  const JobManagementHub({super.key});

  @override
  State<JobManagementHub> createState() => _JobManagementHubState();
}

class _JobManagementHubState extends State<JobManagementHub> {

  Widget _buildFeatureCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              colors: [color.withOpacity(0.1), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 30),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        badge,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF006D77),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Learn More',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 16, color: color),
                ],
              ),
            ],
          ),
        ),
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
          title: Text(
            'Job Management System',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to Frederick Ket',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF006D77),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete job management system with rewards, progress tracking, and real-time collaboration.',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Quick Stats Row
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.stars, color: Colors.amber, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          '1,250',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF006D77),
                          ),
                        ),
                        Text(
                          'Points Earned',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          '23',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF006D77),
                          ),
                        ),
                        Text(
                          'Jobs Completed',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.emoji_events, color: Colors.orange, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          '#5',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF006D77),
                          ),
                        ),
                        Text(
                          'Leaderboard',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Feature Cards Grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85,
              children: [
                // Job Creation & Management
                _buildFeatureCard(
                  title: 'Create Jobs',
                  description: 'Post new jobs with advanced task management features',
                  icon: Icons.add_task,
                  color: Colors.blue,
                  onTap: () {
                    // Navigate to AddJobPage
                    Navigator.pushNamed(context, '/add-job');
                  },
                ),

                // Job Completion
                _buildFeatureCard(
                  title: 'Job Completion',
                  description: 'Submit completed work with files and progress tracking',
                  icon: Icons.assignment_turned_in,
                  color: Colors.green,
                  onTap: () {
                    // Navigate to Job Completion Page
                    Navigator.pushNamed(context, '/job-completion');
                  },
                  badge: '3', // Example: 3 pending submissions
                ),

                // Employer Review
                _buildFeatureCard(
                  title: 'Review Submissions',
                  description: 'Review and approve job completions from employees',
                  icon: Icons.rate_review,
                  color: Colors.orange,
                  onTap: () {
                    // Navigate to Employer Review Page
                    Navigator.pushNamed(context, '/employer-review');
                  },
                  badge: '2', // Example: 2 pending reviews
                ),

                // Progress Tracking
                _buildFeatureCard(
                  title: 'Track Progress',
                  description: 'Monitor task progress with milestones and sub-tasks',
                  icon: Icons.timeline,
                  color: Colors.purple,
                  onTap: () {
                    // Navigate to Task Progress Tracker
                    Navigator.pushNamed(context, '/task-progress');
                  },
                ),

                // Rewards Store
                _buildFeatureCard(
                  title: 'Rewards Store',
                  description: 'Redeem points for vouchers, gifts, and experiences',
                  icon: Icons.redeem,
                  color: Colors.red,
                  onTap: () {
                    // Navigate to Rewards Store
                    Navigator.pushNamed(context, '/rewards-store');
                  },
                ),

                // Leaderboard
                _buildFeatureCard(
                  title: 'Leaderboard',
                  description: 'Real-time rankings and competitive achievements',
                  icon: Icons.leaderboard,
                  color: Colors.amber,
                  onTap: () {
                    // Navigate to Leaderboard
                    Navigator.pushNamed(context, '/leaderboard');
                  },
                ),

                // Admin Panel
                _buildFeatureCard(
                  title: 'Admin Panel',
                  description: 'Manage rewards, monitor system performance',
                  icon: Icons.admin_panel_settings,
                  color: Colors.indigo,
                  onTap: () {
                    // Navigate to Admin Panel
                    Navigator.pushNamed(context, '/admin-panel');
                  },
                ),

                // Analytics & Reports
                _buildFeatureCard(
                  title: 'Analytics',
                  description: 'View detailed reports and performance metrics',
                  icon: Icons.analytics,
                  color: Colors.teal,
                  onTap: () {
                    // Navigate to Analytics Page
                    Navigator.pushNamed(context, '/analytics');
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Recent Activity Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Activity',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF006D77),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // Navigate to full activity log
                        },
                        child: Text(
                          'View All',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: const Color(0xFF006D77),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Activity Items
                  _buildActivityItem(
                    icon: Icons.check_circle,
                    color: Colors.green,
                    title: 'Job Completed',
                    subtitle: 'Web Development Project - Earned 150 points',
                    time: '2 hours ago',
                  ),
                  _buildActivityItem(
                    icon: Icons.star,
                    color: Colors.amber,
                    title: 'Achievement Unlocked!',
                    subtitle: 'Completed 10 jobs milestone',
                    time: '1 day ago',
                  ),
                  _buildActivityItem(
                    icon: Icons.redeem,
                    color: Colors.red,
                    title: 'Reward Redeemed',
                    subtitle: 'RM50 Grab Food Voucher',
                    time: '3 days ago',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Quick Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Actions',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF006D77),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildQuickAction(
                        icon: Icons.add,
                        label: 'New Job',
                        onTap: () => Navigator.pushNamed(context, '/add-job'),
                      ),
                      _buildQuickAction(
                        icon: Icons.search,
                        label: 'Find Jobs',
                        onTap: () => Navigator.pushNamed(context, '/browse-jobs'),
                      ),
                      _buildQuickAction(
                        icon: Icons.message,
                        label: 'Messages',
                        onTap: () => Navigator.pushNamed(context, '/messages'),
                      ),
                      _buildQuickAction(
                        icon: Icons.person,
                        label: 'Profile',
                        onTap: () => Navigator.pushNamed(context, '/profile'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String time,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF006D77).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF006D77),
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF006D77),
            ),
          ),
        ],
      ),
    );
  }
}