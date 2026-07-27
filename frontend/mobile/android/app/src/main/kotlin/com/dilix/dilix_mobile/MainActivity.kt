package com.dilix.dilix_mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// ⚠ عمداً FlutterFragmentActivity و نه FlutterActivity: پلاگینِ local_auth از
// androidx BiometricPrompt استفاده می‌کند که فقط روی یک FragmentActivity اجرا
// می‌شود. با FlutterActivity پرسشِ اثرِ انگشت در زمانِ اجرا با
// «no_fragment_activity» شکست می‌خورد. CI این فایل را از نو می‌سازد، پس همین
// تغییر در `.github/workflows/mobile.yml` هم تکرار شده است.
class MainActivity : FlutterFragmentActivity()
