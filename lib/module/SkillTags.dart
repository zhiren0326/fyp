import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class SkillTagScreen extends StatefulWidget {
  const SkillTagScreen({super.key});

  @override
  _SkillTagScreenState createState() => _SkillTagScreenState();
}

class _SkillTagScreenState extends State<SkillTagScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _skillController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  List<String> skills = [];
  late AnimationController _animationController;
  late Animation<double> _textFieldScaleAnimation;
  late Animation<double> _textFieldFadeAnimation;
  late Animation<double> _fabScaleAnimation;
  bool _isLoading = false;
  bool _isVerifying = false;
  String? _errorMessage;
  File? _selectedImage;
  String? _previewImagePath;

  // Replace with your Gemini API key (use environment variable in production)
  static const String _geminiApiKey = 'AIzaSyA_1MwSsAjtD3LcO5W5cmADXrzAwC7dWII';

  @override
  void initState() {
    super.initState();
    _loadSkills();

    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Text field scale animation
    _textFieldScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    // Text field fade animation
    _textFieldFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    // FAB scale animation
    _fabScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    // Start animations
    _animationController.forward();
  }

  @override
  void dispose() {
    _skillController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadSkills() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _errorMessage = 'No user logged in';
      });
      return;
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('skills')
          .doc('user_skills')
          .get();
      if (snapshot.exists) {
        setState(() {
          skills = List<String>.from(snapshot.data()!['skills'] ?? []);
        });
      } else {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('skills')
            .doc('user_skills')
            .set({'skills': []});
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading skills: $e';
      });
    }
  }

  Future<Map<String, dynamic>> _verifyCertificateWithGemini(String skill, File certificateImage) async {
    setState(() {
      _isVerifying = true;
    });
    try {
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _geminiApiKey,
      );

      final prompt = TextPart(
        'Analyze the certificate image and check if it contains the exact keyword "$skill" or a close variation (e.g., "$skill Developer", "$skill Certification"). Provide a response with three parts separated by newlines:\n'
            '1. A boolean (true or false) indicating if the keyword or variation is found.\n'
            '2. The full extracted text from the certificate (or "No text extracted" if none).\n'
            '3. A reason (e.g., "Keyword found" if true, or "Keyword not found" or "Unable to extract text" if false).\n'
            'Example response:\n'
            'true\n'
            'Flutter Certification 2023\n'
            'Keyword found',
      );
      final image = DataPart('image/jpeg', await certificateImage.readAsBytes());

      final response = await model.generateContent([
        Content.multi([prompt, image])
      ]);

      print('Raw Gemini Response: ${response.text}'); // Detailed debug log

      final resultText = response.text?.trim() ?? 'false\nNo text extracted\nUnable to extract text';
      final lines = resultText.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();

      bool isValid = false;
      String extractedText = '';
      String reason = 'Unable to parse response';

      if (lines.length >= 3) {
        isValid = lines[0].toLowerCase() == 'true';
        extractedText = lines[1].isEmpty ? 'No text extracted' : lines[1];
        reason = lines[2].isEmpty ? 'No reason provided' : lines[2];
      } else if (lines.length >= 1) {
        isValid = lines[0].toLowerCase() == 'true';
        reason = lines.length > 1 ? lines[1] : 'Incomplete response';
      }

      return {
        'isValid': isValid,
        'extractedText': extractedText,
        'reason': reason,
      };
    } catch (e) {
      print('Verification Error: $e'); // Log error for debugging
      return {
        'isValid': false,
        'extractedText': '',
        'reason': 'Server overloaded or error: Please try again later. Details: $e',
      };
    } finally {
      setState(() {
        _isVerifying = false;
      });
    }
  }

  Future<void> _addSkill(String skill, File? certificateImage) async {
    if (skill.isEmpty || skills.contains(skill)) {
      setState(() {
        _errorMessage = skill.isEmpty ? 'Please enter a skill' : 'Skill already exists';
      });
      return;
    }

    if (certificateImage == null) {
      setState(() {
        _errorMessage = 'Please upload or scan a certificate';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _errorMessage = 'No user logged in';
        _isLoading = false;
      });
      return;
    }

    // Verify certificate with Gemini
    final verificationResult = await _verifyCertificateWithGemini(skill, certificateImage);
    print('Verification Result: $verificationResult'); // Debug log
    if (verificationResult['isValid'] as bool) {
      await _addSkillConfirmed(skill, certificateImage);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = verificationResult['reason'] as String;
      });
      // Show dialog to allow retry or manual addition
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Verification Failed'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The certificate verification failed: ${_errorMessage ?? 'Unknown error'}.'),
                const SizedBox(height: 8),
                Text('Extracted Text: ${(verificationResult['extractedText'] as String).isEmpty ? 'No text extracted' : verificationResult['extractedText'] as String}'),
                const SizedBox(height: 8),
                const Text('Would you like to retry or prove the certificate?'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel', style: TextStyle(color: Colors.teal)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'retry'),
              child: const Text('Retry', style: TextStyle(color: Colors.teal)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'prove'),
              child: const Text('Prove Certificate', style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );
      if (action == 'retry') {
        await _addSkill(skill, certificateImage); // Retry the verification
      } else if (action == 'prove') {
        await _addSkillConfirmed(skill, certificateImage); // Allow manual addition
      }
    }
  }

  Future<void> _addSkillConfirmed(String skill, File certificateImage) async {
    try {
      // Upload certificate to Firebase Storage
      final user = FirebaseAuth.instance.currentUser!;
      final storageRef = _storage
          .ref()
          .child('users')
          .child(user.uid)
          .child('certificates')
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
      await storageRef.putFile(certificateImage);
      final certificateUrl = await storageRef.getDownloadURL();

      // Add skill to Firestore
      setState(() {
        skills.add(skill);
      });
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('skills')
          .doc('user_skills')
          .set({
        'skills': skills,
        'certificates': FieldValue.arrayUnion([
          {'skill': skill, 'certificateUrl': certificateUrl, 'timestamp': FieldValue.serverTimestamp()}
        ]),
      }, SetOptions(merge: true));

      setState(() {
        _skillController.clear();
        _selectedImage = null;
        _previewImagePath = null;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill added successfully')),
      );
    } catch (e) {
      setState(() {
        if (skills.contains(skill)) skills.remove(skill); // Revert on error
        _errorMessage = 'Error adding skill: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSkill(int index) async {
    final skill = skills[index];
    setState(() {
      skills.removeAt(index);
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        skills.insert(index, skill);
        _errorMessage = 'No user logged in';
      });
      return;
    }

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('skills')
          .doc('user_skills')
          .set({
        'skills': skills,
      }, SetOptions(merge: true));
    } catch (e) {
      setState(() {
        skills.insert(index, skill);
        _errorMessage = 'Error deleting skill: $e';
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          _previewImagePath = pickedFile.path;
          _selectedImage = File(pickedFile.path);
        });
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Certificate'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.file(
                    File(_previewImagePath!),
                    height: 200,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  const Text('Is this the correct certificate image?'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.teal)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm', style: TextStyle(color: Colors.teal)),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          final skill = _skillController.text.trim();
          await _addSkill(skill, _selectedImage);
        } else {
          setState(() {
            _previewImagePath = null;
            _selectedImage = null;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking image: $e';
        _previewImagePath = null;
        _selectedImage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.teal.shade50, Colors.white],
          ),
        ),
        child: Column(
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            if (_isLoading || _isVerifying)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            if (_previewImagePath != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      'Selected Certificate Preview:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Image.file(
                      File(_previewImagePath!),
                      height: 150,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: FadeTransition(
                opacity: _textFieldFadeAnimation,
                child: ScaleTransition(
                  scale: _textFieldScaleAnimation,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _skillController,
                            decoration: InputDecoration(
                              labelText: 'Add a skill tag',
                              hintText: 'e.g., Flutter, Python',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.teal),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Upload Certificate'),
                              content: const Text('Choose a certificate image to verify the skill.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel', style: TextStyle(color: Colors.teal)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _pickImage(ImageSource.gallery);
                                  },
                                  child: const Text('Upload', style: TextStyle(color: Colors.teal)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _pickImage(ImageSource.camera);
                                  },
                                  child: const Text('Scan', style: TextStyle(color: Colors.teal)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: skills.length,
                itemBuilder: (context, index) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _animationController,
                        curve: Interval(
                          (index / skills.length) * 0.5,
                          1.0,
                          curve: Curves.easeOut,
                        ),
                      ),
                    ),
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        title: Text(
                          skills[index],
                          style: const TextStyle(fontSize: 16),
                        ),
                        trailing: GestureDetector(
                          onTap: () => _deleteSkill(index),
                          child: AnimatedScale(
                            scale: 1.0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnimation,
        child: FloatingActionButton(
          onPressed: () => showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Upload Certificate'),
              content: const Text('Choose a certificate image to verify the skill.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.teal)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                  child: const Text('Upload', style: TextStyle(color: Colors.teal)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                  child: const Text('Scan', style: TextStyle(color: Colors.teal)),
                ),
              ],
            ),
          ),
          backgroundColor: Colors.teal,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}