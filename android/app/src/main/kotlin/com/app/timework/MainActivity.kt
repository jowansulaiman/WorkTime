package com.app.timework

// FlutterFragmentActivity statt FlutterActivity: von local_auth (Biometrie-
// App-Lock, Plan-Entscheidung E2/S5) vorausgesetzt, damit der BiometricPrompt
// einen FragmentActivity-Host bekommt.
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
