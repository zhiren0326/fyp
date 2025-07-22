import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fyp/Splah/splash_screen.dart';
import 'package:fyp/firebase_options.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

bool? seenOnboard;
bool _isFirebaseInitialized = false;
bool _allowDataSharing = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    _isFirebaseInitialized = true;
  } catch (e) {
    print('Firebase initialization failed: $e');
    _isFirebaseInitialized = false;
  }

  // Initialize Firebase Analytics
  FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  await analytics.setAnalyticsCollectionEnabled(true);

  // Show status bar
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.bottom, SystemUiOverlay.top],
  );

  // Load onboarding and privacy settings
  SharedPreferences pref = await SharedPreferences.getInstance();
  seenOnboard = pref.getBool('seenOnboard') ?? false;
  _allowDataSharing = pref.getBool('allowDataSharing') ?? false;

  runApp(MyApp(analytics: analytics));
}

class MyApp extends StatelessWidget {
  final FirebaseAnalytics analytics;

  const MyApp({super.key, required this.analytics});

  // Retrieve allowDataSharing from SharedPreferences
  Future<bool> _getDataSharingAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('allowDataSharing') ?? false;
  }

  // Retrieve user ID from Firebase Auth
  String? _getUserId() {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Job Seeker App',
      theme: ThemeData(
        textTheme: GoogleFonts.manropeTextTheme(
          Theme.of(context).textTheme,
        ),
        primarySwatch: Colors.blue,
      ),
      home: const SplashScreen(),
      navigatorObservers: [
        AnalyticsNavigatorObserver(
          analytics: analytics,
          isDataSharingAllowed: _getDataSharingAllowed,
          getUserId: _getUserId,
          isFirebaseInitialized: () => _isFirebaseInitialized,
        ),
      ],
    );
  }
}

class AnalyticsNavigatorObserver extends NavigatorObserver {
  final FirebaseAnalytics analytics;
  final Future<bool> Function() isDataSharingAllowed;
  final String? Function() getUserId;
  final bool Function() isFirebaseInitialized;

  AnalyticsNavigatorObserver({
    required this.analytics,
    required this.isDataSharingAllowed,
    required this.getUserId,
    required this.isFirebaseInitialized,
  });

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    _logScreenView(route);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _logScreenView(newRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) _logScreenView(previousRoute);
  }

  Future<void> _logScreenView(Route route) async {
    final String? screenName = route.settings.name;
    if (screenName != null &&
        isFirebaseInitialized() &&
        await isDataSharingAllowed() &&
        getUserId() != null) {
      await analytics.logScreenView(
        screenName: screenName,
        screenClass: screenName,
        parameters: {
          'user_id': getUserId()!,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      print('Screen view logged: $screenName');
    }
  }
}