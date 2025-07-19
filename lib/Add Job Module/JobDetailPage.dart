import 'package:flutter/material.dart';

class JobDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;

  const JobDetailPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final taskType = data['isShortTerm'] == true ? 'Short-term' : 'Long-term';

    return Scaffold(
      appBar: AppBar(title: const Text('Job Details')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text('Job Position: ${data['jobPosition'] ?? '-'}'),
            Text('Description: ${data['description'] ?? '-'}'),
            Text('Location: ${data['location'] ?? '-'}'),
            Text('Salary: RM ${data['salary'] ?? '-'}'),
            Text('Required Skill: ${data['requiredSkill'] ?? '-'}'),
            Text('Task Type: $taskType'),
            Text('Start Date: ${data['startDate'] ?? '-'}'),
            if (data['isShortTerm'] == true && data['startTime'] != null)
              Text('Start Time: ${data['startTime']}'),
          ].map((text) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: text,
          )).toList(),
        ),
      ),
    );
  }
}
