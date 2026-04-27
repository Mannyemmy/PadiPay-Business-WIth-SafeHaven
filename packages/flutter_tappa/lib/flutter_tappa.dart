import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tappa/loyalty_response.dart';

import 'EmvQrData.dart';

/// Callback for handling errors from the Tappa SDK
typedef TappaErrorCallback = void Function(int errorCode, String errorMessage);

/// Callback for handling loyalty card data from the Tappa SDK
typedef TappaLoyaltyCardCallback = void Function(String data);

/// Callback fired when a card is detected (before full read completes)
typedef TappaTagDetectedCallback = void Function();

/// FlutterTappa provides access to the Tappa NFC payment SDK for Android.
class FlutterTappa {
  static const MethodChannel _channel = MethodChannel('flutter_tappa');
  static const EventChannel _eventChannel = EventChannel('com.mba.tappa/events');

  /// Error callback for handling errors from the SDK
  TappaErrorCallback? _errorCallback;

  /// Loyalty card callback for handling loyalty card data from the SDK
  TappaLoyaltyCardCallback? _loyaltyCardCallback;

  /// Tag detected callback — fires when a card first touches the NFC reader
  TappaTagDetectedCallback? _tagDetectedCallback;

  /// Singleton instance
  static final FlutterTappa _instance = FlutterTappa._internal();

  /// Factory constructor that returns the singleton instance
  factory FlutterTappa() => _instance;

  /// Private constructor for singleton pattern
  FlutterTappa._internal() {
    _channel.setMethodCallHandler(_handleMethodCall);
    _setupEventChannelListener();
  }

  /// Sets up the event channel listener for loyalty card data and tag events
  void _setupEventChannelListener() {
    _eventChannel.receiveBroadcastStream().listen(
          (event) {
        if (event is Map) {
          if (event['event'] == 'tag_detected') {
            // NFC card first touched — single-fire
            final cb = _tagDetectedCallback;
            _tagDetectedCallback = null;
            cb?.call();
            return;
          }
          if (event['success'] == true && event['data'] != null) {
            // Loyalty card data
            _loyaltyCardCallback?.call(event['data']);
          }
        }
      },
      onError: (error) {
        debugPrint('Event channel error: $error');
      },
    );
  }

  /// Handles method calls from the native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onError':
        final Map<dynamic, dynamic> args = call.arguments;
        final int errorCode = args['errorCode'];
        final String errorMessage = args['errorMessage'];
        _errorCallback?.call(errorCode, errorMessage);
        break;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'Method ${call.method} not implemented',
        );
    }
  }

  /// Initializes the Tappa SDK.
  ///
  /// This must be called before any other methods.
  /// [errorCallback] will be invoked when errors occur in the SDK.
  /// [loyaltyCardCallback] will be invoked when loyalty card data is received.
  /// [isSandBoxMode] sets the payment environment - true for sandbox (default), false for production.
  ///
  /// Returns true if initialization was successful, false otherwise.
  Future<bool> initialize({
    required TappaErrorCallback errorCallback,
    TappaLoyaltyCardCallback? loyaltyCardCallback,
    bool isSandBoxMode = true,
  }) async {
    _errorCallback = errorCallback;
    _loyaltyCardCallback = loyaltyCardCallback;

    try {
      final bool result = await _channel.invokeMethod('initialize', {
        'isSandBoxMode': isSandBoxMode,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Error initializing Tappa: ${e.message}');
      return false;
    }
  }

  Stream<LoyaltyCardResult>? _loyaltyCardStream;

  /// Create a stream for loyalty card results
  ///
  /// Note: This stream is for structured LoyaltyCardResult objects.
  /// For raw loyalty card data, use the loyaltyCardCallback in initialize().
  Stream<LoyaltyCardResult> get loyaltyCardStream {
    _loyaltyCardStream ??= _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is Map && event['success'] == true)
        .map((event) => LoyaltyCardResult.fromMap(event));
    return _loyaltyCardStream!;
  }

  /// Start the loyalty card reading process
  Future<bool> startReadingLoyaltyCard() async {
    try {
      final result = await _channel.invokeMethod('startReadingLoyaltyCard');
      return result as bool;
    } on PlatformException catch (e) {
      debugPrint('Error starting loyalty card reading: ${e.message}');
      return false;
    }
  }

  /// Initializes the terminal with merchant and identification details.
  ///
  /// [terminalId] Terminal ID (TID) for transaction processing.
  /// [uniqueId] Unique identifier (UID) for the terminal.
  /// [clientId] Client identifier for authentication.
  /// [merchantLocation] Location description of the merchant.
  ///
  /// Throws a [PlatformException] if an error occurs.
  Future<void> initTerminal({
    required String terminalId,
    required String uniqueId,
    required String clientId,
    required String merchantLocation,
  }) async {
    try {
      await _channel.invokeMethod('initTerminal', {
        'terminalId': terminalId,
        'uniqueId': uniqueId,
        'clientId': clientId,
        'merchantLocation': merchantLocation,
      });
    } on PlatformException catch (e) {
      debugPrint('Error initializing terminal: ${e.message}');
      rethrow;
    }
  }

  /// Starts a payment transaction using NFC.
  ///
  /// [amount] Transaction amount in minor currency units (e.g., cents).
  /// [accountType] Account type for the transaction (e.g., "10" for savings, "20" for checking).
  /// [rrn] Retrieval Reference Number for the transaction.
  ///
  /// Throws a [PlatformException] if an error occurs.
  Future<void> transact({
    required String amount,
    required String accountType,
    required String rrn,
  }) async {
    try {
      await _channel.invokeMethod('transact', {
        'amount': amount,
        'accountType': accountType,
        'rrn': rrn,
      });
    } on PlatformException catch (e) {
      debugPrint('Error in transaction: ${e.message}');
      rethrow;
    }
  }

  /// Arms NFC tag detection by temporarily overriding Tappa's reader mode.
  ///
  /// When a card is detected, [onTagDetected] fires BEFORE reading completes,
  /// then Tappa is re-armed so it processes the card normally.
  /// Call this immediately after [transact] to get a card-detected signal.
  Future<bool> armTagDetection({
    required String amount,
    required String accountType,
    required String rrn,
    TappaTagDetectedCallback? onTagDetected,
  }) async {
    _tagDetectedCallback = onTagDetected;
    try {
      final result = await _channel.invokeMethod('armTagDetection', {
        'amount': amount,
        'accountType': accountType,
        'rrn': rrn,
      });
      return result as bool? ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error arming tag detection: ${e.message}');
      _tagDetectedCallback = null;
      return false;
    }
  }

  /// Processes a QR code and returns the parsed EMV transaction data.
  ///
  /// The QR code should be in a format compatible with the EMV parsing logic
  /// implemented in the native layer. This method sends the QR code string
  /// to the Android native code, which parses it and returns a map of EMV
  /// fields. These are then converted into an [EmvQrData] object.
  ///
  /// [qrData] The base64-encoded TLV QR code string to be parsed.
  ///
  /// Returns an [EmvQrData] object containing the transaction details,
  /// or `null` if an error occurred or parsing failed.
  Future<EmvQrData?> processQrForResult(String qrData) async {
    try {
      final Map<dynamic, dynamic> result = await _channel.invokeMethod(
        'processQrForResult',
        {'qrData': qrData},
      );
      return result.isNotEmpty ? EmvQrData.fromMap(result) : null;
    } on PlatformException catch (e) {
      debugPrint('Error processing QR for result: ${e.message}');
      return null;
    }
  }

  /// Processes the QR data and performs an EMV transaction in a single operation.
  ///
  /// This function decodes the QR code, extracts EMV transaction data, and initiates a transaction
  /// with the provided parameters.
  ///
  /// [amount] The transaction amount in minor currency units (e.g., cents).
  /// [accountType] The account type code (e.g., "10" for savings, "20" for checking).
  /// [rrn] The Retrieval Reference Number associated with the transaction.
  /// [qrData] The raw QR code string containing base64-encoded TLV EMV data.
  ///
  /// Returns a map containing parsed EMV transaction fields if successful, or null on failure.
  ///
  /// Throws IllegalArgumentException if any parameter is invalid or the QR data is malformed.
  /// Throws Exception for unexpected errors during processing or transaction execution.
  Future<EmvQrData?> processQrAndTransact({
    required String qrData,
    required String amount,
    required String accountType,
    required String rrn,
  }) async {
    try {
      final Map<dynamic, dynamic> result = await _channel.invokeMethod(
        'processQrAndTransact',
        {
          'qrData': qrData,
          'amount': amount,
          'accountType': accountType,
          'rrn': rrn,
        },
      );
      return result.isNotEmpty ? EmvQrData.fromMap(result) : null;
    } on PlatformException catch (e) {
      debugPrint('Error processing QR and transacting: ${e.message}');
      return null;
    }
  }

  /// Clears the registered callbacks (useful for cleanup)
  void clearCallbacks() {
    _errorCallback = null;
    _loyaltyCardCallback = null;
  }
}