import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:padi_pay_business/ui/permission_explanation_sheet copy.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BusinessDocs extends StatefulWidget {
  const BusinessDocs({super.key});

  @override
  State<BusinessDocs> createState() => _BusinessDocsState();
}

class _BusinessDocsState extends State<BusinessDocs> {
  List<GlobalKey<_DocumentUploadFormState>> docKeys = [];
  List<Map<String, dynamic>> requiredDocuments = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => isLoading = false);
      return;
    }

    final fsDoc = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(user.uid)
        .get();

    if (!fsDoc.exists || fsDoc.data() == null) {
      setState(() => isLoading = false);
      return;
    }

    final data = fsDoc.data()!;

    final raw = data['requiredDocuments'];

    if (raw is List) {
      requiredDocuments = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } else if (raw is Map) {
      final map = raw;
      final List<Map<String, dynamic>> fixed = [];
      for (int i = 0; map.containsKey(i.toString()); i++) {
        fixed.add(Map<String, dynamic>.from(map[i.toString()] as Map));
      }
      requiredDocuments = fixed;
      fsDoc.reference.update({'requiredDocuments': fixed});
    } else {
      requiredDocuments = [];
    }

    docKeys = List.generate(
      requiredDocuments.length,
      (_) => GlobalKey<_DocumentUploadFormState>(),
    );

    setState(() => isLoading = false);

    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (int i = 0; i < requiredDocuments.length; i++) {
        final type = requiredDocuments[i]['type'] as String;
        final saved = data[type] as Map<String, dynamic>?;
        if (saved != null) {
          docKeys[i].currentState?.setUploaded(
            saved['path'] as String?,
            saved['name'] as String?,
            saved['textData'] as String?,
          );
        }
      }
    });
  }

  Future<void> _markAsFixed() async {
    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .set({'docs_fixed': true}, SetOptions(merge: true));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Business Documents",
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : requiredDocuments.isEmpty
              ? const Center(child: Text("No documents required"))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: requiredDocuments.length,
                  itemBuilder: (context, index) {
                    return DocumentUploadForm(
                      key: docKeys[index],
                      docType: requiredDocuments[index]['type'] as String,
                      description:
                          requiredDocuments[index]['description'] as String? ?? '',
                    );
                  },
                ),
      bottomNavigationBar: requiredDocuments.isNotEmpty && !isLoading
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _markAsFixed,
                child: Text(
                  "Save",
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            )
          : null,
    );
  }
}

class DocumentUploadForm extends StatefulWidget {
  const DocumentUploadForm({
    super.key,
    required this.docType,
    required this.description,
  });

  final String docType;
  final String description;

  @override
  State<DocumentUploadForm> createState() => _DocumentUploadFormState();
}

class _DocumentUploadFormState extends State<DocumentUploadForm> {
  String? selectedFilePath;
  String? selectedFileName;
  String? uploadedPath;
  String? textData;

  double _progress = 0.0;
  bool _uploadCompleted = false;

  void setUploaded(String? path, String? name, [String? textData]) {
    setState(() {
      uploadedPath = path;
      selectedFileName = name;
      this.textData = textData;
      _uploadCompleted = true;
    });
  }

  void updateProgress(double progress, {bool completed = false}) {
    setState(() {
      _progress = progress;
      _uploadCompleted = completed || progress >= 1.0;
    });
  }

  bool _isTextOnly() {
    return widget.docType.toLowerCase().contains('number');
  }

  String _getLabel() {
    final lower = widget.docType.toLowerCase();
    if (lower.contains('rc')) return 'RC Number';
    if (lower.contains('bn')) return 'BN Number';
    if (lower.contains('de')) return 'DE Number';
    if (lower.contains('tin')) return 'TIN';
    return 'Number';
  }

  String _getPrefix() {
    final lower = widget.docType.toLowerCase();
    if (lower.contains('rc')) return 'RC';
    if (lower.contains('bn')) return 'BN';
    if (lower.contains('de')) return 'DE';
    if (lower.contains('tin')) return '';
    return '';
  }

  Future<bool> _ensureCameraGalleryConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final cameraConsented = prefs.getBool('privacy_consent_camera') ?? false;
    final galleryConsented = prefs.getBool('privacy_consent_gallery') ?? false;
    if (cameraConsented && galleryConsented) return true;
    bool consented = false;
    await showModalBottomSheet(
      context: context,
      isDismissible: true,
      builder: (ctx) => PermissionExplanationSheet(
        type: PermissionType.camera,
        onContinue: () async {
          await prefs.setBool('privacy_consent_camera', true);
          await prefs.setBool('privacy_consent_gallery', true);
          Navigator.of(ctx).pop();
          consented = true;
        },
      ),
    );
    return consented;
  }

  Future<void> _handleUpload() async {
    final isTextOnly = _isTextOnly();
    final label = _getLabel();

    if (isTextOnly) {
      final controller = TextEditingController(
        text: textData?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
      );

      final prefix = _getPrefix();
      final isBN = prefix == 'BN';
      final isDE = prefix == 'DE';
      final int? maxDigits = isBN || isDE ? 8 : null;

      // Truncate old invalid values on edit
      if (maxDigits != null && controller.text.length > maxDigits) {
        controller.text = controller.text.substring(0, maxDigits);
      }

      String hintText = 'Enter digits only';
      if (isBN) {
        hintText = 'Enter 6-8 digits';
      } else if (isDE) hintText = 'Enter 5-8 digits';

      final String? numericPart = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (BuildContext _, StateSetter dialogSetState) {
            String? dialogError;

            return AlertDialog(
              title: Text('Enter $label'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      if (maxDigits != null)
                        LengthLimitingTextInputFormatter(maxDigits),
                    ],
                    decoration: InputDecoration(
                      hintText: hintText,
                      errorText: dialogError,
                      errorMaxLines: 2,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    final entered = controller.text.trim();

                    String? err;
                    if (entered.isEmpty) {
                      err = 'This field is required';
                    } else {
                      final len = entered.length;
                      if (isBN && len < 6) {
                        err = 'BN Number requires at least 6 digits';
                      } else if (isDE && len < 5) {
                        err = 'DE Number requires at least 5 digits';
                      }
                    }

                    if (err != null) {
                      dialogSetState(() => dialogError = err);
                      return;
                    }

                    Navigator.pop(dialogContext, entered);
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        ),
      );

      if (numericPart == null) return;

      String fullText = prefix + numericPart;
      if (prefix.isNotEmpty) fullText = fullText.toUpperCase();

      final saveData = {
        'textData': fullText,
      };

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(user.uid)
          .set({widget.docType: saveData}, SetOptions(merge: true));

      setState(() {
        uploadedPath = null;
        selectedFileName = null;
        textData = fullText;
        _uploadCompleted = true;
        _progress = 1.0;
      });
    } else {
      // Show dialog with options to take photo or select file
      final consented = await _ensureCameraGalleryConsent();
      if (!consented) return;
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Select Source'),
          content: const Text('Choose how to upload your document'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ImageSource.camera),
              child: const Text('Take Photo'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ImageSource.gallery),
              child: const Text('Select File'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (source == null) return;

      String? path;
      String? name;

      if (source == ImageSource.camera) {
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(source: ImageSource.camera);
        if (image == null) return;
        path = image.path;
        name = image.name;
      } else {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'gif'],
        );
        if (result == null) return;
        path = result.files.single.path;
        name = result.files.single.name;
      }

      if (path == null) return;

      setState(() {
        selectedFilePath = path;
        selectedFileName = name;
        _progress = 0.0;
        _uploadCompleted = false;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          selectedFilePath = null;
          selectedFileName = null;
        });
        return;
      }

      try {
        final file = File(selectedFilePath!);
        final ref = FirebaseStorage.instance.ref(
          'business_docs/${user.uid}/${widget.docType}/$name',
        );

        final uploadTask = ref.putFile(file);

        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          updateProgress(progress);
        });

        await uploadTask;

        final fullPath = ref.fullPath;

        final saveData = {
          'path': fullPath,
          'name': name,
        };

        await FirebaseFirestore.instance
            .collection('businesses')
            .doc(user.uid)
            .set({widget.docType: saveData}, SetOptions(merge: true));

        updateProgress(1.0, completed: true);
        setState(() {
          uploadedPath = fullPath;
          textData = null;
          selectedFilePath = null;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
        setState(() {
          selectedFilePath = null;
          selectedFileName = null;
          _progress = 0.0;
          _uploadCompleted = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTextOnly = _isTextOnly();

    final displayText = isTextOnly
        ? (textData ?? 'No ${_getLabel()} entered')
        : (selectedFileName ?? 'No file selected');

    final buttonText = isTextOnly
        ? (textData != null ? 'Change ${_getLabel()}' : 'Enter ${_getLabel()}')
        : (uploadedPath != null ? 'Change File' : 'Upload File');

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.docType.replaceAll('_', ' '),
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Text(
            widget.description,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayText,
                      style: GoogleFonts.inter(
                        color: (isTextOnly ? textData != null : selectedFileName != null)
                            ? Colors.black
                            : Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                    if (!isTextOnly && selectedFilePath != null && !_uploadCompleted) ...[
                      const SizedBox(height: 8),
                      LinearPercentIndicator(
                        width: MediaQuery.of(context).size.width - 160,
                        animation: true,
                        lineHeight: 8.0,
                        animationDuration: 200,
                        percent: _progress.clamp(0.0, 1.0),
                        progressColor: primaryColor,
                        backgroundColor: Colors.grey.shade300,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (!isTextOnly && selectedFilePath != null && _progress > 0 && !_uploadCompleted)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularPercentIndicator(
                    radius: 20.0,
                    lineWidth: 4.0,
                    percent: _progress.clamp(0.0, 1.0),
                    center: Text(
                      "${(_progress * 100).toInt()}%",
                      style: const TextStyle(fontSize: 10),
                    ),
                    progressColor: primaryColor,
                  ),
                )
              else
                ElevatedButton(
                  onPressed: _handleUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    buttonText,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}