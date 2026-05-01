import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';                    // ← Required for cardData parsing

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shimmer/shimmer.dart';

class ReceiptPage extends StatefulWidget {
  final String reference;

  const ReceiptPage({super.key, required this.reference});

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _isLoading = true;

  String transactionNo = '';
  String senderName = '';
  String senderAccountNumber = '';
  String senderBankName = '';
  String amount = '';
  String status = '';
  String transactionDateTime = '';
  String transactionType = '';
  String? failureReason;

  List<Map<String, String>> recipientDetails = [];
  List<Map<String, String>> senderDetails = [];
  List<Map<String, String>> transactionInfo = [];
  List<Map<String, String>> cardDetails = [];           // ← NEW for atm_payment

  String _firstNonEmpty(List<dynamic> values, {String fallback = ''}) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    _generateTransactionIds();
    _fetchTransactionDetails();
  }

  // ---------------------------------------------------------------------------
  // Parse cardData JSON → first 4 + last 4 digits
  // ---------------------------------------------------------------------------
  List<Map<String, String>> _parseCardDetails(String? cardDataStr) {
    if (cardDataStr == null || cardDataStr.isEmpty) {
      return [{'label': 'Card Number', 'value': '•••• •••• •••• ••••'}];
    }
    try {
      final decoded = jsonDecode(cardDataStr) as Map<String, dynamic>;
      final responseData = decoded['data'] as Map<String, dynamic>? ?? decoded;

      String maskedPan = responseData['maskedPan']?.toString() ??
          responseData['pan']?.toString() ??
          responseData['cardNumber']?.toString() ??
          responseData['field2']?.toString() ?? '';

      if (maskedPan.isNotEmpty && (maskedPan.length == 16 || maskedPan.length == 19)) {
        final first4 = maskedPan.substring(0, 4);
        final last4 = maskedPan.substring(maskedPan.length - 4);
        maskedPan = '$first4 **** **** $last4';
      }

      final cardType = responseData['cardType']?.toString() ??
          responseData['scheme']?.toString() ??
          responseData['brand']?.toString() ??
          responseData['cardBrand']?.toString() ??
          'Debit Card';

      return [
        if (maskedPan.isNotEmpty) {'label': 'Card Number', 'value': maskedPan},
        {'label': 'Card Type', 'value': cardType},
      ];
    } catch (e) {
      debugPrint('Card data parse error: $e');
      return [{'label': 'Card Number', 'value': '•••• •••• •••• ••••'}];
    }
  }

  Future<void> _fetchTransactionDetails() async {
    try {
      final transactionDoc = await FirebaseFirestore.instance
          .collection('transactions')
          .where('reference', isEqualTo: widget.reference)
          .get();

      if (transactionDoc.docs.isNotEmpty) {
        final data = transactionDoc.docs.first.data();
        final String? uid = data['actualSender'] ?? data['userId'];
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        final timestamp = data['createdAtFirestore'] ?? data['timestamp'] as Timestamp?;
        final txType = (data['type'] as String? ?? '').toLowerCase();
        final isAnonymousTransfer =
            txType == 'ghost_transfer' || txType == 'anonymous_transfer';
        final isSent = uid == currentUserId || data['userId'] == currentUserId;
        final isReceivedAnonymously = isAnonymousTransfer && !isSent;

        String currentUserName = '';
        String currentUserAccountNumber = '';
        String currentUserBankName = '';
        if (currentUserId != null && currentUserId.isNotEmpty) {
          try {
            final currentUserDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUserId)
                .get();
            if (currentUserDoc.exists) {
              final currentUserData = currentUserDoc.data() ?? <String, dynamic>{};
              currentUserName = _firstNonEmpty([
                '${currentUserData['firstName'] ?? ''} ${currentUserData['lastName'] ?? ''}'.trim(),
                currentUserData['userName'],
                currentUserData['email'],
              ]);
              final currentVa = getVirtualAccountData(currentUserData);
              currentUserAccountNumber =
                  currentVa?['attributes']?['accountNumber']?.toString() ?? '';
              currentUserBankName =
                  currentVa?['attributes']?['bank']?['name']?.toString() ?? '';
            }
          } catch (e) {
            debugPrint('Error fetching current user for receipt details: $e');
          }
        }

        // Fetch sender / merchant details (businesses first, then users)
        String fetchedSenderName = _firstNonEmpty([
          data['senderName'],
          data['debitAccountName'],
          data['originatorName'],
          data['originatorAccountName'],
          data['senderAccountName'],
          data['counterParty']?['accountName'],
          data['api_response']?['data']?['attributes']?['senderName'],
          data['api_response']?['data']?['attributes']?['nameEnquiry']?['accountName'],
        ]);
        String fetchedSenderAccountNumber = _firstNonEmpty([
          data['senderAccountNumber'],
          data['debitAccountNumber'],
          data['originatorAccountNumber'],
          data['counterParty']?['accountNumber'],
        ]);
        String fetchedSenderBankName = _firstNonEmpty([
          data['senderBankName'],
          data['debitBankName'],
          data['originatorBankName'],
          data['bankName'],
        ]);

        if (!isReceivedAnonymously && uid != null && uid.isNotEmpty) {
          // Check businesses collection first
          final busSnap = await FirebaseFirestore.instance.collection('businesses').doc(uid).get();

          if (busSnap.exists && busSnap.data() != null) {
            final busData = busSnap.data()!;
            final String kycStatus = busData['kycStatus'] ?? '';

            if (kycStatus == 'APPROVED') {
              fetchedSenderName = _firstNonEmpty([
                fetchedSenderName,
                busData['business_data']?['name'],
                busData['businessName'],
              ], fallback: 'Business User');

              final virtualAccData = getVirtualAccountData(busData);
              if (virtualAccData != null) {
                fetchedSenderAccountNumber = virtualAccData['attributes']?['accountNumber']?.toString() ?? '';
                fetchedSenderBankName = virtualAccData['attributes']?['bank']?['name']?.toString() ?? '';
                fetchedSenderName = _firstNonEmpty([
                  fetchedSenderName,
                  virtualAccData['attributes']?['accountName'],
                ], fallback: fetchedSenderName);
              }
            }
          }

          // Fallback to users collection if no approved business account
          if (fetchedSenderName.isEmpty || fetchedSenderAccountNumber.isEmpty) {
            final userSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
            if (userSnap.exists && userSnap.data() != null) {
              final userData = userSnap.data()!;
              fetchedSenderName = _firstNonEmpty([
                fetchedSenderName,
                "${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}".trim(),
                userData['userName'],
                userData['email'],
              ], fallback: 'User');

              final vaData = getVirtualAccountData(userData);
              if (vaData != null) {
                fetchedSenderName = _firstNonEmpty([
                  fetchedSenderName,
                  vaData['attributes']?['accountName'],
                ], fallback: fetchedSenderName);
                fetchedSenderAccountNumber =
                    vaData['attributes']?['accountNumber']?.toString() ??
                    fetchedSenderAccountNumber;
                fetchedSenderBankName =
                    vaData['attributes']?['bank']?['name']?.toString() ??
                    fetchedSenderBankName;
              }
            }
          }
        } else if (isReceivedAnonymously) {
          fetchedSenderName = _firstNonEmpty([
            data['senderName'],
            data['senderAccountName'],
          ], fallback: 'PadiPay');
        }

        // If still empty, try to fetch by accountId from api_response
        if (fetchedSenderAccountNumber.isEmpty || fetchedSenderName.isEmpty || fetchedSenderBankName.isEmpty) {
          final accountId = data['api_response']?['data']?['relationships']?['account']?['data']?['id']?.toString();
          if (accountId != null && accountId.isNotEmpty) {
            // 1. Try users collection
            final userQuery = await FirebaseFirestore.instance.collection('users').where('sudoData.virtualAccount.data.id', isEqualTo: accountId).get();
            if (userQuery.docs.isNotEmpty) {
              final userData = userQuery.docs.first.data();
              final userVa = getVirtualAccountData(userData);
              fetchedSenderName = _firstNonEmpty([
                fetchedSenderName,
                userVa?['attributes']?['accountName'],
              ]);
              fetchedSenderAccountNumber = userVa?['attributes']?['accountNumber']?.toString() ?? '';
              fetchedSenderBankName = userVa?['attributes']?['bank']?['name']?.toString() ?? '';
            } else {
              // 2. Try businesses collection
              final businessQuery = await FirebaseFirestore.instance.collection('businesses').where('sudoData.virtualAccount.data.id', isEqualTo: accountId).get();
              if (businessQuery.docs.isNotEmpty) {
                final busData = businessQuery.docs.first.data();
                final busVa = getVirtualAccountData(busData);
                fetchedSenderName = _firstNonEmpty([
                  fetchedSenderName,
                  busVa?['attributes']?['accountName'],
                  busData['business_data']?['name'],
                ]);
                fetchedSenderAccountNumber = busVa?['attributes']?['accountNumber']?.toString() ?? '';
                fetchedSenderBankName = busVa?['attributes']?['bank']?['name']?.toString() ?? '';
              } else {
                // 3. Try posStands array in businesses
                final allBusinesses = await FirebaseFirestore.instance.collection('businesses').get();
                for (var busDoc in allBusinesses.docs) {
                  final busData = busDoc.data();
                  final posStands = busData['posStands'] as List?;
                  if (posStands != null) {
                    for (var stand in posStands) {
                      final standAccountId = stand['accountData']?['data']?['id']?.toString();
                      if (standAccountId == accountId) {
                        fetchedSenderName = stand['accountData']?['data']?['attributes']?['accountName']?.toString() ?? '';
                        fetchedSenderAccountNumber = stand['accountData']?['data']?['attributes']?['accountNumber']?.toString() ?? '';
                        fetchedSenderBankName = stand['accountData']?['data']?['attributes']?['bank']?['name']?.toString() ?? '';
                        break;
                      }
                    }
                  }
                  if (fetchedSenderAccountNumber.isNotEmpty) break;
                }
              }
            }
          }
        }

        setState(() {
          transactionType = data['type'] ?? '';
          amount = (data['amount'] ?? 0).toString();
          status = data['status'] ?? (data['api_response']?['data']?['attributes']?['status'] ?? '');
          if (status.toLowerCase() == 'success') status = 'successful';

          if (data['type'] == 'atm_payment' &&
              ['failed', 'unsuccessful'].contains(status.toLowerCase())) {
            final t = data['failureTitle'] as String?;
            final d = data['failureDetail'] as String?;
            failureReason = (t != null && d != null) ? '$t: $d' : t ?? d;
          }

          transactionDateTime = timestamp != null
              ? DateFormat("MMMM d, yyyy 'at' h:mm:ss a 'UTC+1'").format(timestamp.toDate())
              : '';

          final isCreditLike =
              txType == 'deposit' || txType == 'add_money' || txType == 'fund';
          final recipientName = _firstNonEmpty([
            data['recipientName'],
            data['creditAccountName'],
            data['beneficiaryAccountName'],
            currentUserName,
          ]);
          final recipientAccountNumber = _firstNonEmpty([
            data['creditAccountNumber'],
            data['beneficiaryAccountNumber'],
            data['account_number'],
            data['accountNumber'],
            currentUserAccountNumber,
          ]);
          final recipientBank = _firstNonEmpty([
            data['recipientBankName'],
            data['creditBankName'],
            data['beneficiaryBankName'],
            data['bankName'],
            currentUserBankName,
          ]);

          // ------------------- RECIPIENT / PAYMENT DETAILS -------------------
          if (transactionType == 'transfer' || transactionType == 'ghost_transfer' || isCreditLike) {
            recipientDetails = [
              {'label': 'Recipient Name', 'value': recipientName},
              {'label': 'Bank Name', 'value': recipientBank},
              {
                'label': 'Account Number',
                'value': recipientAccountNumber.isNotEmpty
                    ? _maskAccountNumber(recipientAccountNumber)
                    : '',
              },
            ];
          } else if (transactionType == 'airtime') {
            recipientDetails = [
              {'label': 'Phone Number', 'value': data['phoneNumber'] ?? ''},
              {'label': 'Network', 'value': data['network'] ?? ''},
            ];
          } else if (transactionType == 'data') {
            recipientDetails = [
              {'label': 'Phone Number', 'value': data['phoneNumber'] ?? ''},
              {'label': 'Network', 'value': data['network'] ?? ''},
              {'label': 'Bundle', 'value': data['bundle'] ?? ''},
            ];
          } else if (transactionType == 'cable') {
            recipientDetails = [
              {'label': 'Smartcard Number', 'value': data['fullData']?['customerDetail']?['smartcardNumber'] ?? ''},
              {'label': 'Provider', 'value': data['network'] ?? ''},
              {'label': 'Plan', 'value': data['plan'] ?? ''},
            ];
          } else if (transactionType == 'electricity') {
            recipientDetails = [
              {'label': 'Meter Number', 'value': data['meterNumber'] ?? ''},
              {'label': 'Disco', 'value': data['disco'] ?? ''},
              {'label': 'Token', 'value': data['token'] ?? ''},
              {'label': 'Units', 'value': data['units'] ?? ''},
            ];
          } else if (transactionType == 'atm_payment') {
            recipientDetails = [
              {'label': 'Payment Type', 'value': 'Card Payment'},
              {'label': 'Terminal ID', 'value': data['terminalId']?.toString() ?? ''},
              {'label': 'RRN', 'value': data['rrn']?.toString() ?? data['reference'] ?? ''},
            ];

            // NEW: Parse card details (first 4 + last 4)
            cardDetails = _parseCardDetails(data['cardData'] as String?);

            transactionType = 'atm_payment';
          }

          senderName = fetchedSenderName.isNotEmpty
              ? fetchedSenderName
              : (isSent ? currentUserName : 'Unknown');
          senderAccountNumber = fetchedSenderAccountNumber;
          senderBankName = fetchedSenderBankName;

          senderDetails = [
            {'label': 'Sender Name', 'value': senderName},
            if (senderBankName.isNotEmpty)
              {'label': 'Bank Name', 'value': senderBankName},
            if (senderAccountNumber.isNotEmpty)
              {'label': 'Account Number', 'value': _maskAccountNumber(senderAccountNumber)},
          ];

          transactionInfo = [
            {'label': 'Transaction No.', 'value': transactionNo},
            {'label': 'Reference', 'value': widget.reference},
          ];

          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching transaction details: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _generateTransactionIds() {
    setState(() {
      transactionNo = widget.reference;
    });
  }

  String getFormattedAmount() {
    final number = double.parse(amount.isEmpty ? '0' : amount);
    final formatter = NumberFormat('#,###');
    return formatter.format(number);
  }

  String _maskAccountNumber(String accountNumber) {
    if (accountNumber.length < 7) return accountNumber;
    return '${accountNumber.substring(0, 3)}****${accountNumber.substring(accountNumber.length - 3)}';
  }

  Color _getStatusColor() {
    switch (status.toUpperCase()) {
      case 'SUCCESSFUL':
      case 'SUCCESS':
      case 'COMPLETED':
        return const Color(0xFF00A86B);
      case 'FAILED':
      case 'UNSUCCESSFUL':
        return Colors.red;
      case 'PENDING':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  PdfColor _getPdfStatusColor() {
    switch (status.toUpperCase()) {
      case 'SUCCESSFUL':
        return PdfColor.fromHex('00A86B');
      case 'FAILED':
        return PdfColors.red;
      case 'PENDING':
        return PdfColors.orange;
      default:
        return PdfColors.grey;
    }
  }

  Future<void> _shareImage() async {
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = await File('${dir.path}/receipt.png').writeAsBytes(pngBytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      debugPrint('Share image error: $e');
    }
  }

  pw.Widget _buildStatusIcon(double iconSize) {
    return pw.CustomPaint(
      size: PdfPoint(iconSize, iconSize),
      painter: (PdfGraphics canvas, PdfPoint size) {
        canvas.setStrokeColor(_getPdfStatusColor());
        canvas.setLineWidth(2);
        canvas.drawEllipse(0, 0, size.x, size.y);
        canvas.strokePath();
        if (status.toUpperCase() == 'SUCCESSFUL') {
          canvas.moveTo(size.x * 0.2, size.y * 0.55);
          canvas.lineTo(size.x * 0.45, size.y * 0.75);
          canvas.lineTo(size.x * 0.8, size.y * 0.35);
          canvas.strokePath();
        } else if (status.toUpperCase() == 'FAILED') {
          canvas.moveTo(size.x * 0.3, size.y * 0.3);
          canvas.lineTo(size.x * 0.7, size.y * 0.7);
          canvas.moveTo(size.x * 0.7, size.y * 0.3);
          canvas.lineTo(size.x * 0.3, size.y * 0.7);
          canvas.strokePath();
        } else {
          canvas.moveTo(size.x * 0.5, size.y * 0.2);
          canvas.lineTo(size.x * 0.5, size.y * 0.8);
          canvas.strokePath();
        }
      },
    );
  }

  pw.Widget _buildDetailsSection(String title, List<Map<String, String>> details) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        ...details.map((item) => pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  item['label'] ?? '',
                  style: pw.TextStyle(color: PdfColors.grey, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(item['value'] ?? '', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 10),
          ],
        )),
      ],
    );
  }

  Future<Uint8List> _generatePdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => pw.Stack(
          children: [
            pw.CustomPaint(
              size: PdfPoint(context.page.pageFormat.width - 64, context.page.pageFormat.height - 64),
              painter: (PdfGraphics canvas, PdfPoint size) {
                canvas.saveContext();
                final currentTransform = canvas.getTransform();
                final rotation = vm.Matrix4.rotationZ(45 * math.pi / 180);
                canvas.setTransform(rotation.multiplied(currentTransform));
                canvas.setFillColor(PdfColor(0.5, 0.5, 0.5, 0.07));
                const spacing = 100.0;
                for (double x = -size.x * 2; x < size.x * 2; x += spacing) {
                  for (double y = -size.y * 2; y < size.y * 2; y += spacing) {
                    canvas.drawString(PdfFont.helvetica(pdf.document), 25, 'PadiPay', x, y / 4);
                  }
                }
                canvas.restoreContext();
              },
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.SizedBox(height: 10),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(14),
                      decoration: pw.BoxDecoration(color: _getPdfStatusColor(), shape: pw.BoxShape.circle),
                      child: _buildStatusIcon(30),
                    ),
                  ),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      "NGN ${getFormattedAmount()}",
                      style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        _buildStatusIcon(16),
                        pw.SizedBox(width: 5),
                        pw.Text(status, style: pw.TextStyle(color: _getPdfStatusColor())),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      transactionDateTime,
                      style: pw.TextStyle(fontSize: 14, color: PdfColors.grey500, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 5),

                  // ────────────────────── CONDITIONAL SECTIONS FOR PDF ──────────────────────
                  if (transactionType == 'atm_payment') ...[
                    _buildDetailsSection("Payment Details", recipientDetails),
                    _buildDetailsSection("Card Details", cardDetails),
                    _buildDetailsSection("Receiver Details", senderDetails),
                  ] else ...[
                    _buildDetailsSection("Recipient Details", recipientDetails),
                    _buildDetailsSection("Sender Details", senderDetails),
                  ],

                  pw.SizedBox(height: 10),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 10),
                  _buildDetailsSection("Transaction Information", transactionInfo),
                  pw.SizedBox(height: 20),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(color: PdfColors.grey50, borderRadius: pw.BorderRadius.circular(20)),
                    child: pw.Text(
                      "Enjoy a better life with PadiPay. Get free transfers, instant loans, and cashback rewards.",
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(color: PdfColors.grey500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  Future<void> _sharePdf() async {
    try {
      final bytes = await _generatePdf();
      final dir = await getTemporaryDirectory();
      final file = await File('${dir.path}/receipt.pdf').writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      debugPrint('Share PDF error: $e');
    }
  }

  Future<void> refresh() async {
    navigateTo(context, ReceiptPage(reference: widget.reference), type: NavigationType.replace);
  }

  Widget _buildDetailsSectionUI(String title, List<Map<String, String>> details) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        ...details.map((item) => Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item['label'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.grey, fontSize: 12),
                ),
                Text(
                  item['value'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        )),
      ],
    );
  }

  Widget _buildShimmerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 120, height: 14, color: Colors.white),
        const SizedBox(height: 10),
        ...List.generate(3, (index) => Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(width: 100, height: 12, color: Colors.white),
                Container(width: 120, height: 12, color: Colors.white),
              ],
            ),
            const SizedBox(height: 10),
          ],
        )),
      ],
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 58, height: 58, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
            const SizedBox(height: 16),
            Container(width: 200, height: 30, color: Colors.white),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 16, height: 16, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Container(width: 80, height: 16, color: Colors.white),
              ],
            ),
            const SizedBox(height: 10),
            Container(width: 150, height: 16, color: Colors.white),
            const SizedBox(height: 10),
            Divider(color: Colors.grey.shade300),
            const SizedBox(height: 5),
            _buildShimmerSection(),
            Divider(color: Colors.grey.shade300),
            const SizedBox(height: 10),
            _buildShimmerSection(),
            const SizedBox(height: 10),
            Divider(color: Colors.grey.shade300),
            const SizedBox(height: 10),
            _buildShimmerSection(),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(20)),
              child: Container(height: 20, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: SafeArea(
        bottom: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: _shareImage,
              child: Container(
                margin: const EdgeInsets.only(left: 20, top: 15, bottom: 25),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 10),
                    Text("Share Image", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: _sharePdf,
              child: Container(
                margin: const EdgeInsets.only(right: 20, top: 15, bottom: 25),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.article, size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 10),
                    Text("Share PDF", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        surfaceTintColor: Colors.white,
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.arrow_back_ios, color: Colors.black87, size: 20),
        ),
        title: const Text("Share Receipt", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: primaryColor,
        backgroundColor: Colors.white,
        onRefresh: () => refresh(),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.grey.shade100, offset: const Offset(1, 1.5))],
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            child: _isLoading
                ? _buildShimmer()
                : Theme(
                    data: Theme.of(context).copyWith(brightness: Brightness.light),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(platformBrightness: Brightness.light),
                      child: RepaintBoundary(
                        key: _boundaryKey,
                        child: Container(
                          color: Colors.white,
                          child: CustomPaint(
                            painter: WatermarkPainter(),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor().withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    status.toUpperCase() == 'SUCCESSFUL'
                                        ? Icons.check_circle_outline_rounded
                                        : status.toUpperCase() == 'FAILED'
                                            ? Icons.close_rounded
                                            : Icons.hourglass_empty_rounded,
                                    size: 30,
                                    color: _getStatusColor(),
                                  ),
                                ),
                                Text(
                                  "₦${getFormattedAmount()}",
                                  style: const TextStyle(color: Colors.black, fontSize: 30, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      status.toUpperCase() == 'SUCCESSFUL'
                                          ? Icons.check_circle_outline_rounded
                                          : status.toUpperCase() == 'FAILED'
                                              ? Icons.close_rounded
                                              : Icons.hourglass_empty_rounded,
                                      size: 16,
                                      color: _getStatusColor(),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(status, style: TextStyle(color: _getStatusColor())),
                                  ],
                                ),
                                if (failureReason != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    child: Text(
                                      failureReason!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                Text(
                                  transactionDateTime,
                                  style:  TextStyle(color: Colors.grey.shade500, fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 10),
                                Divider(color: Colors.grey.shade300),
                                const SizedBox(height: 5),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Column(
                                    children: [
                                      // ────────────────────── CONDITIONAL UI SECTIONS ──────────────────────
                                      if (transactionType == 'atm_payment') ...[
                                        _buildDetailsSectionUI("Payment Details", recipientDetails),
                                        _buildDetailsSectionUI("Card Details", cardDetails),
                                        _buildDetailsSectionUI("Receiver Details", senderDetails),
                                      ] else ...[
                                        _buildDetailsSectionUI("Recipient Details", recipientDetails),
                                        _buildDetailsSectionUI("Sender Details", senderDetails),
                                      ],

                                      const SizedBox(height: 10),
                                      Divider(color: Colors.grey.shade300),
                                      const SizedBox(height: 10),
                                      _buildDetailsSectionUI("Transaction Information", transactionInfo),
                                      const SizedBox(height: 20),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child:  Text(
                                          "Enjoy a better life with PadiPay. Get free transfers, instant loans, and cashback rewards.",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey.shade500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class WatermarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.srcOver);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'PadiPay',
        style: TextStyle(fontSize: 25, color: ui.Color.fromARGB(14, 0, 0, 0), fontWeight: FontWeight.w300),
      ),
      textDirection: ui.TextDirection.ltr,
    );

    textPainter.layout();

    canvas.save();
    canvas.rotate(45 * math.pi / 180);

    const spacing = 100.0;
    for (double x = -size.width * 2; x < size.width * 2; x += spacing) {
      for (double y = -size.height * 2; y < size.height * 2; y += spacing) {
        textPainter.paint(canvas, Offset(x, y / 4));
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}