import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/utils.dart';
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

  final TextEditingController ninController = TextEditingController();

  StreamSubscription<DocumentSnapshot>? _userDocSub;
  bool _bvnFromQore = false;

  // BVN conflict detection
  bool _bvnConflict = false;
  Timer? _bvnCheckTimer;
  String? _lastQueriedBvn;
  bool _externalBvnMatch = false;

  @override
  void initState() {
    super.initState();
    _fetchStates();
    _listenForIdNumber();
    _checkInitialBvnConflict();
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

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      await _handleGetLocation();
      return;
    }

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      builder: (context) => SafeArea(
        bottom: true,
        child: Container(
          padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Location Permission Required',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'This app needs your location to proceed with tier upgrade.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    permission = await Geolocator.requestPermission();
                    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
                      await _handleGetLocation();
                    } else if (permission == LocationPermission.denied) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Location permissions are denied')),
                        );
                      }
                    } else if (permission == LocationPermission.deniedForever) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Location permissions are permanently denied')),
                        );
                      }
                    }
                  },
                  child: const Text('Continue'),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _handleGetLocation() async {
    setState(() {
      _isGettingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
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
      final bvnAllowed = !_bvnConflict || _externalBvnMatch;
      isFormValid = _controller.text.isNotEmpty &&
          _dobController.text.isNotEmpty &&
          _streetController.text.isNotEmpty &&
          selectedState != null &&
          selectedCity != null &&
          selectedGender != null &&
          bvnAllowed;
    } else {
      isFormValid = ninController.text.isNotEmpty &&
          selectedIdType != null &&
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
                  readOnly: _bvnFromQore,
                  onChanged: _onBvnChanged,
                  decoration: InputDecoration(
                    counterText: "",
                    hintText: _bvnFromQore ? 'BVN (verification provided)' : 'Enter BVN',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    errorText: (_bvnConflict && !_externalBvnMatch) ? 'BVN already registered with another account' : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: (_bvnConflict && !_externalBvnMatch) ? Colors.red : Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: (_bvnConflict && !_externalBvnMatch) ? Colors.red : Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: (_bvnConflict && !_externalBvnMatch) ? Colors.red : primaryColor, width: 2),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: (_bvnConflict && !_externalBvnMatch) ? Colors.red : Colors.grey.shade200),
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
                  "NIN",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  maxLength: 11,
                  controller: ninController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: Colors.black87),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    counterText: "",
                    hintText: 'Enter NIN (11 digits)',
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

  Future<String?> _tryMatchExistingCustomerByBvn(String? bvn, DocumentReference docRef, String uid) async {
    if (bvn == null) return null;
    final bvnToMatch = bvn.replaceAll(RegExp(r'\D'), '').trim();
    if (bvnToMatch.isEmpty) return null;

    try {
      final functions = FirebaseFunctions.instance;
      print('Searching fetchAllCustomers for BVN: $bvnToMatch');
      final fetchRes = await functions.httpsCallable('fetchAllCustomers').call();
      final List<dynamic>? customers = (fetchRes.data is Map && fetchRes.data['data'] is List)
          ? List<dynamic>.from(fetchRes.data['data'] as List)
          : (fetchRes.data is List ? List<dynamic>.from(fetchRes.data as List) : null);

      if (customers == null || customers.isEmpty) return null;

      for (var item in customers) {
        try {
          final Map<String, dynamic> it = Map<String, dynamic>.from(item as Map);
          final attrs = (it['attributes'] is Map) ? Map<String, dynamic>.from(it['attributes'] as Map) : {};
          String? itemBvn;

          if (attrs['identificationLevel2'] is Map) {
            itemBvn = (attrs['identificationLevel2'] as Map)['bvn']?.toString();
          }
          itemBvn ??= attrs['bvn']?.toString();

          if (itemBvn != null && itemBvn.replaceAll(RegExp(r'\D'), '').trim() == bvnToMatch) {
            final foundId = it['id']?.toString() ?? '';
            print('Found matching customer in fetchAllCustomers: $foundId');

            try {
              final Map<String, dynamic> updateMap = {
                'getAnchorData.customerCreation': {'data': it},
              };

              final Map<String, dynamic>? verification = (attrs['verification'] is Map)
                  ? Map<String, dynamic>.from(attrs['verification'] as Map)
                  : null;

              if (verification != null) {
                updateMap['getAnchorData.upgradeKyc'] = {
                  'status': 'success',
                  'data': verification,
                };

                final verLevel = (verification['level']?.toString() ?? '').toUpperCase();
                final verStatus = (verification['status']?.toString() ?? '').toLowerCase();
                if (verLevel == 'TIER_2' || verStatus == 'approved') {
                  updateMap['getAnchorData.tier'] = 2;
                }
              }

              await docRef.update(updateMap);
              print('Saved existing customer data and verification to user document for user $uid');
            } catch (e) {
              print('Failed to save existing customer data/verification: $e');
            }

            // Attempt to create electronic account for this customer
            try {
              print('Attempting to create electronic account for customer: $foundId');
              final createVaRes = await functions
                  .httpsCallable('createElectronicAccount')
                  .call({'customerId': foundId, 'userId': uid, 'currency': 'NGN', 'type': 'IndividualCustomer', 'idempotencyKey': const Uuid().v4()});
              if (createVaRes.data != null) {
                final vaUpdate = {
                  'getAnchorData.virtualAccount': createVaRes.data,
                };

                final Map<String, dynamic>? verificationMap = (attrs['verification'] is Map)
                    ? Map<String, dynamic>.from(attrs['verification'] as Map)
                    : null;
                final bool verTier2OrApproved = verificationMap != null && ((verificationMap['level']?.toString().toUpperCase() == 'TIER_2') || (verificationMap['status']?.toString().toLowerCase() == 'approved'));

                if (!verTier2OrApproved) {
                  vaUpdate['getAnchorData.tier'] = 2;
                }

                await docRef.update(vaUpdate);
                print('Created and saved electronic account for user $uid');
              } else {
                print('createElectronicAccount returned no data for $foundId');
              }
            } catch (e) {
              print('Failed to create electronic account for $foundId: $e');
            }

            return foundId;
          }
        } catch (e) {
          // ignore malformed entries
        }
      }
    } catch (e) {
      print('Error searching fetchAllCustomers: $e');
    }

    return null;
  }

  void _listenForIdNumber() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _userDocSub?.cancel();
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data() ?? <String, dynamic>{};
      final qore = data['qoreIdData'] as Map<String, dynamic>?;
      final verification = qore?['verification'] as Map<String, dynamic>?;
      final metadata = verification?['metadata'] as Map<String, dynamic>?;
      final idNumber = metadata?['idNumber']?.toString();
      if (!mounted) return;
      setState(() {
        if (idNumber != null && idNumber.isNotEmpty) {
          _controller.text = idNumber;
          _bvnFromQore = true;
        } else {
          _bvnFromQore = false;
        }
      });
      _populateFieldsFromDoc(data);
      if (idNumber != null && idNumber.isNotEmpty) {
        _checkBvnConflict(idNumber);
        _maybeFetchGetAnchorByBvn(idNumber);
      } else {
        _checkBvnConflict('');
      }
    });
  }

  Future<void> _checkInitialBvnConflict() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = snap.data();
      String? candidate = _controller.text.trim();
      if (candidate.isEmpty) candidate = data?['bvn']?.toString();
      if (candidate == null || candidate.isEmpty) {
        final qore = data?['qoreIdData'] as Map<String, dynamic>?;
        final verification = qore?['verification'] as Map<String, dynamic>?;
        final metadata = verification?['metadata'] as Map<String, dynamic>?;
        candidate = metadata?['idNumber']?.toString();
      }
      if (candidate != null && candidate.isNotEmpty) {
        await _checkBvnConflict(candidate);
        _maybeFetchGetAnchorByBvn(candidate);
      }
    } catch (e) {
      print('Error during initial BVN conflict check: $e');
    }
  }

  Future<void> _checkBvnConflict(String bvn) async {
    if (bvn.isEmpty || bvn.length != 11) {
      if (_bvnConflict) setState(() => _bvnConflict = false);
      return;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      final q1 = await FirebaseFirestore.instance
          .collection('users')
          .where('bvn', isEqualTo: bvn)
          .get();
      final q2 = await FirebaseFirestore.instance
          .collection('users')
          .where('qoreIdData.verification.metadata.idNumber', isEqualTo: bvn)
          .get();
      final allDocs = <String, QueryDocumentSnapshot>{};
      for (var d in q1.docs) {
        allDocs[d.id] = d;
      }
      for (var d in q2.docs) {
        allDocs[d.id] = d;
      }
      final conflict = allDocs.keys.any((id) => id != user?.uid);
      if (mounted) setState(() => _bvnConflict = conflict);
    } catch (e) {
      print('Error checking BVN conflict: $e');
    }
  }

  void _onBvnChanged(String val) {
    _bvnCheckTimer?.cancel();
    _bvnCheckTimer = Timer(const Duration(milliseconds: 500), () {
      _checkBvnConflict(val);
      _maybeFetchGetAnchorByBvn(val);
    });
    if (val.isEmpty || val.length != 11) {
      if (_externalBvnMatch) setState(() => _externalBvnMatch = false);
    }
    setState(() {});
  }

  String _formatDateFromApi(String date) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(date);
    if (m != null) return '${m.group(3)}-${m.group(2)}-${m.group(1)}';
    return date;
  }

  void _populateFieldsFromDoc(Map<String, dynamic>? data) {
    if (data == null) return;
    final bvn = data['bvn']?.toString();
    if (bvn != null && bvn.isNotEmpty && _controller.text != bvn) _controller.text = bvn;
    final nin = data['nin']?.toString();
    if (nin != null && nin.isNotEmpty && ninController.text != nin) ninController.text = nin;
    String? dob = data['dateOfBirth']?.toString();
    if ((dob == null || dob.isEmpty) && data['getAnchorData'] is Map) {
      final gc = (data['getAnchorData'] as Map)['customerCreation'] as Map<String, dynamic>?;
      final cdata = gc?['data'] as Map<String, dynamic>?;
      dob = cdata?['dateOfBirth']?.toString() ?? cdata?['dob']?.toString();
      if ((dob == null || dob.isEmpty) && cdata != null && cdata['attributes'] is Map) {
        final attrs = cdata['attributes'] as Map<String, dynamic>;
        dob = attrs['dateOfBirth']?.toString() ?? attrs['dob']?.toString();
      }
    }
    if (dob != null && dob.isNotEmpty) {
      final display = _formatDateFromApi(dob);
      if (_dobController.text != display) _dobController.text = display;
    }
    String? gender = data['gender']?.toString();
    if ((gender == null || gender.isEmpty) && data['getAnchorData'] is Map) {
      final gc = (data['getAnchorData'] as Map)['customerCreation'] as Map<String, dynamic>?;
      final cdata = gc?['data'] as Map<String, dynamic>?;
      if (cdata != null) {
        gender = cdata['gender']?.toString();
        if (gender == null && cdata['attributes'] is Map) gender = (cdata['attributes'] as Map)['gender']?.toString();
      }
    }
    if (gender != null && gender.isNotEmpty && selectedGender != gender) {
      setState(() => selectedGender = gender);
    }
    if (data['getAnchorData'] is Map) {
      if (!_externalBvnMatch && mounted) setState(() => _externalBvnMatch = true);
    }
  }

  Future<void> _maybeFetchGetAnchorByBvn(String bvn) async {
    if (bvn.isEmpty || bvn.length != 11) {
      if (_externalBvnMatch) setState(() => _externalBvnMatch = false);
      return;
    }
    if (_lastQueriedBvn == bvn) return;
    _lastQueriedBvn = bvn;
    try {
      final functions = FirebaseFunctions.instance;
      final fetchRes = await functions.httpsCallable('fetchAllCustomers').call();
      final List<dynamic>? customers =
          (fetchRes.data is Map && fetchRes.data['data'] is List)
              ? List<dynamic>.from(fetchRes.data['data'] as List)
              : (fetchRes.data is List ? List<dynamic>.from(fetchRes.data as List) : null);
      if (customers == null || customers.isEmpty) {
        if (_externalBvnMatch) setState(() => _externalBvnMatch = false);
        return;
      }
      final String bvnToMatch = bvn.replaceAll(RegExp(r'\D'), '').trim();
      Map<String, dynamic>? matchedCustomer;
      for (var item in customers) {
        try {
          final Map<String, dynamic> it = Map<String, dynamic>.from(item as Map);
          final attrs = (it['attributes'] is Map) ? Map<String, dynamic>.from(it['attributes'] as Map) : {};
          String? itemBvn;
          if (attrs['identificationLevel2'] is Map) {
            itemBvn = (attrs['identificationLevel2'] as Map)['bvn']?.toString();
          }
          itemBvn ??= attrs['bvn']?.toString();
          if (itemBvn != null && itemBvn.replaceAll(RegExp(r'\D'), '').trim() == bvnToMatch) {
            matchedCustomer = it;
            break;
          }
        } catch (e) {
          // ignore
        }
      }
      if (matchedCustomer == null) {
        if (_externalBvnMatch) setState(() => _externalBvnMatch = false);
        return;
      }
      if (!_externalBvnMatch && mounted) setState(() => _externalBvnMatch = true);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      await docRef.update({'getAnchorData.customerCreation': {'data': matchedCustomer}});
      try {
        final refreshed = await docRef.get();
        _populateFieldsFromDoc(refreshed.data());
      } catch (e) {
        print('Failed to refresh user doc: $e');
      }
    } catch (e) {
      print('Error searching fetchAllCustomers during auto-find: $e');
    }
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

        // Create/Get existing Getanchor Customer (try fetchAllCustomers by BVN first)
        final functions = FirebaseFunctions.instance;
        String? customerId;
        try {
          final matched = await _tryMatchExistingCustomerByBvn(_controller.text, docRef, uid);
          if (matched != null) {
            customerId = matched;
            print('Matched existing customer $customerId; proceeding with KYC/VA steps');
          } else {
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
            customerId = createUserResult.data['data']['id'];

            // Save customer creation response
            await docRef.update({
              'getAnchorData.customerCreation': createUserResult.data,
            });
          }
        } catch (e) {
          print('Error matching/creating customer: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error creating or matching customer: $e')));
          }
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Attempt KYC upgrade for Tier 2 (if we have a customerId) but skip if upgrade already succeeded
        if (customerId != null && customerId.isNotEmpty) {
          // re-fetch to check for existing upgradeKyc
          final refreshed = await docRef.get();
          final Map<String, dynamic>? refreshedMap = refreshed.data() as Map<String, dynamic>?;
          final Map<String, dynamic>? storedUpgrade = (refreshedMap != null && refreshedMap['getAnchorData'] is Map)
              ? (refreshedMap['getAnchorData'] as Map<String, dynamic>)['upgradeKyc'] as Map<String, dynamic>?
              : null;

          final bool upgradeKycPreviouslySucceeded = storedUpgrade != null &&
              (storedUpgrade['success'] == true ||
                  (storedUpgrade['status']?.toString().toLowerCase() == 'success') ||
                  (storedUpgrade['data'] is Map && (storedUpgrade['data']['success'] == true)));

          if (!upgradeKycPreviouslySucceeded) {
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
          } else {
            print('Skipping KYC upgrade: previous upgrade succeeded');
          }
        } else {
          print('No customerId available for KYC upgrade');
        }

        // Create Electronic Account (if not already created)
        final refreshedAfterKyc = await docRef.get();
        final Map<String, dynamic>? refreshedAfterMap = refreshedAfterKyc.data() as Map<String, dynamic>?;
        final existingVa = refreshedAfterMap != null ? (refreshedAfterMap['getAnchorData'] is Map ? (refreshedAfterMap['getAnchorData'] as Map<String, dynamic>)['virtualAccount'] : null) : null;
        if (existingVa != null) {
          print('Electronic account already exists, skipping creation');
          final currentTier = refreshedAfterMap != null && refreshedAfterMap['getAnchorData'] is Map ? (refreshedAfterMap['getAnchorData'] as Map<String, dynamic>)['tier'] : null;
          if (currentTier != 2) {
            await docRef.update({'getAnchorData.tier': 2});
          }
        } else {
          if (customerId == null || customerId.isEmpty) {
            print('No customerId available to create electronic account');
          } else {
            try {
              HttpsCallable createAccountFunc = functions.httpsCallable('createElectronicAccount');
              final idempotencyKey = Uuid().v4();
              final accountPayload = {
                'customerId': customerId,
                'currency': 'NGN',
                "type": "IndividualCustomer",
                'idempotencyKey': idempotencyKey,
              };
              print('Sending createElectronicAccount payload: $accountPayload');
              final createAccountResult = await createAccountFunc.call(accountPayload);
              print('Create Electronic Account Response: ${createAccountResult.data}');
              await docRef.update({
                'getAnchorData.virtualAccount': createAccountResult.data,
              });

              // Save tier
              await docRef.update({'getAnchorData.tier': widget.tier});
            } catch (e) {
              print('Error creating electronic account: $e');
            }
          }
        }
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
          'nin': ninController.text,
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
    _userDocSub?.cancel();
    _bvnCheckTimer?.cancel();
    _controller.dispose();
    ninController.dispose();
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