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
      appBar: AppBar(
        leading: GestureDetector(
          onTapDown: (_) {
            _controller.reverse();
          },
          onTapUp: (_) {
            _controller.forward();
            Navigator.pop(context);
          },
          onTapCancel: () {
            _controller.forward();
          },
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: const Icon(Icons.arrow_back, color: Colors.white),
              );
            },
          ),
        ),
        title: FadeTransition(
          opacity: _fadeAnimation,
          child: Text(
            'Privacy Policy',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFB2DFDB).withOpacity(_fadeAnimation.value),
                  Colors.white,
                ],
              ),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      'Privacy Policy',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  SlideTransition(
                    position: _slideAnimation,
                    child: Text(
                      '''
Last Updated: July 20, 2025

At Job Seaker App, we are committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information.

1. **Information We Collect**
- **Personal Information**: Name, email, and other details provided during account creation or job applications.
- **Usage Data**: Information on how you interact with the app, such as pages visited and features used.
- **Location Data**: If enabled in Privacy Settings, we collect location data to enhance job recommendations.

2. **How We Use Your Information**
- To provide and improve our services, such as matching you with job opportunities.
- To personalize your experience based on your preferences and location (if enabled).
- To analyze usage patterns via Firebase Analytics, if you allow data sharing.

3. **Data Sharing**
- We do not share your personal information with third parties except as required by law or with your consent.
- Aggregated, anonymized data may be used for analytics purposes.

4. **Data Security**
- We implement industry-standard security measures to protect your data.
- However, no method of transmission over the Internet is 100% secure.

5. **Your Choices**
- You can manage data sharing and location tracking in the Privacy Settings page.
- You may request deletion of your account by contacting support@jobseakerapp.com.

6. **Changes to This Policy**
- We may update this Privacy Policy from time to time. The updated version will be indicated by the "Last Updated" date above.

For questions, contact us at support@jobseakerapp.com.
                      ''',
                      style: GoogleFonts.manrope(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}