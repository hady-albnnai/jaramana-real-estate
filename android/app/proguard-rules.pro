# ════════════════════════════════════════════════════════
# ProGuard / R8 rules — المكتب العقاري الالكتروني - جرمانا
# تُطبَّق مع isMinifyEnabled = true في buildTypes.release
# ════════════════════════════════════════════════════════

# ── Flutter ──
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# ── flutter_local_notifications ──
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Gson (تستخدمه بعض الإضافات) — حافظ على الأنواع العامة
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.google.gson.**

# ── image_picker / flutter_image_compress ──
-keep class androidx.lifecycle.** { *; }

# ── desugaring ──
-keep class j$.** { *; }
-dontwarn j$.**

# ── الحفاظ على أسماء النماذج (تجنّب كسر JSON serialization اليدوي) ──
# نماذجنا تستخدم Map يدوي وليست reflection، لكن نُبقيها احتياطاً:
-keep class com.hadyalbnnai.jaramanarealestate.** { *; }

# ── عام: لا تحذّر من الفئات الناقصة لمكتبات الطرف الثالث ──
-ignorewarnings
