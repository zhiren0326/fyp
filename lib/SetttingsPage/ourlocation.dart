import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class OurLocationsPage extends StatefulWidget {
  const OurLocationsPage({super.key});

  @override
  _OurLocationsPageState createState() => _OurLocationsPageState();
}

class _OurLocationsPageState extends State<OurLocationsPage> with SingleTickerProviderStateMixin {
  bool _isFirebaseInitialized = false;
  bool _allowDataSharing = false;
  User? _currentUser;
  late FirebaseAnalytics _analytics;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  // Sample office locations (replace with actual data)
  final List<Map<String, String>> _locations = [
    {
      'name': 'Headquarters',
      'address': '123 Job St, Career City, CA 90210, USA',
      'phone': '+1-800-555-1234',
      'email': 'hq@jobseakerapp.com',
      'mapsUrl': 'https://maps.google.com/?q=123+Job+St,+Career+City,+CA+90210',
    },
    {
      'name': 'New York Office',
      'address': '456 Work Ave, New York, NY 10001, USA',
      'phone': '+1-800-555-5678',
      'email': 'ny@jobseakerapp.com',
      'mapsUrl': 'https://maps.google.com/?q=456+Work+Ave,+New+York,+NY+10001',
    },
  ];

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
          screenName: 'OurLocationsPage',
          screenClass: 'OurLocationsPage',
          parameters: <String, String>{
            'user_id': _currentUser!.uid,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        print('Screen view logged for OurLocationsPage');
      } catch (e) {
        print('Error logging screen view: $e');
      }
    }
  }

  // Log contact actions
  Future<void> _logAction(String action, String locationName) async {
    if (_isFirebaseInitialized && _allowDataSharing && _currentUser != null) {
      try {
        await _analytics.logEvent(
          name: action,
          parameters: <String, String>{
            'user_id': _currentUser!.uid,
            'location': locationName,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        print('$action logged for $locationName');
      } catch (e) {
        print('Error logging $action for $locationName: $e');
      }
    }
  }

  // Launch map
  Future<void> _launchMap(String mapsUrl, String locationName) async {
    if (await canLaunchUrl(Uri.parse(mapsUrl))) {
      await launchUrl(Uri.parse(mapsUrl), mode: LaunchMode.externalApplication);
      await _logAction('map_clicked', locationName);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open map for $locationName')),
      );
    }
  }

  // Launch phone
  Future<void> _launchPhone(String phone, String locationName) async {
    final phoneUrl = 'tel:$phone';
    if (await canLaunchUrl(Uri.parse(phoneUrl))) {
      await launchUrl(Uri.parse(phoneUrl));
      await _logAction('phone_clicked', locationName);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to make a call to $locationName')),
      );
    }
  }

  // Launch email
  Future<void> _launchEmail(String email, String locationName) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': 'Inquiry from $locationName'},
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
      await _logAction('email_clicked', locationName);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open email client for $locationName')),
      );
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
            'Our Locations',
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
                      'Our Locations',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  ..._locations.map((location) => SlideTransition(
                    position: _slideAnimation,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              location['name']!,
                              style: GoogleFonts.manrope(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 8),
                            ListTile(
                              leading: Icon(Icons.location_on, color: Colors.teal),
                              title: Text(
                                location['address']!,
                                style: GoogleFonts.manrope(),
                              ),
                              onTap: () => _launchMap(location['mapsUrl']!, location['name']!),
                            ),
                            ListTile(
                              leading: Icon(Icons.phone, color: Colors.teal),
                              title: Text(
                                location['phone']!,
                                style: GoogleFonts.manrope(),
                              ),
                              onTap: () => _launchPhone(location['phone']!, location['name']!),
                            ),
                            ListTile(
                              leading: Icon(Icons.email, color: Colors.teal),
                              title: Text(
                                location['email']!,
                                style: GoogleFonts.manrope(),
                              ),
                              onTap: () => _launchEmail(location['email']!, location['name']!),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}