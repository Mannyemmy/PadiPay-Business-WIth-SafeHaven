package com.mba.flutter_tappa

import android.content.Context
import android.nfc.NfcAdapter
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import android.app.Activity
import com.mba.tappa.TappaAndroid
import com.mba.tappa.TappaAndroidImpl

/** FlutterTappaPlugin */
class FlutterTappaPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var activity: Activity? = null
    private lateinit var tappaAndroid: TappaAndroidImpl
    private var isSandBoxMode: Boolean = true

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_tappa")
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "com.mba.tappa/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                // Nothing to clean up
            }
        })
        context = flutterPluginBinding.applicationContext
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "initialize" -> {
                if (activity == null) {
                    result.error("ACTIVITY_NULL", "Activity is null, cannot initialize TappaAndroid", null)
                    return
                }

                val errorCallback = object : TappaAndroid.ErrorCallback {
                    override fun onError(errorCode: Int, errorMessage: String?) {
                        // Send error back to Flutter through an event channel
                        activity?.runOnUiThread {
                            val errorMap = mapOf(
                                "success" to false,
                                "errorCode" to errorCode,
                                "errorMessage" to errorMessage
                            )
                            channel.invokeMethod("onError", errorMap)
                        }
                    }
                }

                val loyaltyCardCallback = object : TappaAndroid.LoyaltyCardCallback {
                    override fun onLoyaltyCardData(data: String) {
                        // Send success response back to Flutter through event channel
                        activity?.runOnUiThread {
                            val resultMap = mapOf(
                                "success" to true,
                                "data" to data
                            )
                            eventSink?.success(resultMap)
                        }
                    }
                }

                tappaAndroid = TappaAndroidImpl()

                // Get sandbox mode from Flutter call arguments, default to true
                isSandBoxMode = call.argument<Boolean>("isSandBoxMode") ?: true

                // Fix: Call initialize with correct parameter order
                val success = tappaAndroid.initialize(
                    isSandBoxMode = isSandBoxMode,
                    activity = activity,
                    errorCallback = errorCallback,
                    loyaltyCardCallback = loyaltyCardCallback
                )
                result.success(success)
            }
            "initTerminal" -> {
                if (!::tappaAndroid.isInitialized) {
                    result.error("NOT_INITIALIZED", "TappaAndroid has not been initialized", null)
                    return
                }

                val terminalId = call.argument<String>("terminalId")
                val uniqueId = call.argument<String>("uniqueId")
                val clientId = call.argument<String>("clientId")
                val merchantLocation = call.argument<String>("merchantLocation")

                if (terminalId == null || uniqueId == null || clientId == null || merchantLocation == null) {
                    result.error("INVALID_ARGUMENTS", "Terminal parameters cannot be null", null)
                    return
                }

                try {
                    tappaAndroid.initTerminal(isSandBoxMode, terminalId, uniqueId, clientId, merchantLocation)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INIT_TERMINAL_ERROR", "Error initializing terminal: ${e.message}", null)
                }
            }
            "transact" -> {
                if (!::tappaAndroid.isInitialized) {
                    result.error("NOT_INITIALIZED", "TappaAndroid has not been initialized", null)
                    return
                }

                val amount = call.argument<String>("amount")
                val accountType = call.argument<String>("accountType")
                val rrn = call.argument<String>("rrn")

                if (amount == null || accountType == null || rrn == null) {
                    result.error("INVALID_ARGUMENTS", "Transaction parameters cannot be null", null)
                    return
                }

                try {
                    tappaAndroid.transact(amount, accountType, rrn)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("TRANSACT_ERROR", "Error initiating transaction: ${e.message}", null)
                }
            }
            "startReadingLoyaltyCard" -> {
                if (!::tappaAndroid.isInitialized) {
                    result.error("NOT_INITIALIZED", "TappaAndroid has not been initialized", null)
                    return
                }

                try {
                    tappaAndroid.readLoyaltyCard()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("LOYALTY_CARD_ERROR", "Error starting loyalty card reading: ${e.message}", null)
                }
            }
            "processQrForResult" -> {
                if (!::tappaAndroid.isInitialized) {
                    result.error("NOT_INITIALIZED", "TappaAndroid has not been initialized", null)
                    return
                }

                val qrData = call.argument<String>("qrData")
                if (qrData == null) {
                    result.error("INVALID_ARGUMENTS", "QR data cannot be null", null)
                    return
                }

                try {
                    val resultMap = tappaAndroid.processQrForResult(qrData)
                    result.success(resultMap)
                } catch (e: Exception) {
                    result.error("QR_PROCESS_ERROR", "Error processing QR code: ${e.message}", null)
                }
            }
            "processQrAndTransact" -> {
                if (!::tappaAndroid.isInitialized) {
                    result.error("NOT_INITIALIZED", "TappaAndroid has not been initialized", null)
                    return
                }

                val qrData = call.argument<String>("qrData")
                val amount = call.argument<String>("amount")
                val accountType = call.argument<String>("accountType")
                val rrn = call.argument<String>("rrn")

                if (qrData == null || amount == null || accountType == null || rrn == null) {
                    result.error("INVALID_ARGUMENTS", "QR data and transaction parameters cannot be null", null)
                    return
                }

                try {
                    tappaAndroid.processQrAndTransact(amount, accountType, rrn, qrData)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("QR_TRANSACT_ERROR", "Error processing QR and performing transaction: ${e.message}", null)
                }
            }

            "armTagDetection" -> {
                val amount = call.argument<String>("amount") ?: ""
                val accountType = call.argument<String>("accountType") ?: ""
                val rrn = call.argument<String>("rrn") ?: ""

                val nfcAdapter = NfcAdapter.getDefaultAdapter(context)
                val act = activity

                if (nfcAdapter == null || act == null || !::tappaAndroid.isInitialized) {
                    result.success(false)
                    return
                }

                // Override Tappa's reader mode with our wrapper.
                // When tag is detected: notify Flutter, then re-arm Tappa on main thread
                // so the card (still present) is picked up and processed normally.
                nfcAdapter.enableReaderMode(
                    act,
                    { _ ->
                        act.runOnUiThread {
                            eventSink?.success(mapOf("event" to "tag_detected"))
                        }
                        Handler(Looper.getMainLooper()).postDelayed({
                            try {
                                if (::tappaAndroid.isInitialized) {
                                    tappaAndroid.transact(amount, accountType, rrn)
                                }
                            } catch (e: Exception) {
                                android.util.Log.e("TappaWrapper", "Re-arm transact failed: ${e.message}")
                            }
                        }, 100L)
                    },
                    NfcAdapter.FLAG_READER_NFC_A or
                    NfcAdapter.FLAG_READER_NFC_B or
                    NfcAdapter.FLAG_READER_NFC_F or
                    NfcAdapter.FLAG_READER_NFC_V or
                    NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,
                    null
                )
                result.success(true)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
