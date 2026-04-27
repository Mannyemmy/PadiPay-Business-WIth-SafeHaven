import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/ui/permission_explanation_sheet.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:nigerian_states_and_lga/nigerian_states_and_lga.dart';

class UpgradeTier extends StatefulWidget {
  final int tier;
  const UpgradeTier({super.key, required this.tier});

  @override
  State<UpgradeTier> createState() => _UpgradeTierState();
}

class _UpgradeTierState extends State<UpgradeTier> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _idNumberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  List<String> states = [];
  String? selectedState;
  List<String> cities = [];
  String? selectedCity;
  String? selectedGender;
  String? selectedIdType;
  bool _isLoading = false;
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    _fetchStates();
  }

  Future<void> _fetchStates() async {
    setState(() {
      states = NigerianStatesAndLGA.allStates;
    });
  }

  Future<void> _fetchCities(String state) async {
    setState(() {
      cities = NigerianStatesAndLGA.getStateLGAs(state);
      selectedCity = null;
    });
  }

  Future<void> _getCurrentLocation() async {
    if (_isGettingLocation) return;

    // Privacy consent gate — location
    final prefs = await SharedPreferences.getInstance();
    final alreadyConsented = prefs.getBool('privacy_consent_location') ?? false;
    if (!alreadyConsented) {
      if (!mounted) return;
      final result = await showPermissionExplanationSheet(
        context,
        title: 'Location Permission Required',
        explanation:
            'PadiPay needs access to your location to auto-fill your address. Your location data is used only for this purpose and is not shared with third parties.',
      );
      if (result != true) return;
      await prefs.setBool('privacy_consent_location', true);
    }

    setState(() {
      _isGettingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        showToast("Please turn on your location", Colors.red);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied'),
          ),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        final street =
            (place.street ?? '').toLowerCase().contains('unnamed road')
                ? ''
                : (place.street ?? '');

        setState(() {
          _streetController.text = "$street, ${place.subLocality ?? ''}"
              .trim()
              .trimLeft()
              .trimRight()
              .replaceAll(RegExp(r'^,|,$'), '');

          selectedState = _getStateFromName(place.administrativeArea ?? '');
          selectedCity = place.locality ?? place.subLocality;
        });

        if (selectedState != null) {
          await _fetchCities(selectedState!);
          if (cities.contains(selectedCity)) {
            selectedCity = selectedCity;
          } else {
            selectedCity = cities.isNotEmpty ? cities.first : null;
          }
        }

        showToast("Location detected successfully", Colors.green);
      }
    } catch (e) {
      print('Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
        });
      }
    }
  }

  String? _getStateFromName(String stateName) {
    List<String> stateNames = [
      'Abia',
      'Adamawa',
      'Akwa Ibom',
      'Anambra',
      'Bauchi',
      'Bayelsa',
      'Benue',
      'Borno',
      'Cross River',
      'Delta',
      'Ebonyi',
      'Edo',
      'Ekiti',
      'Enugu',
      'FCT',
      'Gombe',
      'Imo',
      'Jigawa',
      'Kaduna',
      'Kano',
      'Katsina',
      'Kebbi',
      'Kogi',
      'Kwara',
      'Lagos',
      'Nasarawa',
      'Niger',
      'Ogun',
      'Ondo',
      'Osun',
      'Oyo',
      'Plateau',
      'Rivers',
      'Sokoto',
      'Taraba',
      'Yobe',
      'Zamfara',
    ];

    for (String state in stateNames) {
      if (stateName.toLowerCase().contains(state.toLowerCase()) ||
          state.toLowerCase().contains(stateName.toLowerCase())) {
        return state;
      }
    }
    return null;
  }

  Widget _buildLocationIcon() {
    if (_isGettingLocation) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _isGettingLocation ? null : _getCurrentLocation,
      child: Container(
        padding: EdgeInsets.all(12),
        child: FaIcon(
          FontAwesomeIcons.locationArrow,
          color: _isGettingLocation ? Colors.grey.shade400 : primaryColor,
          size: 20,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isFormValid;

    if (widget.tier == 2) {
      isFormValid = _controller.text.isNotEmpty &&
          _dobController.text.isNotEmpty &&
          _streetController.text.isNotEmpty &&
          selectedState != null &&
          selectedCity != null &&
          selectedGender != null;
    } else {
      isFormValid = selectedIdType != null &&
          _idNumberController.text.isNotEmpty &&
          _expiryController.text.isNotEmpty;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 20),
              Row(
                children: [
                  SizedBox(width: 10),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: Icon(
                      Icons.arrow_back_ios,
                      color: Colors.black54,
                      size: 20,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 30),
              Text(
                'Verify Your Identity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 10),
              Text(
                "To comply with CBN guidelines, we are required to verify every customer.",
                style: TextStyle(color: Colors.grey.shade600),
              ),
              SizedBox(height: 20),
              if (widget.tier == 2)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't know your BVN? ",
                      style: TextStyle(fontSize: 14),
                    ),
                    InkWell(
                      onTap: () async {
                        final Uri callUri = Uri(scheme: 'tel', path: '*565*0#');
                        if (await canLaunchUrl(callUri)) {
                          await launchUrl(callUri);
                        }
                      },
                      child: Row(
                        children: const [
                          Icon(Icons.phone, size: 18, color: Colors.blue),
                          SizedBox(width: 4),
                          Text(
                            "Dial *565*0#",
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              SizedBox(height: 20),
              if (widget.tier == 2) ...[
                Text(
                  "BVN",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  maxLength: 11,
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: Colors.black87),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    counterText: "",
                    hintText: 'Enter BVN',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Date of Birth',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _dobController,
                  keyboardType: TextInputType.datetime,
                  style: TextStyle(color: Colors.black87),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'DD-MM-YYYY',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    suffixIcon: Icon(
                      Icons.calendar_today,
                      color: Colors.grey.shade500,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  readOnly: true,
                  onTap: () => _selectDob(context),
                ),
                SizedBox(height: 20),
                Text(
                  'Gender',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  )
                      .copyWith(borderRadius: BorderRadius.circular(8))
                      .toBoxDecoration(),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedGender,
                      isExpanded: true,
                      hint: Text(
                        'Select Gender',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      items: ['Male', 'Female', 'Others']
                          .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedGender = val;
                        });
                      },
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Street Address',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _streetController,
                  style: TextStyle(color: Colors.black87),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Enter Street Address',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    suffixIcon: _buildLocationIcon(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'State',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  )
                      .copyWith(borderRadius: BorderRadius.circular(8))
                      .toBoxDecoration(),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedState,
                      isExpanded: true,
                      hint: Text(
                        'Select State',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      items: states
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedState = val;
                        });
                        if (val != null) _fetchCities(val);
                      },
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'City / LGA',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  )
                      .copyWith(borderRadius: BorderRadius.circular(8))
                      .toBoxDecoration(),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedCity,
                      isExpanded: true,
                      hint: Text(
                        'Select City',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      items: cities
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedCity = val;
                        });
                      },
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'ID Type',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  )
                      .copyWith(borderRadius: BorderRadius.circular(8))
                      .toBoxDecoration(),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedIdType,
                      isExpanded: true,
                      hint: Text(
                        'Select ID Type',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      items: [
                        'PASSPORT',
                        'DRIVERS_LICENSE',
                        'VOTERS_CARD',
                        'NATIONAL_ID'
                      ].map((id) => DropdownMenuItem(value: id, child: Text(id))).toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedIdType = val;
                        });
                      },
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'ID Number',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _idNumberController,
                  keyboardType: TextInputType.text,
                  style: TextStyle(color: Colors.black87),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Enter ID Number',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Expiry Date',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _expiryController,
                  keyboardType: TextInputType.datetime,
                  style: TextStyle(color: Colors.black87),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'DD-MM-YYYY',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    suffixIcon: Icon(
                      Icons.calendar_today,
                      color: Colors.grey.shade500,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  readOnly: true,
                  onTap: () => _selectExpiry(context),
                ),
              ],
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (isFormValid && !_isLoading) ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    disabledBackgroundColor: primaryColor.withValues(
                      alpha: 0.2,
                    ),
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text(
                          'Upgrade Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDob(BuildContext context) async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      String formattedDate =
          "${pickedDate.day.toString().padLeft(2, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.year}";
      setState(() {
        _dobController.text = formattedDate;
      });
    }
  }

  Future<void> _selectExpiry(BuildContext context) async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null) {
      String formattedDate =
          "${pickedDate.day.toString().padLeft(2, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.year}";
      setState(() {
        _expiryController.text = formattedDate;
      });
    }
  }

  String _formatDateForApi(String date) {
    // Convert DD-MM-YYYY to YYYY-MM-DD
    var parts = date.split('-');
    if (parts.length != 3) return date;
    return '${parts[2]}-${parts[1]}-${parts[0]}';
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
    });

    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      print('Error: No user logged in');
      showToast('No user logged in', Colors.red);
      setState(() {
        _isLoading = false;
      });
      return;
    }

    DocumentReference docRef = FirebaseFirestore.instance.collection('users').doc(uid);

    try {
      // Get user data
      DocumentSnapshot snap = await docRef.get();
      if (!snap.exists) {
        print('Error: User document not found');
        showToast('User document not found', Colors.red);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      Map<String, dynamic>? userData = snap.data() as Map<String, dynamic>?;
      if (userData == null) {
        print('Error: User data is null');
        showToast('User data is null', Colors.red);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      if (widget.tier == 2) {
        // Validate required fields for Tier 2
        String? firstName = userData['firstName'];
        String? lastName = userData['lastName'];
        String? email = userData['email'];
        String? phoneNumber = userData['phone']?.replaceFirst('+234', '');

        if (firstName == null || firstName.trim().isEmpty) {
          print('Error: firstName is missing or empty in Firestore');
          showToast('First name is missing in user data', Colors.red);
          setState(() {
            _isLoading = false;
          });
          return;
        }
        if (lastName == null || lastName.trim().isEmpty) {
          print('Error: lastName is missing or empty in Firestore');
          showToast('Last name is missing in user data', Colors.red);
          setState(() {
            _isLoading = false;
          });
          return;
        }
        if (email == null || email.trim().isEmpty) {
          print('Error: email is missing or empty in Firestore');
          showToast('Email is missing in user data', Colors.red);
          setState(() {
            _isLoading = false;
          });
          return;
        }
        if (phoneNumber == null || phoneNumber.trim().isEmpty) {
          print('Error: phoneNumber is missing or empty in Firestore');
          showToast('Phone number is missing in user data', Colors.red);
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Format phone number: Prepend '0' if 10 digits
        phoneNumber = phoneNumber.trim();
        if (phoneNumber.length == 10 && RegExp(r'^\d{10}$').hasMatch(phoneNumber)) {
          phoneNumber = '0$phoneNumber';
        }
        // Validate phone number: Must be 11 digits and start with '0'
        if (!RegExp(r'^0\d{10}$').hasMatch(phoneNumber)) {
          print('Error: Invalid phone number format. Must be 11 digits starting with 0');
          showToast('Invalid phone number format. Must be 11 digits starting with 0', Colors.red);
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Parse DOB and check age for Tier 2
        var parts = _dobController.text.split('-');
        int day = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int year = int.parse(parts[2]);
        DateTime birthDate = DateTime(year, month, day);
        DateTime today = DateTime.now();
        int age = today.year - birthDate.year;
        if (today.month < birthDate.month ||
            (today.month == birthDate.month && today.day < birthDate.day)) {
          age--;
        }
        if (age < 18) {
          print('Error: User must be at least 18 years old');
          showToast('You must be at least 18 years old', Colors.red);
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Prepare Tier 2 data
        String formattedDateForApi = _formatDateForApi(_dobController.text);
        String gender = selectedGender!;
        String street = _streetController.text;
        String city = selectedCity!;
        String state = selectedState!;
        int postalCode = Random().nextInt(900000) + 100000;

        // Save Tier 2 data to Firestore
        Map<String, dynamic> updateData = {
          'bvn': _controller.text,
          'dateOfBirth': formattedDateForApi,
          'gender': gender,
          'address': {
            'street': street,
            'city': city,
            'state': state,
            'country': 'NG',
            'postalCode': postalCode,
          },
        };
        await docRef.update(updateData);

        // Create Getanchor User
        final functions = FirebaseFunctions.instance;
        HttpsCallable createUserFunc = functions.httpsCallable('createGetanchorUser');
        final payload = {
          'firstName': firstName,
          'lastName': lastName,
          'email': email,
          'country': 'NG',
          'state': state,
          'addressLine1': street,
          'city': city,
          'postalCode': postalCode,
          'phoneNumber': phoneNumber,
        };
        print('Sending createGetanchorUser payload: $payload');
        final createUserResult = await createUserFunc.call(payload);
        print('Create Getanchor User Response: ${createUserResult.data}');
        String customerId = createUserResult.data['data']['id'];

        // Save customer creation response
        await docRef.update({
          'getAnchorData.customerCreation': createUserResult.data,
        });

        // Attempt KYC upgrade for Tier 2
        HttpsCallable upgradeKycFunc = functions.httpsCallable('upgradeCustomerKyc');
        final kycPayload = {
          'customerId': customerId,
          'level': 'TIER_2',
          'bvn': _controller.text,
          'dateOfBirth': formattedDateForApi,
          'gender': gender,
        };
        print('Sending upgradeCustomerKyc payload: $kycPayload');
        final upgradeKycResult = await upgradeKycFunc.call(kycPayload);
        print('Upgrade Customer KYC Response: ${upgradeKycResult.data}');
        await docRef.update({
          'getAnchorData.upgradeKyc': upgradeKycResult.data,
        });

        // Create Electronic Account
        HttpsCallable createAccountFunc = functions.httpsCallable('createElectronicAccount');
        final idempotencyKey = Uuid().v4();
        final accountPayload = {
          'customerId': customerId,
          'currency': 'NGN',
          'type':"IndividualCustomer",
          'idempotencyKey': idempotencyKey,
        };
        print('Sending createElectronicAccount payload: $accountPayload');
        final createAccountResult = await createAccountFunc.call(accountPayload);
        print('Create Electronic Account Response: ${createAccountResult.data}');
        await docRef.update({
          'getAnchorData.virtualAccount': createAccountResult.data,
        });

        // Send virtual account creation email
        try {
          final vaData = createAccountResult.data?['data']?['attributes'];
          final vaAccountNumber = vaData?['accountNumber']?.toString() ?? '';
          final vaBankName = vaData?['bankName']?.toString() ?? 'Your Bank';
          final userEmail = email ?? '';
          final userName = firstName ?? 'Business Owner';
          if (userEmail.isNotEmpty) {
            await FirebaseFunctions.instance.httpsCallable('sendEmail').call({
              'to': userEmail,
              'subject': '🎉 Your PadiPay Business Virtual Account is Ready',
              'html': ''
                  '<!DOCTYPE html><html><head><meta charset="UTF-8"></head>'
                  '<body style="margin:0;padding:0;background:#f0f2f5;font-family:\'Helvetica Neue\',Helvetica,Arial,sans-serif;">'
                  '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:40px 0;">'
                  '<tr><td align="center"><table width="520" cellpadding="0" cellspacing="0" style="max-width:520px;width:100%;">'
                  '<tr><td align="center" style="padding-bottom:24px;">'
                  '<span style="font-size:26px;font-weight:700;color:#1a1a2e;letter-spacing:-0.5px;">Padi<span style="color:#4f46e5;">Pay</span> Business</span>'
                  '</td></tr>'
                  '<tr><td style="background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.07);">'
                  '<table width="100%" cellpadding="0" cellspacing="0">'
                  '<tr><td style="background:linear-gradient(135deg,#7c3aed 0%,#4f46e5 100%);height:5px;font-size:0;line-height:0;">&nbsp;</td></tr>'
                  '<tr><td style="padding:48px 48px 36px;">'
                  '<p style="margin:0 0 6px;font-size:13px;font-weight:600;letter-spacing:1.2px;text-transform:uppercase;color:#7c3aed;">Account Ready</p>'
                  '<h1 style="margin:0 0 16px;font-size:26px;font-weight:800;color:#0f0f1a;">Your Virtual Account is Ready! 🎉</h1>'
                  '<p style="margin:0 0 28px;font-size:15px;color:#6b7280;line-height:1.7;">Hi \$userName! Your PadiPay Business virtual bank account has been successfully created. You can now receive payments from anyone, anywhere.</p>'
                  '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f5f3ff;border-radius:12px;padding:28px;margin:0 0 28px;text-align:center;">'
                  '<tr><td><p style="margin:0 0 8px;font-size:13px;color:#6b7280;letter-spacing:0.5px;">ACCOUNT NUMBER</p>'
                  '<p style="margin:0 0 12px;font-size:32px;font-weight:800;color:#4f46e5;letter-spacing:4px;">\$vaAccountNumber</p>'
                  '<p style="margin:0;font-size:14px;color:#374151;font-weight:600;">\$vaBankName</p>'
                  '</td></tr></table>'
                  '<p style="margin:0 0 12px;font-size:14px;color:#6b7280;line-height:1.7;">Share this account number with clients and partners to receive payments instantly.</p>'
                  '</td></tr>'
                  '<tr><td style="padding:0 48px;"><div style="border-top:1px solid #f3f4f6;"></div></td></tr>'
                  '<tr><td style="padding:24px 48px;"><p style="margin:0;font-size:12px;color:#d1d5db;">&copy; 2026 PadiPay Business</p></td></tr>'
                  '</table></td></tr>'
                  '</table></td></tr>'
                  '</table></body></html>',
            });
          }
        } catch (e) {
          print('Virtual account email error (non-fatal): $e');
        }

        // Save tier
        await docRef.update({'getAnchorData.tier': widget.tier});
      } else {
        // Tier 3: Only call upgradeCustomerKyc and update Firestore
        // Get customerId
        String? customerId = userData['getAnchorData']?['customerCreation']?['data']?['id'];
        if (customerId == null) {
          print('Error: customerId not found in Firestore');
          showToast('Customer ID not found. Please complete Tier 2 first.', Colors.red);
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Save Tier 3 data to Firestore
        Map<String, dynamic> updateData = {
          'idType': selectedIdType,
          'idNumber': _idNumberController.text,
          'expiryDate': _formatDateForApi(_expiryController.text),
        };
        await docRef.update(updateData);

        // Call upgradeCustomerKyc for Tier 3
        final functions = FirebaseFunctions.instance;
        HttpsCallable upgradeKycFunc = functions.httpsCallable('upgradeCustomerKyc');
        final kycPayload = {
          'customerId': customerId,
          'level': 'TIER_3',
          'idType': selectedIdType,
          'idNumber': _idNumberController.text,
          'expiryDate': _formatDateForApi(_expiryController.text),
        };
        print('Sending upgradeCustomerKyc payload: $kycPayload');
        final upgradeKycResult = await upgradeKycFunc.call(kycPayload);
        print('Upgrade Customer KYC Response: ${upgradeKycResult.data}');

        // Update Firestore with KYC response and tier
        await docRef.update({
          'getAnchorData.upgradeKyc': upgradeKycResult.data,
          'getAnchorData.tier': widget.tier,
        });
      }

      print('✅ Account upgraded successfully');
      showToast('Account upgraded successfully', Colors.green);
      navigateTo(context, HomePage());
    } catch (e) {
      print('Error during submission: $e');
      showToast('Error: $e', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _idNumberController.dispose();
    _expiryController.dispose();
    _dobController.dispose();
    _streetController.dispose();
    super.dispose();
  }
}

extension OutlineInputBorderToBoxDecoration on OutlineInputBorder {
  BoxDecoration toBoxDecoration() {
    return BoxDecoration(
      borderRadius: borderRadius,
      border: Border.all(color: borderSide.color, width: borderSide.width),
    );
  }
}