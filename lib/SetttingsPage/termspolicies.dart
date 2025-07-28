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

class _TermsPoliciesPageState extends State<TermsPoliciesPage> {
  bool _isFirebaseInitialized = false;
  bool _allowDataSharing = false;
  User? _currentUser;
  late FirebaseAnalytics _analytics;
  bool _termsAgreed = false;

  @override
  void initState() {
    super.initState();
    _analytics = FirebaseAnalytics.instance;
    _checkFirebaseInitialization();
    _checkUserAndLoadPreferences();
    _logScreenView();
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
        SnackBar(content: Text('Unable to open $documentType')),
      );
    }
  }

  // Agree to terms
  Future<void> _agreeToTerms() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please log in to agree to terms'),
          action: SnackBarAction(
            label: 'Log In',
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
        SnackBar(content: Text('Terms agreed successfully')),
      );
    } catch (e) {
      print('Error saving terms agreement: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save terms agreement: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Terms and Policies',
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB2DFDB), Colors.white],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.all(16.0),
          children: [
            // Terms of Service Section
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ExpansionTile(
                title: Text(
                  'Terms of Service',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
                ),
                children: [
                  Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'By using Job Seaker App, you agree to our Terms of Service. These terms govern your use of the app, including job applications, user conduct, and data handling. For the full terms, click the link below.\n\nLast updated: July 20, 2025',
                      style: GoogleFonts.manrope(),
                    ),
                  ),
                  ListTile(
                    title: Text(
                      'View Full Terms',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w500),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, color: Colors.teal),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const FullTermsPage(),
                          settings: const RouteSettings(name: 'FullTermsPage'),
                        ),
                      );
                      _logLegalDocumentView('terms');
                    },
                  ),
                  ListTile(
                    title: Text(
                      'Open Terms in Browser',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w500),
                    ),
                    trailing: Icon(Icons.open_in_browser, color: Colors.teal),
                    onTap: () => _launchUrl(
                      'https://www.jobseakerapp.com/terms',
                      'terms',
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            // Privacy Policy Section
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ExpansionTile(
                title: Text(
                  'Privacy Policy',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
                ),
                children: [
                  Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'Our Privacy Policy explains how we collect, use, and protect your data. This includes personal information, location data, and usage analytics. For the full policy, click the link below.\n\nLast updated: July 20, 2025',
                      style: GoogleFonts.manrope(),
                    ),
                  ),
                  ListTile(
                    title: Text(
                      'View Full Privacy Policy',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w500),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, color: Colors.teal),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const FullPrivacyPolicyPage(),
                          settings: const RouteSettings(name: 'FullPrivacyPolicyPage'),
                        ),
                      );
                      _logLegalDocumentView('policy');
                    },
                  ),
                  ListTile(
                    title: Text(
                      'Open Privacy Policy in Browser',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w500),
                    ),
                    trailing: Icon(Icons.open_in_browser, color: Colors.teal),
                    onTap: () => _launchUrl(
                      'https://www.jobseakerapp.com/privacy',
                      'policy',
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            // Agree to Terms Button
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                title: Text(
                  _termsAgreed ? 'Terms Agreed' : 'Agree to Terms',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  _termsAgreed
                      ? 'You have agreed to the Terms of Service'
                      : 'Confirm that you agree to our Terms of Service',
                  style: GoogleFonts.manrope(),
                ),
                trailing: Icon(
                  _termsAgreed ? Icons.check_circle : Icons.check_circle_outline,
                  color: _termsAgreed ? Colors.teal : Colors.grey,
                ),
                onTap: _termsAgreed ? null : _agreeToTerms,
              ),
            ),
            SizedBox(height: 16),
            // Save Button
            ElevatedButton(
              onPressed: _currentUser != null
                  ? _agreeToTerms
                  : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please log in to agree to terms'),
                    action: SnackBarAction(
                      label: 'Log In',
                      onPressed: () => Navigator.pushNamed(context, '/account'),
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _currentUser != null ? Colors.teal : Colors.grey,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                _currentUser != null ? 'Confirm Agreement' : 'Log In to Agree',
                style: GoogleFonts.manrope(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}