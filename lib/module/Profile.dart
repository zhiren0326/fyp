import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:fyp/module/SkillTags.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final _icController = TextEditingController();
  final _addressController = TextEditingController();
  DateTime? _selectedDate;
  bool _isEditing = false;
  bool _isLoading = false;
  bool _showResetPassword = false;
  String? _errorMessage;
  String? _photoURL;
  bool _hasSetProfilePicture = false;
  List<Map<String, dynamic>> _skills = []; // Store fetched skills

  // Animation controller and animations
  late AnimationController _animationController;
  late Animation<double> _profilePictureScaleAnimation;
  late Animation<double> _textFieldFadeAnimation;
  late Animation<double> _buttonSlideAnimation;

  // Predefined profile picture asset paths
  static const String _boyProfileAsset = 'assets/boy.jpg';
  static const String _girlProfileAsset = 'assets/girl.jpg';

  @override
  void initState() {
    super.initState();
    _fetchUserData();

    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Profile picture scale animation
    _profilePictureScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    // Text field fade animation
    _textFieldFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    // Button slide animation
    _buttonSlideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    // Start animations
    _animationController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _icController.dispose();
    _addressController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _nameController.text = user.displayName ?? '';
      _emailController.text = user.email ?? '';
    });

    try {
      final fsDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('profiledetails')
          .doc('profile')
          .get();

      final skillsDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('skills')
          .doc('user_skills')
          .get();

      if (fsDoc.exists) {
        final data = fsDoc.data()!;
        setState(() {
          _photoURL = data['photoURL'];
          _phoneController.text = data['phone'] ?? '';
          _bioController.text = data['bio'] ?? '';
          _icController.text = data['icNumber'] ?? '';
          _addressController.text = data['address'] ?? '';
          _selectedDate = data['dateOfBirth'] != null
              ? (data['dateOfBirth'] as Timestamp).toDate()
              : null;
          _hasSetProfilePicture = _photoURL != null;
        });
      }

      if (skillsDoc.exists) {
        final data = skillsDoc.data()!;
        setState(() {
          _skills = List<Map<String, dynamic>>.from((data['skills'] as List?)?.map((item) => {
            'skill': item['skill'] ?? 'Unknown Skill',
            'certificateBase64': item['certificateBase64'] ?? '',
            'iconName': item['iconName'] ?? 'star',
            'timestamp': item['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
            'verified': item['verified'] ?? false,
          }) ?? []);
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching profile or skills: $e';
      });
    }
  }

  Future<void> _selectProfilePicture() async {
    if (_hasSetProfilePicture) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Profile Picture'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundImage: AssetImage(_boyProfileAsset),
              ),
              title: const Text('Boy'),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Warning'),
                    content: const Text('This is a one-time selection. Are you sure?'),
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
                  setState(() {
                    _photoURL = _boyProfileAsset;
                    _hasSetProfilePicture = true;
                  });
                }
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundImage: AssetImage(_girlProfileAsset),
              ),
              title: const Text('Girl'),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Warning'),
                    content: const Text('This is a one-time selection. Are you sure?'),
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
                  setState(() {
                    _photoURL = _girlProfileAsset;
                    _hasSetProfilePicture = true;
                  });
                }
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<String> _reverseGeocode(LatLng point) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=1',
        ),
        headers: {'User-Agent': 'MyFYPApp/1.0'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['display_name'] ?? 'Unknown address';
      } else {
        return 'Failed to fetch address';
      }
    } catch (e) {
      return 'Error fetching address: $e';
    }
  }

  Future<void> _selectAddress() async {
    try {
      final LatLng? selectedLocation = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MapPickerScreen(
            onLocationSelected: (LatLng location) async {
              final address = await _reverseGeocode(location);
              setState(() {
                _addressController.text = address;
              });
            },
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Error opening map: $e';
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

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

    try {
      await user.updateDisplayName(_nameController.text);
      await user.updateEmail(_emailController.text);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('profiledetails')
          .doc('profile')
          .set({
        'name': _nameController.text,
        'email': _emailController.text,
        'phone': _phoneController.text,
        'bio': _bioController.text,
        'icNumber': _icController.text,
        'address': _addressController.text,
        'dateOfBirth': _selectedDate != null ? Timestamp.fromDate(_selectedDate!) : null,
        'photoURL': _photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _isEditing = false;
        _isLoading = false;
        _hasSetProfilePicture = _photoURL != null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Error updating profile: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      setState(() {
        _errorMessage = 'No user logged in or email not found';
        _isLoading = false;
      });
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
      setState(() {
        _isLoading = false;
        _showResetPassword = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent')),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Error sending reset email: $e';
        _isLoading = false;
      });
    }
  }

  void _navigateToSkillTagScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SkillTagScreen()),
    );
  }

  void _viewCertificate(String? base64Image, String skillName) {
    if (base64Image == null || base64Image.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Certificate'),
          content: Text('No certificate available for the skill "$skillName".'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );
      return;
    }
    final bytes = base64Decode(base64Image);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Certificate for $skillName'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Profile'),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.close : Icons.edit, color: Colors.white),
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
                _errorMessage = null;
                _showResetPassword = false;
                _animationController.reset();
                _animationController.forward();
              });
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB2DFDB), Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      Center(
                        child: ScaleTransition(
                          scale: _profilePictureScaleAnimation,
                          child: GestureDetector(
                            onTap: _isEditing && !_hasSetProfilePicture ? _selectProfilePicture : null,
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                CircleAvatar(
                                  radius: 50,
                                  backgroundImage: _photoURL != null
                                      ? AssetImage(_photoURL!)
                                      : const NetworkImage('https://via.placeholder.com/150')
                                  as ImageProvider,
                                ),
                                if (_isEditing && !_hasSetProfilePicture)
                                  CircleAvatar(
                                    radius: 15,
                                    backgroundColor: Colors.teal,
                                    child: const Icon(
                                      Icons.camera_alt,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildAnimatedTextField(
                        controller: _nameController,
                        labelText: 'Name',
                        hintText: 'Enter your full name',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildAnimatedTextField(
                        controller: _emailController,
                        labelText: 'Email',
                        hintText: 'Enter your email address',
                        validator: (value) {
                          if (value == null || !value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildAnimatedTextField(
                        controller: _phoneController,
                        labelText: 'Phone Number',
                        hintText: 'Enter your phone number (e.g., +1234567890)',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildAnimatedTextField(
                        controller: _icController,
                        labelText: 'IC Number',
                        hintText: 'Enter your identification number',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your IC number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildAnimatedTextField(
                        controller: _addressController,
                        labelText: 'Address',
                        hintText: 'Select or enter your address',
                        maxLines: 2,
                        suffixIcon: _isEditing
                            ? IconButton(
                          icon: const Icon(Icons.map, color: Colors.teal),
                          onPressed: _selectAddress,
                        )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _buildAnimatedTextField(
                        controller: TextEditingController(
                          text: _selectedDate != null
                              ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                              : '',
                        ),
                        labelText: 'Date of Birth',
                        hintText: 'Select your date of birth',
                        readOnly: true,
                        onTap: _isEditing ? () => _selectDate(context) : null,
                        validator: (value) {
                          if (_selectedDate == null) {
                            return 'Please select your date of birth';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildAnimatedTextField(
                        controller: _bioController,
                        labelText: 'Bio',
                        hintText: 'Tell us about yourself',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      FadeTransition(
                        opacity: _textFieldFadeAnimation,
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
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Skills',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _skills.isEmpty
                                  ? const Text(
                                'No skills added. Go to Skills Tags to add skills.',
                                style: TextStyle(color: Colors.grey),
                              )
                                  : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _skills.map((skillData) {
                                  return GestureDetector(
                                    onTap: () => _viewCertificate(
                                      skillData['certificateBase64'],
                                      skillData['skill'],
                                    ),
                                    child: Chip(
                                      label: Text(skillData['skill']),
                                      avatar: Stack(
                                        children: [
                                          Icon(
                                            _getIconData(skillData['iconName'] ?? 'star'),
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
                                      backgroundColor: Colors.teal.shade50,
                                      labelStyle: const TextStyle(color: Colors.teal),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Manage Skills'),
                                      content: const Text(
                                          'To add or remove skills, please go to the Skills Tags section.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('Cancel',
                                              style: TextStyle(color: Colors.teal)),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _navigateToSkillTagScreen();
                                          },
                                          child: const Text('Go to Skills Tags',
                                              style: TextStyle(color: Colors.teal)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Manage Skills',
                                  style: TextStyle(
                                    color: Colors.teal,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_isEditing && !_showResetPassword)
                        AnimatedBuilder(
                          animation: _buttonSlideAnimation,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(0, _buttonSlideAnimation.value),
                              child: FadeTransition(
                                opacity: _textFieldFadeAnimation,
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _showResetPassword = true;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Reset Password',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      if (_isEditing && _showResetPassword)
                        AnimatedBuilder(
                          animation: _buttonSlideAnimation,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(0, _buttonSlideAnimation.value),
                              child: FadeTransition(
                                opacity: _textFieldFadeAnimation,
                                child: Column(
                                  children: [
                                    const Text(
                                      'A password reset email will be sent to your email address.',
                                      style: TextStyle(fontSize: 14, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: _resetPassword,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text(
                                        'Send Reset Email',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _showResetPassword = false;
                                        });
                                      },
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(color: Colors.teal),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      if (_isEditing) const SizedBox(height: 20),
                      if (_isEditing)
                        AnimatedBuilder(
                          animation: _buttonSlideAnimation,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(0, _buttonSlideAnimation.value),
                              child: FadeTransition(
                                opacity: _textFieldFadeAnimation,
                                child: ElevatedButton(
                                  onPressed: _saveProfile,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Save Profile',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    int maxLines = 1,
    bool readOnly = false,
    void Function()? onTap,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return FadeTransition(
      opacity: _textFieldFadeAnimation,
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
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: labelText,
            hintText: hintText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            suffixIcon: suffixIcon,
          ),
          enabled: _isEditing,
          maxLines: maxLines,
          readOnly: readOnly,
          onTap: onTap,
          validator: validator,
        ),
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
    return iconMap[iconName] ?? Icons.star; // Fallback to star
  }
}

class MapPickerScreen extends StatefulWidget {
  final Function(LatLng) onLocationSelected;

  const MapPickerScreen({super.key, required this.onLocationSelected});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  LatLng? _selectedLocation;
  LatLng _initialPosition = const LatLng(0, 0);
  double _initialZoom = 2;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  // Animation controller and animations
  late AnimationController _animationController;
  late Animation<double> _searchBarFadeAnimation;
  late Animation<double> _searchBarScaleAnimation;

  @override
  void initState() {
    super.initState();
    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Search bar fade animation
    _searchBarFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    // Search bar scale animation
    _searchBarScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    // Start animations
    _animationController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _searchLocation(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return [];
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(query)}&addressdetails=1&limit=5',
        ),
        headers: {'User-Agent': 'MyFYPApp/1.0'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        final results = data.map((item) => {
          'display_name': item['display_name'] as String,
          'lat': double.parse(item['lat'] as String),
          'lon': double.parse(item['lon'] as String),
        }).toList();

        setState(() {
          _searchResults = results;
          if (results.isNotEmpty) {
            _initialPosition = LatLng(results[0]['lat'] as double, results[0]['lon'] as double);
            _initialZoom = 15;
            _mapController.move(_initialPosition, _initialZoom);
          }
        });
        return results;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to search location')),
        );
        return [];
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching location: $e')),
      );
      return [];
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Select Location'),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (_selectedLocation != null)
            IconButton(
              icon: const Icon(Icons.check, color: Colors.white),
              onPressed: () {
                widget.onLocationSelected(_selectedLocation!);
                Navigator.pop(context);
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialPosition,
              initialZoom: _initialZoom,
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedLocation = point;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.fyp',
              ),
              MarkerLayer(
                markers: [
                  // Markers for search results
                  ..._searchResults.asMap().entries.map((entry) {
                    final index = entry.key;
                    final result = entry.value;
                    return Marker(
                      point: LatLng(result['lat'] as double, result['lon'] as double),
                      width: 80,
                      height: 80,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedLocation = LatLng(result['lat'] as double, result['lon'] as double);
                          });
                        },
                        child: Icon(
                          Icons.location_pin,
                          color: Colors.blue,
                          size: 40,
                        ),
                      ),
                    );
                  }).toList(),
                  // Marker for user-selected location
                  if (_selectedLocation != null)
                    Marker(
                      point: _selectedLocation!,
                      width: 80,
                      height: 80,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Column(
              children: [
                FadeTransition(
                  opacity: _searchBarFadeAnimation,
                  child: ScaleTransition(
                    scale: _searchBarScaleAnimation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: const InputDecoration(
                                hintText: 'Search for a location (e.g., Kuala Lumpur)',
                                border: InputBorder.none,
                              ),
                              onSubmitted: (value) => _searchLocation(value),
                            ),
                          ),
                          IconButton(
                            icon: _isSearching
                                ? const CircularProgressIndicator(strokeWidth: 2)
                                : const Icon(Icons.search, color: Colors.teal),
                            onPressed: _isSearching
                                ? null
                                : () => _searchLocation(_searchController.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black54,
                  child: Text(
                    _searchResults.isEmpty
                        ? 'Search or pinch to zoom and drag to navigate. Tap to select a location.'
                        : 'Tap a blue pin to select a searched location or tap the map to choose another.',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}