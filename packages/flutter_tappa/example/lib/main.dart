// main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tappa/EmvQrData.dart';
import 'package:flutter_tappa/flutter_tappa.dart';
import 'package:flutter_tappa/qr_widget.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Tappa Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const TappaExamplePage(),
    );
  }
}

class TappaExamplePage extends StatefulWidget {
  const TappaExamplePage({super.key});

  @override
  _TappaExamplePageState createState() => _TappaExamplePageState();
}

class _TappaExamplePageState extends State<TappaExamplePage> {
  final FlutterTappa _tappa = FlutterTappa();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitialized = false;
  bool _isInitTerminal = false;
  String _statusMessage = 'Tappa SDK not initialized';
  bool _isReading = false;
  StreamSubscription? _subscription;

  // Terminal configuration
  final TextEditingController _terminalIdController = TextEditingController(text: '21SWH241');
  final TextEditingController _uniqueIdController = TextEditingController(text: '202602121447TAOEH');
  final TextEditingController _clientIdController = TextEditingController(text: 'P260300000564');
  final TextEditingController _merchantLocationController = TextEditingController(text: 'Main Street Store');

  // Transaction configuration
  final TextEditingController _amountController = TextEditingController(text: '1000');
  final TextEditingController _accountTypeController = TextEditingController(text: '10');
  final TextEditingController _rrnController = TextEditingController(text: '202602121447TAOEH');

  @override
  void initState() {
    super.initState();
    _initializeTappa();
  }

  @override
  void dispose() {
    _terminalIdController.dispose();
    _uniqueIdController.dispose();
    _clientIdController.dispose();
    _merchantLocationController.dispose();
    _amountController.dispose();
    _accountTypeController.dispose();
    _rrnController.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  String? _cardData;
  Future<void> _initializeTappa() async {
    try {
      await _tappa.initialize(
          errorCallback: (errorCode, errorMessage) {
            _showSnackBar('Tappa error: $errorCode - $errorMessage');
          }
      );
      setState(() {
        _isInitialized = true;
        _statusMessage = 'Tappa SDK initialized';
      });
      _subscription = _tappa.loyaltyCardStream.listen((result) {


        print("Have this ${result.success}");
        print("Have this ${result.data}");
        setState(() {
          _isReading = false;
          if (result.success) {
            _cardData = result.data ?? 'No data received';
            _showSnackBar('Card Data: $_cardData');
          } else {
            _cardData = 'Error: ${result.errorMessage}';
          }
        });
      });
      _showSnackBar('Tappa SDK initialized successfully');
    } catch (e) {
      setState(() {
        _statusMessage = 'Initialization error: $e';
      });
      _showSnackBar('Failed to initialize Tappa SDK: $e');
    }
  }

  Future<void> _initTerminal() async {
    if (!_isInitialized) {
      _showSnackBar('Please initialize Tappa SDK first');
      return;
    }

    try {
      await _tappa.initTerminal(
        terminalId: _terminalIdController.text,
        uniqueId: _uniqueIdController.text,
        clientId: _clientIdController.text,
        merchantLocation: _merchantLocationController.text,
      );
      setState(() {
        _isInitTerminal = true;
        _statusMessage = 'Terminal initialized';
      });
      _showSnackBar('Terminal initialized successfully');
    } catch (e) {
      setState(() {
        _statusMessage = 'Terminal initialization error: $e';
      });
      _showSnackBar('Failed to initialize terminal: $e');
    }
  }

  Future<void> _startTransaction() async {
    if (!_isInitialized) {
      _showSnackBar('Please initialize Tappa SDK first');
      return;
    }
    if (!_isInitTerminal) {
      _showSnackBar('Please initialize Terminal first');
      return;
    }

    try {
      setState(() {
        _statusMessage = 'Transaction in progress...';
      });

      await _tappa.transact(
        amount: _amountController.text,
        accountType: _accountTypeController.text,
        rrn: _rrnController.text,
      );

      setState(() {
        _statusMessage = 'Transaction completed';
      });
      _showSnackBar('Transaction completed successfully');
    } catch (e) {
      setState(() {
        _statusMessage = 'Transaction error: $e';
      });
      _showSnackBar('Transaction failed: $e');
    }
  }

  Future<void> _readLoyaltyCard() async {
    if (!_isInitialized) {
      _showSnackBar('Please initialize Tappa SDK first');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Please tap your loyalty card...'),
            ],
          ),
        );
      },
    );

    try {
      setState(() {
        _isReading = true;
        _statusMessage = 'Reading loyalty card...';
      });

      final cardData = await _tappa.startReadingLoyaltyCard();


      print("We met at this $cardData");
      setState(() {
        _statusMessage = 'Loyalty card read successfully';
      });
      _showSnackBar('Loyalty card data: $cardData');
    } catch (e) {
      setState(() {
        _statusMessage = 'Loyalty card error: $e';
      });
      _showSnackBar('Failed to read loyalty card: $e');
    } finally{
      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _scanQrAndProcess() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: AspectRatio(
            aspectRatio: 1.0, // Makes it square
            child: QrScannerWidget(
              onScanResult: (qrData) async {
                Navigator.of(context).pop(); // Close the bottom sheet
                if (qrData == null || qrData.isEmpty) {
                  _showSnackBar('No QR code scanned');
                  return;
                }

                try {
                  final EmvQrData? result = await _tappa.processQrForResult(qrData);
                  if (result != null) {
                    print('QR Processed: ${result.pan}');
                  } else {
                    _showSnackBar('Failed to process QR');
                  }
                } catch (e) {
                  _showSnackBar('Error: $e');
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Flutter Tappa Example'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _scanQrAndProcess,
        tooltip: 'Scan QR and Process',
        child: const Icon(Icons.qr_code_scanner),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status: $_statusMessage',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isInitialized ? null : _initializeTappa,
                      child: const Text('Initialize Tappa SDK'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Terminal Configuration',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _terminalIdController,
                      decoration: const InputDecoration(
                        labelText: 'Terminal ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _uniqueIdController,
                      decoration: const InputDecoration(
                        labelText: 'Unique ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _clientIdController,
                      decoration: const InputDecoration(
                        labelText: 'Client ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _merchantLocationController,
                      decoration: const InputDecoration(
                        labelText: 'Merchant Location',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isInitialized ? _initTerminal : null,
                      child: const Text('Initialize Terminal'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Transaction Settings',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      decoration: const InputDecoration(
                        labelText: 'Amount (in minor units)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _accountTypeController,
                      decoration: const InputDecoration(
                        labelText: 'Account Type',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _rrnController,
                      decoration: const InputDecoration(
                        labelText: 'RRN',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isInitialized ? _startTransaction : null,
                      child: const Text('Start Transaction'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Loyalty Card',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isInitialized ? _readLoyaltyCard : null,
                      child: const Text('Read Loyalty Card'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}