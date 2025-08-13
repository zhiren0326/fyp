import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp/SetttingsPage/FullPrivacy.dart';
import 'package:fyp/SetttingsPage/FullTerms.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class TermsPoliciesPage extends StatefulWidget {
  const TermsPoliciesPage({super.key});

  @override
  _TermsPoliciesPageState createState() => _TermsPoliciesPageState();
}

class _TermsPoliciesPageState extends State<TermsPoliciesPage> with TickerProviderStateMixin {
  bool _isFirebaseInitialized = false;
  bool _allowDataSharing = false;
  User? _currentUser;
  late FirebaseAnalytics _analytics;
  bool _termsAgreed = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late AnimationController _agreementAnimationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _analytics = FirebaseAnalytics.instance;
    _animationController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    _agreementAnimationController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _agreementAnimationController, curve: Curves.elasticOut),
    );
    _checkFirebaseInitialization();
    _checkUserAndLoadPreferences();
    _logScreenView();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _agreementAnimationController.dispose();
    super.dispose();
  }

  // Check Firebase initialization
  Future<void> _checkFirebaseInitialization() async {
    try {
      setState(() {
        _isFirebaseInitialized = true; // Assume initialized from main.dart
      });
      await _analytics.setAnalyticsCollectionEnabled(true);
    } catch (e) {
      print('Firebase initialization check failed: $e');
      setState(() {
        _isFirebaseInitialized = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Analytics initialization failed.'),
          backgroundColor: Colors.red.shade400,
        ),
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
    if (_currentUser != null) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('terms_agreements')
            .doc('agreement')
            .get();
        if (doc.exists) {
          setState(() {
            _termsAgreed = doc['agreed'] ?? false;
          });
          if (_termsAgreed) {
            _agreementAnimationController.forward();
          }
        }
      } catch (e) {
        print('Error loading terms agreement: $e');
      }
    }
  }

  // Log screen view
  Future<void> _logScreenView() async {
    if (_isFirebaseInitialized && _allowDataSharing && _currentUser != null) {
      try {
        await _analytics.logScreenView(
          screenName: 'TermsPoliciesPage',
          screenClass: 'TermsPoliciesPage',
          parameters: <String, String>{
            'user_id': _currentUser!.uid,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        print('Screen view logged for TermsPoliciesPage');
      } catch (e) {
        print('Error logging screen view: $e');
      }
    }
  }

  // Log terms or policy view
  Future<void> _logLegalDocumentView(String documentType) async {
    if (_isFirebaseInitialized && _allowDataSharing && _currentUser != null) {
      try {
        await _analytics.logEvent(
          name: '${documentType}_viewed',
          parameters: <String, String>{
            'user_id': _currentUser!.uid,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        print('$documentType view logged');
      } catch (e) {
        print('Error logging $documentType view: $e');
      }
    }
  }

  // Launch external URL
  Future<void> _launchUrl(String url, String documentType) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      await _logLegalDocumentView(documentType);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open $documentType'),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }

  // Agree to terms
  Future<void> _agreeToTerms() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please log in to agree to terms'),
          backgroundColor: Colors.orange.shade400,
          action: SnackBarAction(
            label: 'Log In',
            textColor: Colors.white,
            onPressed: () => Navigator.pushNamed(context, '/account'),
          ),
        ),
      );
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('terms_agreements')
          .doc('agreement')
          .set(<String, dynamic>{
        'agreed': true,
        'timestamp': DateTime.now().toIso8601String(),
        'user_id': _currentUser!.uid,
      }, SetOptions(merge: true));
      setState(() {
        _termsAgreed = true;
      });
      _agreementAnimationController.forward();
      if (_isFirebaseInitialized && _allowDataSharing) {
        try {
          await _analytics.logEvent(
            name: 'terms_agreed',
            parameters: <String, String>{
              'user_id': _currentUser!.uid,
              'timestamp': DateTime.now().toIso8601String(),
            },
          );
          print('Terms agreement logged');
        } catch (e) {
          print('Error logging terms agreement: $e');
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terms agreed successfully'),
          backgroundColor: Colors.green.shade400,
        ),
      );
    } catch (e) {
      print('Error saving terms agreement: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save terms agreement: $e'),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF3B82F6).withOpacity(0.3),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              Icons.gavel,
              color: Colors.white,
              size: 40,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Terms & Policies',
            style: GoogleFonts.manrope(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Important legal information and agreements',
            style: GoogleFonts.manrope(
              fontSize: 16,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalSection({
    required String title,
    required String description,
    required String lastUpdated,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onViewFull,
    required VoidCallback onOpenBrowser,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF1F2937).withOpacity(0.08),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  lastUpdated,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                    fontStyle: FontStyle.italic,
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        title: 'View Full',
                        icon: Icons.visibility,
                        onPressed: onViewFull,
                        gradientColors: [Color(0xFF10B981), Color(0xFF059669)],
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _buildActionButton(
                        title: 'Open Browser',
                        icon: Icons.open_in_browser,
                        onPressed: onOpenBrowser,
                        gradientColors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String title,
    required IconData icon,
    required VoidCallback onPressed,
    required List<Color> gradientColors,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAgreementSection() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        margin: EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: _termsAgreed
              ? Border.all(color: Color(0xFF10B981), width: 2)
              : Border.all(color: Color(0xFFE5E7EB), width: 1),
          boxShadow: [
            BoxShadow(
              color: _termsAgreed
                  ? Color(0xFF10B981).withOpacity(0.2)
                  : Color(0xFF1F2937).withOpacity(0.08),
              blurRadius: 20,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _termsAgreed
                            ? [Color(0xFF10B981), Color(0xFF059669)]
                            : [Color(0xFF6B7280), Color(0xFF4B5563)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      _termsAgreed ? Icons.check_circle : Icons.check_circle_outline,
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
                          _termsAgreed ? 'Terms Agreed' : 'Agree to Terms',
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _termsAgreed ? Color(0xFF10B981) : Color(0xFF1F2937),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _termsAgreed
                              ? 'You have agreed to the Terms of Service'
                              : 'Confirm that you agree to our Terms of Service',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!_termsAgreed) ...[
                SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: _currentUser != null
                        ? LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                        : LinearGradient(
                      colors: [Color(0xFFE5E7EB), Color(0xFFD1D5DB)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: _currentUser != null
                        ? [
                      BoxShadow(
                        color: Color(0xFF3B82F6).withOpacity(0.3),
                        blurRadius: 15,
                        offset: Offset(0, 6),
                      ),
                    ]
                        : [],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: _currentUser != null
                          ? _agreeToTerms
                          : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Please log in to agree to terms'),
                            backgroundColor: Colors.orange.shade400,
                            action: SnackBarAction(
                              label: 'Log In',
                              textColor: Colors.white,
                              onPressed: () => Navigator.pushNamed(context, '/account'),
                            ),
                          ),
                        );
                      },
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _currentUser != null ? Icons.check : Icons.login,
                              color: _currentUser != null ? Colors.white : Color(0xFF9CA3AF),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              _currentUser != null ? 'Confirm Agreement' : 'Log In to Agree',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _currentUser != null ? Colors.white : Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF1F2937).withOpacity(0.1),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(Icons.arrow_back, color: Color(0xFF374151)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          physics: BouncingScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildLegalSection(
                      title: 'Terms of Service',
                      description:
                      'By using Job Seaker App, you agree to our Terms of Service. These terms govern your use of the app, including job applications, user conduct, and data handling. For the full terms, click the link below.',
                      lastUpdated: 'Last updated: July 20, 2025',
                      icon: Icons.description,
                      gradientColors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                      onViewFull: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FullTermsPage(),
                            settings: const RouteSettings(name: 'FullTermsPage'),
                          ),
                        );
                        _logLegalDocumentView('terms');
                      },
                      onOpenBrowser: () => _launchUrl(
                        'https://www.jobseakerapp.com/terms',
                        'terms',
                      ),
                    ),
                    _buildLegalSection(
                      title: 'Privacy Policy',
                      description:
                      'Our Privacy Policy explains how we collect, use, and protect your data. This includes personal information, location data, and usage analytics. For the full policy, click the link below.',
                      lastUpdated: 'Last updated: July 20, 2025',
                      icon: Icons.privacy_tip,
                      gradientColors: [Color(0xFF10B981), Color(0xFF059669)],
                      onViewFull: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FullPrivacyPolicyPage(),
                            settings: const RouteSettings(name: 'FullPrivacyPolicyPage'),
                          ),
                        );
                        _logLegalDocumentView('policy');
                      },
                      onOpenBrowser: () => _launchUrl(
                        'https://www.jobseakerapp.com/privacy',
                        'policy',
                      ),
                    ),
                    _buildAgreementSection(),
                    SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}