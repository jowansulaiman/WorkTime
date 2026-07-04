package com.app.timework

import android.view.WindowManager
// FlutterFragmentActivity statt FlutterActivity: von local_auth (Biometrie-
// App-Lock, Plan-Entscheidung E2/S5) vorausgesetzt, damit der BiometricPrompt
// einen FragmentActivity-Host bekommt.
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    // Screenshot-/Recents-Schutz fuer sensible Inhalte (Passwortmanager PM-S10):
    // FLAG_SECURE blockiert Screenshots und verbirgt den Inhalt in der
    // App-Uebersicht. Wird vom Dart-Helper `ScreenSecurity` getoggelt.
    private val screenSecurityChannel = "worktime/screen_security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            screenSecurityChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE,
                    )
                    result.success(true)
                }
                "disable" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
