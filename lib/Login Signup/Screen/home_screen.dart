import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp/Add%20Job%20Module/AddJobPage.dart';
import 'package:fyp/Notification%20Module/NotificationScreen.dart';
import 'package:fyp/module/ActivityLog.dart';
import 'package:fyp/module/Profile.dart';
import 'package:fyp/module/Report.dart';
import 'package:fyp/module/Settings.dart';
import 'package:fyp/module/SkillTags.dart';
import '../../Login With Google/google_auth.dart';
import 'login.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  static const List<Widget> _screens = [
    ActivityLogScreen(),
    ProfileScreen(),
    SkillTagScreen(),
    ReportScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: const Offset(0, 0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    print('AnimationController initialized');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      print('Selected index: $index');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const Center(child: Text('Please log in'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My App'),
        backgroundColor: Colors.teal,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              print('Menu icon tapped');
              _controller.forward(); // Start animation
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const NotificationScreen()),
              );
            },
          )
        ],
      ),
      drawer: SizedBox(
        width: MediaQuery.of(context).size.width * 0.75,
        child: SlideTransition(
          position: _offsetAnimation,
          child: AnimatedDrawer(
            controller: _controller,
            onSignOut: () async {
              try {
                await FirebaseServices().googleSignOut();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              } catch (e) {
                print('Sign out error: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sign out failed: $e')),
                );
              }
            },
            onItemTapped: (index) {
              _onItemTapped(index); // Update selected index
              Navigator.pop(context); // Close the drawer
              _controller.reverse(); // Reset animation
            },
          ),
        ),
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            activeIcon: AnimatedNavIcon(icon: Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            activeIcon: AnimatedNavIcon(icon: Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_offer),
            activeIcon: AnimatedNavIcon(icon: Icons.local_offer),
            label: 'Activity',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assessment),
            activeIcon: AnimatedNavIcon(icon: Icons.assessment),
            label: 'Report',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            activeIcon: AnimatedNavIcon(icon: Icons.settings),
            label: 'Settings',
          )
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
        elevation: 10,
        backgroundColor: Colors.white,
      ),
    );
  }
}

class AnimatedNavIcon extends StatelessWidget {
  final IconData icon;

  const AnimatedNavIcon({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.teal, size: 28),
    );
  }
}

class AnimatedDrawer extends StatelessWidget {
  final AnimationController controller;
  final VoidCallback onSignOut;
  final Function(int) onItemTapped;

  const AnimatedDrawer({
    super.key,
    required this.controller,
    required this.onSignOut,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withOpacity(0.95),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseAuth.instance.currentUser != null
                ? FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .collection('profiledetails')
                .doc('profile')
                .snapshots()
                : const Stream.empty(),
            builder: (context, snapshot) {
              print('Snapshot data: ${snapshot.data?.data()}'); // Debug print
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const DrawerHeader(
                  decoration: BoxDecoration(color: Colors.teal),
                  child: Center(child: CircularProgressIndicator(color: Colors.white)),
                );
              }
              if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                print('Error or no data: ${snapshot.error}');
                final user = FirebaseAuth.instance.currentUser;
                return DrawerHeader(
                  decoration: const BoxDecoration(color: Colors.teal),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: NetworkImage(
                          user?.photoURL ?? 'https://via.placeholder.com/150',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        user?.displayName ?? 'User',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
              print('Fetched data: $data'); // Debug print
              final user = FirebaseAuth.instance.currentUser;
              final photoURL = data['photoURL'] ?? user?.photoURL ?? 'https://via.placeholder.com/150';
              return DrawerHeader(
                decoration: const BoxDecoration(color: Colors.teal),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: photoURL.startsWith('assets/')
                          ? AssetImage(photoURL) as ImageProvider
                          : NetworkImage(photoURL),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      data['name'] ?? user?.displayName ?? 'User',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      data['email'] ?? user?.email ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          ListTile(
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: Colors.teal[200],
              child: const Icon(Icons.home, size: 18, color: Colors.teal),
            ),
            title: const Text('Home'),
            onTap: () {
              onItemTapped(0); // Maps to ActivityLogScreen
            },
          ),
          ListTile(
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: Colors.red[200],
              child: const Icon(Icons.person, size: 18, color: Colors.red),
            ),
            title: const Text('Profile'),
            onTap: () {
              onItemTapped(1); // Maps to ProfileScreen
            },
          ),
          ListTile(
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: Colors.pink[200],
              child: const Icon(Icons.local_offer, size: 18, color: Colors.pink),
            ),
            title: const Text('Skill Tags'),
            onTap: () {
              onItemTapped(2); // Maps to SkillTagScreen
            },
          ),
          ListTile(
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: Colors.purple[200],
              child: const Icon(Icons.assessment, size: 18, color: Colors.purple),
            ),
            title: const Text('Report'),
            onTap: () {
              onItemTapped(3); // Maps to ReportScreen
            },
          ),
          ListTile(
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: Colors.orange[200],
              child: const Icon(Icons.settings, size: 18, color: Colors.orange),
            ),
            title: const Text('Settings'),
            onTap: () {
              onItemTapped(4); // Maps to SettingsScreen
            },
          ),
          ListTile(
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: Colors.red,
              child: const Icon(Icons.logout, size: 18, color: Colors.white),
            ),
            title: const Text('Logout'),
            onTap: () {
              onSignOut();
            },
          ),
        ],
      ),
    );
  }
}