# 📦 دليل البناء والنشر — عقارات السويداء

> دليل عملي خطوة بخطوة لبناء التطبيق ونشره على Android و iOS.
> **مهم:** أوامر البناء (`flutter build`) تُنفَّذ على جهازك المحلي، وليست ضمن البيئة السحابية.

---

## 0. المتطلبات

```bash
flutter --version        # تأكد من Flutter (channel stable)
flutter doctor           # يجب أن تكون كل البنود ✔
```
- Flutter SDK ‏3.x ، Dart ‏3.x
- Android: JDK 17 + Android SDK (compileSdk 36)
- iOS: Xcode حديث + حساب Apple Developer (للنشر)

---

## 1. تجهيز المشروع

```bash
git clone https://github.com/hady-albnnai/sweeda-real-estate-office-elc.git
cd sweeda-real-estate-office-elc
flutter pub get
flutter analyze          # يجب أن يمر دون أخطاء
flutter test             # (إن وُجدت اختبارات)
```

> **ملاحظة:** أُضيفت تبعية `path_provider` في المرحلة 4، لذا `flutter pub get` ضروري.

---

## 2. رفع الإصدار (Versioning)

عدّل في `pubspec.yaml`:
```yaml
version: 1.0.0+2     # الصيغة: versionName+versionCode
```
- `versionName` (1.0.0): يظهر للمستخدم.
- `versionCode` (2): رقم صحيح **يجب زيادته** مع كل رفع لمتجر Google.

---

## 3. 🤖 بناء Android

### 3.1 إنشاء مفتاح التوقيع (مرة واحدة)
```bash
keytool -genkey -v -keystore ~/sweeda-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias sweeda
```
احفظ كلمات المرور في مكان آمن — فقدانها يعني عدم القدرة على تحديث التطبيق لاحقاً.

### 3.2 إنشاء `android/key.properties` (لا يُرفع للمستودع)
```properties
storePassword=كلمة_مرور_المخزن
keyPassword=كلمة_مرور_المفتاح
keyAlias=sweeda
storeFile=/المسار/المطلق/إلى/sweeda-release.jks
```
> الملف مُستثنى في `.gitignore`. إعداد Gradle يقرأه تلقائياً ويستخدم توقيع release؛ وإن لم يوجد، يقع على توقيع debug حتى لا يتعطّل التطوير.

### 3.3 البناء
```bash
# APK (للتثبيت المباشر / التوزيع خارج المتجر)
flutter build apk --release

# App Bundle (المطلوب لرفع Google Play)
flutter build appbundle --release

# (اختياري) تقسيم APK حسب المعمارية لتصغير الحجم
flutter build apk --release --split-per-abi
```
المخرجات:
- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

### 3.4 ملاحظات Android المطبّقة في هذا المشروع
- `applicationId = com.sweeda.realestate`
- `minSdk = 24` ، `targetSdk = 36`
- تم **إزالة Firebase/google-services** (المشروع يعتمد Supabase) لتفادي فشل البناء.
- `isMinifyEnabled = true` + `proguard-rules.pro` (محفوظة قواعد Flutter والإشعارات).
- الأذونات في `AndroidManifest.xml`: إنترنت، إشعارات، وسائط (صور)، SMS (لـ OTP).

---

## 4. 🍎 بناء iOS

```bash
cd ios && pod install && cd ..
flutter build ios --release          # ثم الأرشفة عبر Xcode
# أو إنشاء IPA مباشرة:
flutter build ipa --release
```
ثم في Xcode: **Product → Archive → Distribute App → App Store Connect / TestFlight**.

### ملاحظات iOS المطبّقة
- `PRODUCT_BUNDLE_IDENTIFIER = com.sweeda.realestate`
- أذونات `Info.plist`: مكتبة الصور، الكاميرا، حفظ الصور (بوصف عربي).
- اللغة الافتراضية `ar` + دعم `en`.
- يتطلب التوقيع: حساب Apple Developer + Provisioning Profile (في Xcode → Signing & Capabilities).

---

## 5. 🗄️ السيرفر (Supabase)

السيرفر جاهز ومُوثّق. لإعداد مشروع Supabase جديد:
1. نفّذ `supabase/setup.sql` بالكامل في SQL Editor (13 جدول + 12 دالة + RLS + Config).
2. أنشئ Storage bucket باسم `offer_images` (Public).
3. حدّث `supabaseUrl` و `supabaseAnonKey` في `lib/main.dart` و `lib/app.dart`.
4. راجع `docs/SECURITY_REVIEW.md` وطبّق ترقيات RLS الإدارية قبل الإطلاق.

> راجع `supabase/FUNCTIONS_REFERENCE.md` لتفاصيل الدوال.

---

## 6. ✅ قائمة تحقق ما قبل النشر

- [ ] `flutter analyze` يمر دون أخطاء
- [ ] رفع `versionCode` في `pubspec.yaml`
- [ ] keystore الإنتاج جاهز + `key.properties` (غير مرفوع)
- [ ] اختبار على جهاز حقيقي (تسجيل دخول OTP، نشر عرض، حجز موعد، إشعارات)
- [ ] تطبيق ترقيات RLS من `docs/SECURITY_REVIEW.md`
- [ ] أيقونة التطبيق النهائية + Splash native (اختياري: `flutter_launcher_icons`)
- [ ] لقطات شاشة + وصف للمتجر (عربي)
- [ ] سياسة خصوصية (مطلوبة لمتجري Google/Apple)
- [ ] تدوير أي توكن/مفتاح استُخدم أثناء التطوير

---

## 7. 🧪 أوامر مفيدة

```bash
flutter clean && flutter pub get     # تنظيف عند مشاكل البناء
flutter build apk --release --verbose # تتبّع أخطاء البناء
flutter install                      # تثبيت على جهاز موصول
flutter logs                         # عرض السجلّات
```

---

## 8. ⚠️ مشاكل شائعة وحلولها

| المشكلة | الحل |
|---|---|
| `File google-services.json is missing` | تم حلّه: أُزيل google-services من Gradle. لو عاد الخطأ تأكد من `settings.gradle.kts` و `app/build.gradle.kts`. |
| فشل التوقيع release | تأكد من صحّة مسارات وكلمات مرور `key.properties`. |
| `Execution failed for task ':app:minifyReleaseWithR8'` | أضف قاعدة keep للمكتبة المتأثرة في `proguard-rules.pro`. |
| رفض أذونات الصور على iOS | تأكد من مفاتيح `NSPhotoLibraryUsageDescription`/`NSCameraUsageDescription`. |
| الإشعارات لا تظهر (Android 13+) | يُطلب إذن `POST_NOTIFICATIONS` وقت التشغيل. |
