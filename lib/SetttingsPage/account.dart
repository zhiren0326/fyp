import 'package:flutter/material.dart';
import 'package:fyp/SetttingsPage/contactUS.dart';
import 'package:fyp/SetttingsPage/helpsupport.dart';
import 'package:fyp/SetttingsPage/ourlocation.dart';
import 'package:fyp/SetttingsPage/privacy.dart';
import 'package:fyp/SetttingsPage/reportproblem.dart';
import 'package:fyp/SetttingsPage/security.dart';
import 'package:fyp/SetttingsPage/termspolicies.dart';
import 'package:fyp/module/Profile.dart';

class AccountPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(8.0),
                children: [
                  Card(
                    child: ExpansionTile(
                      title: Text(
                        'Account',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      children: [
                        ListTile(
                          leading: Icon(Icons.person),
                          title: Text('Profile'),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen()));
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.security),
                          title: Text('Security'),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => SecurityPage()));
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.lock),
                          title: Text('Privacy'),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => PrivacyPage()));
                          },
                        ),
                      ],
                    ),
                  ),
                  Card(
                    child: ExpansionTile(
                      title: Text(
                        'Support & About',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      children: [
                        ListTile(
                          leading: Icon(Icons.help),
                          title: Text('Help & Support'),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => HelpSupportPage()));
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.description),
                          title: Text('Terms and Policies'),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => TermsPoliciesPage()));
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.contact_phone),
                          title: Text('Contact Us'),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => ContactUsPage()));
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.location_on),
                          title: Text('Our Locations'),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => OurLocationsPage()));
                          },
                        ),
                      ],
                    ),
                  ),
                  Card(
                    child: ExpansionTile(
                      title: Text(
                        'Actions',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      children: [
                        ListTile(
                          leading: Icon(Icons.report_problem),
                          title: Text('Report a problem'),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => ReportProblemPage()));
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.logout),
                          title: Text('Log out'),
                          onTap: () {
                            // Add logout logic here
                          },
                        ),
                      ],
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