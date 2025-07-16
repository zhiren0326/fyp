import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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

  // Predefined profile picture asset paths
  static const String _boyProfileAsset = 'assets/boy.jpg';
  static const String _girlProfileAsset = 'assets/girl.jpg';

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _icController.dispose();
    _addressController.dispose();
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
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching profile: $e';
      });
    }
  }

  Future<void> _selectProfilePicture() async {
    if (_hasSetProfilePicture) return; // Prevent changing picture if already set

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
      // Update Firebase Authentication profile
      await user.updateDisplayName(_nameController.text);
      await user.updateEmail(_emailController.text);

      // Update all fields in Firestore
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.close : Icons.edit),
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
                _errorMessage = null;
                _showResetPassword = false;
              });
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
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
              GestureDetector(
                onTap: _isEditing && !_hasSetProfilePicture ? _selectProfilePicture : null,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: _photoURL != null
                          ? AssetImage(_photoURL!)
                          : NetworkImage('https://via.placeholder.com/150') as ImageProvider,
                    ),
                    if (_isEditing && !_hasSetProfilePicture)
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: Colors.teal,
                        child: Icon(
                          Icons.camera_alt,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                enabled: _isEditing,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                enabled: _isEditing,
                validator: (value) {
                  if (value == null || !value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                ),
                enabled: _isEditing,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _icController,
                decoration: const InputDecoration(
                  labelText: 'IC Number',
                  border: OutlineInputBorder(),
                ),
                enabled: _isEditing,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your IC number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
                enabled: _isEditing,
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Date of Birth',
                  border: OutlineInputBorder(),
                ),
                enabled: _isEditing,
                readOnly: true,
                controller: TextEditingController(
                  text: _selectedDate != null
                      ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                      : '',
                ),
                onTap: _isEditing ? () => _selectDate(context) : null,
                validator: (value) {
                  if (_selectedDate == null) {
                    return 'Please select your date of birth';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  border: OutlineInputBorder(),
                ),
                enabled: _isEditing,
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              if (_isEditing && !_showResetPassword)
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showResetPassword = true;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Reset Password',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              if (_isEditing && _showResetPassword)
                Column(
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
              if (_isEditing) const SizedBox(height: 20),
              if (_isEditing)
                ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Save Profile',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}