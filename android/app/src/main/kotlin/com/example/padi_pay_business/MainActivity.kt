package com.example.padi_pay_business

import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.nfc.NfcAdapter
import android.view.WindowManager
import com.qoreid.qoreidsdk.QoreidsdkPlugin

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "com.padipay/tappa_nfc"
    private val SECURE_CHANNEL = "com.padipay/screen_secure"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Initialize QoreID native plugin (your existing code)
        QoreidsdkPlugin.initialize(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ←←← NEW: MethodChannel to disable NFC reader mode from Dart
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "disableReaderMode") {
                val adapter = NfcAdapter.getDefaultAdapter(this)
                adapter?.disableReaderMode(this)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // MethodChannel to toggle Android FLAG_SECURE (prevent screenshots)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "secureOn" -> {
                        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "secureOff" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("error", e.message, null)
            }
        }
    }

    // ←←← NEW: Extra safety — disable NFC reader every time the app goes to background
    override fun onPause() {
        super.onPause()
        val adapter = NfcAdapter.getDefaultAdapter(this)
        adapter?.disableReaderMode(this)
    }
}