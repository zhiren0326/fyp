import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FullPrivacyPolicyPage extends StatefulWidget {
  const FullPrivacyPolicyPage({super.key});

  @override
  _FullPrivacyPolicyPageState createState() => _FullPrivacyPolicyPageState();
}

class _FullPrivacyPolicyPageState extends State<FullPrivacyPolicyPage> with SingleTickerProviderStateMixin {
  bool _isFirebaseInitialized = false;
  bool _allowDataSharing = false;
  User? _currentUser;
  late FirebaseAnalytics _analytics;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _analytics = FirebaseAnalytics.instance;
    // Initialize animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _slideAnimation = Tween<Offset>(begin: Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.forward();
    _checkFirebaseInitialization();
    _checkUserAndLoadPreferences();
    _logScreenView();
  }

  // Check Firebase initialization
  Future<void> _checkFirebaseInitialization() async {
    try {
      setState(() {
        _isFirebaseInitialized = true;
      });
      await _analytics.setAnalyticsCollectionEnabled(true);
    } catch (e) {
      print('Firebase initialization check failed: $e');
      setState(() {
        _isFirebaseInitialized = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analytics initialization failed.')),
      );
    }
  }

  // Check user and load preferences
  Future<void> _checkUserAndLoadPreferences() async {
    _currentUser = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _allowDataSharing = prefs.getBool('allowDataSharing') ?? false;
    });
  }

  // Log screen view
  Future<void> _logScreenView() async {
    if (_isFirebaseInitialized && _allowDataSharing && _currentUser != null) {
      try {
        await _analytics.logScreenView(
          screenName: 'FullPrivacyPolicyPage',
          screenClass: 'FullPrivacyPolicyPage',
          parameters: <String, String>{
            'user_id': _currentUser!.uid,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        print('Screen view logged for FullPrivacyPolicyPage');
      } catch (e) {
        print('Error logging screen view: $e');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: GestureDetector(
          onTapDown: (_) => _controller.reverse(),
          onTapUp: (_) {
            _controller.forward();
            Navigator.pop(context);
          },
          onTapCancel: () => _controller.forward(),
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  margin: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Icon(Icons.arrow_back, color: Colors.black87),
                ),
              );
            },
          ),
        ),
        title: FadeTransition(
          opacity: _fadeAnimation,
          child: Text(
            'Privacy Policy',
            style: GoogleFonts.poppins(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 22,
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB2DFDB), Colors.white],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Section
                  SizedBox(height: 20),
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.4)),
                          ),
                          child: Icon(
                            Icons.privacy_tip,
                            color: Colors.black87,
                            size: 28,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Privacy Policy',
                                style: GoogleFonts.poppins(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                'Your privacy matters to us',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 32),

                  // Last Updated Badge
                  SlideTransition(
                    position: _slideAnimation,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Color(0xFF2196F3).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Color(0xFF2196F3).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.update,
                            size: 16,
                            color: Color(0xFF2196F3),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Last Updated: July 20, 2025',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Color(0xFF2196F3),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24),

                  // Introduction Card
                  SlideTransition(
                    position: _slideAnimation,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'At Job Seaker App, we are committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information.',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.black87,
                            height: 1.6,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 24),

                  // Privacy Policy Sections
                  _buildPolicySection(
                    icon: Icons.info_outline,
                    iconColor: Color(0xFF2196F3),
                    title: 'Information We Collect',
                    content: [
                      '• Personal Information: Name, email, and other details provided during account creation or job applications.',
                      '• Usage Data: Information on how you interact with the app, such as pages visited and features used.',
                      '• Location Data: If enabled in Privacy Settings, we collect location data to enhance job recommendations.',
                    ],
                  ),

                  _buildPolicySection(
                    icon: Icons.settings_outlined,
                    iconColor: Color(0xFF4CAF50),
                    title: 'How We Use Your Information',
                    content: [
                      '• To provide and improve our services, such as matching you with job opportunities.',
                      '• To personalize your experience based on your preferences and location (if enabled).',
                      '• To analyze usage patterns via Firebase Analytics, if you allow data sharing.',
                    ],
                  ),

                  _buildPolicySection(
                    icon: Icons.share_outlined,
                    iconColor: Color(0xFFFF9800),
                    title: 'Data Sharing',
                    content: [
                      '• We do not share your personal information with third parties except as required by law or with your consent.',
                      '• Aggregated, anonymized data may be used for analytics purposes.',
                    ],
                  ),

                  _buildPolicySection(
                    icon: Icons.security_outlined,
                    iconColor: Color(0xFF9C27B0),
                    title: 'Data Security',
                    content: [
                      '• We implement industry-standard security measures to protect your data.',
                      '• However, no method of transmission over the Internet is 100% secure.',
                    ],
                  ),

                  _buildPolicySection(
                    icon: Icons.tune_outlined,
                    iconColor: Color(0xFFE91E63),
                    title: 'Your Choices',
                    content: [
                      '• You can manage data sharing and location tracking in the Privacy Settings page.',
                      '• You may request deletion of your account by contacting support@jobseakerapp.com.',
                    ],
                  ),

                  _buildPolicySection(
                    icon: Icons.update_outlined,
                    iconColor: Color(0xFF00BCD4),
                    title: 'Changes to This Policy',
                    content: [
                      '• We may update this Privacy Policy from time to time. The updated version will be indicated by the "Last Updated" date above.',
                    ],
                  ),

                  SizedBox(height: 24),

                  // Contact Card
                  SlideTransition(
                    position: _slideAnimation,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF00BCD4).withOpacity(0.3),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.email,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Questions?',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'Contact us at support@jobseakerapp.com',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPolicySection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<String> content,
  }) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        margin: EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 15,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section Header
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: iconColor,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 16),

              // Content
              ...content.map((item) => Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: EdgeInsets.only(top: 8, right: 12),
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: iconColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.substring(2), // Remove the bullet point
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: Colors.black87,
                          height: 1.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}