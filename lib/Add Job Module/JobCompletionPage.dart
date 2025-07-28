import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

class JobCompletionPage extends StatefulWidget {
  final String jobId;
  final Map<String, dynamic> jobData;

  const JobCompletionPage({
    super.key,
    required this.jobId,
    required this.jobData,
  });

  @override
  State<JobCompletionPage> createState() => _JobCompletionPageState();
}

class _JobCompletionPageState extends State<JobCompletionPage>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  // Form controllers
  final TextEditingController _completionNotesController = TextEditingController();
  final TextEditingController _additionalInfoController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  // File management
  List<File> _selectedImages = [];
  List<File> _selectedFiles = [];
  List<String> _uploadedImageUrls = [];
  List<String> _uploadedFileUrls = [];

  // State management
  bool _isSubmitting = false;
  bool _hasSubmitted = false;
  String? _submissionStatus;
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _employerProfile;

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkSubmissionStatus();
    _loadEmployerProfile();
    _loadMessages();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _completionNotesController.dispose();
    _additionalInfoController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _checkSubmissionStatus() async {
    try {
      final submissionDoc = await FirebaseFirestore.instance
          .collection('jobSubmissions')
          .doc(widget.jobId)
          .get();

      if (submissionDoc.exists) {
        final data = submissionDoc.data()!;
        setState(() {
          _hasSubmitted = true;
          _submissionStatus = data['status'];
          _completionNotesController.text = data['completionNotes'] ?? '';
          _additionalInfoController.text = data['additionalInfo'] ?? '';
          _uploadedImageUrls = List<String>.from(data['imageUrls'] ?? []);
          _uploadedFileUrls = List<String>.from(data['fileUrls'] ?? []);
        });
      }
    } catch (e) {
      print('Error checking submission status: $e');
    }
  }

  Future<void> _loadEmployerProfile() async {
    try {
      final employerId = widget.jobData['postedBy'];
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(employerId)
          .collection('profiledetails')
          .doc('profile')
          .get();

      if (profileDoc.exists) {
        setState(() {
          _employerProfile = profileDoc.data();
        });
      }
    } catch (e) {
      print('Error loading employer profile: $e');
    }
  }

  Future<void> _loadMessages() async {
    try {
      final messagesSnapshot = await FirebaseFirestore.instance
          .collection('jobSubmissions')
          .doc(widget.jobId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .get();

      setState(() {
        _messages = messagesSnapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      });
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser!;

      await FirebaseFirestore.instance
          .collection('jobSubmissions')
          .doc(widget.jobId)
          .collection('messages')
          .add({
        'senderId': currentUser.uid,
        'senderName': 'Employee', // You can get this from user profile
        'message': _messageController.text.trim(),
        'timestamp': Timestamp.now(),
        'type': 'text',
      });

      _messageController.clear();
      _loadMessages(); // Refresh messages

      // Send notification to employer
      await _sendMessageNotification();

    } catch (e) {
      _showSnackBar('Error sending message: $e');
    }
  }

  Future<void> _sendMessageNotification() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.jobData['postedBy'])
          .collection('notifications')
          .add({
        'type': 'job_message',
        'title': 'New Message on Job',
        'message': 'Employee sent a message about "${widget.jobData['jobPosition']}"',
        'jobId': widget.jobId,
        'fromUserId': FirebaseAuth.instance.currentUser!.uid,
        'timestamp': Timestamp.now(),
        'read': false,
      });
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage();
      setState(() {
        _selectedImages = images.map((image) => File(image.path)).toList();
      });
    } catch (e) {
      _showSnackBar('Error picking images: $e');
    }
  }

  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'xlsx', 'pptx'],
      );

      if (result != null) {
        setState(() {
          _selectedFiles = result.paths.map((path) => File(path!)).toList();
        });
      }
    } catch (e) {
      _showSnackBar('Error picking files: $e');
    }
  }

  Future<List<String>> _uploadImages() async {
    List<String> urls = [];

    for (int i = 0; i < _selectedImages.length; i++) {
      try {
        final fileName = 'job_completion/${widget.jobId}/images/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final ref = FirebaseStorage.instance.ref().child(fileName);
        await ref.putFile(_selectedImages[i]);
        final url = await ref.getDownloadURL();
        urls.add(url);
      } catch (e) {
        print('Error uploading image $i: $e');
      }
    }

    return urls;
  }

  Future<List<String>> _uploadFiles() async {
    List<String> urls = [];

    for (int i = 0; i < _selectedFiles.length; i++) {
      try {
        final fileName = 'job_completion/${widget.jobId}/files/${DateTime.now().millisecondsSinceEpoch}_${_selectedFiles[i].path.split('/').last}';
        final ref = FirebaseStorage.instance.ref().child(fileName);
        await ref.putFile(_selectedFiles[i]);
        final url = await ref.getDownloadURL();
        urls.add(url);
      } catch (e) {
        print('Error uploading file $i: $e');
      }
    }

    return urls;
  }

  Future<void> _submitCompletion() async {
    if (_completionNotesController.text.trim().isEmpty) {
      _showSnackBar('Please provide completion notes');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser!;

      // Upload images and files
      final imageUrls = await _uploadImages();
      final fileUrls = await _uploadFiles();

      // Create submission document
      await FirebaseFirestore.instance
          .collection('jobSubmissions')
          .doc(widget.jobId)
          .set({
        'jobId': widget.jobId,
        'jobTitle': widget.jobData['jobPosition'],
        'employerId': widget.jobData['postedBy'],
        'employeeId': currentUser.uid,
        'completionNotes': _completionNotesController.text.trim(),
        'additionalInfo': _additionalInfoController.text.trim(),
        'imageUrls': [..._uploadedImageUrls, ...imageUrls],
        'fileUrls': [..._uploadedFileUrls, ...fileUrls],
        'status': 'pending_review',
        'submittedAt': Timestamp.now(),
        'lastUpdated': Timestamp.now(),
        'jobData': widget.jobData,
      });

      // Update job status
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .update({
        'completionSubmitted': true,
        'submissionStatus': 'pending_review',
        'lastUpdated': Timestamp.now(),
      });

      // Send notification to employer
      await _sendCompletionNotification();

      // Log activity
      await _logActivity('Job Completion Submitted');

      setState(() {
        _hasSubmitted = true;
        _submissionStatus = 'pending_review';
        // Clear selected files after successful upload
        _selectedImages.clear();
        _selectedFiles.clear();
      });

      _showSnackBar('Job completion submitted successfully!');

    } catch (e) {
      _showSnackBar('Error submitting completion: $e');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _sendCompletionNotification() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.jobData['postedBy'])
          .collection('notifications')
          .add({
        'type': 'job_completion_submitted',
        'title': 'Job Completion Submitted',
        'message': 'An employee has submitted completion for "${widget.jobData['jobPosition']}"',
        'jobId': widget.jobId,
        'fromUserId': FirebaseAuth.instance.currentUser!.uid,
        'timestamp': Timestamp.now(),
        'read': false,
      });
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  Future<void> _logActivity(String action) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('activityLog')
          .add({
        'action': action,
        'taskId': widget.jobId,
        'taskTitle': widget.jobData['jobPosition'],
        'timestamp': Timestamp.now(),
        'details': {
          'submissionStatus': _submissionStatus,
        }
      });
    } catch (e) {
      print('Error logging activity: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF006D77),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending_review':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending_review':
        return 'Pending Review';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Unknown';
    }
  }

  Widget _buildStatusCard() {
    if (!_hasSubmitted) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getStatusColor(_submissionStatus!).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getStatusColor(_submissionStatus!)),
      ),
      child: Row(
        children: [
          Icon(
            _submissionStatus == 'approved' ? Icons.check_circle :
            _submissionStatus == 'rejected' ? Icons.cancel :
            Icons.access_time,
            color: _getStatusColor(_submissionStatus!),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Submission Status',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _getStatusText(_submissionStatus!),
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(_submissionStatus!),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobInfoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_hasSubmitted) _buildStatusCard(),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Job Details',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF006D77),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.jobData['jobPosition'] ?? 'Job Title',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.jobData['description'] ?? 'No description',
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    widget.jobData['location'] ?? 'Location not specified',
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.attach_money, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'RM ${widget.jobData['salary'] ?? 0}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (_employerProfile != null) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Employer',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF006D77),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: _employerProfile!['photoURL'] != null
                          ? NetworkImage(_employerProfile!['photoURL'])
                          : null,
                      child: _employerProfile!['photoURL'] == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _employerProfile!['name'] ?? 'Employer',
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompletionTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Job Completion Details',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF006D77),
                ),
              ),
              const SizedBox(height: 16),

              // Completion Notes
              Text(
                'Completion Notes *',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _completionNotesController,
                maxLines: 4,
                enabled: !_hasSubmitted,
                decoration: InputDecoration(
                  hintText: 'Describe what you have completed and any important details...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 16),

              // Additional Information
              Text(
                'Additional Information',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _additionalInfoController,
                maxLines: 3,
                enabled: !_hasSubmitted,
                decoration: InputDecoration(
                  hintText: 'Any additional information or challenges faced...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Attachments Section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Attachments',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF006D77),
                ),
              ),
              const SizedBox(height: 12),

              // Upload buttons
              if (!_hasSubmitted) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _pickImages,
                        icon: const Icon(Icons.image),
                        label: const Text('Add Images'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF006D77),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _pickFiles,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Add Files'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF006D77),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Selected images preview
              if (_selectedImages.isNotEmpty || _uploadedImageUrls.isNotEmpty) ...[
                Text(
                  'Images (${_selectedImages.length + _uploadedImageUrls.length})',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length + _uploadedImageUrls.length,
                    itemBuilder: (context, index) {
                      if (index < _selectedImages.length) {
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              children: [
                                Image.file(
                                  _selectedImages[index],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                                if (!_hasSubmitted)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedImages.removeAt(index);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      } else {
                        final urlIndex = index - _selectedImages.length;
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _uploadedImageUrls[urlIndex],
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(child: CircularProgressIndicator());
                              },
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Selected files list
              if (_selectedFiles.isNotEmpty || _uploadedFileUrls.isNotEmpty) ...[
                Text(
                  'Files (${_selectedFiles.length + _uploadedFileUrls.length})',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                ..._selectedFiles.map((file) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file, size: 20, color: Color(0xFF006D77)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          file.path.split('/').last,
                          style: GoogleFonts.poppins(fontSize: 14),
                        ),
                      ),
                      if (!_hasSubmitted)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedFiles.remove(file);
                            });
                          },
                          child: const Icon(Icons.close, size: 16, color: Colors.red),
                        ),
                    ],
                  ),
                )).toList(),
                ..._uploadedFileUrls.asMap().entries.map((entry) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file, size: 20, color: Color(0xFF006D77)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Uploaded File ${entry.key + 1}',
                          style: GoogleFonts.poppins(fontSize: 14),
                        ),
                      ),
                      const Icon(Icons.cloud_done, size: 16, color: Colors.green),
                    ],
                  ),
                )).toList(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Submit button
        if (!_hasSubmitted)
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitCompletion,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006D77),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _isSubmitting
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(
              'Submit Completion',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessagesTab() {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.message,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No messages yet',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start a conversation with the employer',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              final isFromEmployee = message['senderId'] == FirebaseAuth.instance.currentUser!.uid;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: isFromEmployee
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  children: [
                    if (!isFromEmployee) ...[
                      CircleAvatar(
                        radius: 16,
                        backgroundImage: _employerProfile?['photoURL'] != null
                            ? NetworkImage(_employerProfile!['photoURL'])
                            : null,
                        child: _employerProfile?['photoURL'] == null
                            ? const Icon(Icons.person, size: 16)
                            : null,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isFromEmployee
                              ? const Color(0xFF006D77)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message['message'],
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: isFromEmployee ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatTimestamp(message['timestamp'] as Timestamp),
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: isFromEmployee
                                    ? Colors.white.withOpacity(0.7)
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isFromEmployee) ...[
                      const SizedBox(width: 8),
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF006D77),
                        child: const Icon(Icons.person, size: 16, color: Colors.white),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),

        // Message input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  maxLines: null,
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: const Color(0xFF006D77),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final dateTime = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB2DFDB), Colors.white],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            'Job Completion',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF006D77),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(icon: Icon(Icons.info), text: 'Job Info'),
              Tab(icon: Icon(Icons.assignment_turned_in), text: 'Completion'),
              Tab(icon: Icon(Icons.message), text: 'Messages'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildJobInfoTab(),
            _buildCompletionTab(),
            _buildMessagesTab(),
          ],
        ),
      ),
    );
  }
}