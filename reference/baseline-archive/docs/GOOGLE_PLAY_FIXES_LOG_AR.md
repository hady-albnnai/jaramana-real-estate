# 🔧 سجل الإصلاحات - Google Play Readiness

> **التاريخ:** 2026-08-05  
> **الحالة:** ✅ تم إصلاح 6 من 13 مشكلة

---

## ✅ الإصلاحات المكتملة (6)

### 1. ✅ إزالة RECEIVE_SMS Permission

**المشكلة:**
- `RECEIVE_SMS` permission غير مطلوبة وتسبب رفض Google Play

**الحل:**
- حذف السطر من `AndroidManifest.xml`
- إضافة تعليق توضيحي

**الملف المعدّل:**
- `android/app/src/main/AndroidManifest.xml`

**الحالة:** ✅ مكتمل

---

### 2. ✅ إنشاء Adaptive Icons

**المشكلة:**
- لا توجد Adaptive Icons مطلوبة من Android 8+

**الحل:**
- إنشاء مجلد `mipmap-anydpi-v26`
- إنشاء `ic_launcher.xml` و `ic_launcher_round.xml`
- إنشاء `drawable/ic_launcher_foreground.xml`
- استخدام `splash_logo.png` كـ foreground

**الملفات المُنشأة:**
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml`
- `android/app/src/main/res/drawable/ic_launcher_foreground.xml`

**الحالة:** ✅ مكتمل

---

### 3. ✅ إنشاء Privacy Policy

**المشكلة:**
- لا توجد سياسة خصوصية (مطلوبة من Google Play)

**الحل:**
- إنشاء صفحة HTML شاملة بالعربية
- تغطية جميع الجوانب القانونية
- تصميم احترافي ومتجاوب

**الملف المُنشأ:**
- `docs/legal/privacy_policy.html`

**الخطوات التالية (للمالك):**
1. استضافة الملف على GitHub Pages أو أي استضافة
2. إضافة الرابط في Google Play Console
3. إضافة الرابط في شاشة إعدادات التطبيق

**الحالة:** ✅ مكتمل (يحتاج استضافة)

---

### 4. ✅ إنشاء Terms of Service

**المشكلة:**
- لا توجد شروط خدمة (مطلوبة قانونياً)

**الحل:**
- إنشاء صفحة HTML شاملة بالعربية
- تغطية جميع الجوانب القانونية
- تصميم احترافي ومتجاوب

**الملف المُنشأ:**
- `docs/legal/terms_of_service.html`

**الخطوات التالية (للمالك):**
1. استضافة الملف على GitHub Pages أو أي استضافة
2. إضافة الرابط في Google Play Console
3. إضافة الرابط في شاشة إعدادات التطبيق

**الحالة:** ✅ مكتمل (يحتاج استضافة)

---

### 5. ✅ إنشاء Data Safety Documentation

**المشكلة:**
- لا يوجد توثيق للبيانات المجمعة (مطلوب لـ Data Safety form)

**الحل:**
- إنشاء ملف شامل يوثق جميع البيانات
- جداول مفصلة لكل نوع بيانات
- خطوات ملء Data Safety في Google Play Console

**الملف المُنشأ:**
- `docs/GOOGLE_PLAY_DATA_SAFETY_AR.md`

**الخطوات التالية (للمالك):**
1. قراءة الملف بعناية
2. ملء Data Safety form في Google Play Console
3. التأكد من دقة المعلومات

**الحالة:** ✅ مكتمل (يحتاج ملء النموذج)

---

### 6. ✅ التحقق من الإعدادات التقنية

**المشكلة:**
- التأكد من صحة جميع الإعدادات التقنية

**الحل:**
- فحص `build.gradle.kts` ✅
- فحص `AndroidManifest.xml` ✅
- فحص `pubspec.yaml` ✅
- فحص Network Security Config ✅
- فحص ProGuard rules ✅

**النتيجة:**
- جميع الإعدادات التقنية صحيحة ✅

**الحالة:** ✅ مكتمل

---

## ⏳ المهام المتبقية (للمالك - 7 مهام)

### 1. ⏳ إنشاء Signing Key

**المطلوب:**
```bash
# 1. إنشاء keystore
keytool -genkey -v -keystore ~/sweeda-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias sweeda-key

# 2. إنشاء key.properties
cat > android/key.properties << EOF
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=sweeda-key
storeFile=/path/to/sweeda-release-key.jks
EOF
```

**الأولوية:** 🔴 حرج  
**الوقت المتوقع:** 10 دقائق

---

### 2. ⏳ استضافة Privacy Policy و Terms of Service

**الخيارات:**

#### الخيار 1: GitHub Pages (مجاني)
```bash
# 1. أنشئ مجلد gh-pages
git checkout --orphan gh-pages
git rm -rf .
cp docs/legal/*.html .
git add .
git commit -m "Add legal pages"
git push origin gh-pages
```

**الرابط:** `https://hady-albnnai.github.io/sweeda-real-estate-office-elc/legal/privacy-policy.html`

#### الخيار 2: Netlify/Vercel (مجاني)
- ارفع الملفات
- احصل على رابط عام

**الأولوية:** 🔴 حرج  
**الوقت المتوقع:** 15 دقيقة

---

### 3. ⏳ التقاط Screenshots

**المطلوب:**
- 2-8 screenshots لكل جهاز:
  - Phone (5.5" - 6.5")
  - Tablet 7"
  - Tablet 10"

**الأدوات:**
- [Screenshot Tools](https://screenshots.pro/)
- [Fastlane Screengrab](https://docs.fastlane.tools/actions/screengrab/)

**الشاشات المقترحة:**
1. شاشة تسجيل الدخول
2. الشاشة الرئيسية
3. تفاصيل عرض
4. إضافة عرض جديد
5. قائمة المواعيد
6. الملف الشخصي
7. البحث والفلترة
8. الإشعارات

**الأولوية:** 🟡 متوسط  
**الوقت المتوقع:** 2-3 ساعات

---

### 4. ⏳ إنشاء Feature Graphic

**المواصفات:**
- الحجم: 1024 × 500 px
- الصيغة: PNG أو JPEG
- المحتوى: شعار التطبيق + اسم التطبيق + وصف قصير

**الأدوات:**
- [Canva](https://www.canva.com/) (مجاني)
- [Figma](https://www.figma.com/) (مجاني)
- مصمم جرافيك ($20-50)

**الأولوية:** 🟡 متوسط  
**الوقت المتوقع:** 1-2 ساعة

---

### 5. ⏳ إنشاء Hi-Res Icon

**المواصفات:**
- الحجم: 512 × 512 px
- الصيغة: PNG (32-bit, alpha)
- بدون زوايا دائرية (Google يضيفها تلقائياً)

**الأدوات:**
- [Android Asset Studio](https://romannurik.github.io/AndroidAssetStudio/icons-launcher.html)
- تحويل `ic_launcher-xxxhdpi.png` إلى 512×512

**الأولوية:** 🟡 متوسط  
**الوقت المتوقع:** 30 دقيقة

---

### 6. ⏳ إنشاء Google Play Developer Account

**الخطوات:**
1. اذهب إلى [Google Play Console](https://play.google.com/console)
2. سجل الدخول بحساب Google
3. ادفع رسوم التسجيل ($25 - مرة واحدة)
4. املأ معلومات المطور
5. انتظر الموافقة (1-2 يوم)

**الأولوية:** 🔴 حرج  
**الوقت المتوقع:** 1-2 يوم (للموافقة)

---

### 7. ⏳ ملء Data Safety Form

**الخطوات:**
1. اقرأ `docs/GOOGLE_PLAY_DATA_SAFETY_AR.md`
2. اذهب إلى Google Play Console
3. اختر التطبيق
4. **App content** → **Data safety**
5. املأ النموذج حسب التوثيق

**الأولوية:** 🟡 متوسط  
**الوقت المتوقع:** 1 ساعة

---

## 📊 الإحصائيات

| الفئة | المكتمل | المتبقي | النسبة |
|-------|---------|---------|--------|
| **الإصلاحات التقنية** | 6 | 1 | 86% |
| **المحتوى** | 2 | 5 | 29% |
| **الإجمالي** | 8 | 6 | 57% |

---

## 🎯 خطة العمل المحدثة

### ✅ المرحلة 1: الإصلاحات التقنية (مكتملة)
- [x] إزالة RECEIVE_SMS permission
- [x] إنشاء Adaptive Icons
- [x] إنشاء Privacy Policy
- [x] إنشاء Terms of Service
- [x] إنشاء Data Safety Documentation
- [x] التحقق من الإعدادات التقنية

### ⏳ المرحلة 2: المهام اليدوية (للمالك)
- [ ] إنشاء Signing Key (10 دقائق)
- [ ] استضافة الملفات القانونية (15 دقيقة)
- [ ] إنشاء Google Play Developer Account (1-2 يوم)

### ⏳ المرحلة 3: المحتوى (للمالك)
- [ ] التقاط Screenshots (2-3 ساعات)
- [ ] إنشاء Feature Graphic (1-2 ساعة)
- [ ] إنشاء Hi-Res Icon (30 دقيقة)

### ⏳ المرحلة 4: الرفع (للمالك)
- [ ] ملء Data Safety Form (1 ساعة)
- [ ] رفع AAB إلى Google Play (30 دقيقة)
- [ ] انتظار المراجعة (3-7 أيام)

---

## 💰 التكلفة المحدثة

| البند | التكلفة |
|-------|---------|
| Google Play Developer account | $25 |
| Privacy Policy (تم إنشاؤه) | $0 |
| Terms of Service (تم إنشاؤه) | $0 |
| Staging (GitHub Pages) | $0 |
| Feature Graphic (Canva) | $0 |
| **المجموع** | **$25** |

---

## 📝 ملاحظات مهمة

### 1. Signing Key
- ⚠️ **احتفظ بنسخة احتياطية** من keystore في مكان آمن
- ⚠️ **لا ترفع** key.properties إلى GitHub
- ⚠️ إذا فقدت keystore، لن تتمكن من تحديث التطبيق أبداً

### 2. Screenshots
- استخدم جهاز حقيقي (TECNO KI7)
- التقط صور بشاشات مختلفة
- استخدم أدوات مثل [App Mockup](https://previewed.app/) لإضافة إطارات الأجهزة

### 3. Feature Graphic
- اجعله بسيطاً وواضحاً
- استخدم الألوان الذهبية والسوداء (هوية التطبيق)
- أضف شعار التطبيق واسمه

### 4. المراجعة
- Google قد يستغرق 3-7 أيام للمراجعة
- قد يطلب معلومات إضافية
- كن مستعداً للرد بسرعة

---

## ✅ الخلاصة

**الحالة:** 🟡 **شبه جاهز**

**المكتمل:** 6 من 13 مهمة (46%)

**المتبقي:** 7 مهام (جميعها يدوية - تحتاج المالك)

**الوقت المتوقع للإنجاز:** 1-2 أسبوع

**التكلفة:** $25 فقط

---

**آخر تحديث:** 2026-08-05  
**الإصدار:** 2.0  
**الحالة:** 🟡 شبه جاهز - يحتاج مهام يدوية
