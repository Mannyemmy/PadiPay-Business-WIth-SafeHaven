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
  // BVN & verification fields (aligned with user app)
  final TextEditingController _bvnController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _ninController = TextEditingController();
  final TextEditingController _idNumberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();

  List<String> states = [];
  String? selectedState;
  List<String> cities = [];
  String? selectedCity;
  String? selectedGender;
  String? selectedIdType;

  bool _isLoading = false;
  bool _isGettingLocation = false;

  // BVN verification state (mirrors user app)
  bool _bvnVerifying = false;
  bool? _bvnVerified;
  String? _bvnVerifyStatus;
  Map<String, bool>? _bvnFieldMatches;

  Timer? _bvnCheckTimer;
  Timer? _bvnVerifyTimer;
  bool _bvnFromQore = false;
  bool _bvnConflict = false;
  bool _externalBvnMatch = false;
  String? _lastQueriedBvn;

  // Firestore listener
  StreamSubscription<DocumentSnapshot>? _userDocSub;

  bool get _isIdentityVerificationStep => widget.tier == 1;
  bool get _isBvnTierFlow => widget.tier == 1 || widget.tier == 2;

  @override
  void initState() {
    super.initState();
    _fetchStates();
    _listenForUserData();
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

  // ------------------------------------------------------------
  //   Location logic (unchanged, but respect BVN lock)
  // ------------------------------------------------------------
  Future<void> _getCurrentLocation() async {
    if (_isGettingLocation || _bvnVerified == true) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
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
                      if (permission == LocationPermission.always ||
                          permission == LocationPermission.whileInUse) {
                        await _handleGetLocation();
                      } else if (permission == LocationPermission.denied) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Location permissions are denied'),
                            ),
                          );
                        }
                      } else if (permission ==
                          LocationPermission.deniedForever) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Location permissions are permanently denied',
                              ),
                            ),
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
    setState(() => _isGettingLocation = true);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
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
      onTap: (_isGettingLocation || _bvnVerified == true)
          ? null
          : _getCurrentLocation,
      child: Container(
        padding: EdgeInsets.all(12),
        child: FaIcon(
          FontAwesomeIcons.locationArrow,
          color: (_isGettingLocation || _bvnVerified == true)
              ? Colors.grey.shade400
              : primaryColor,
          size: 20,
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  //   BVN verification (copied from user app)
  // ------------------------------------------------------------
  Future<void> _verifyBvn() async {
    final bvn = _bvnController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    if (bvn.length != 11 || firstName.isEmpty || lastName.isEmpty) return;

    if (_isUnder18() == true) {
      setState(() {
        _bvnVerified = false;
        _bvnVerifyStatus = 'You must be 18 or older to verify your BVN';
      });
      return;
    }

    setState(() {
      _bvnVerifying = true;
      _bvnVerified = null;
      _bvnVerifyStatus = null;
      _bvnFieldMatches = null;
    });

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyBvnNoFace')
          .call({'bvn': bvn, 'firstName': firstName, 'lastName': lastName});
      print('verifyBvnNoFace Response: ${result.data}');

      final resData = result.data as Map<String, dynamic>;
      bool isVerified = resData['verified'] as bool? ?? false;
      String? verifyStatus = resData['status']?.toString();

      final Map<String, dynamic> fm = Map<String, dynamic>.from(
        resData['fieldMatches'] as Map? ?? {},
      );
      final rawBd = resData['bvnData'];
      final bvnDobRaw = rawBd != null
          ? (rawBd as Map)['birthdate']?.toString()
          : null;
      final bvnDobDisplay = (bvnDobRaw != null && bvnDobRaw.isNotEmpty)
          ? _formatDateFromApi(bvnDobRaw)
          : null;
      final bvnGender = rawBd != null
          ? (rawBd as Map)['gender']?.toString()
          : null;
      final enteredDob = _dobController.text.trim();
      final enteredGender = selectedGender;
      final fieldMatches = {
        'firstname': fm['firstname'] as bool? ?? false,
        'lastname': fm['lastname'] as bool? ?? false,
        'birthdate': enteredDob.isEmpty || (bvnDobDisplay ?? '').isEmpty
            ? true
            : enteredDob == bvnDobDisplay,
        'gender': (enteredGender ?? '').isEmpty || (bvnGender ?? '').isEmpty
            ? true
            : enteredGender!.toLowerCase() == bvnGender!.toLowerCase(),
      };
      final anyMismatch = fieldMatches.values.any((v) => v == false);
      if (anyMismatch) {
        isVerified = false;
        verifyStatus = 'NO_MATCH';
      }

      setState(() {
        _bvnVerified = isVerified;
        _bvnVerifyStatus = verifyStatus;
        _bvnFieldMatches = fieldMatches;
      });

      // Save BVN data to Firestore
      final rawBvnData = resData['bvnData'];
      if (rawBvnData != null) {
        final bvnData = Map<String, dynamic>.from(rawBvnData as Map);
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final Map<String, dynamic> updates = {};
          bvnData.forEach((key, value) {
            if (value != null)
              updates['qoreIdData.bvnVerificationNoFace.$key'] = value;
          });
          final currentDob = _dobController.text.trim();
          if (currentDob.isNotEmpty)
            updates['dateOfBirth'] = _formatDateForApi(currentDob);
          else if ((bvnData['birthdate'] ?? '').toString().isNotEmpty)
            updates['dateOfBirth'] = bvnData['birthdate'];
          if ((bvnData['gender'] ?? '').toString().isNotEmpty &&
              selectedGender == null)
            updates['gender'] = bvnData['gender'];
          if ((bvnData['phone'] ?? '').toString().isNotEmpty)
            updates['phone'] = bvnData['phone'];
          final currentFn = _firstNameController.text.trim();
          final currentLn = _lastNameController.text.trim();
          if (currentFn.isNotEmpty) updates['firstName'] = currentFn;
          if (currentLn.isNotEmpty) updates['lastName'] = currentLn;
          if (currentFn.isEmpty &&
              (bvnData['firstname'] ?? '').toString().isNotEmpty) {
            updates['firstName'] = _toTitleCase(
              bvnData['firstname'].toString(),
            );
          }
          if (currentLn.isEmpty &&
              (bvnData['lastname'] ?? '').toString().isNotEmpty) {
            updates['lastName'] = _toTitleCase(bvnData['lastname'].toString());
          }
          updates['qoreIdData.bvnVerificationNoFace.verified'] = isVerified;
          updates['qoreIdData.bvnVerificationNoFace.status'] = verifyStatus;
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update(updates);
        }

        if (mounted) {
          setState(() {
            final dob = bvnData['birthdate']?.toString();
            if (dob != null && dob.isNotEmpty && _dobController.text.isEmpty)
              _dobController.text = _formatDateFromApi(dob);
            final gender = bvnData['gender']?.toString();
            if (gender != null && gender.isNotEmpty && selectedGender == null)
              selectedGender = gender;
            final fn = bvnData['firstname']?.toString();
            if (fn != null &&
                fn.isNotEmpty &&
                _firstNameController.text.isEmpty)
              _firstNameController.text = _toTitleCase(fn);
            final ln = bvnData['lastname']?.toString();
            if (ln != null && ln.isNotEmpty && _lastNameController.text.isEmpty)
              _lastNameController.text = _toTitleCase(ln);
          });
        }
      }
    } on FirebaseFunctionsException catch (e) {
      final raw = e.message ?? '';
      final userMsg =
          raw.toLowerCase().contains('404') ||
              raw.toLowerCase().contains('not found')
          ? 'BVN not found'
          : raw.isNotEmpty
          ? raw
          : 'Verification failed please try again';
      setState(() {
        _bvnVerified = false;
        _bvnVerifyStatus = userMsg;
      });
    } catch (e) {
      setState(() {
        _bvnVerified = false;
        _bvnVerifyStatus = 'Verification failed please try again';
      });
    } finally {
      setState(() => _bvnVerifying = false);
    }
  }

  bool? _isUnder18() {
    final dob = _dobController.text.trim();
    if (dob.isEmpty) return null;
    final parts = dob.split('-');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    final birthDate = DateTime(year, month, day);
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day))
      age--;
    return age < 18;
  }

  String _formatDateForApi(String date) {
    var parts = date.split('-');
    if (parts.length != 3) return date;
    return '${parts[2]}-${parts[1]}-${parts[0]}';
  }

  String _formatDateFromApi(String date) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(date);
    if (m != null) return '${m.group(3)}-${m.group(2)}-${m.group(1)}';
    return date;
  }

  String _toTitleCase(String s) {
    if (s.isEmpty) return s;
    return s
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  // Fix _onBvnChanged to respect prereqs:
  void _onBvnChanged(String val) {
    _bvnCheckTimer?.cancel();
    _bvnVerifyTimer?.cancel();

    _bvnCheckTimer = Timer(const Duration(milliseconds: 500), () {
      _checkBvnConflict(val);
    });

    final bool prereqsMet =
        _isBvnTierFlow &&
        _firstNameController.text.isNotEmpty &&
        _lastNameController.text.isNotEmpty &&
        _dobController.text.isNotEmpty &&
        selectedGender != null &&
        _isUnder18() != true;

    if (val.length == 11 && prereqsMet) {
      _bvnVerifyTimer = Timer(const Duration(milliseconds: 800), _verifyBvn);
    } else if (_isBvnTierFlow) {
      setState(() {
        _bvnVerified = null;
        _bvnVerifyStatus = null;
        _bvnFieldMatches = null;
      });
    }
  }

  // ------------------------------------------------------------
  //   Firestore listener (restore verified state, prefill)
  // ------------------------------------------------------------
  void _listenForUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _userDocSub?.cancel();
    // Fix _listenForUserData to wrap _bvnFromQore in setState:
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data() ?? <String, dynamic>{};
          if (!mounted) return; // ADD THIS

          final docFn = data['firstName']?.toString() ?? '';
          final docLn = data['lastName']?.toString() ?? '';
          if (_firstNameController.text.isEmpty && docFn.isNotEmpty)
            _firstNameController.text = docFn;
          if (_lastNameController.text.isEmpty && docLn.isNotEmpty)
            _lastNameController.text = docLn;

          final qore = data['qoreIdData'] as Map<String, dynamic>?;
          final bvnVerif =
              qore?['bvnVerificationNoFace'] as Map<String, dynamic>?;
          final bvnFromVerif = bvnVerif?['bvn']?.toString();
          final prefilledBvn = (bvnFromVerif != null && bvnFromVerif.isNotEmpty)
              ? bvnFromVerif
              : data['bvn']?.toString();

          // WRAP IN setState:
          setState(() {
            if (prefilledBvn != null &&
                prefilledBvn.isNotEmpty &&
                _bvnController.text != prefilledBvn) {
              _bvnController.text = prefilledBvn;
              _bvnFromQore = true;
            } else {
              _bvnFromQore = false;
            }
            if (_bvnVerified == null &&
                bvnVerif != null &&
                bvnVerif['verified'] == true) {
              _bvnVerified = true;
              _bvnVerifyStatus = bvnVerif['status']?.toString();
            }
          });

          _populateFieldsFromDoc(data);
          if (prefilledBvn != null && prefilledBvn.isNotEmpty) {
            _checkBvnConflict(prefilledBvn);
          } else {
            _checkBvnConflict('');
          }
        });
  }

  void _populateFieldsFromDoc(Map<String, dynamic>? data) {
    if (data == null) return;

    final dob = data['dateOfBirth']?.toString();
    if (dob != null && dob.isNotEmpty && _dobController.text.isEmpty) {
      _dobController.text = _formatDateFromApi(dob);
    }
    final gender = data['gender']?.toString();
    if (gender != null && gender.isNotEmpty && selectedGender == null) {
      selectedGender = gender;
    }
    final address = data['address'] as Map<String, dynamic>?;
    final street = address?['street']?.toString();
    final city = address?['city']?.toString();
    final state = address?['state']?.toString();
    if (street != null && street.isNotEmpty && _streetController.text.isEmpty)
      _streetController.text = street;
    if (state != null && state.isNotEmpty && selectedState != state) {
      selectedState = state;
      _fetchCities(state);
    }
    if (city != null && city.isNotEmpty && selectedCity != city)
      selectedCity = city;
  }

  Future<void> _checkInitialBvnConflict() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data();
      String? candidate = _bvnController.text.trim();
      if (candidate.isEmpty) candidate = data?['bvn']?.toString();
      if (candidate == null || candidate.isEmpty) {
        final qore = data?['qoreIdData'] as Map<String, dynamic>?;
        final bvnVerif =
            qore?['bvnVerificationNoFace'] as Map<String, dynamic>?;
        candidate = bvnVerif?['bvn']?.toString();
      }
      if (candidate != null && candidate.isNotEmpty)
        await _checkBvnConflict(candidate);
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
          .where('qoreIdData.bvnVerificationNoFace.bvn', isEqualTo: bvn)
          .get();
      final allDocs = <String, QueryDocumentSnapshot>{};
      for (var doc in q1.docs) allDocs[doc.id] = doc;
      for (var doc in q2.docs) allDocs[doc.id] = doc;
      final conflict = allDocs.keys.any((id) => id != user?.uid);
      if (mounted) setState(() => _bvnConflict = conflict);
    } catch (e) {
      print('Error checking BVN conflict: $e');
    }
  }

  // ------------------------------------------------------------
  //   Submission (simplified, but ensure BVN is verified)
  // ------------------------------------------------------------
  Future<String?> _tryMatchExistingCustomerByBvn(
    String? bvn,
    DocumentReference docRef,
    String uid,
  ) async {
    // Kept for compatibility, but not essential for BVN verification UI
    if (bvn == null) return null;
    final bvnToMatch = bvn.replaceAll(RegExp(r'\D'), '').trim();
    if (bvnToMatch.isEmpty) return null;
    try {
      final functions = FirebaseFunctions.instance;
      final fetchRes = await functions
          .httpsCallable('fetchAllCustomers')
          .call();
      final List<dynamic>? customers =
          (fetchRes.data is Map && fetchRes.data['data'] is List)
          ? List<dynamic>.from(fetchRes.data['data'] as List)
          : (fetchRes.data is List
                ? List<dynamic>.from(fetchRes.data as List)
                : null);
      if (customers == null || customers.isEmpty) return null;
      for (var item in customers) {
        try {
          final Map<String, dynamic> it = Map<String, dynamic>.from(
            item as Map,
          );
          final attrs = (it['attributes'] is Map)
              ? Map<String, dynamic>.from(it['attributes'] as Map)
              : {};
          String? itemBvn;
          if (attrs['identificationLevel2'] is Map)
            itemBvn = (attrs['identificationLevel2'] as Map)['bvn']?.toString();
          itemBvn ??= attrs['bvn']?.toString();
          if (itemBvn != null &&
              itemBvn.replaceAll(RegExp(r'\D'), '').trim() == bvnToMatch) {
            final foundId = it['id']?.toString() ?? '';
            await docRef.update({
              'sudoData.customerCreation': {'data': it},
            });
            return foundId;
          }
        } catch (e) {}
      }
    } catch (e) {}
    return null;
  }

  /// Add this method to the class
  Future<String?> _runIdentityVerificationFlow({
    required String bvn,
    required FirebaseFunctions functions,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // Step 1: Check if already verified from a previous webhook
    final existingSetup = await FirebaseFirestore.instance
        .collection('safehavenUserSetup')
        .doc(uid)
        .get();
    final existingData = existingSetup.data();
    final existingStatus = existingData?['identityCheckStatus']?.toString();
    final existingId = existingData?['identityId']?.toString();
    if (existingStatus == 'SUCCESS' &&
        existingId != null &&
        existingId.isNotEmpty) {
      print('Identity already verified via webhook. identityId: $existingId');
      return existingId;
    }

    // Step 2: Initiate — triggers SafeHaven to send OTP to BVN phone
    final HttpsCallable initiateFunc = functions.httpsCallable(
      'safehavenInitiateIdentityVerification',
    );
    await initiateFunc.call({'type': 'BVN', 'number': bvn});

    // Step 3: Show OTP sheet with no gap — queue sheet before hiding loader
    if (!mounted) throw Exception('Widget unmounted after initiate');

    String? otp;
    final otpFuture = Future<String?>.microtask(
      () => _showIdentityOtpBottomSheet(),
    );

    // Hide loading indicator — sheet is already queued
    setState(() => _isLoading = false);
    otp = await otpFuture;

    if (otp == null || otp.isEmpty) {
      throw Exception('Identity verification cancelled: OTP not provided');
    }

    // Step 4: Re-show loading and poll for webhook SUCCESS
    if (mounted) setState(() => _isLoading = true);

    // Step 5: Poll safehavenUserSetup for webhook-confirmed SUCCESS
    // The webhook fires ~1-3s after initiate. By the time the user has
    // typed their OTP (10-30s), the webhook has almost certainly already
    // written SUCCESS to Firestore.
    String? identityId;
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) break;
      final doc = await FirebaseFirestore.instance
          .collection('safehavenUserSetup')
          .doc(uid)
          .get();
      final data = doc.data();
      final status = data?['identityCheckStatus']?.toString();
      final id = data?['identityId']?.toString();
      print('Polling attempt $i: status=$status, identityId=$id');

      if (status == 'SUCCESS' && id != null && id.isNotEmpty) {
        identityId = id;
        print('Webhook confirmed SUCCESS. identityId: $identityId');
        break;
      }

      if (status == 'FAILED' || status == 'DECLINED') {
        throw Exception('Identity verification failed: $status');
      }
    }

    if (identityId == null) {
      throw Exception(
        'Identity verification timed out. Please check your OTP and try again.',
      );
    }

    // Save to user doc
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'safehavenData.identityVerification': {
        'identityId': identityId,
        'type': 'BVN',
        'verified': true,
        'timestamp': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));

    return identityId;
  }

  /// Replace _submit entirely
  Future<void> _submit() async {
    setState(() => _isLoading = true);

    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      showToast('No user logged in', Colors.red);
      setState(() => _isLoading = false);
      return;
    }

    DocumentReference docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid);

    try {
      DocumentSnapshot snap = await docRef.get();
      if (!snap.exists) {
        showToast('User document not found', Colors.red);
        setState(() => _isLoading = false);
        return;
      }
      Map<String, dynamic>? userData = snap.data() as Map<String, dynamic>?;
      if (userData == null) {
        showToast('User data is null', Colors.red);
        setState(() => _isLoading = false);
        return;
      }

      if (_isBvnTierFlow) {
        // ----- Tier 1 & Tier 2: BVN flow -----
        String firstName = _firstNameController.text.trim();
        String lastName = _lastNameController.text.trim();
        String email = userData['email'] ?? '';
        String phoneNumber = (userData['phone'] ?? '')
            .replaceFirst('+234', '')
            .trim();

        if (firstName.isEmpty ||
            lastName.isEmpty ||
            email.isEmpty ||
            phoneNumber.isEmpty) {
          showToast('Missing required user information', Colors.red);
          setState(() => _isLoading = false);
          return;
        }
        if (phoneNumber.length == 10 &&
            RegExp(r'^\d{10}$').hasMatch(phoneNumber)) {
          phoneNumber = '0$phoneNumber';
        }
        if (!RegExp(r'^0\d{10}$').hasMatch(phoneNumber)) {
          showToast('Invalid phone number format', Colors.red);
          setState(() => _isLoading = false);
          return;
        }

        final parts = _dobController.text.split('-');
        final birthDate = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
        if (DateTime.now().difference(birthDate).inDays < 18 * 365) {
          showToast('You must be at least 18 years old', Colors.red);
          setState(() => _isLoading = false);
          return;
        }

        String formattedDob = _formatDateForApi(_dobController.text);
        String gender = selectedGender!;
        String street = _streetController.text;
        String city = selectedCity!;
        String state = selectedState!;
        int postalCode = Random().nextInt(900000) + 100000;

        await docRef.update({
          'firstName': firstName,
          'lastName': lastName,
          'bvn': _bvnController.text,
          'dateOfBirth': formattedDob,
          'gender': gender,
          'address': {
            'street': street,
            'city': city,
            'state': state,
            'country': 'NG',
            'postalCode': postalCode,
          },
        });

        final functions = FirebaseFunctions.instance;
        String? customerId =
            userData['sudoData']?['customerCreation']?['data']?['id']
                ?.toString();

        if (customerId == null) {
          print('➡️ Trying to match existing customer by BVN...');
          final matched = await _tryMatchExistingCustomerByBvn(
            _bvnController.text,
            docRef,
            uid,
          );
          if (matched != null) {
            customerId = matched;
            print('✅ Matched existing customer: $customerId');
          } else {
            print('➡️ Creating new customer via sudoCreateUser...');
            final createResult = await functions
                .httpsCallable('sudoCreateUser')
                .call({
                  'firstName': firstName,
                  'lastName': lastName,
                  'email': email,
                  'country': 'NG',
                  'state': state,
                  'addressLine1': street,
                  'city': city,
                  'postalCode': postalCode,
                  'phoneNumber': phoneNumber,
                });
            customerId = createResult.data['data']['id'];
            await docRef.update({
              'sudoData.customerCreation': createResult.data,
            });
            print('✅ Customer created: $customerId');
          }
        }

        final existingVa = userData['sudoData']?['virtualAccount'];
        if (existingVa != null) {
          // VA already exists — just update tier if needed
          print('Electronic account already exists, skipping creation');
          final currentTier = userData['sudoData']?['tier'];
          if (currentTier != widget.tier) {
            await docRef.update({'sudoData.tier': widget.tier});
          }
        } else if (customerId != null && customerId.isNotEmpty) {
          // Run identity verification via webhook flow (no validate API)
          String? resolvedIdentityId;
          try {
            resolvedIdentityId = await _runIdentityVerificationFlow(
              bvn: _bvnController.text.trim(),
              functions: functions,
            );
          } catch (e) {
            showToast(e.toString().replaceFirst('Exception: ', ''), Colors.red);
            setState(() => _isLoading = false);
            return;
          }

          // Create sub-account — only save tier on confirmed success
          try {
            print('➡️ Creating sub-account via safehavenCreateSubAccount...');
            final accountResult = await functions
                .httpsCallable('safehavenCreateSubAccount')
                .call({
                  'customerId': customerId,
                  'currency': 'NGN',
                  'type': 'IndividualCustomer',
                  'idempotencyKey': const Uuid().v4(),
                  'firstName': firstName,
                  'lastName': lastName,
                  'email': email,
                  'phoneNumber': phoneNumber,
                  'country': 'NG',
                  'state': state,
                  'addressLine1': street,
                  'city': city,
                  'postalCode': postalCode.toString(),
                  'bvn': _bvnController.text.trim(),
                  if (resolvedIdentityId != null &&
                      resolvedIdentityId.isNotEmpty)
                    'identityId': resolvedIdentityId,
                });

            // ✅ Only save tier AFTER confirmed successful VA creation
            await docRef.update({
              'sudoData.virtualAccount': accountResult.data,
              'sudoData.tier': widget.tier,
            });
            print('✅ Sub-account created, tier updated to ${widget.tier}');
          } catch (e, st) {
            print('❌ Error creating sub-account: $e');
            // Check if VA was actually saved despite the error (e.g. network timeout)
            try {
              final verify = await docRef.get();
              final verifyData = verify.data() as Map<String, dynamic>?;
              final verifyVa = verifyData?['sudoData']?['virtualAccount'];
              if (verifyVa != null) {
                // VA exists — safe to save tier now
                await docRef.update({'sudoData.tier': widget.tier});
                print('✅ VA confirmed in Firestore despite error; tier saved');
                // Fall through to success
              } else {
                showToast(
                  'Account setup failed. Please try again.',
                  Colors.red,
                );
                setState(() => _isLoading = false);
                return;
              }
            } catch (_) {
              showToast('Account setup failed. Please try again.', Colors.red);
              setState(() => _isLoading = false);
              return;
            }
          }
        } else {
          print('No customerId available to create electronic account');
        }
      } else {
        // ----- Tier 3: NIN & ID flow -----
        String? customerId =
            userData['sudoData']?['customerCreation']?['data']?['id'];
        if (customerId == null) {
          showToast('Please complete Tier 2 first', Colors.red);
          setState(() => _isLoading = false);
          return;
        }
        await docRef.update({
          'nin': _ninController.text,
          'idType': selectedIdType,
          'idNumber': _idNumberController.text,
          'expiryDate': _formatDateForApi(_expiryController.text),
        });
        await docRef.update({'sudoData.tier': widget.tier});
      }

      showToast('Account upgraded successfully', Colors.green);
      if (mounted) navigateTo(context, HomePage());
    } catch (e, stackTrace) {
      print('❌ ERROR during upgrade: $e');
      print('Stack trace: $stackTrace');
      showToast('Error: ${_getDetailedErrorMessage(e)}', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Enhanced error message that includes the function name if possible.
  String _getDetailedErrorMessage(dynamic e) {
    if (e is FirebaseFunctionsException) {
      // Example: functionsException.code could be "NOT_FOUND", "permission-denied", etc.
      final code = e.code ?? 'unknown';
      final message = e.message ?? 'No details';
      // Try to infer which call failed from the message or code
      if (code == 'NOT_FOUND') {
        if (message.contains('BVN') || message.contains('identity')) {
          return 'NOT_FOUND: BVN verification failed – BVN not registered or invalid';
        } else if (message.contains('customer')) {
          return 'NOT_FOUND: Customer not found – please complete profile first';
        } else {
          return 'NOT_FOUND: $message';
        }
      }
      return '[$code] $message';
    } else if (e is FirebaseException) {
      return '${e.code}: ${e.message}';
    } else {
      return e.toString();
    }
  }

  /// Helper to extract a human‑readable message from any exception.
  String _getErrorMessage(dynamic e) {
    if (e is FirebaseFunctionsException) {
      // Firebase Functions exceptions usually have a message and optional details
      return e.message ?? 'Firebase function error (code: ${e.code})';
    } else if (e is FirebaseException) {
      return e.message ?? 'Firebase error: ${e.code}';
    } else if (e is Exception) {
      return e.toString().replaceFirst('Exception: ', '');
    } else if (e is String) {
      return e;
    } else {
      return 'An unknown error occurred';
    }
  }

  Future<String?> _showIdentityOtpBottomSheet() async {
    final otpController = TextEditingController();
    String? errorText;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setModalState) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Verify Your Identity',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'An OTP has been sent to your registered phone number. Enter it below.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Enter OTP',
                      counterText: '',
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        final otp = otpController.text.trim();
                        if (otp.length < 4) {
                          setModalState(
                            () => errorText = 'Please enter a valid OTP',
                          );
                          return;
                        }
                        Navigator.pop(ctx, otp);
                      },
                      child: const Text(
                        'Verify',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    otpController.dispose();
    return result;
  }

  // ------------------------------------------------------------
  //   UI Build – now with full BVN verification and field locking
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // In build(), add this before isFormValid:
    final bool bvnPrereqsMet =
        _isBvnTierFlow &&
        _firstNameController.text.isNotEmpty &&
        _lastNameController.text.isNotEmpty &&
        _dobController.text.isNotEmpty &&
        selectedGender != null &&
        _isUnder18() != true;
    // Determine if form is valid (BVN verified + all required fields)
    bool isFormValid = false;
    if (_isBvnTierFlow) {
      isFormValid =
          _bvnController.text.isNotEmpty &&
          _bvnVerified == true &&
          _firstNameController.text.isNotEmpty &&
          _lastNameController.text.isNotEmpty &&
          _dobController.text.isNotEmpty &&
          _streetController.text.isNotEmpty &&
          selectedState != null &&
          selectedCity != null &&
          selectedGender != null &&
          _isUnder18() != true;
    } else {
      isFormValid =
          _ninController.text.isNotEmpty &&
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
              const SizedBox(height: 20),
              Row(
                children: [
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.arrow_back_ios,
                      color: Colors.black54,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Text(
                _isIdentityVerificationStep
                    ? 'Verify Your Identity'
                    : 'Complete Your Profile',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isIdentityVerificationStep
                    ? 'Confirm your BVN details, verify the OTP sent to your phone, and activate your wallet.'
                    : 'To comply with CBN guidelines, we are required to verify every customer.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              if (_isBvnTierFlow)
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
                        if (await canLaunchUrl(callUri))
                          await launchUrl(callUri);
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
              // if (_bvnVerified == true) ...[
              //   Container(
              //     width: double.infinity,
              //     padding: const EdgeInsets.all(16),
              //     margin: const EdgeInsets.only(bottom: 20),
              //     decoration: BoxDecoration(
              //       color: Colors.green.shade50,
              //       borderRadius: BorderRadius.circular(12),
              //       border: Border.all(color: Colors.green.shade200),
              //     ),
              //     child: Row(
              //       children: [
              //         Icon(
              //           Icons.check_circle,
              //           color: Colors.green.shade600,
              //           size: 24,
              //         ),
              //         const SizedBox(width: 12),
              //         Expanded(
              //           child: Column(
              //             crossAxisAlignment: CrossAxisAlignment.start,
              //             children: [
              //               Text(
              //                 'BVN Verified ✓',
              //                 style: TextStyle(
              //                   fontWeight: FontWeight.bold,
              //                   color: Colors.green.shade800,
              //                   fontSize: 16,
              //                 ),
              //               ),
              //               Text(
              //                 'Your BVN is verified and cannot be changed.',
              //                 style: TextStyle(
              //                   color: Colors.green.shade700,
              //                   fontSize: 14,
              //                 ),
              //               ),
              //             ],
              //           ),
              //         ),
              //       ],
              //     ),
              //   ),
              // ],
              const SizedBox(height: 20),
              // First Name – shown for Tier 1 AND Tier 2
              if (_isBvnTierFlow) ...[
                Text(
                  'First Name',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _firstNameController,
                  readOnly: _bvnVerified == true,
                  onChanged: _bvnVerified == true
                      ? null
                      : (val) {
                          if (_bvnVerified != null)
                            setState(() {
                              _bvnVerified = null;
                              _bvnVerifyStatus = null;
                              _bvnFieldMatches = null;
                            });
                        },
                  decoration: InputDecoration(
                    hintText: 'First name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnFieldMatches?['firstname'] == false
                            ? Colors.red.shade400
                            : Colors.grey.shade200,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnFieldMatches?['firstname'] == false
                            ? Colors.red.shade400
                            : Colors.grey.shade200,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnFieldMatches?['firstname'] == false
                            ? Colors.red
                            : primaryColor,
                        width: 2,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnFieldMatches?['firstname'] == false
                            ? Colors.red.shade400
                            : Colors.grey.shade200,
                      ),
                    ),
                    suffixIcon: _bvnVerified == true
                        ? Icon(Icons.lock_outline, color: Colors.grey.shade500)
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
                if (_bvnFieldMatches?['firstname'] == false)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 13,
                          color: Colors.red.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'First name does not match BVN records',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Last Name',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _lastNameController,
                  readOnly: _bvnVerified == true,
                  onChanged: _bvnVerified == true
                      ? null
                      : (val) {
                          if (_bvnVerified != null)
                            setState(() {
                              _bvnVerified = null;
                              _bvnVerifyStatus = null;
                              _bvnFieldMatches = null;
                            });
                        },
                  decoration: InputDecoration(
                    hintText: 'Last name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnFieldMatches?['lastname'] == false
                            ? Colors.red.shade400
                            : Colors.grey.shade200,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnFieldMatches?['lastname'] == false
                            ? Colors.red.shade400
                            : Colors.grey.shade200,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnFieldMatches?['lastname'] == false
                            ? Colors.red
                            : primaryColor,
                        width: 2,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnFieldMatches?['lastname'] == false
                            ? Colors.red.shade400
                            : Colors.grey.shade200,
                      ),
                    ),
                    suffixIcon: _bvnVerified == true
                        ? Icon(Icons.lock_outline, color: Colors.grey.shade500)
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
                if (_bvnFieldMatches?['lastname'] == false)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 13,
                          color: Colors.red.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Last name does not match BVN records',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                // Date of Birth
                Text(
                  'Date of Birth',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _dobController,
                  readOnly: true,
                  onTap: _bvnVerified == true
                      ? null
                      : () => _selectDob(context),
                  decoration: InputDecoration(
                    hintText: 'DD-MM-YYYY',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnFieldMatches?['birthdate'] == false
                            ? Colors.red.shade400
                            : Colors.grey.shade200,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnFieldMatches?['birthdate'] == false
                            ? Colors.red.shade400
                            : Colors.grey.shade200,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnFieldMatches?['birthdate'] == false
                            ? Colors.red
                            : primaryColor,
                        width: 2,
                      ),
                    ),
                    suffixIcon: Icon(
                      Icons.calendar_today,
                      color: Colors.grey.shade500,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
                if (_bvnFieldMatches?['birthdate'] == false)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 13,
                          color: Colors.red.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Date of birth does not match BVN records',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_isUnder18() == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 13,
                          color: Colors.red.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'You must be 18 or older to upgrade',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                // Gender
                Text(
                  'Gender',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: _bvnFieldMatches?['gender'] == false
                          ? Colors.red.shade400
                          : Colors.grey.shade200,
                    ),
                  ).toBoxDecoration(),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedGender,
                      isExpanded: true,
                      hint: Text(
                        'Select Gender',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      items: ['Male', 'Female', 'Others']
                          .map(
                            (g) => DropdownMenuItem(value: g, child: Text(g)),
                          )
                          .toList(),
                      onChanged: _bvnVerified == true
                          ? null
                          : (val) {
                              setState(() => selectedGender = val);
                              if (_bvnVerified != null)
                                setState(() => _bvnVerified = null);
                            },
                    ),
                  ),
                ),
                if (_bvnFieldMatches?['gender'] == false)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 13,
                          color: Colors.red.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Gender does not match BVN records',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                // BVN field with verification indicator
                Text(
                  'BVN',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  maxLength: 11,
                  controller: _bvnController,
                  keyboardType: TextInputType.number,
                  // Fix BVN TextField readOnly:
                  readOnly:
                      _bvnFromQore || _bvnVerified == true || (!bvnPrereqsMet),
                  onChanged: _bvnVerified == true ? null : _onBvnChanged,
                  decoration: InputDecoration(
                    counterText: "",
                    // Fix BVN hint text:
                    hintText: _bvnFromQore
                        ? 'BVN (verification provided)'
                        : !bvnPrereqsMet
                        ? 'Fill in name, date of birth & gender first'
                        : 'Enter BVN',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnVerified == true
                            ? Colors.green
                            : (_bvnVerified == false
                                  ? Colors.red.shade300
                                  : Colors.grey.shade200),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnVerified == true
                            ? Colors.green
                            : (_bvnVerified == false
                                  ? Colors.red.shade300
                                  : Colors.grey.shade200),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnVerified == true
                            ? Colors.green
                            : (_bvnVerified == false
                                  ? Colors.red
                                  : primaryColor),
                        width: 2,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _bvnVerified == true
                            ? Colors.green
                            : Colors.grey.shade200,
                      ),
                    ),
                    suffixIcon: _bvnVerifying
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  primaryColor,
                                ),
                              ),
                            ),
                          )
                        : _bvnVerified == true
                        ? Icon(Icons.check_circle, color: Colors.green)
                        : (_bvnVerified == false
                              ? Icon(Icons.cancel, color: Colors.red)
                              : null),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (_bvnVerifying)
                  Text(
                    'Verifying BVN, please wait...',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  )
                else if (_bvnVerified == true)
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 14,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'BVN verified',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  )
                // Add retry button after BVN failed status row:
                else if (_bvnVerified == false)
                  Row(
                    children: [
                      Icon(
                        Icons.cancel_outlined,
                        size: 14,
                        color: Colors.red.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _bvnVerifyStatus ?? 'Unable to verify BVN',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                      // ADD THIS:
                      if (bvnPrereqsMet && _bvnController.text.length == 11)
                        GestureDetector(
                          onTap: _verifyBvn,
                          child: Text(
                            'Retry',
                            style: TextStyle(
                              fontSize: 12,
                              color: primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 20),
                // Address fields
                Text(
                  'Street Address',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _streetController,
                  readOnly: _bvnVerified == true,
                  onChanged: _bvnVerified == true
                      ? null
                      : (val) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Enter Street Address',
                    suffixIcon: _buildLocationIcon(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'State',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ).toBoxDecoration(),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedState,
                      isExpanded: true,
                      hint: Text(
                        'Select State',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      items: states
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: _bvnVerified == true
                          ? null
                          : (val) {
                              setState(() {
                                selectedState = val;
                                selectedCity = null;
                              });
                              if (val != null) _fetchCities(val);
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'City / LGA',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ).toBoxDecoration(),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedCity,
                      isExpanded: true,
                      hint: Text(
                        'Select City',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      items: cities
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: _bvnVerified == true
                          ? null
                          : (val) => setState(() => selectedCity = val),
                    ),
                  ),
                ),
              ] else ...[
                // Tier 3 – NIN & ID fields (unchanged)
                Text(
                  'NIN',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  maxLength: 11,
                  controller: _ninController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    counterText: "",
                    hintText: 'Enter NIN (11 digits)',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'ID Type',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ).toBoxDecoration(),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedIdType,
                      isExpanded: true,
                      hint: Text(
                        'Select ID Type',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      items:
                          [
                                'PASSPORT',
                                'DRIVERS_LICENSE',
                                'VOTERS_CARD',
                                'NATIONAL_ID',
                              ]
                              .map(
                                (id) => DropdownMenuItem(
                                  value: id,
                                  child: Text(id),
                                ),
                              )
                              .toList(),
                      onChanged: (val) => setState(() => selectedIdType = val),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'ID Number',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _idNumberController,
                  decoration: InputDecoration(hintText: 'Enter ID Number'),
                ),
                const SizedBox(height: 20),
                Text(
                  'Expiry Date',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _expiryController,
                  readOnly: true,
                  onTap: () => _selectExpiry(context),
                  decoration: InputDecoration(
                    hintText: 'DD-MM-YYYY',
                    suffixIcon: Icon(
                      Icons.calendar_today,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
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
                          _isIdentityVerificationStep
                              ? 'Verify and Continue'
                              : 'Upgrade Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 40),
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
        _bvnFieldMatches = null;
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
      setState(() => _expiryController.text = formattedDate);
    }
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    _bvnCheckTimer?.cancel();
    _bvnVerifyTimer?.cancel();
    _bvnController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _dobController.dispose();
    _streetController.dispose();
    _ninController.dispose();
    _idNumberController.dispose();
    _expiryController.dispose();
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
