import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:padi_pay_business/profile/profile_page.dart';
import 'package:padi_pay_business/ui/permission_explanation_sheet copy.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  String? firstName;
  String? lastName;
  String? phone;
  String? email;
  DateTime? dobDate;
  String? dob;
  String? address1;
  String? state;
  String? country;
  String? postalCode;
  String? profilePhotoUrl;
  
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _dobController = TextEditingController();
  final _address1Controller = TextEditingController();
  final _stateController = TextEditingController();
  final _countryController = TextEditingController();
  final _postalCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      DocumentSnapshot snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (snap.exists) {
        var data = snap.data() as Map<String, dynamic>;
        setState(() {
          firstName = data['firstName'] ?? '';
          lastName = data['lastName'] ?? '';
          phone = data['phone'] ?? '';
          email = data['email'] ?? '';
          dob = data['dob'];
          address1 = data['address1'] ?? '';
          state = data['state'] ?? '';
          country = data['country'] ?? '';
          postalCode = data['postalCode'] ?? '';
          profilePhotoUrl = data['profilePhotoUrl'];
        });
        
        // Populate controllers with fetched data
        _firstNameController.text = firstName ?? '';
        _lastNameController.text = lastName ?? '';
        _phoneController.text = phone ?? '';
        _emailController.text = email ?? '';
        _address1Controller.text = address1 ?? '';
        _stateController.text = state ?? '';
        _countryController.text = country ?? '';
        _postalCodeController.text = postalCode ?? '';
        
        // Handle DOB
        if (dob != null && dob!.isNotEmpty) {
          try {
            dobDate = DateTime.parse(dob!);
            _dobController.text = DateFormat('dd/MM/yyyy').format(dobDate!);
          } catch (e) {
            // Invalid date format, leave empty
            dobDate = null;
            _dobController.clear();
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching data: $e')),
      );
    }
  }

  Future<void> _updateProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyConsented = prefs.getBool('privacy_consent_gallery') ?? false;
    if (!alreadyConsented) {
      bool consented = false;
      await showModalBottomSheet(
        context: context,
        isDismissible: true,
        builder: (ctx) => PermissionExplanationSheet(
          type: PermissionType.gallery,
          onContinue: () async {
            await prefs.setBool('privacy_consent_gallery', true);
            Navigator.of(ctx).pop();
            consented = true;
          },
        ),
      );
      if (!consented) return;
    }
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      File file = File(pickedFile.path);
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final storageRef = FirebaseStorage.instance.ref(
            'profile_photos/${user.uid}.jpg',
          );
          await storageRef.putFile(file);
          final url = await storageRef.getDownloadURL();
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'profilePhotoUrl': url});
          setState(() {
            profilePhotoUrl = url;
          });
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating photo: $e')),
          );
        }
      }
    }
  }

  Future<void> _selectDate() async {
    dobDate ??= DateTime.now().subtract(const Duration(days: 7300));
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: dobDate!,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != dobDate) {
      setState(() {
        dobDate = picked;
        _dobController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _saveProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      Map<String, dynamic> updates = {
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'address1': _address1Controller.text.trim(),
        'state': _stateController.text.trim(),
        'country': _countryController.text.trim(),
        'postalCode': _postalCodeController.text.trim(),
      };

      if (dobDate != null) {
        updates['dob'] = dobDate!.toIso8601String().split('T')[0];
      } else if (_dobController.text.isEmpty) {
        updates['dob'] = null; // Remove DOB if empty
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update(updates);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );

      navigateTo(
        context,
        ProfilePage(),
        type: NavigationType.clearStack,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        navigateTo(
          context,
          ProfilePage(),
          type: NavigationType.clearStack,
        );
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SizedBox.expand(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 20),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios, size: 25),
                              onPressed: () => navigateTo(
                                context,
                                ProfilePage(),
                                type: NavigationType.clearStack,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        const Row(
                          children: [
                            SizedBox(width: 16),
                            Text(
                              'Edit Profile',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 60,
                                  backgroundImage: profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty
                                      ? NetworkImage(profilePhotoUrl!)
                                      : const AssetImage("assets/profile_placeholder.png"),
                                ),
                                Positioned(
                                  bottom: 10,
                                  right: 10,
                                  child: GestureDetector(
                                    onTap: _updateProfilePhoto,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: primaryColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.add_a_photo,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                        _buildTextField("First Name", _firstNameController),
                        _buildTextField("Last Name", _lastNameController),
                        _buildTextField("Phone", _phoneController, keyboardType: TextInputType.phone),
                        _buildTextField("Email", _emailController, keyboardType: TextInputType.emailAddress),
                        _buildDateField(),
                        _buildTextField("Address", _address1Controller),
                        _buildTextField("State", _stateController),
                        _buildTextField("Country", _countryController),
                        _buildTextField("Postal Code", _postalCodeController, keyboardType: TextInputType.number),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              "Save Changes",
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () {
                                // Handle close account
                              },
                              child: const Text(
                                "Close Account",
                                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 150),
                      ],
                    ),
                  ),
                ),
                // Positioned(
                //   bottom: 25,
                //   left: 0,
                //   right: 0,
                //   child: Align(
                //     alignment: Alignment.bottomCenter,
                //     child: BottomNavBar(
                //       currentIndex: _selectedIndex,
                //       onTap: (index) {
                //         if (index == 0) {
                //         navigateTo(
                //             context,
                //             HomePage(),
                //             type: NavigationType.clearStack,
                //           );
                //         } else {
                //           setState(() => _selectedIndex = index);
                //         }
                //       },
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primaryColor),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Date of Birth", style: TextStyle(fontWeight: FontWeight.w400, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _dobController,
            readOnly: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey.shade50,
              suffixIcon: const Icon(Icons.calendar_today),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primaryColor),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onTap: _selectDate,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _address1Controller.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }
}