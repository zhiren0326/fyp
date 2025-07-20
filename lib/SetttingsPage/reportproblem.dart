import 'dart:io';
import 'dart:convert'; // Added for Base64 encoding
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportProblemPage extends StatefulWidget {
  const ReportProblemPage({super.key});

  @override
  _ReportProblemPageState createState() => _ReportProblemPageState();
}

class _ReportProblemPageState extends State<ReportProblemPage> with SingleTickerProviderStateMixin {
  bool _isFirebaseInitialized = false;
  bool _allowDataSharing = false;
  User? _currentUser;
  late FirebaseAnalytics _analytics;
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  File? _selectedImage;
  bool _isUploading = false;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimationSubject;
  late Animation<Offset> _slideAnimationDescription;
  late Animation<Offset> _slideAnimationPhoto;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _analytics = FirebaseAnalytics.instance;
    // Initialize animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _slideAnimationSubject = Tween<Offset>(begin: Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _slideAnimationDescription = Tween<Offset>(begin: Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Interval(0.2, 0.8, curve: Curves.easeOut)),
    );
    _slideAnimationPhoto = Tween<Offset>(begin: Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Interval(0.4, 1.0, curve: Curves.easeOut)),
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
          screenName: 'ReportProblemPage',
          screenClass: 'ReportProblemPage',
          parameters: <String, String>{
            'user_id': _currentUser!.uid,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        print('Screen view logged for ReportProblemPage');
      } catch (e) {
        print('Error logging screen view: $e');
      }
    }
  }

  // Log problem report submission
  Future<void> _logProblemReportSubmitted() async {
    if (_isFirebaseInitialized && _allowDataSharing && _currentUser != null) {
      try {
        await _analytics.logEvent(
          name: 'problem_report_submitted',
          parameters: <String, String>{
            'user_id': _currentUser!.uid,
            'timestamp': DateTime.now().toIso8601String(),
            'subject': _subjectController.text,
            'has_attachment': _selectedImage != null ? 'true' : 'false',
          },
        );
        print('Problem report submission logged');
      } catch (e) {
        print('Error logging problem report submission: $e');
      }
    }
  }

  // Pick image from gallery or camera
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source, maxWidth: 800, maxHeight: 800);
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  // Submit problem report
  Future<void> _submitReport() async {
    if (_formKey.currentState!.validate()) {
      if (_currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please log in to submit a problem report'),
            action: SnackBarAction(
              label: 'Log In',
              onPressed: () => Navigator.pushNamed(context, '/account'),
            ),
          ),
        );
        return;
      }
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Submission', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
          content: Text('Are you sure you want to submit this problem report?', style: GoogleFonts.manrope()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.manrope()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: Text('Submit', style: GoogleFonts.manrope()),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      setState(() {
        _isUploading = true;
      });
      try {
        String? imageBase64;
        if (_selectedImage != null) {
          final bytes = await _selectedImage!.readAsBytes();
          imageBase64 = base64Encode(bytes);
        }
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('problem_reports')
            .add(<String, dynamic>{
          'subject': _subjectController.text,
          'description': _descriptionController.text,
          'attachment_base64': imageBase64, // Store Base64 string instead of URL
          'timestamp': DateTime.now().toIso8601String(),
          'user_id': _currentUser!.uid,
        });
        await _logProblemReportSubmitted();
        _subjectController.clear();
        _descriptionController.clear();
        setState(() {
          _selectedImage = null;
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Problem report submitted successfully')),
        );
      } catch (e) {
        print('Error submitting problem report: $e');
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit problem report: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
                child: const Icon(Icons.arrow_back, color: Colors.white),
              );
            },
          ),
        ),
        title: FadeTransition(
          opacity: _fadeAnimation,
          child: Text(
            'Report a Problem',
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
                      'Report a Problem',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  SlideTransition(
                    position: _slideAnimationSubject,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tell us about the issue',
                                style: GoogleFonts.manrope(fontWeight: FontWeight.w500),
                              ),
                              SizedBox(height: 8),
                              SlideTransition(
                                position: _slideAnimationSubject,
                                child: TextFormField(
                                  controller: _subjectController,
                                  decoration: InputDecoration(
                                    labelText: 'Subject',
                                    border: OutlineInputBorder(),
                                    labelStyle: GoogleFonts.manrope(),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter a subject';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(height: 8),
                              SlideTransition(
                                position: _slideAnimationDescription,
                                child: TextFormField(
                                  controller: _descriptionController,
                                  decoration: InputDecoration(
                                    labelText: 'Description',
                                    border: OutlineInputBorder(),
                                    labelStyle: GoogleFonts.manrope(),
                                  ),
                                  maxLines: 5,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter a description';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(height: 16),
                              SlideTransition(
                                position: _slideAnimationPhoto,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Attach a Photo (Optional)',
                                      style: GoogleFonts.manrope(fontWeight: FontWeight.w500),
                                    ),
                                    SizedBox(height: 8),
                                    if (_selectedImage != null)
                                      Stack(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.file(
                                              _selectedImage!,
                                              height: 150,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: GestureDetector(
                                              onTap: () => setState(() => _selectedImage = null),
                                              child: Container(
                                                padding: EdgeInsets.all(4),
                                                color: Colors.black54,
                                                child: Icon(Icons.close, color: Colors.white, size: 20),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (_selectedImage == null) ...[
                                      ListTile(
                                        leading: Icon(Icons.photo_library, color: Colors.teal),
                                        title: Text(
                                          'Select from Album',
                                          style: GoogleFonts.manrope(),
                                        ),
                                        onTap: () => _pickImage(ImageSource.gallery),
                                      ),
                                      ListTile(
                                        leading: Icon(Icons.camera_alt, color: Colors.teal),
                                        title: Text(
                                          'Take a Photo',
                                          style: GoogleFonts.manrope(),
                                        ),
                                        onTap: () => _pickImage(ImageSource.camera),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              SizedBox(height: 16),
                              _isUploading
                                  ? Center(child: CircularProgressIndicator(color: Colors.teal))
                                  : ElevatedButton(
                                onPressed: _submitReport,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(
                                  'Submit Report',
                                  style: GoogleFonts.manrope(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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