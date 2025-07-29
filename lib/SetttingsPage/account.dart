import 'package:flutter/material.dart';
import 'package:fyp/Login%20Signup/Screen/login.dart';
import 'package:fyp/SetttingsPage/contactUS.dart';
import 'package:fyp/SetttingsPage/helpsupport.dart';
import 'package:fyp/SetttingsPage/ourlocation.dart';
import 'package:fyp/SetttingsPage/privacy.dart';
import 'package:fyp/SetttingsPage/reportproblem.dart';
import 'package:fyp/SetttingsPage/termspolicies.dart';
import 'package:fyp/module/Profile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp/module/SkillTags.dart';
import 'package:fyp/module/Translate.dart';
import 'package:fyp/module/report.dart';

class AccountPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Future<void> _logout() async {
      try {
        await FirebaseAuth.instance.signOut();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => LoginScreen()),
              (Route<dynamic> route) => false,
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: $e')),
        );
      }
    }

    return Scaffold(
      body: Column(
        children: [
          // Header Section with Original Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFB2DFDB), Colors.white],
              ),
            ),
            child: SafeArea(
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 32, horizontal: 120),
                child: Column(
                  children: [
                    // Profile Avatar
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                        border: Border.all(color: Colors.grey.shade300, width: 3),
                      ),
                      child: Icon(
                        Icons.person,
                        size: 45,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        letterSpacing: 1.5,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Customize your experience',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Settings Content
          Expanded(
            child: Container(
              color: Colors.white,
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 10, 14, 24),
                children: [
                  // Account Section
                  _buildSectionHeader('Account', Icons.account_circle_outlined),
                  SizedBox(height: 16),
                  _buildSettingsCard(
                    context,
                    icon: Icons.person_outline,
                    title: 'Profile',
                    subtitle: 'Manage your personal information',
                    iconColor: Color(0xFF2196F3),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen())),
                  ),
                  _buildSettingsCard(
                    context,
                    icon: Icons.stars_outlined,
                    title: 'Skills',
                    subtitle: 'Update your skills and expertise',
                    iconColor: Color(0xFFFF9800),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SkillTagScreen())),
                  ),
                  _buildSettingsCard(
                    context,
                    icon: Icons.security_outlined,
                    title: 'Privacy',
                    subtitle: 'Control your privacy settings',
                    iconColor: Color(0xFF4CAF50),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PrivacyPage())),
                  ),

                  SizedBox(height: 36),

                  // Support & About Section
                  _buildSectionHeader('Support & About', Icons.help_outline),
                  SizedBox(height: 16),
                  _buildSettingsCard(
                    context,
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    subtitle: 'Get help and support',
                    iconColor: Color(0xFF9C27B0),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => HelpSupportPage())),
                  ),
                  _buildSettingsCard(
                    context,
                    icon: Icons.description_outlined,
                    title: 'Terms and Policies',
                    subtitle: 'Read our terms and policies',
                    iconColor: Color(0xFF607D8B),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => TermsPoliciesPage())),
                  ),
                  _buildSettingsCard(
                    context,
                    icon: Icons.contact_phone_outlined,
                    title: 'Contact Us',
                    subtitle: 'Get in touch with our team',
                    iconColor: Color(0xFF00BCD4),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ContactUsPage())),
                  ),
                  _buildSettingsCard(
                    context,
                    icon: Icons.location_on_outlined,
                    title: 'Our Locations',
                    subtitle: 'Find our office locations',
                    iconColor: Color(0xFFE91E63),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => OurLocationsPage())),
                  ),

                  SizedBox(height: 36),

                  // Actions Section
                  _buildSectionHeader('Actions', Icons.settings_outlined),
                  SizedBox(height: 16),
                  _buildSettingsCard(
                    context,
                    icon: Icons.report_problem_outlined,
                    title: 'Report a Problem',
                    subtitle: 'Let us know about any issues',
                    iconColor: Color(0xFFFF5722),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ReportProblemPage())),
                  ),
                  _buildSettingsCard(
                    context,
                    icon: Icons.translate,
                    title: 'Translate',
                    subtitle: 'Translate any Word',
                    iconColor: Color(0xFF2287C6),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => TranslatePasteScreen())),
                  ),
                  _buildSettingsCard(
                    context,
                    icon: Icons.report,
                    title: 'Report',
                    subtitle: 'Report Your Money',
                    iconColor: Color(0xFF4A2393),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ReportScreen())),
                  ),
                  _buildSettingsCard(
                    context,
                    icon: Icons.logout_outlined,
                    title: 'Log Out',
                    subtitle: 'Sign out of your account',
                    iconColor: Color(0xFFF44336),
                    onTap: _logout,
                  ),

                  SizedBox(height: 36),

                  // App Version
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      'Taaz for android v11.9.0(5837)\nstore bundled arm64-v6a',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Color(0xFF2196F3).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF2196F3).withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 22,
            color: Color(0xFF2196F3),
          ),
        ),
        SizedBox(width: 16),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.grey[800],
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required Color iconColor,
        required VoidCallback onTap,
      }) {
    return Container(
      margin: EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          splashColor: iconColor.withOpacity(0.1),
          highlightColor: iconColor.withOpacity(0.05),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Row(
              children: [
                // Icon Container
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: iconColor.withOpacity(0.2), width: 1),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 26,
                  ),
                ),
                SizedBox(width: 18),
                // Title and Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                // Arrow Icon
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}