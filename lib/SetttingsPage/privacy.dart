import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fyp/SetttingsPage/account.dart'; // Import AccountPage for navigation

class PrivacyPage extends StatefulWidget {
  @override
  _PrivacyPageState createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> with TickerProviderStateMixin {
  bool _allowDataSharing = false;
  bool _enableLocationTracking = false;
  bool _isFirebaseInitialized = false;
  User? _currentUser;
  late FirebaseAnalytics _analytics;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _analytics = FirebaseAnalytics.instance;
    _animationController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _checkFirebaseInitialization();
    _checkUserAndLoadPreferences();
    _logScreenView();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Log screen view for PrivacyPage
  Future<void> _logScreenView() async {
    if (_isFirebaseInitialized && _allowDataSharing && _currentUser != null) {
      try {
        await _analytics.logScreenView(
          screenName: 'PrivacyPage',
          screenClass: 'PrivacyPage',
          parameters: {
            'user_id': _currentUser!.uid,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        print('Screen view logged for PrivacyPage');
      } catch (e) {
        print('Error logging screen view: $e');
      }
    }
  }

  // Check if Firebase is initialized
  Future<void> _checkFirebaseInitialization() async {
    try {
      await Firebase.initializeApp();
      setState(() {
        _isFirebaseInitialized = true;
      });
      await _analytics.setAnalyticsCollectionEnabled(true);
      print('Firebase initialized successfully');
    } catch (e) {
      print('Firebase initialization failed: $e');
      setState(() {
        _isFirebaseInitialized = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Firebase initialization failed. Analytics may not work.'),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }

  // Check current user and load preferences from Firestore
  Future<void> _checkUserAndLoadPreferences() async {
    _currentUser = FirebaseAuth.instance.currentUser;
    if (_currentUser != null) {
      await _loadPreferences();
    } else {
      print('No user logged in');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please log in to access privacy settings'),
          backgroundColor: Colors.orange.shade400,
        ),
      );
    }
  }

  // Load saved preferences from Firestore
  Future<void> _loadPreferences() async {
    if (_currentUser == null) return;
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('privacy_settings')
          .doc('settings')
          .get();
      if (doc.exists) {
        setState(() {
          _allowDataSharing = doc['allowDataSharing'] ?? false;
          _enableLocationTracking = doc['enableLocationTracking'] ?? false;
        });
        if (_enableLocationTracking) {
          await _startLocationTracking();
        }
      }
    } catch (e) {
      print('Error loading preferences: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load privacy settings: $e'),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }

  // Save data sharing preference
  Future<void> _saveDataSharingPreference(bool value) async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please log in to save privacy settings'),
          backgroundColor: Colors.orange.shade400,
        ),
      );
      setState(() {
        _allowDataSharing = false;
      });
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('privacy_settings')
          .doc('settings')
          .set(
        {'allowDataSharing': value, 'enableLocationTracking': _enableLocationTracking},
        SetOptions(merge: true),
      );
      if (_isFirebaseInitialized) {
        try {
          await _analytics.setAnalyticsCollectionEnabled(value);
          await _analytics.logEvent(
            name: value ? 'data_sharing_enabled' : 'data_sharing_disabled',
            parameters: {
              'enabled': value.toString(),
              'timestamp': DateTime.now().toIso8601String(),
              'user_id': _currentUser!.uid,
            },
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Data sharing ${value ? 'enabled' : 'disabled'}'),
              backgroundColor: Colors.green.shade400,
            ),
          );
        } catch (e) {
          print('Error updating analytics: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update analytics settings: $e'),
              backgroundColor: Colors.red.shade400,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Data sharing ${value ? 'enabled' : 'disabled'}, but analytics not available'),
            backgroundColor: Colors.orange.shade400,
          ),
        );
      }
    } catch (e) {
      print('Error saving data sharing preference: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save data sharing preference: $e'),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }

  // Save location tracking preference
  Future<void> _saveLocationTrackingPreference(bool value) async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please log in to save privacy settings'),
          backgroundColor: Colors.orange.shade400,
        ),
      );
      setState(() {
        _enableLocationTracking = false;
      });
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('privacy_settings')
          .doc('settings')
          .set(
        {'allowDataSharing': _allowDataSharing, 'enableLocationTracking': value},
        SetOptions(merge: true),
      );
      if (value) {
        await _startLocationTracking();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location tracking disabled'),
            backgroundColor: Colors.orange.shade400,
          ),
        );
        if (_isFirebaseInitialized) {
          try {
            await _analytics.logEvent(
              name: 'location_tracking_disabled',
              parameters: {
                'enabled': value.toString(),
                'timestamp': DateTime.now().toIso8601String(),
                'user_id': _currentUser!.uid,
              },
            );
          } catch (e) {
            print('Error logging location tracking disabled: $e');
          }
        }
      }
    } catch (e) {
      print('Error saving location tracking preference: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save location tracking preference: $e'),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }

  // Start location tracking with permission handling and retry
  Future<void> _startLocationTracking() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please log in to enable location tracking'),
          backgroundColor: Colors.orange.shade400,
        ),
      );
      setState(() {
        _enableLocationTracking = false;
        _saveLocationTrackingPreference(false);
      });
      return;
    }
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location services are disabled. Please enable them in settings.'),
          backgroundColor: Colors.orange.shade400,
          action: SnackBarAction(
            label: 'Open Settings',
            textColor: Colors.white,
            onPressed: () async {
              await Geolocator.openLocationSettings();
              if (await Geolocator.isLocationServiceEnabled()) {
                await _startLocationTracking(); // Retry after enabling
              }
            },
          ),
        ),
      );
      setState(() {
        _enableLocationTracking = false;
        _saveLocationTrackingPreference(false);
      });
      return;
    }

    PermissionStatus status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      int retries = 3;
      while (retries > 0) {
        try {
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          );
          print('Location: ${position.latitude}, ${position.longitude}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Location tracking enabled'),
              backgroundColor: Colors.green.shade400,
            ),
          );
          if (_isFirebaseInitialized && _allowDataSharing) {
            try {
              await _analytics.logEvent(
                name: 'location_tracking_enabled',
                parameters: {
                  'enabled': 'true',
                  'latitude': position.latitude.toString(),
                  'longitude': position.longitude.toString(),
                  'timestamp': DateTime.now().toIso8601String(),
                  'user_id': _currentUser!.uid,
                },
              );
            } catch (e) {
              print('Error logging location tracking enabled: $e');
            }
          }
          return;
        } catch (e) {
          String errorMessage;
          if (e is LocationServiceDisabledException) {
            errorMessage = 'Location services disabled';
          } else if (e is TimeoutException) {
            errorMessage = 'Location request timed out';
          } else if (e is PermissionDeniedException) {
            errorMessage = 'Location permission denied';
          } else {
            errorMessage = e.toString();
          }
          print('Error getting location (attempt ${4 - retries}/3): $errorMessage');
          retries--;
          if (retries == 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to access location: $errorMessage'),
                backgroundColor: Colors.red.shade400,
              ),
            );
            setState(() {
              _enableLocationTracking = false;
              _saveLocationTrackingPreference(false);
            });
            await Future.delayed(Duration(seconds: 2));
          }
        }
      }
    } else if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location permission permanently denied. Please enable in settings.'),
          backgroundColor: Colors.red.shade400,
          action: SnackBarAction(
            label: 'Open Settings',
            textColor: Colors.white,
            onPressed: () async {
              await openAppSettings();
              if (await Permission.locationWhenInUse.isGranted) {
                await _startLocationTracking(); // Retry after enabling
              }
            },
          ),
        ),
      );
      setState(() {
        _enableLocationTracking = false;
        _saveLocationTrackingPreference(false);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location permission denied'),
          backgroundColor: Colors.red.shade400,
        ),
      );
      setState(() {
        _enableLocationTracking = false;
        _saveLocationTrackingPreference(false);
      });
    }
  }

  // Launch privacy policy URL
  Future<void> _launchPrivacyPolicy() async {
    const url = 'https://www.example.com/privacy-policy'; // Replace with actual URL
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (_isFirebaseInitialized && _allowDataSharing && _currentUser != null) {
        try {
          await _analytics.logEvent(
            name: 'privacy_policy_viewed',
            parameters: {
              'timestamp': DateTime.now().toIso8601String(),
              'user_id': _currentUser!.uid,
            },
          );
        } catch (e) {
          print('Error logging privacy policy view: $e');
        }
      }
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.privacy_tip, color: Color(0xFF6366F1), size: 28),
              SizedBox(width: 10),
              Text(
                'Privacy Policy',
                style: TextStyle(
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'Unable to load privacy policy. Please check your internet connection or contact support.\n\n'
                  'This is a placeholder for the privacy policy. In a real app, this would contain detailed information '
                  'about data usage, storage, and user rights.\n\nLast updated: July 20, 2025',
              style: TextStyle(color: Color(0xFF6B7280), height: 1.5),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Color(0xFF6366F1),
                backgroundColor: Color(0xFFF3F4F6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text('Close', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }
  }

  // Save all settings
  Future<void> _saveSettings() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please log in to save privacy settings'),
          backgroundColor: Colors.orange.shade400,
          action: SnackBarAction(
            label: 'Log In',
            textColor: Colors.white,
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AccountPage()),
            ),
          ),
        ),
      );
      return;
    }
    await _saveDataSharingPreference(_allowDataSharing);
    await _saveLocationTrackingPreference(_enableLocationTracking);
    if (_isFirebaseInitialized && _allowDataSharing) {
      try {
        await _analytics.logEvent(
          name: 'privacy_settings_saved',
          parameters: {
            'data_sharing': _allowDataSharing.toString(),
            'location_tracking': _enableLocationTracking.toString(),
            'timestamp': DateTime.now().toIso8601String(),
            'user_id': _currentUser!.uid,
          },
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Privacy settings saved successfully'),
            backgroundColor: Colors.green.shade400,
          ),
        );
      } catch (e) {
        print('Error logging save settings: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Settings saved, but analytics logging failed: $e'),
            backgroundColor: Colors.orange.shade400,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings saved, but analytics not available'),
          backgroundColor: Colors.orange.shade400,
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
                colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF8B5CF6).withOpacity(0.3),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              Icons.security,
              color: Colors.white,
              size: 40,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Privacy Settings',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Manage your data and privacy preferences',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
    required List<Color> gradientColors,
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
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                icon,
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
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 1.2,
              child: Switch(
                value: value,
                onChanged: _currentUser != null ? onChanged : null,
                activeColor: gradientColors[1],
                activeTrackColor: gradientColors[0].withOpacity(0.3),
                inactiveThumbColor: Color(0xFFE5E7EB),
                inactiveTrackColor: Color(0xFFF3F4F6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyPolicyCard() {
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _launchPrivacyPolicy,
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.article,
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
                        'View Privacy Policy',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Learn more about how we handle your data',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    color: Color(0xFF6B7280),
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: _currentUser != null
            ? LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        )
            : LinearGradient(
          colors: [Color(0xFFE5E7EB), Color(0xFFD1D5DB)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: _currentUser != null
            ? [
          BoxShadow(
            color: Color(0xFF8B5CF6).withOpacity(0.3),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _currentUser != null
              ? _saveSettings
              : () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Please log in to save privacy settings'),
                backgroundColor: Colors.orange.shade400,
                action: SnackBarAction(
                  label: 'Log In',
                  textColor: Colors.white,
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => AccountPage()),
                  ),
                ),
              ),
            );
          },
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _currentUser != null ? Icons.save : Icons.login,
                  color: _currentUser != null ? Colors.white : Color(0xFF9CA3AF),
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  _currentUser != null ? 'Save Changes' : 'Log In to Save',
                  style: TextStyle(
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
        actions: [
          Container(
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
              icon: Icon(
                Icons.save,
                color: _currentUser != null ? Color(0xFF6366F1) : Color(0xFF9CA3AF),
              ),
              onPressed: _currentUser != null ? _saveSettings : null,
              tooltip: _currentUser != null ? 'Save Settings' : 'Log in to save settings',
            ),
          ),
        ],
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
                    _buildSettingCard(
                      title: 'Allow Data Sharing',
                      subtitle: 'Share usage data to improve the app',
                      icon: Icons.share,
                      value: _allowDataSharing,
                      onChanged: (value) {
                        setState(() {
                          _allowDataSharing = value;
                          _saveDataSharingPreference(value);
                        });
                      },
                      gradientColors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                    ),
                    _buildSettingCard(
                      title: 'Enable Location Tracking',
                      subtitle: 'Allow the app to access your location',
                      icon: Icons.location_on,
                      value: _enableLocationTracking,
                      onChanged: (value) {
                        setState(() {
                          _enableLocationTracking = value;
                          _saveLocationTrackingPreference(value);
                        });
                      },
                      gradientColors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                    ),
                    _buildPrivacyPolicyCard(),
                    SizedBox(height: 20),
                    _buildSaveButton(),
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