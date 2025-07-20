import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  _HelpSupportPageState createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  bool _isFirebaseInitialized = false;
  bool _allowDataSharing = false;
  User? _currentUser;
  late FirebaseAnalytics _analytics;
  final TextEditingController _feedbackController = TextEditingController();

  // FAQ data
  final List<Map<String, String>> _faqs = [
    {
      'question': 'How do I reset my password?',
      'answer': 'Go to the Account page, select "Forgot Password," and follow the instructions to reset your password via email.',
    },
    {
      'question': 'How do I enable location tracking?',
      'answer': 'Navigate to the Privacy page in Settings and toggle "Enable Location Tracking." Ensure location permissions are granted.',
    },
    {
      'question': 'How can I contact support?',
      'answer': 'Use the "Contact Support" button below to send an email, or submit feedback through the form.',
    },
  ];

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
  }

  // Log screen view
  Future<void> _logScreenView() async {
    if (_isFirebaseInitialized && _allowDataSharing && _currentUser != null) {
      try {
        await _analytics.logScreenView(
          screenName: 'HelpSupportPage',
          screenClass: 'HelpSupportPage',
          parameters: <String, String>{
            'user_id': _currentUser!.uid,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        print('Screen view logged for HelpSupportPage');
      } catch (e) {
        print('Error logging screen view: $e');
      }
    }
  }

  // Log FAQ expansion
  Future<void> _logFaqInteraction(int index) async {
    if (_isFirebaseInitialized && _allowDataSharing && _currentUser != null) {
      try {
        await _analytics.logEvent(
          name: 'faq_viewed',
          parameters: <String, String>{
            'faq_index': index.toString(),
            'question': _faqs[index]['question']!,
            'user_id': _currentUser!.uid,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        print('FAQ interaction logged: ${_faqs[index]['question']}');
      } catch (e) {
        print('Error logging FAQ interaction: $e');
      }
    }
  }

  // Launch support email
  Future<void> _launchSupportEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'chiazr-wp22@student.tarc.edu.my',
      queryParameters: {
        'subject': 'Support Request from Job Seaker App',
        'body': 'Please describe your issue or question:',
      },
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
      if (_isFirebaseInitialized && _allowDataSharing && _currentUser != null) {
        try {
          await _analytics.logEvent(
            name: 'support_email_launched',
            parameters: <String, String>{
              'user_id': _currentUser!.uid,
              'timestamp': DateTime.now().toIso8601String(),
            },
          );
          print('Support email launch logged');
        } catch (e) {
          print('Error logging support email launch: $e');
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to launch email client')),
      );
    }
  }

  // Launch support website
  Future<void> _launchSupportWebsite() async {
    const url = 'https://www.jobseakerapp.com/support';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (_isFirebaseInitialized && _allowDataSharing && _currentUser != null) {
        try {
          await _analytics.logEvent(
            name: 'support_website_viewed',
            parameters: <String, String>{
              'user_id': _currentUser!.uid,
              'timestamp': DateTime.now().toIso8601String(),
            },
          );
          print('Support website view logged');
        } catch (e) {
          print('Error logging support website view: $e');
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open support website')),
      );
    }
  }

  // Submit feedback to Firestore
  Future<void> _submitFeedback(String feedback) async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please log in to submit feedback'),
          action: SnackBarAction(
            label: 'Log In',
            onPressed: () => Navigator.pushNamed(context, '/account'),
          ),
        ),
      );
      return;
    }
    if (feedback.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter feedback before submitting')),
      );
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('feedback')
          .add(<String, dynamic>{
        'feedback': feedback,
        'timestamp': DateTime.now().toIso8601String(),
        'user_id': _currentUser!.uid,
      });
      if (_isFirebaseInitialized && _allowDataSharing) {
        try {
          await _analytics.logEvent(
            name: 'feedback_submitted',
            parameters: <String, String>{
              'user_id': _currentUser!.uid,
              'timestamp': DateTime.now().toIso8601String(),
              'feedback_length': feedback.length.toString(),
            },
          );
          print('Feedback submission logged');
        } catch (e) {
          print('Error logging feedback submission: $e');
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Feedback submitted successfully')),
      );
      _feedbackController.clear();
    } catch (e) {
      print('Error submitting feedback: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit feedback: $e')),
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
          'Help & Support',
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
            // FAQs Section
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ExpansionTile(
                title: Text(
                  'Frequently Asked Questions',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
                ),
                children: _faqs.asMap().entries.map((entry) {
                  int index = entry.key;
                  Map<String, String> faq = entry.value;
                  return ListTile(
                    title: Text(
                      faq['question']!,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      faq['answer']!,
                      style: GoogleFonts.manrope(),
                    ),
                    onTap: () => _logFaqInteraction(index),
                  );
                }).toList(),
              ),
            ),
            SizedBox(height: 16),
            // Contact Support Button
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                title: Text(
                  'Contact Support',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Send an email to our support team',
                  style: GoogleFonts.manrope(),
                ),
                trailing: Icon(Icons.email, color: Colors.teal),
                onTap: _launchSupportEmail,
              ),
            ),
            SizedBox(height: 16),
            // Support Website Button
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                title: Text(
                  'Visit Support Website',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Access our online support resources',
                  style: GoogleFonts.manrope(),
                ),
                trailing: Icon(Icons.web, color: Colors.teal),
                onTap: _launchSupportWebsite,
              ),
            ),
            SizedBox(height: 16),
            // Feedback Form
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Submit Feedback',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: _feedbackController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Enter your feedback or issue...',
                        hintStyle: GoogleFonts.manrope(),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: () => _submitFeedback(_feedbackController.text),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'Submit',
                          style: GoogleFonts.manrope(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }
}