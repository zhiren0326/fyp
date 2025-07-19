import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> skills = []; // Store skill, certificate base64, and icon name
  late AnimationController _animationController;
  late Animation<double> _textFieldScaleAnimation;
  late Animation<double> _textFieldFadeAnimation;
  late Animation<double> _fabScaleAnimation;
  late Animation<double> _previewScaleAnimation;
  late Animation<double> _titleFadeAnimation;
  late Animation<double> _titleScaleAnimation;
  bool _isLoading = false;
  bool _isVerifying = false;
  String? _errorMessage;
  File? _selectedImage;
  String? _previewImagePath;

  // Replace with your Gemini API key (use environment variable in production)
  static const String _geminiApiKey = 'AIzaSyCFdlu9A8pY0FaZEMVaZ7eL-D9XcveMufo';

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

    // Preview image scale animation
    _previewScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    // Title fade animation
    _titleFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    // Title scale animation
    _titleScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
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
        final data = snapshot.data();
        setState(() {
          skills = List<Map<String, dynamic>>.from((data?['skills'] as List?)?.map((item) => {
            'skill': item['skill'] ?? 'Unknown Skill',
            'certificateBase64': item['certificateBase64'] ?? '',
            'iconName': item['iconName'] ?? 'star',
            'timestamp': item['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
            'verified': item['verified'] ?? false,
          }) ?? []);
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

  Future<String> _selectIconForSkill(String skill) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _geminiApiKey,
      );

      final prompt = TextPart(
        'Given the skill "$skill", suggest the most suitable Flutter icon name from the Material Icons class (e.g., "code", "build", "star", "brush", "computer", "school", "work", "settings", "palette", "data_usage"). Return only the icon name as a single word or underscore-separated string (e.g., "code"). If no suitable icon is found, return "star".',
      );

      final response = await model.generateContent([
        Content.text(prompt.text)
      ]);

      final iconName = response.text?.trim() ?? 'star';
      // Validate icon name against iconMap
      const iconMap = {
        'code': Icons.code,
        'build': Icons.build,
        'star': Icons.star,
        'brush': Icons.brush,
        'computer': Icons.computer,
        'school': Icons.school,
        'work': Icons.work,
        'settings': Icons.settings,
        'palette': Icons.palette,
        'data_usage': Icons.data_usage,
      };
      if (iconName.isEmpty || !iconMap.containsKey(iconName)) {
        return 'star'; // Fallback icon
      }
      return iconName;
    } catch (e) {
      print('Icon Selection Error: $e');
      setState(() {
        _errorMessage = 'Error selecting icon: $e';
      });
      return 'star'; // Fallback icon
    }
  }

  Future<void> _addSkill(String skill, File? certificateImage, {bool requiresVerification = true}) async {
    if (skill.isEmpty || skills.any((s) => s['skill'] == skill)) {
      setState(() {
        _errorMessage = skill.isEmpty ? 'Please enter a skill' : 'Skill already exists';
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

    if (requiresVerification && certificateImage == null) {
      setState(() {
        _errorMessage = 'Please upload or scan a certificate';
        _isLoading = false;
      });
      return;
    }

    // Verify certificate with Gemini if required
    if (requiresVerification && certificateImage != null) {
      final verificationResult = await _verifyCertificateWithGemini(skill, certificateImage);
      print('Verification Result: $verificationResult'); // Debug log
      if (verificationResult['isValid'] as bool) {
        final iconName = await _selectIconForSkill(skill);
        await _addSkillConfirmed(skill, certificateImage, iconName, verified: true);
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
                  const Text('Would you like to retry or add without verification?'),
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
                onPressed: () => Navigator.pop(context, 'add_without_verification'),
                child: const Text('Add Without Verification', style: TextStyle(color: Colors.teal)),
              ),
            ],
          ),
        );
        if (action == 'retry') {
          await _addSkill(skill, certificateImage, requiresVerification: true); // Retry the verification
        } else if (action == 'prove') {
          final iconName = await _selectIconForSkill(skill);
          await _addSkillConfirmed(skill, certificateImage, iconName, verified: true);
        } else if (action == 'add_without_verification') {
          final iconName = await _selectIconForSkill(skill);
          await _addSkillConfirmed(skill, null, iconName, verified: false);
        }
      }
    } else {
      // Add skill without verification
      final iconName = await _selectIconForSkill(skill);
      await _addSkillConfirmed(skill, null, iconName, verified: false);
    }
  }

  Future<void> _addSkillConfirmed(String skill, File? certificateImage, String iconName, {required bool verified}) async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      String? certificateBase64;
      if (certificateImage != null) {
        final bytes = await certificateImage.readAsBytes();
        certificateBase64 = base64Encode(bytes);
      }

      // Store skill, certificate (if any), and icon name in Firestore
      setState(() {
        skills.add({
          'skill': skill,
          'certificateBase64': certificateBase64 ?? '',
          'iconName': iconName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'verified': verified,
        });
        _animationController.reset();
        _animationController.forward(); // Restart animation for new item
      });
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('skills')
          .doc('user_skills')
          .set({
        'skills': skills
            .map((s) => {
          'skill': s['skill'] ?? 'Unknown Skill',
          'certificateBase64': s['certificateBase64'] ?? '',
          'iconName': s['iconName'] ?? 'star',
          'timestamp': s['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
          'verified': s['verified'] ?? false,
        })
            .toList(),
      }, SetOptions(merge: true));

      setState(() {
        _skillController.clear();
        _selectedImage = null;
        _previewImagePath = null;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(verified ? 'Skill added successfully' : 'Skill added without verification')),
      );
    } catch (e) {
      setState(() {
        skills.removeWhere((s) => s['skill'] == skill); // Revert on error
        _errorMessage = 'Error adding skill: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSkill(int index) async {
    final skill = skills[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Skill'),
        content: Text('Are you sure you want to delete the skill "${skill['skill']}"? This will also remove the associated certificate and icon.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.teal)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

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
        'skills': skills
            .map((s) => {
          'skill': s['skill'] ?? 'Unknown Skill',
          'certificateBase64': s['certificateBase64'] ?? '',
          'iconName': s['iconName'] ?? 'star',
          'timestamp': s['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
          'verified': s['verified'] ?? false,
        })
            .toList(),
      }, SetOptions(merge: true));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill deleted successfully')),
      );
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
          _animationController.reset();
          _animationController.forward(); // Restart animation for preview
        });
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Certificate'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_previewImagePath != null)
                    ScaleTransition(
                      scale: _previewScaleAnimation,
                      child: Image.file(
                        File(_previewImagePath!),
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                    )
                  else
                    const Text('No preview available'),
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
          await _addSkill(skill, _selectedImage, requiresVerification: true);
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

  void _viewCertificate(String base64Image) {
    if (base64Image.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No certificate available for this skill')),
      );
      return;
    }
    final bytes = base64Decode(base64Image);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Certificate'),
        content: SingleChildScrollView(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );
  }

  IconData _getIconData(String iconName) {
    // Map string icon names to IconData
    const iconMap = {
      'code': Icons.code,
      'build': Icons.build,
      'star': Icons.star,
      'brush': Icons.brush,
      'computer': Icons.computer,
      'school': Icons.school,
      'work': Icons.work,
      'settings': Icons.settings,
      'palette': Icons.palette,
      'data_usage': Icons.data_usage,
    };
    return iconMap[iconName] ?? Icons.star; // Fallback to star icon
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Skills'),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
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
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _errorMessage ?? 'Unknown error',
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
                    ScaleTransition(
                      scale: _previewScaleAnimation,
                      child: _previewImagePath != null
                          ? Image.file(
                        File(_previewImagePath!),
                        height: 150,
                        fit: BoxFit.contain,
                      )
                          : const Text('No preview available'),
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
                              title: const Text('Add Skill'),
                              content: const Text('Choose how to add the skill:'),
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
                                  child: const Text('Upload Certificate', style: TextStyle(color: Colors.teal)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _pickImage(ImageSource.camera);
                                  },
                                  child: const Text('Scan Certificate', style: TextStyle(color: Colors.teal)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    final skill = _skillController.text.trim();
                                    _addSkill(skill, null, requiresVerification: false);
                                  },
                                  child: const Text('Add Without Certificate', style: TextStyle(color: Colors.teal)),
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
                  final skillData = skills[index];
                  return FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _animationController,
                      curve: Interval(
                        (index / skills.length) * 0.5,
                        1.0,
                        curve: Curves.easeIn,
                      ),
                    ),
                    child: SlideTransition(
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
                          leading: ScaleTransition(
                            scale: CurvedAnimation(
                              parent: _animationController,
                              curve: Curves.easeOutBack,
                            ),
                            child: Stack(
                              children: [
                                Icon(
                                  _getIconData(skillData['iconName'] ?? 'star'),
                                  size: 30,
                                  color: Colors.teal,
                                ),
                                if (skillData['verified'] == true)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Icon(
                                      Icons.verified,
                                      size: 16,
                                      color: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          title: Text(
                            skillData['skill'] ?? 'Unknown Skill',
                            style: const TextStyle(fontSize: 16),
                          ),
                          subtitle: GestureDetector(
                            onTap: () => _viewCertificate(skillData['certificateBase64'] ?? ''),
                            child: Text(
                              skillData['certificateBase64']?.isNotEmpty == true
                                  ? 'View Certificate'
                                  : 'No Certificate',
                              style: TextStyle(
                                color: Colors.teal,
                                decoration: skillData['certificateBase64']?.isNotEmpty == true
                                    ? TextDecoration.underline
                                    : TextDecoration.none,
                              ),
                            ),
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
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}