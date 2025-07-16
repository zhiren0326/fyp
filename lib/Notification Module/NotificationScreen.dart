import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        backgroundColor: Colors.teal,
      ),
      body: const Center(
        child: Text("No new notifications", style: TextStyle(fontSize: 16)),
      ),
    );
  }
}
