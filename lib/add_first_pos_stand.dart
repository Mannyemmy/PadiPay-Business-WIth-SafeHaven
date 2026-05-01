import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:padi_pay_business/feedback.dart';
import 'package:padi_pay_business/ui/permission_explanation_sheet.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AddPosStand extends StatefulWidget {
  const AddPosStand({super.key});

  @override
  State<AddPosStand> createState() => _AddPosStandState();
}

class _AddPosStandState extends State<AddPosStand> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _loginEmailController = TextEditingController();
  final TextEditingController _loginPasswordController =
      TextEditingController();
  bool _isLoading = false;
  List<dynamic> _posStands = [];
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    super.dispose();
  }

  /// Returns (businessData, ownerBusinessId, customerId, accountType)
  /// Returns (businessData, ownerBusinessId, customerId, accountType)
  Future<(Map<String, dynamic>?, String?, String?, String?)> _getBusinessData(
    String uid,
  ) async {
    try {
      Map<String, dynamic>? finalData;
      String? ownerBusinessId = uid;
      String? customerId;
      String? accountType = 'IndividualCustomer';

      // 1. Check businesses collection
      final businessDoc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(uid)
          .get();

      if (businessDoc.exists) {
        finalData = Map<String, dynamic>.from(businessDoc.data() ?? {});
        ownerBusinessId = uid;
      }

      // 2. Check users collection (for sudo data + customer type)
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() ?? {};

        // Handle POS stand user case
        final String? parentBusinessId = userData['parentBusinessId']
            ?.toString();
        if (parentBusinessId != null && parentBusinessId.isNotEmpty) {
          final parentDoc = await FirebaseFirestore.instance
              .collection('businesses')
              .doc(parentBusinessId)
              .get();
          if (parentDoc.exists) {
            finalData = Map<String, dynamic>.from(parentDoc.data() ?? {});
            ownerBusinessId = parentBusinessId;
          }
        }

        // Merge data
        if (finalData == null) {
          finalData = Map<String, dynamic>.from(userData);
        } else if (finalData['sudoData'] == null) {
          finalData['sudoData'] = userData['sudoData'];
        }

        // Determine customerId
        customerId =
            finalData['sudoData']?['kybCreation']?['data']?['id'] ??
            finalData['sudoData']?['customerCreation']?['data']?['id'];

        // Determine accountType based on customerId
        if (customerId != null) {
          if (customerId.contains('anc_ind_cst') ||
              customerId.contains('_ind_')) {
            accountType = 'IndividualCustomer';
          } else if (customerId.contains('anc_bus_cst') ||
              customerId.contains('_bus_')) {
            accountType = 'BusinessCustomer';
          }
        }

        // Explicit type fallback
        if (accountType == 'IndividualCustomer' &&
            (userData['customerType'] == 'Business' ||
                userData['accountType'] == 'BusinessCustomer')) {
          accountType = 'BusinessCustomer';
        }
      }

      // Final customerId fallback
      if (customerId == null && finalData != null) {
        customerId = finalData['customerId'] ?? finalData['sudoCustomerId'];
      }

      print(
        '✅ Final - CustomerID: $customerId | AccountType: $accountType | Owner: $ownerBusinessId',
      );

      return (finalData, ownerBusinessId, customerId, accountType);
    } catch (e) {
      debugPrint('Error in _getBusinessData: $e');
      return (null, null, null, null);
    }
  }

  /// After creating the electronic account, we immediately fetch the real
  /// account number & bank name and enrich the accountData map (in place).
  /// After creating the electronic account, we immediately fetch the real
  /// account number & bank name and enrich the accountData map (in place).
  /// After creating the electronic account, we immediately fetch the real
  /// account number & bank name and enrich the accountData map (in place).
  Future<void> _fetchAndEnrichAccountData(
    Map<String, dynamic> accountData,
  ) async {
    try {
      final accountId = accountData['data']?['id']?.toString();
      if (accountId == null) {
        debugPrint(
          'fetchAndEnrichAccountData: accountId not found in response',
        );
        return;
      }

      print('Calling sudoFetchAccountNumber for accountId: $accountId');

      final callable = FirebaseFunctions.instance.httpsCallable(
        'sudoFetchAccountNumber',
      );
      final result = await callable.call({'accountId': accountId});
      print('sudoFetchAccountNumber response: ${result.data}');

      dynamic resp = result.data;
      String? accountNumber;
      String? bankName;

      if (resp is Map) {
        // Safe handling for both web and mobile (Map<Object?, Object?>)
        final safeResp = Map<String, dynamic>.from(resp);

        // Try multiple possible paths where the data might be
        accountNumber =
            safeResp['accountNumber']?.toString() ??
            safeResp['data']?['attributes']?['accountNumber']?.toString() ??
            safeResp['data']?['accountNumber']?.toString() ??
            safeResp['account']?['number']?.toString();

        // Bank name parsing
        if (safeResp['bank'] != null) {
          if (safeResp['bank'] is Map) {
            final bankMap = Map<String, dynamic>.from(safeResp['bank'] as Map);
            bankName = bankMap['name']?.toString();
          } else {
            bankName = safeResp['bank']?.toString();
          }
        }
        bankName ??=
            safeResp['data']?['attributes']?['bank']?['name']?.toString() ??
            safeResp['bankName']?.toString() ??
            safeResp['data']?['bank']?['name']?.toString();
      }

      if (accountNumber == null && bankName == null) {
        print('sudoFetchAccountNumber: no accountNumber or bank found in response');
        // Even if function says "not found", try to extract from the raw response anyway
        print('Raw response was: $resp');
        return;
      }

      // Enrich the original accountData
      accountData['data'] ??= <String, dynamic>{};
      final dataMap = accountData['data'] as Map<String, dynamic>;

      dataMap['attributes'] ??= <String, dynamic>{};
      final attributesMap = dataMap['attributes'] as Map<String, dynamic>;

      if (accountNumber != null) {
        attributesMap['accountNumber'] = accountNumber;
      }
      if (bankName != null) {
        attributesMap['bank'] = {'name': bankName};
      }

      print(
        '✅ Successfully enriched accountData with accountNumber: $accountNumber | bank: $bankName',
      );
    } catch (e) {
      debugPrint('Error in _fetchAndEnrichAccountData: $e');

      // Extra debug: print the full error if it's "Account number not found"
      if (e.toString().contains('Account number not found')) {
        print(
          '⚠️ Cloud Function returned "Account number not found". '
          'This usually means the accountId is not yet ready in the backend '
          'or the function has a small delay issue.',
        );
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final (data, _, _, _) = await _getBusinessData(user.uid);
      _posStands = List.from(data?['posStands'] ?? []);
    } catch (e) {
      debugPrint('Error loading posStands: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    // ... (unchanged)
    // Privacy consent gate — location
    final prefs = await SharedPreferences.getInstance();
    final alreadyConsented = prefs.getBool('privacy_consent_location') ?? false;
    if (!alreadyConsented) {
      if (!mounted) return;
      final result = await showPermissionExplanationSheet(
        context,
        title: 'Location Permission Required',
        explanation:
            'PadiPay needs access to your location to auto-fill your business address. Your location data is used only for this purpose and is not shared with third parties.',
      );
      if (result != true) return;
      await prefs.setBool('privacy_consent_location', true);
    }
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
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
            content: Text(
              'Location permissions are permanently denied. Opening app settings.',
            ),
          ),
        );
        await Geolocator.openAppSettings();
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
        String address =
            '${place.street ?? ''}, ${place.locality ?? ''}, ${place.postalCode ?? ''}, ${place.country ?? ''}';
        setState(() {
          _locationController.text = address.trim();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
    }
  }

  Future<void> _handleNext() async {
    if (_isLoading) return;

    if (_nameController.text.trim().isEmpty ||
        _locationController.text.trim().isEmpty ||
        _loginEmailController.text.trim().isEmpty ||
        _loginPasswordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'User not logged in';

      final (businessData, ownerBusinessId, customerId, accountType) =
          await _getBusinessData(user.uid);

      if (businessData == null ||
          ownerBusinessId == null ||
          customerId == null ||
          accountType == null) {
        throw 'Missing business or customer data. Please complete tier upgrade first.';
      }

      print(
        '✅ Creating electronic account with type: $accountType for customer: $customerId',
      );

      // 1. Create Electronic Account
      final functions = FirebaseFunctions.instance;
      final createAccountFunc = functions.httpsCallable(
        'safehavenCreateSubAccount',
      );
      final idempotencyKey = const Uuid().v4();

      final accountResult = await createAccountFunc.call({
        'customerId': customerId,
        'currency': 'NGN',
        'type': accountType,
        'idempotencyKey': idempotencyKey,
      });

      // Safe conversion of response
      Map<String, dynamic> accountData = (accountResult.data is Map)
          ? Map<String, dynamic>.from(accountResult.data as Map)
          : <String, dynamic>{};

      // 2. Enrich with real account number & bank name
      await _fetchAndEnrichAccountData(accountData);

      // 3. Create Stand User
      final standEmail = _loginEmailController.text.trim();
      final standPassword = _loginPasswordController.text.trim();
      final standId = const Uuid().v4();

      try {
        await functions.httpsCallable('createStandUser').call({
          'email': standEmail,
          'password': standPassword,
          'parentBusinessId': ownerBusinessId,
          'standId': standId,
        });
        print('✅ Stand user created successfully');
      } catch (e) {
        if (e.toString().contains('already in use')) {
          debugPrint('Stand email already exists - continuing with creation');
        } else {
          debugPrint('Stand user creation warning: $e');
        }
      }

      // 4. Build new stand with enriched accountData
      final newStand = {
        'name': _nameController.text.trim(),
        'location': _locationController.text.trim(),
        'accountData': accountData, // Enriched version
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'standId': standId,
        'standLoginEmail': standEmail,
        'standLoginPassword': standPassword,
        'parentBusinessId': ownerBusinessId,
      };

      // 5. Add to existing posStands and save
      List<dynamic> posStands = List.from(businessData['posStands'] ?? []);
      posStands.add(newStand);

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(ownerBusinessId)
          .set({'posStands': posStands}, SetOptions(merge: true));

      showSnackBar(context, "POS Stand created successfully", Colors.green);
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Error in _handleNext: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Image.asset("assets/imgg.png", width: double.infinity),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    const Row(
                      children: [
                        Text(
                          "Add POS Stand",
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: const Text(
                            "Register where you'll accept payments.",
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 15,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      "Stand Name",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: "POS Stand 1",
                        hintStyle: const TextStyle(color: Colors.black38),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Stand Location",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      controller: _locationController,
                      decoration: InputDecoration(
                        hintText: "Enter location",
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.location_on,
                            color: primaryColor,
                          ),
                          onPressed: _getCurrentLocation,
                        ),
                        hintStyle: const TextStyle(color: Colors.black38),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Stand Login Email",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      controller: _loginEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: "stand@example.com",
                        hintStyle: const TextStyle(color: Colors.black38),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Stand Login Password",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.done,
                      controller: _loginPasswordController,
                      obscureText: !_isPasswordVisible,
                      decoration: InputDecoration(
                        hintText: "Enter a password",
                        hintStyle: const TextStyle(color: Colors.black38),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.black38,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "A new account number will be generated for this POS Stand.",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 15),
                    GestureDetector(
                      onTap: _handleNext,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        width: MediaQuery.of(context).size.width,
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                "Save",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
