import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:padi_pay_business/cards_page.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/my_business/my_business.dart';
import 'package:padi_pay_business/padi_book/padi_book_page.dart';
import 'package:padi_pay_business/profile/profile_page.dart';
import 'package:padi_pay_business/receipt_page.dart';
import 'package:padi_pay_business/ui/bottom_nav_bar.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shimmer/shimmer.dart';

class TransactionsHistory extends StatefulWidget {
  const TransactionsHistory({super.key});

  @override
  State<TransactionsHistory> createState() => _TransactionsHistoryState();
}

class _TransactionsHistoryState extends State<TransactionsHistory> {
  int _selectedIndex = 3;
  final String uid = FirebaseAuth.instance.currentUser!.uid;
  String _selectedCategory = 'All Categories';
  String _selectedStatus = 'All';
  String _searchQuery = '';
  DateTime? _selectedMonth;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _showCustomDateRange = false;
  final TextEditingController _searchController = TextEditingController();
  bool _filtersExpanded = true;
  List<String> _searchSuggestions = [];
  bool _showSuggestions = false;
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _allTransactionData = [];

  final Map<String, List<String>> _categoryTypes = {
    'All Categories': [],
    'Mobile Data': ['data', 'mobile_data'],
    'Add Money': ['deposit'],
    'Giveaway': ['giveaway_claim'],
    'Loans': ['loan', 'loans'],
    'Ghost Mode Transfers': ['ghost_transfer'],
    'Bill Payments': ['bill_payment', 'electricity', 'cable'],
    'Airtime': ['airtime'],
    'Data Bundle': ['data', 'mobile_data'],
    'Electricity': ['electricity'],
    'Cable': ['cable'],
    'Transfer': ['transfer'],
    'ATM Payment': ['atm_payment'],
    'Cashback': ['cashback_earned', 'cashback_spent'],
  };

  String _getStatus(Map<String, dynamic> data) {
    if (data['status'] != null) {
      return data['status'].toString().toLowerCase();
    }
    if (data['api_response']?['data']?['attributes']?['status'] != null) {
      return data['api_response']['data']['attributes']['status']
          .toString()
          .toLowerCase();
    }
    if (data['fullData']?['attributes']?['status'] != null) {
      return data['fullData']['attributes']['status'].toString().toLowerCase();
    }
    return 'unknown';
  }

  IconData _getIcon(String type, bool isOutgoing) {
    switch (type.toLowerCase()) {
      case 'transfer':
        return isOutgoing ? FontAwesomeIcons.paperPlane : Icons.arrow_downward;
      case 'airtime':
        return FontAwesomeIcons.phone;
      case 'data':
      case 'mobile_data':
        return FontAwesomeIcons.wifi;
      case 'electricity':
        return FontAwesomeIcons.bolt;
      case 'cable':
        return Icons.tv;
      case 'add_money':
      case 'fund':
        return Icons.add;
      case 'giveaway_claim':
        return FontAwesomeIcons.gift;
      case 'giveaway_create':
        return FontAwesomeIcons.gift;
      case 'cashback_earned':
        return Icons.savings;
      case 'cashback_spent':
        return Icons.local_offer_outlined;
      case 'ghost_transfer':
        return FontAwesomeIcons.ghost;
      case 'atm_payment':
        return FontAwesomeIcons.creditCard;
      case 'bill_payment':
        return FontAwesomeIcons.fileInvoiceDollar;
      case 'loan':
      case 'loans':
        return FontAwesomeIcons.handHoldingDollar;
      default:
        return FontAwesomeIcons.exchangeAlt;
    }
  }

  DateTime _getDocDate(Map<String, dynamic> data) {
    final dynamic ts =
        data['timestamp'] ??
        data['createdAtFirestore'] ??
        data['createdAt'] ??
        data['createdAtUtc'];
    if (ts == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is String) {
      try {
        return DateTime.parse(ts);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
        _customStartDate = null;
        _customEndDate = null;
        _showCustomDateRange = false;
      });
    }
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _customStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _customStartDate = picked;
        if (_customEndDate != null && _customEndDate!.isBefore(picked)) {
          _customEndDate = null;
        }
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _customEndDate ?? (_customStartDate ?? DateTime.now()),
      firstDate: _customStartDate ?? DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _customEndDate = picked;
      });
    }
  }

  void _clearDateFilters() {
    setState(() {
      _selectedMonth = null;
      _customStartDate = null;
      _customEndDate = null;
      _showCustomDateRange = false;
    });
  }

  void _toggleCustomDateRange() {
    setState(() {
      _showCustomDateRange = !_showCustomDateRange;
      if (_showCustomDateRange) {
        _selectedMonth = null;
      } else {
        _customStartDate = null;
        _customEndDate = null;
      }
    });
  }

  void _updateSearchSuggestions(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    Set<String> suggestions = <String>{};
    for (var doc in _allTransactionData) {
      if (doc['recipientName'] != null &&
          doc['recipientName'].toString().toLowerCase().contains(
            query.toLowerCase(),
          )) {
        suggestions.add(doc['recipientName'].toString());
      }
      if (doc['phoneNumber'] != null &&
          doc['phoneNumber'].toString().contains(query)) {
        suggestions.add(doc['phoneNumber'].toString());
      }
      if (doc['meterNumber'] != null &&
          doc['meterNumber'].toString().contains(query)) {
        suggestions.add(doc['meterNumber'].toString());
      }
      if (doc['account_number'] != null &&
          doc['account_number'].toString().contains(query)) {
        suggestions.add(doc['account_number'].toString());
      }
    }
    setState(() {
      _searchSuggestions = suggestions.take(10).toList();
      _showSuggestions = _searchSuggestions.isNotEmpty;
    });
  }

  void _selectSuggestion(String suggestion) {
    _searchController.text = suggestion;
    setState(() {
      _searchQuery = suggestion.toLowerCase();
      _showSuggestions = false;
    });
    _searchFocusNode.unfocus();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchSuggestions = [];
      _showSuggestions = false;
    });
  }

  void _toggleFilters() {
    setState(() {
      _filtersExpanded = !_filtersExpanded;
    });
  }

  void _clearAllFilters() {
    setState(() {
      _selectedCategory = 'All Categories';
      _selectedStatus = 'All';
      _selectedMonth = null;
      _customStartDate = null;
      _customEndDate = null;
      _showCustomDateRange = false;
      _searchController.clear();
      _searchQuery = '';
      _searchSuggestions = [];
      _showSuggestions = false;
    });
  }

  bool _hasActiveFilters() {
    return _selectedCategory != 'All Categories' ||
        _selectedStatus != 'All' ||
        _selectedMonth != null ||
        _customStartDate != null ||
        _customEndDate != null ||
        _searchQuery.isNotEmpty;
  }

  int _countActiveFilters() {
    int count = 0;
    if (_selectedCategory != 'All Categories') count++;
    if (_selectedStatus != 'All') count++;
    if (_selectedMonth != null) count++;
    if (_customStartDate != null) count++;
    if (_customEndDate != null) count++;
    if (_searchQuery.isNotEmpty) count++;
    return count;
  }

  void _updateAllTransactionData() {
    final allDocs = [...sentDocs, ...receivedCpDocs];
    _allTransactionData = allDocs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {
        'recipientName': data['recipientName'],
        'phoneNumber': data['phoneNumber'],
        'meterNumber': data['meterNumber'],
        'account_number': data['account_number'],
      };
    }).toList();
  }

  Future<Map<String, dynamic>> _getUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {};
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) return {};
      return doc.data() as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      return {};
    }
  }

  Future<void> _generateAndDownloadPDF(
    List<QueryDocumentSnapshot> filteredDocs,
  ) async {
    try {
      final pdf = pw.Document();
      final userData = await _getUserData();
      final String fullName =
          '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
      final String phone = userData['phone']?.toString() ?? 'N/A';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) => [
            pw.Center(
              child: pw.Text(
                'Statement',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                'Generated on ${DateFormat('MMMM dd, yyyy').format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Account Holder',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Name: $fullName',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Phone: $phone',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Description', 'Category', 'Status', 'Amount'],
              data: filteredDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final transactionDate = _getDocDate(data);
                final formattedDate = DateFormat(
                  'dd/MM/yyyy',
                ).format(transactionDate);
                final amountValue =
                    (data['amount'] ?? data['debitAmount'] ?? 0) as num;
                final type = data['type']?.toString().toLowerCase() ?? '';
                final sign =
                    (type == 'credit' ||
                        type == 'deposit' ||
                        type == 'giveaway_claim' ||
                        type == 'add_money' ||
                        type == 'fund')
                    ? '+'
                    : '-';
                return [
                  formattedDate,
                  data['description']?.toString() ?? '-',
                  data['category']?.toString() ?? '-',
                  data['status']?.toString() ?? '-',
                  '$sign ${NumberFormat.currency(symbol: '₦', decimalDigits: 2).format(amountValue)}',
                ];
              }).toList(),
              border: null,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellHeight: 30,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.center,
                4: pw.Alignment.centerRight,
              },
              cellStyle: const pw.TextStyle(fontSize: 11),
            ),
          ],
        ),
      );

      final output = await getTemporaryDirectory();
      final file = File(
        '${output.path}/statement_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(await pdf.save());

      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        if (navigatorKey.currentContext != null) {
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            SnackBar(
              content: Text('PDF saved, but could not open: ${result.message}'),
            ),
          );
        }
      } else {
        if (navigatorKey.currentContext != null) {
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            const SnackBar(content: Text('Statement PDF generated and opened')),
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error generating PDF: $e\n$stackTrace');
      if (navigatorKey.currentContext != null) {
        ScaffoldMessenger.of(
          navigatorKey.currentContext!,
        ).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
      }
    }
  }

  (List<QueryDocumentSnapshot>, double) _getFilteredData() {
    List<QueryDocumentSnapshot> docs = [];
    if (isPosStandUser) {
      docs = sentDocs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final accountId =
            data['api_response']?['data']?['relationships']?['account']?['data']?['id'];
        return accountId == userAccountId;
      }).toList();
    } else if (isBusinessOwner) {
      docs = sentDocs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final accountId =
            data['api_response']?['data']?['relationships']?['account']?['data']?['id'];
        if (accountId != null && posStandAccountIds.contains(accountId)) {
          return true;
        }
        return accountId == userAccountId;
      }).toList();
    } else {
      if (userAccountId == null) {
        // No virtual account yet – show all the user's own transactions.
        docs = sentDocs.toList();
      } else {
        docs = sentDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final accountId =
              data['api_response']?['data']?['relationships']?['account']?['data']?['id'];
          // Include if accountId matches OR the transaction has no accountId
          // (e.g. airtime, bills, NFC payments).
          return accountId == null || accountId == userAccountId;
        }).toList();
      }
    }
    docs = [...docs, ...receivedCpDocs];

    Map<String, QueryDocumentSnapshot> uniqueDocs = {};
    for (var doc in docs) {
      uniqueDocs[doc.id] = doc;
    }
    final sortedDocs = uniqueDocs.values.toList()
      ..sort((a, b) {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        return _getDocDate(bData).compareTo(_getDocDate(aData));
      });

    double totalAmount = 0.0;

    final filteredDocs = sortedDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type']?.toString().toLowerCase() ?? '';
      final status = _getStatus(data);
      final date = _getDocDate(data);

      bool matchesSearch = _searchQuery.isEmpty;
      if (!matchesSearch) {
        final searchFields = [
          data['recipientName']?.toString().toLowerCase() ?? '',
          data['phoneNumber']?.toString().toLowerCase() ?? '',
          data['meterNumber']?.toString().toLowerCase() ?? '',
          data['account_number']?.toString().toLowerCase() ?? '',
          data['reference']?.toString().toLowerCase() ?? '',
          type,
        ];
        matchesSearch = searchFields.any(
          (field) => field.contains(_searchQuery),
        );
      }

      bool matchesCategory = _selectedCategory == 'All Categories'
          ? true
          : _categoryTypes[_selectedCategory]?.contains(type) ?? false;

      bool matchesStatus = _selectedStatus == 'All'
          ? true
          : _selectedStatus.toLowerCase() == status ||
                (_selectedStatus.toLowerCase() == 'successful' &&
                    (status == 'success' || status == 'completed')) ||
                (_selectedStatus.toLowerCase() == 'to be paid' &&
                    status == 'to be paid') ||
                (_selectedStatus.toLowerCase() == 'reversed' &&
                    status == 'reversed') ||
                (_selectedStatus.toLowerCase() == 'pending' &&
                    status == 'pending') ||
                (_selectedStatus.toLowerCase() == 'failed' &&
                    (status == 'failed' || status == 'unsuccessful'));

      bool matchesDate = true;
      if (_selectedMonth != null) {
        matchesDate =
            date.year == _selectedMonth!.year &&
            date.month == _selectedMonth!.month;
      } else if (_customStartDate != null || _customEndDate != null) {
        if (_customStartDate != null) {
          matchesDate = date.isAfter(
            DateTime(
              _customStartDate!.year,
              _customStartDate!.month,
              _customStartDate!.day,
            ).subtract(const Duration(days: 1)),
          );
        }
        if (_customEndDate != null && matchesDate) {
          matchesDate = date.isBefore(
            DateTime(
              _customEndDate!.year,
              _customEndDate!.month,
              _customEndDate!.day,
            ).add(const Duration(days: 1)),
          );
        }
      }

      final shouldInclude =
          matchesSearch && matchesCategory && matchesStatus && matchesDate;
      if (shouldInclude) {
        final amount = (data['amount'] ?? data['debitAmount'] ?? 0) as num;
        totalAmount += amount.toDouble();
      }
      return shouldInclude;
    }).toList();

    return (filteredDocs, totalAmount);
  }

  void _showFilterPopup(
    BuildContext context,
    String type,
    List<String> items,
    String selectedValue,
    Function(String) onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width),
      builder: (context) => SafeArea(
        bottom: true,
        child: Container(
          width: MediaQuery.of(context).size.width,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items
                    .map(
                      (item) => GestureDetector(
                        onTap: () {
                          onSelect(item);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: item == selectedValue
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.grey[200],
                            border: item == selectedValue
                                ? Border.all(color: Colors.blue, width: 1)
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item == selectedValue)
                                const Icon(
                                  Icons.check,
                                  color: Colors.blue,
                                  size: 16,
                                ),
                              if (item == selectedValue)
                                const SizedBox(width: 4),
                              Text(
                                item,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: item == selectedValue
                                      ? Colors.blue
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  StreamSubscription<QuerySnapshot>? _cpSub;
  StreamSubscription<QuerySnapshot>? _receivedCpSub;
  StreamSubscription<QuerySnapshot>? _allTransactionsSub;

  List<QueryDocumentSnapshot> sentDocs = [];
  List<QueryDocumentSnapshot> receivedCpDocs = [];
  List<String> cpIds = [];

  // For business logic
  String? businessDocId;
  List<String> posStandAccountIds = [];
  String? userAccountId; // For POS stand user
  bool isPosStandUser = false;
  bool isBusinessOwner = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initBusinessLogic()
        .catchError((e) => debugPrint('[TxHistory] init error: $e'))
        .whenComplete(() {
          if (mounted) setState(() => _isInitialized = true);
        });

    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        setState(() {
          _showSuggestions = false;
        });
      }
    });

    _allTransactionsSub = FirebaseFirestore.instance
        .collection('transactions')
        .where(
          Filter.or(
            Filter('userId', isEqualTo: uid),
            Filter('actualSender', isEqualTo: uid),
          ),
        )
        .orderBy('timestamp', descending: true)
        .limit(500)
        .snapshots()
        .listen(
          (snap) {
            final excludedTypes = {'va_settlement', 'va_settlement_failed'};

            final filteredDocs = snap.docs.where((doc) {
              final data = doc.data();
              // Filter out by type OR by isInternal flag (catches old docs too)
              if (excludedTypes.contains(data['type'])) return false;
              if (data['isInternal'] == true) return false;
              return true;
            }).toList();

            setState(() {
              sentDocs = filteredDocs;
              _updateAllTransactionData();
            });
          },
          onError: (e) =>
              debugPrint('[TxHistory] transactions stream error: $e'),
        );
    _cpSub = FirebaseFirestore.instance
        .collection('counterparties')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
          setState(() {
            cpIds = snap.docs.map((doc) => doc.id).toList();
            _updateCpStream();
          });
        });
  }

  Future<void> _initBusinessLogic() async {
    try {
      final userEmail = FirebaseAuth.instance.currentUser!.email;
      // First, check standUsers for POS stand user
      final standUserSnap = await FirebaseFirestore.instance
          .collection('standUsers')
          .where('email', isEqualTo: userEmail)
          .get();
      if (standUserSnap.docs.isNotEmpty) {
        isPosStandUser = true;
        final standUserData = standUserSnap.docs.first.data();
        final parentBusinessId = standUserData['parentBusinessId'];
        final businessSnap = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(parentBusinessId)
            .get();
        if (businessSnap.exists) {
          final data = businessSnap.data()!;
          final posStands = (data['posStands'] as List?) ?? [];
          final posStand = posStands.firstWhere(
            (e) => e['standLoginEmail'] == userEmail,
            orElse: () => null,
          );
          if (posStand != null) {
            userAccountId = posStand['accountData']?['data']?['id'];
          }
        }
        setState(() {});
      } else {
        // Else, check businesses.doc(uid).get()
        final businessSnap = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(uid)
            .get();
        if (businessSnap.exists) {
          final data = businessSnap.data()!;
          final posStands = (data['posStands'] as List?) ?? [];
          if (posStands.isNotEmpty) {
            // Business owner with POS stands
            isBusinessOwner = true;
            businessDocId = businessSnap.id;
            posStandAccountIds = posStands
                .map((e) => (e['accountData']?['data']?['id'] ?? ''))
                .whereType<String>()
                .where((id) => id.isNotEmpty)
                .toList();
            userAccountId = getVirtualAccountData(data)?['id']?.toString();
            print('posStandAccountIds: $posStandAccountIds');
            print('userAccountId: $userAccountId');
          } else {
            // Regular user with business doc
            userAccountId = getVirtualAccountData(data)?['id']?.toString();
          }
          setState(() {});
        } else {
          // Regular user without business doc
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint('[TxHistory] _initBusinessLogic error: $e');
    }
  }

  void _updateCpStream() {
    _receivedCpSub?.cancel();
    if (cpIds.isEmpty) {
      receivedCpDocs = [];
      return;
    }
    _receivedCpSub = FirebaseFirestore.instance
        .collection('transactions')
        .where(
          'api_response.data.relationships.counterParty.data.id',
          whereIn: cpIds,
        )
        .snapshots()
        .listen((snap) {
          const excludedTypes = {'va_settlement', 'va_settlement_failed'};
          setState(() {
            receivedCpDocs = snap.docs.where((doc) {
              final data = doc.data();
              if (excludedTypes.contains(data['type'])) return false;
              if (data['isInternal'] == true) return false;
              return true;
            }).toList();
            _updateAllTransactionData();
          });
        });
  }

  @override
  void dispose() {
    _cpSub?.cancel();
    _receivedCpSub?.cancel();
    _allTransactionsSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox.expand(
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      const Text(
                        'Transaction History',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: Shimmer.fromColors(
                          baseColor: Colors.grey[300]!,
                          highlightColor: Colors.grey[100]!,
                          child: ListView.builder(
                            itemCount: 10,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 25,
                                  left: 5,
                                  right: 5,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            height: 14,
                                            width: double.infinity,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            height: 12,
                                            width: 100,
                                            color: Colors.white,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          height: 12,
                                          width: 60,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(height: 2),
                                        Container(
                                          height: 12,
                                          width: 50,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    bottom: 25,
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: BottomNavBar(
                        currentIndex: _selectedIndex,
                        onTap: (index) {
                          if (index == 0) {
                            navigateTo(
                              context,
                              HomePage(),
                              type: NavigationType.push,
                            );
                            return;
                          }

                          if (index == 2) {
                            navigateTo(
                              context,
                              MyBusiness(),
                              type: NavigationType.push,
                            );
                          }
                          if (index == 4) {
                            navigateTo(
                              context,
                              ProfilePage(),
                              type: NavigationType.push,
                            );
                          }
                          if (index == 5) {
                            navigateTo(
                              context,
                              const PadiBookPage(),
                              type: NavigationType.push,
                            );
                          }
                          if (index == 3) {
                            navigateTo(
                              context,
                              TransactionsHistory(),
                              type: NavigationType.push,
                            );
                          } else {
                            setState(() => _selectedIndex = index);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SizedBox.expand(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'Transaction History',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _toggleFilters,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.tune,
                                size: 18,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Filters',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_countActiveFilters() > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primaryColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_countActiveFilters()}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Icon(
                            _filtersExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          if (_hasActiveFilters())
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _clearAllFilters,
                                icon: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.red,
                                ),
                                label: const Text(
                                  'Clear All',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          Stack(
                            children: [
                              TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onChanged: (value) {
                                  setState(() => _searchQuery = value);
                                  _updateSearchSuggestions(value);
                                },
                                decoration: InputDecoration(
                                  hintText: 'Search transactions...',
                                  hintStyle: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: Colors.grey,
                                    size: 20,
                                  ),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            color: Colors.grey,
                                            size: 18,
                                          ),
                                          onPressed: _clearSearch,
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: primaryColor),
                                  ),
                                ),
                              ),
                              if (_showSuggestions &&
                                  _searchSuggestions.isNotEmpty)
                                Positioned(
                                  top: 48,
                                  left: 0,
                                  right: 0,
                                  child: Material(
                                    elevation: 4,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        maxHeight: 150,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: _searchSuggestions.length,
                                        itemBuilder: (context, index) {
                                          final suggestion =
                                              _searchSuggestions[index];
                                          return ListTile(
                                            dense: true,
                                            title: Text(
                                              suggestion,
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                            onTap: () =>
                                                _selectSuggestion(suggestion),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _selectMonth(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: _selectedMonth != null
                                            ? primaryColor
                                            : Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.calendar_month,
                                          size: 16,
                                          color: _selectedMonth != null
                                              ? primaryColor
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            _selectedMonth != null
                                                ? DateFormat(
                                                    'MMM yyyy',
                                                  ).format(_selectedMonth!)
                                                : 'Month',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: _selectedMonth != null
                                                  ? primaryColor
                                                  : Colors.grey,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _toggleCustomDateRange,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: _showCustomDateRange
                                          ? primaryColor
                                          : Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    color: _showCustomDateRange
                                        ? primaryColor.withOpacity(0.05)
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.date_range,
                                        size: 16,
                                        color: _showCustomDateRange
                                            ? primaryColor
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Custom Range',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _showCustomDateRange
                                              ? primaryColor
                                              : Colors.grey,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_selectedMonth != null ||
                                  _customStartDate != null ||
                                  _customEndDate != null) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _clearDateFilters,
                                  child: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_showCustomDateRange) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _selectStartDate(context),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: _customStartDate != null
                                              ? primaryColor
                                              : Colors.grey.shade300,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _customStartDate != null
                                            ? DateFormat(
                                                'dd/MM/yy',
                                              ).format(_customStartDate!)
                                            : 'Start Date',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _customStartDate != null
                                              ? primaryColor
                                              : Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _selectEndDate(context),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: _customEndDate != null
                                              ? primaryColor
                                              : Colors.grey.shade300,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _customEndDate != null
                                            ? DateFormat(
                                                'dd/MM/yy',
                                              ).format(_customEndDate!)
                                            : 'End Date',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _customEndDate != null
                                              ? primaryColor
                                              : Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _showFilterPopup(
                                    context,
                                    'category',
                                    _categoryTypes.keys.toList(),
                                    _selectedCategory,
                                    (value) => setState(
                                      () => _selectedCategory = value,
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color:
                                            _selectedCategory !=
                                                'All Categories'
                                            ? primaryColor
                                            : Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _selectedCategory,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color:
                                                  _selectedCategory !=
                                                      'All Categories'
                                                  ? primaryColor
                                                  : Colors.black54,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.filter_list,
                                          size: 20,
                                          color:
                                              _selectedCategory !=
                                                  'All Categories'
                                              ? primaryColor
                                              : Colors.grey,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _showFilterPopup(
                                    context,
                                    'status',
                                    [
                                      'All',
                                      'Successful',
                                      'To be paid',
                                      'Reversed',
                                      'Pending',
                                      'Failed',
                                    ],
                                    _selectedStatus,
                                    (value) =>
                                        setState(() => _selectedStatus = value),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: _selectedStatus != 'All'
                                            ? primaryColor
                                            : Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _selectedStatus,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: _selectedStatus != 'All'
                                                  ? primaryColor
                                                  : Colors.black54,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.filter_list,
                                          size: 20,
                                          color: _selectedStatus != 'All'
                                              ? primaryColor
                                              : Colors.grey,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: Builder(
                              builder: (context) {
                                final (filteredDocs, _) = _getFilteredData();
                                return ElevatedButton.icon(
                                  onPressed: () =>
                                      _generateAndDownloadPDF(filteredDocs),
                                  icon: const Icon(
                                    Icons.download,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Download as PDF',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                      crossFadeState: _filtersExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 300),
                    ),
                    const SizedBox(height: 10),
                    Builder(
                      builder: (context) {
                        final (filteredDocs, totalAmount) = _getFilteredData();
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue.withOpacity(0.1),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Total Transactions',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${filteredDocs.length} transactions',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'Total Amount',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₦${NumberFormat('#,##0.00').format(totalAmount)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: RefreshIndicator(
                        color: primaryColor,
                        backgroundColor: Colors.white,
                        onRefresh: () async {},
                        child: Builder(
                          builder: (context) {
                            final (filteredDocs, _) = _getFilteredData();
                            if (filteredDocs.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.receipt_long,
                                      size: 80,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No transactions found',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Try changing your filters or search query',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return ListView.builder(
                              padding: const EdgeInsets.only(top: 20),
                              itemCount: filteredDocs.length + 1,
                              itemBuilder: (context, index) {
                                if (index == filteredDocs.length) {
                                  return const SizedBox(height: 100);
                                }
                                final doc = filteredDocs[index];
                                final data = doc.data() as Map<String, dynamic>;
                                final type =
                                    data['type']?.toString().toLowerCase() ??
                                    '';
                                bool isOutgoing = true;
                                String otherId = '';
                                if (type == 'transfer' ||
                                    type == 'ghost_transfer') {
                                  final accountId =
                                      data['api_response']?['data']?['relationships']?['account']?['data']?['id'];
                                  if (posStandAccountIds.contains(accountId)) {
                                    isOutgoing = true;
                                    otherId = data['receiverId'] ?? '';
                                  } else if (data['userId'] == uid ||
                                      data['actualSender'] == uid) {
                                    isOutgoing = true;
                                    otherId = data['receiverId'] ?? '';
                                  } else {
                                    isOutgoing = false;
                                    otherId = data['userId'] ?? '';
                                  }
                                } else {
                                  isOutgoing = true;
                                  otherId = '';
                                }
                                final icon = _getIcon(type, isOutgoing);
                                final status = _getStatus(data);
                                final amountSign =
                                    (!isOutgoing ||
                                        type == 'deposit' ||
                                        type == 'giveaway_claim' ||
                                        (type == 'atm_payment' &&
                                            [
                                              'success',
                                              'completed',
                                              'successful',
                                            ].contains(status)))
                                    ? '+'
                                    : '-';

                                Color statusColor = Colors.grey;
                                if ([
                                  'success',
                                  'completed',
                                  'successful',
                                ].contains(status)) {
                                  statusColor = Colors.green;
                                } else if ([
                                  'pending',
                                  'to be paid',
                                ].contains(status)) {
                                  statusColor = Colors.orange;
                                } else if ([
                                  'failed',
                                  'unsuccessful',
                                ].contains(status)) {
                                  statusColor = Colors.red;
                                } else if (status == 'reversed') {
                                  statusColor = Colors.grey;
                                }

                                Color bgColor = Colors.blue.withValues(
                                  alpha: 0.1,
                                );
                                Color iconColor = Colors.blue;
                                Offset offset = Offset.zero;
                                if (type == 'transfer') {
                                  bgColor = isOutgoing
                                      ? const Color(
                                          0xFFFDC3F5,
                                        ).withValues(alpha: .49)
                                      : Colors.green.withValues(alpha: 0.1);
                                  iconColor = isOutgoing
                                      ? const Color(0xFFE103E5)
                                      : Colors.green;
                                  if (isOutgoing) {
                                    offset = const Offset(-2, 2);
                                  }
                                }
                                if (type.contains('ghost')) {
                                  bgColor = Colors.grey.shade200;
                                  iconColor = Colors.grey.shade600;
                                }
                                if (type.contains('giveaway')) {
                                  bgColor = Colors.yellow.shade200;
                                  iconColor = Colors.yellow.shade900;
                                }

                                final date = _getDocDate(data);
                                final formattedTime = DateFormat(
                                  'HH:mm',
                                ).format(date);
                                final formattedDate = DateFormat(
                                  'MMMM d, yyyy',
                                ).format(date);
                                final initialName =
                                    data['senderName'] ??
                                    data['senderAccountName'] ??
                                    data['originatorName'] ??
                                    data['nameEnquiry']?['accountName'] ??
                                    data['api_response']?['data']?['attributes']?['nameEnquiry']?['accountName'] ??
                                    data['recipientName'] ??
                                    data['phoneNumber'] ??
                                    data['meterNumber'] ??
                                    data['smartcard_number'] ??
                                    data['account_number'] ??
                                    'Unknown';
                                final amountInNaira =
                                    ((data['amount'] as num?) ??
                                    (data['debitAmount'] as num? ?? 0));
                                final formattedAmount = NumberFormat(
                                  '#,##0.00',
                                ).format(amountInNaira);
                                final reference =
                                    data['reference'] ??
                                    (data['api_response']?['data']?['attributes']?['reference']
                                        as String?) ??
                                    (data['transactionId'] as String?) ??
                                    '';
                                Map<String, dynamic>? cardDataForItem;
                                if (type == 'atm_payment') {
                                  cardDataForItem = {
                                    'type': type,
                                    'amount': data['amount'],
                                    'merchant': data['tag'] ?? 'Card Payment',
                                    'channel': 'NFC',
                                    'currency': data['currency'] ?? 'NGN',
                                    'timestamp': data['timestamp'],
                                    'reference':
                                        data['reference'] ?? data['rrn'] ?? '',
                                    'status': data['status'] ?? 'success',
                                  };
                                }
                                return TransactionItem(
                                  docId: doc.id,
                                  icon: icon,
                                  otherId: otherId,
                                  amount: '$amountSign₦$formattedAmount',
                                  amountColor: statusColor,
                                  formattedTime: formattedTime,
                                  formattedDate: formattedDate,
                                  status: status,
                                  statusColor: statusColor,
                                  isOutgoing: isOutgoing,
                                  otherName: initialName,
                                  type: type,
                                  reference: reference,
                                  bgColor: bgColor,
                                  iconColor: iconColor,
                                  offset: offset,
                                  cardData: cardDataForItem,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 80),
                  ],
                ),
                Positioned(
                  bottom: 25,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: BottomNavBar(
                      currentIndex: _selectedIndex,
                      onTap: (index) {
                        if (index == 0) {
                          navigateTo(
                            context,
                            HomePage(),
                            type: NavigationType.push,
                          );
                          return;
                        }

                        if (index == 1) {
                          navigateTo(
                            context,
                            CardsPage(),
                            type: NavigationType.push,
                          );
                        }
                        if (index == 2) {
                          navigateTo(
                            context,
                            MyBusiness(),
                            type: NavigationType.push,
                          );
                        }
                        if (index == 4) {
                          navigateTo(
                            context,
                            ProfilePage(),
                            type: NavigationType.push,
                          );
                        }
                        if (index == 5) {
                          navigateTo(
                            context,
                            const PadiBookPage(),
                            type: NavigationType.push,
                          );
                        }
                        if (index == 3) {
                          navigateTo(
                            context,
                            TransactionsHistory(),
                            type: NavigationType.push,
                          );
                        } else {
                          setState(() => _selectedIndex = index);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TransactionItem extends StatefulWidget {
  final String docId;
  final IconData icon;
  final String otherId;
  final String amount;
  final Color amountColor;
  final String formattedTime;
  final String formattedDate;
  final String status;
  final Color statusColor;
  final bool isOutgoing;
  final String otherName;
  final String type;
  final String reference;
  final Color bgColor;
  final Color iconColor;
  final Offset offset;
  final Map<String, dynamic>? cardData;

  const TransactionItem({
    super.key,
    required this.docId,
    required this.icon,
    required this.otherId,
    required this.amount,
    required this.amountColor,
    required this.formattedTime,
    required this.formattedDate,
    required this.status,
    required this.statusColor,
    required this.isOutgoing,
    required this.otherName,
    required this.type,
    required this.reference,
    required this.bgColor,
    required this.iconColor,
    required this.offset,
    this.cardData,
  });

  @override
  State<TransactionItem> createState() => _TransactionItemState();
}

class _TransactionItemState extends State<TransactionItem> {
  String? _fetchedName;

  @override
  void initState() {
    super.initState();
    if (widget.type.toLowerCase() == 'transfer' &&
        !widget.isOutgoing &&
        widget.otherId.isNotEmpty) {
      _fetchName();
    }
  }

  Future<void> _fetchName() async {
    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherId)
          .get();
      if (docSnap.exists) {
        final data = docSnap.data()!;
        final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
            .trim();
        if (name.isNotEmpty) {
          setState(() {
            _fetchedName = name;
          });
        }
      }
    } catch (e) {
      // ignore
    }
  }

  String _getTitle(String type, String otherName, bool isOutgoing) {
    switch (type) {
      case 'transfer':
        return isOutgoing
            ? 'Transfer to $otherName'
            : 'Transfer from $otherName';
      case 'airtime':
        return otherName != 'Unknown'
            ? 'Airtime for $otherName'
            : 'Airtime Purchase';
      case 'data':
      case 'mobile_data':
        return otherName != 'Unknown'
            ? 'Data Bundle for $otherName'
            : 'Data Purchase';
      case 'electricity':
        return 'Electricity Bill';
      case 'cable':
        return 'Cable Subscription';
      case 'add_money':
      case 'fund':
        return 'Add Money';
      case 'giveaway_claim':
        return 'Giveaway Claim';
      case 'giveaway_create':
        return 'Giveaway Created';
      case 'deposit':
        return 'Transfer from $otherName';
      case 'loans':
        return isOutgoing ? 'Loan Disbursed' : 'Loan Received';
      case 'ghost_transfer':
        return "Ghost Transfer";
      case 'anonymous_transfer':
        return 'Anonymous Transfer';
      case 'bill_payment':
        return 'Bill Payment for $otherName';
      case 'atm_payment':
        return 'Card Payment';
      case 'card_debit':
        return 'Virtual Card Payment at $otherName';
      case 'card_declined':
        return 'Virtual Card Payment at $otherName';
      case 'card_refund':
        return 'Card Refund from $otherName';
      case 'cashback_earned':
        return 'Cashback Earned';
      case 'cashback_spent':
        return 'Cashback Spent';
      default:
        return otherName != 'Unknown'
            ? '$type for $otherName'
            : type.toUpperCase();
    }
  }

  void _showCardDetail(BuildContext context) {
    final data = widget.cardData!;
    final type = data['type']?.toString() ?? '';
    final currency = data['currency']?.toString() ?? 'NGN';
    final merchant = data['merchant']?.toString() ?? 'Unknown';
    final channel = data['channel']?.toString() ?? '';
    final reference = data['reference']?.toString() ?? '';
    final status =
        data['status']?.toString() ??
        (type == 'card_declined' ? 'declined' : 'approved');
    final ts = data['timestamp'] as Timestamp?;
    final date = ts != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate())
        : '';
    final isDeclined = type == 'card_declined' || status == 'declined';
    final isRefund = type == 'card_refund';
    final statusLabel = isDeclined
        ? 'Declined'
        : isRefund
        ? 'Refunded'
        : 'Successful';
    final statusColor = isDeclined
        ? Colors.red
        : isRefund
        ? Colors.blue
        : Colors.green;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.amount,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: GoogleFonts.inter(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _detailRow('Merchant', merchant),
            if (channel.isNotEmpty)
              _detailRow('Channel', channel.toUpperCase()),
            _detailRow('Currency', currency),
            if (date.isNotEmpty) _detailRow('Date', date),
            if (reference.isNotEmpty) _detailRow('Reference', reference),
            if (data['reason'] != null)
              _detailRow('Reason', data['reason'].toString()),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _fetchedName ?? widget.otherName;
    final title = _getTitle(widget.type, displayName, widget.isOutgoing);

    return GestureDetector(
      onTap: () {
        navigateTo(
          context,
          ReceiptPage(reference: widget.reference, cardData: widget.cardData),
          type: NavigationType.push,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 0, right: 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: widget.bgColor,
              child: Transform.translate(
                offset: widget.offset,
                child: Icon(widget.icon, color: widget.iconColor, size: 16),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Colors.grey.shade500,
                        size: 10,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.formattedTime,
                        style: GoogleFonts.inter(
                          color: Colors.grey.shade600,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        ' • ',
                        style: GoogleFonts.inter(
                          color: Colors.grey.shade400,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        widget.formattedDate,
                        style: GoogleFonts.inter(
                          color: Colors.grey.shade600,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  widget.amount,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: widget.amountColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.status,
                  style: GoogleFonts.inter(
                    color: widget.statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
