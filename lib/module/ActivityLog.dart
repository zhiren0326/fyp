import 'package:flutter/material.dart';
import 'package:fyp/Add%20Job%20Module/AddJobPage.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  @override
  void initState() {
    super.initState();

    // Show snackbar after frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tap the + button to create a new task'),
          duration: Duration(seconds: 3),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(
        child: Text(
          "Activity Logs Screen",
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: Tooltip(
        message: 'Tap to create a new task',
        waitDuration: Duration(milliseconds: 500),
        showDuration: Duration(seconds: 2),
        child: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const AddJobPage()),
            );
          },
          backgroundColor: Colors.teal,
          child: const Icon(Icons.add, size: 30),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }
}
