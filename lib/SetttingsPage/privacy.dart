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

class _PrivacyPageState extends State<PrivacyPage> {
  bool _allowDataSharing = false;
  bool _enableLocationTracking = false;
  bool _isFirebaseInitialized = false;
  User? _currentUser;
  late FirebaseAnalytics _analytics;

  @override
  void initState() {
    super.initState();
    _analytics = FirebaseAnalytics.instance;
    _checkFirebaseInitialization();
    _checkUserAndLoadPreferences();
    _logScreenView(); // Log screen view when PrivacyPage is initialized
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
        SnackBar(content: Text('Firebase initialization failed. Analytics may not work.')),
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
        SnackBar(content: Text('Please log in to access privacy settings')),
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
        SnackBar(content: Text('Failed to load privacy settings: $e')),
      );
    }
  }

  // Save data sharing preference
  Future<void> _saveDataSharingPreference(bool value) async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please log in to save privacy settings')),
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
            SnackBar(content: Text('Data sharing ${value ? 'enabled' : 'disabled'}')),
          );
        } catch (e) {
          print('Error updating analytics: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update analytics settings: $e')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data sharing ${value ? 'enabled' : 'disabled'}, but analytics not available')),
        );
      }
    } catch (e) {
      print('Error saving data sharing preference: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save data sharing preference: $e')),
      );
    }
  }

  // Save location tracking preference
  Future<void> _saveLocationTrackingPreference(bool value) async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please log in to save privacy settings')),
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
          SnackBar(content: Text('Location tracking disabled')),
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
        SnackBar(content: Text('Failed to save location tracking preference: $e')),
      );
    }
  }

  // Start location tracking with permission handling and retry
  Future<void> _startLocationTracking() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please log in to enable location tracking')),
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
          action: SnackBarAction(
            label: 'Open Settings',
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
            SnackBar(content: Text('Location tracking enabled')),
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
              SnackBar(content: Text('Failed to access location: $errorMessage')),
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
          action: SnackBarAction(
            label: 'Open Settings',
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
        SnackBar(content: Text('Location permission denied')),
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
          title: Text('Privacy Policy'),
          content: SingleChildScrollView(
            child: Text(
              'Unable to load privacy policy. Please check your internet connection or contact support.\n\n'
                  'This is a placeholder for the privacy policy. In a real app, this would contain detailed information '
                  'about data usage, storage, and user rights.\n\nLast updated: July 20, 2025',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: Colors.teal)),
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
          action: SnackBarAction(
            label: 'Log In',
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
          SnackBar(content: Text('Privacy settings saved successfully')),
        );
      } catch (e) {
        print('Error logging save settings: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Settings saved, but analytics logging failed: $e')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Settings saved, but analytics not available')),
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
        title: const Text('Privacy'),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.save, color: _currentUser != null ? Colors.white : Colors.grey),
            onPressed: _currentUser != null ? _saveSettings : null,
            tooltip: _currentUser != null ? 'Save Settings' : 'Log in to save settings',
          ),
        ],
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
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: SwitchListTile(
                title: Text('Allow Data Sharing'),
                subtitle: Text('Share usage data to improve the app'),
                value: _allowDataSharing,
                onChanged: _currentUser != null
                    ? (value) {
                  setState(() {
                    _allowDataSharing = value;
                    _saveDataSharingPreference(value);
                  });
                }
                    : null,
                activeColor: Colors.teal,
                inactiveTrackColor: Colors.grey,
              ),
            ),
            SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: SwitchListTile(
                title: Text('Enable Location Tracking'),
                subtitle: Text('Allow the app to access your location'),
                value: _enableLocationTracking,
                onChanged: _currentUser != null
                    ? (value) {
                  setState(() {
                    _enableLocationTracking = value;
                    _saveLocationTrackingPreference(value);
                  });
                }
                    : null,
                activeColor: Colors.teal,
                inactiveTrackColor: Colors.grey,
              ),
            ),
            SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                title: Text('View Privacy Policy'),
                subtitle: Text('Learn more about how we handle your data'),
                trailing: Icon(Icons.arrow_forward_ios, color: Colors.teal),
                onTap: _launchPrivacyPolicy,
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _currentUser != null
                  ? _saveSettings
                  : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please log in to save privacy settings'),
                    action: SnackBarAction(
                      label: 'Log In',
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => AccountPage()),
                      ),
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
              child: Text(_currentUser != null ? 'Save Changes' : 'Log In to Save'),
            ),
          ],
        ),
      ),
    );
  }
}