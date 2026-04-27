import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ui/permission_explanation_sheet.dart';
import 'package:padi_pay_business/add_first_pos_stand.dart';
import 'package:padi_pay_business/utils.dart';
import 'dart:io';

class RepresentativeDetails extends StatefulWidget {
  const RepresentativeDetails({super.key});

  @override
  State<RepresentativeDetails> createState() => _RepresentativeDetailsState();
}

class _RepresentativeDetailsState extends State<RepresentativeDetails> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _bvnController = TextEditingController();
  bool _isLoading = false;
  bool _isUploading = false;
  File? _idFile;
  double _uploadProgress = 0.0;
  String? _uploadedFileName;
  String? _idUrl;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        var doc = await FirebaseFirestore.instance.collection('businesses').doc(user.uid).get();
        if (doc.exists) {
          var data = doc.data()!;
          _fullNameController.text = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
          _dobController.text = data['dateOfBirth'] ?? '';
          _phoneController.text = data['businessPhone'] ?? '';
          _emailController.text = data['businessEmail'] ?? '';
          _bvnController.text = data['bvn'] ?? '';
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching data: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickId() async {
    // Only show explanation if permission not already granted
    bool granted = false;
    // Permission.photos is iOS, Permission.storage is Android
    try {
      if (Platform.isIOS) {
        granted = await Permission.photos.isGranted;
      } else {
        granted = await Permission.storage.isGranted;
      }
    } catch (_) {}
    if (!granted) {
      final proceed = await showPermissionExplanationSheet(
        context,
        title: 'Photo Access Required',
        explanation: 'We need access to your photos to let you upload a valid ID image for verification. Your image will only be used for this purpose.',
        confirmText: 'Allow',
        cancelText: 'Not Now',
      );
      if (proceed != true) return;
    }
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _idFile = File(pickedFile.path);
        _uploadedFileName = null;
        _uploadProgress = 0.0;
        _idUrl = null;
        _isUploading = true;
      });
      String? url = await _uploadId();
      setState(() {
        _isUploading = false;
      });
      if (url != null) {
        setState(() {
          _idUrl = url;
          _uploadedFileName = _idFile!.path.split('/').last;
        });
      }
    }
  }

  Future<String?> _uploadId() async {
    if (_idFile == null) return null;
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final ref = FirebaseStorage.instance.ref('business_ids/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      final uploadTask = ref.putFile(_idFile!);
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        setState(() {
          _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
        });
      });
      await uploadTask;
      return await ref.getDownloadURL();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      return null;
    }
  }

  Future<void> _saveDetails() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'User not logged in';
      await FirebaseFirestore.instance.collection('businesses').doc(user.uid).update({
        'repFullName': _fullNameController.text.trim(),
        'repDob': _dobController.text.trim(),
        'repPhone': _phoneController.text.trim(),
        'repEmail': _emailController.text.trim(),
        'repBvn': _bvnController.text.trim(),
        if (_idUrl != null) 'repIdUrl': _idUrl,
      });
      navigateTo(context, AddPosStand());
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving details: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _dobController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Image.asset("assets/weird_img.png", width: double.infinity),
              Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          "Representative Details",
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
                          child: Text(
                            "Confirm who manages this account.",
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 15,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 30),
                    Text(
                      "Full Name",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    TextField(
                      controller: _fullNameController,
                      decoration: InputDecoration(
                        hintText: "Enter full name",
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
                    SizedBox(height: 20),
                    Text(
                      "Date of Birth",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    TextField(
                      controller: _dobController,
                      readOnly: true,
                      onTap: _selectDate,
                      decoration: InputDecoration(
                        hintText: "Enter date of birth",
                        suffixIcon: Icon(
                          Icons.calendar_month,
                          color: Colors.black38,
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
                    SizedBox(height: 20),
                    Text(
                      "Phone Number",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    TextField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        hintText: "Enter phone number",
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
                    SizedBox(height: 20),
                    Text(
                      "Email Address",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: "Enter email address",
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
                    SizedBox(height: 20),
                    Text(
                      "BVN",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    TextField(
                      controller: _bvnController,
                      decoration: InputDecoration(
                        hintText: "Enter BVN",
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
                    SizedBox(height: 20),
                    Text(
                      "Upload ID",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    GestureDetector(
                      onTap: _pickId,
                      child: DottedBorder(
                        options: RectDottedBorderOptions(
                          color: Colors.grey,
                          strokeWidth: 1,
                          dashPattern: [6, 3],
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.cloud_upload, color: Colors.grey),
                              SizedBox(width: 10),
                              Text(
                                "Click to Upload",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_idFile != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _uploadedFileName ?? _idFile!.path.split('/').last,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                if (_uploadProgress == 1.0)
                                  Icon(
                                    Icons.check_circle,
                                    color: primaryColor,
                                    size: 20,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "${(_idFile!.lengthSync() / 1024).toStringAsFixed(0)}KB",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w300,
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: LinearProgressIndicator(
                                    borderRadius: BorderRadius.circular(20),
                                    value: _uploadProgress,
                                    valueColor: AlwaysStoppedAnimation(primaryColor),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  "${(_uploadProgress * 100).toStringAsFixed(0)}%",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 30),
                    GestureDetector(
                      onTap: (_isUploading || _isLoading) ? null : _saveDetails,
                      child: Container(
                        alignment: Alignment.center,
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: (_isUploading || _isLoading) ? Colors.grey : primaryColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        width: MediaQuery.of(context).size.width,
                        child: _isLoading
                            ? CircularProgressIndicator(color: Colors.white)
                            : Text(
                                "Next",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(height: 20),
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