import 'package:flutter/material.dart';
import 'package:fyp/Login%20Signup/Screen/login.dart';
import 'package:fyp/SetttingsPage/contactUS.dart';
import 'package:fyp/SetttingsPage/helpsupport.dart';
import 'package:fyp/SetttingsPage/ourlocation.dart';
import 'package:fyp/SetttingsPage/privacy.dart';
import 'package:fyp/SetttingsPage/reportproblem.dart';
import 'package:fyp/SetttingsPage/termspolicies.dart';
import 'package:fyp/module/Profile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp/module/SkillTags.dart'; // Added for Firebase Authentication


class AccountPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Future<void> _logout() async {
      try {
        await FirebaseAuth.instance.signOut();
        // Navigate to sign-in page and remove all previous routes
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => LoginScreen()),
              (Route<dynamic> route) => false,
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: $e')),
        );
      }
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB2DFDB), Colors.white],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(8.0),
                children: [
                  // Account Section Header
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Account',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.symmetric(vertical: 4.0),
                    child: ListTile(
                      leading: Icon(Icons.person, color: Colors.black),
                      title: Text('Profile', style: TextStyle(color: Colors.black)),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen()));
                      },
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.symmetric(vertical: 4.0),
                    child: ListTile(
                      leading: Icon(Icons.ac_unit, color: Colors.black),
                      title: Text('Skills', style: TextStyle(color: Colors.black)),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => SkillTagScreen()));
                      },
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.symmetric(vertical: 4.0),
                    child: ListTile(
                      leading: Icon(Icons.lock, color: Colors.black),
                      title: Text('Privacy', style: TextStyle(color: Colors.black)),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => PrivacyPage()));
                      },
                    ),
                  ),
                  // Support & About Section Header
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Support & About',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.symmetric(vertical: 4.0),
                    child: ListTile(
                      leading: Icon(Icons.help, color: Colors.black),
                      title: Text('Help & Support', style: TextStyle(color: Colors.black)),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => HelpSupportPage()));
                      },
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.symmetric(vertical: 4.0),
                    child: ListTile(
                      leading: Icon(Icons.description, color: Colors.black),
                      title: Text('Terms and Policies', style: TextStyle(color: Colors.black)),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => TermsPoliciesPage()));
                      },
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.symmetric(vertical: 4.0),
                    child: ListTile(
                      leading: Icon(Icons.contact_phone, color: Colors.black),
                      title: Text('Contact Us', style: TextStyle(color: Colors.black)),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => ContactUsPage()));
                      },
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.symmetric(vertical: 4.0),
                    child: ListTile(
                      leading: Icon(Icons.location_on, color: Colors.black),
                      title: Text('Our Locations', style: TextStyle(color: Colors.black)),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => OurLocationsPage()));
                      },
                    ),
                  ),
                  // Actions Section Header
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Actions',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.symmetric(vertical: 4.0),
                    child: ListTile(
                      leading: Icon(Icons.report_problem, color: Colors.black),
                      title: Text('Report a problem', style: TextStyle(color: Colors.black)),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => ReportProblemPage()));
                      },
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.symmetric(vertical: 4.0),
                    child: ListTile(
                      leading: Icon(Icons.logout, color: Colors.black),
                      title: Text('Log out', style: TextStyle(color: Colors.black)),
                      onTap: () {
                        _logout(); // Call logout function
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Taaz for android v11.9.0(5837) store bundled arm64-v6a',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}