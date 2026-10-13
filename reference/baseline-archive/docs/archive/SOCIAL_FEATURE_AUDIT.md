# 🔍 تقرير تدقيق ميزة النشر على السوشال ميديا

> تاريخ التدقيق: 2026-07-13
> الحالة: ❌ يوجد 9 أخطاء — 3 حرجة + 3 متوسطة + 3 خفيفة

---

## 🔴 الأخطاء الحرجة (Critical)

### ❌ BUG #1: اسم الإجراء غير متطابق — الميزة لا تعمل إطلاقاً!

**الملف**: `lib/core/services/business_service.dart` (سطر 424)

```dart
// Flutter يرسل:
'action': 'social_published',  // ❌ خطأ!

// لكن user-offers Edge Function يتوقع:
if (action === "mark_social_published") {  // ✅ الاسم الصحيح
```

**النتيجة**: عندما يضغط المستخدم "نشر على وسائل التواصل"، الـ Edge Function ما رح يتعرف على الإجراء ويرجع `UNKNOWN_ACTION`. الميزة **معطّلة بالكامل**.

**الحل**: تغيير `'social_published'` → `'mark_social_published'` في `business_service.dart`

---

### ❌ BUG #2: لا يوجد نشر تلقائي فعلي — فقط فتح شريط المشاركة

الميزة الحالية فقط:
1. تولّد نص ← `generateSocialPost()`
2. تفتح شريط المشاركة الأصلي ← `SharePlus.instance.share()`
3. تعلّم `soc_pub = 1` في الداتابيز

**لا يوجد أي اتصال بـ Facebook أو Instagram API!** المستخدم لازم ينسخ النص يدوياً وينشره. هذا مو "نشر تلقائي".

**اللي لازم يتضاف**:
- Edge Function جديد `social-publish` يتصل بـ Meta Graph API
- يرسل المنشور مباشرة لصفحة فيس بوك + حساب انستغرام تجاري
- التوكنز محفوظة بـ `app_config`

---

### ❌ BUG #3: لا يوجد منع تكرار المشاركة — استغلال النقاط

المستخدم يقدر يضغط "نشر على وسائل التواصل" 100 مرة ويحصل على 100 نقطة كل مرة!

```dart
// في _shareAndMark() — لا يوجد فحص إذا كان socPub == 1
await BusinessService().markSocialPublished(...);
await BusinessService().awardEvent(..., 'soc', fallback: 100);  // كل مرة!
```

والـ SQL كمان ما يمنع:
```sql
-- mark_social_published_internal: دائماً يضع soc_pub = 1 بدون فحص
UPDATE offers SET soc_pub = 1, soc_txt = COALESCE(p_text, '')
```

**الحل**: 
1. Flutter: فحص `if (_offer!.socPub == 1)` قبل إظهار الزر أو منح النقاط
2. SQL: إضافة فحص `AND soc_pub = 0` في الـ UPDATE + التحقق من FOUND

---

## 🟡 الأخطاء المتوسطة (Medium)

### ⚠️ BUG #4: النقاط تُمنح حتى لو فشل تعليم النشر

```dart
// في _shareAndMark():
await BusinessService().markSocialPublished(...);  // ممكن يرجع false
// ❌ ما في فحص للنتيجة!
await BusinessService().awardEvent(...);  // دائماً يُنفّذ
```

**الحل**: التحقق من قيمة الإرجاع:
```dart
final marked = await BusinessService().markSocialPublished(...);
if (marked) {
  await BusinessService().awardEvent(...);
}
```

---

### ⚠️ BUG #5: كشف نجاح المشاركة غير موثوق

```dart
if (result.status == ShareResultStatus.success) {
```

على أندرويد، `SharePlus` غالباً يرجع `ShareResultStatus.unavailable` حتى لو المستخدم شارك فعلياً. على iOS السلوك مختلف.

**النتيجة**: 
- على أندرويد: النقاط **ما رح تُمنح أبداً** رغم إنو المستخدم شارك
- على iOS: ممكن تُمنح حتى لو ما شارك

**الحل**: بدل الاعتماد على `result.status`، نعتمد على تعليم النشر من الـ Edge Function (لما يكون في نشر تلقائي حقيقي). مؤقتاً، نحسب المشاركة ناجحة إذا ما رمى استثناء.

---

### ⚠️ BUG #6: تنفيذ مكرّر في Edge Function

نفس الوظيفة موجودة باثنين:

| الملف | الإجراء |
|-------|---------|
| `user-offers/index.ts` | `mark_social_published` → يطلب `mark_social_published_internal` |
| `user-rewards/index.ts` | `social_published` → يطلب `mark_social_published_internal` |

الـ Flutter يرسل لـ `user-offers` بس. اللي بـ `user-rewards` مو مستخدم.

**الحل**: إزالة `social_published` من `user-rewards` لأنه مكرّر ومو مستخدم.

---

## 🟢 الأخطاء الخفيفة (Minor)

### 💡 BUG #7: حقل `i_soc` غير مستخدم

جدول `offers` فيه حقل `i_soc` (0 أو 1) يبدو إنو مفروض يكون "تفعيل النشر التلقائي"، لكنه:
- دائماً بيساوي 0
- ما في أي كود يقرأه أو يكتبه
- غير مستخدم بأي شاشة

**الحل**: لما نضيف النشر التلقائي، نستعمل `i_soc = 1` كعلم "هاد العرض مفعّل فيه النشر التلقائي" ونعطي المستخدم خيار تفعيله عند إنشاء العرض.

---

### 💡 BUG #8: `matching_offers_screen` يستخدم API قديم

```dart
// matching_offers_screen.dart سطر 585
await Share.share(text, subject: offer.ttl);  // ❌ API قديم
```

بدل:
```dart
await SharePlus.instance.share(ShareParams(text: text, subject: offer.ttl));  // ✅ API جديد
```

كمان ما بيعطي نقاط ولا يعلم النشر.

---

### 💡 BUG #9: `generateSocialPost` لا يولّد رابط صورة

الانستغرام **لا ينشر نص فقط** — لازم صورة. الدالة `generateSocialPost` بترجع نص بس بدون أي رابط صورة.

كمان فيس بوك أفضل بمنشور فيه صورة مرفقة.

**الحل**: الدالة لازم ترجع كائن `{text, imageUrl}` مو بس نص. `imageUrl` يكون أول صورة من `offer.imgs`.

---

## 🔒 مشكلة أمنية: صلاحيات `mark_social_published_internal`

على السيرفر الحالي:
```sql
-- الـ migration اللي اننفذ (2026_06_12):
GRANT EXECUTE ON FUNCTION mark_social_published_internal(UUID, UUID, TEXT) TO anon, authenticated;
```

هاد يعني أي مستخدم مسجّل يقدر يستدعي الدالة مباشرة عبر REST API بدون المرور بالـ Edge Function!

**ما فيه migration لسا يلغي هاد الصلاحية.**

**الحل**: إضافة migration:
```sql
REVOKE ALL ON FUNCTION mark_social_published_internal(UUID, UUID, TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION mark_social_published_internal(UUID, UUID, TEXT) TO service_role;
```

---

## 📊 ملخص

| # | الخطأ | الخطورة | حالة |
|---|-------|---------|------|
| 1 | اسم الإجراء غير متطابق | 🔴 حرج | يكسر الميزة بالكامل |
| 2 | لا نشر تلقائي فعلي | 🔴 حرج | ميزة مفقودة |
| 3 | لا منع تكرار المشاركة | 🔴 حرج | استغلال نقاط |
| 4 | نقاط رغم فشل التعليم | 🟡 متوسط | منطق خاطئ |
| 5 | كشف نجاح المشاركة غير موثوق | 🟡 متوسط | نقاط لا تُمنح على أندرويد |
| 6 | تنفيذ مكرّر بـ user-rewards | 🟡 متوسط | كود ميت |
| 7 | حقل i_soc غير مستخدم | 🟢 خفيف | ميزة ناقصة |
| 8 | API قديم بـ matching_offers | 🟢 خفيف | توافقية |
| 9 | لا صورة بالمنشور | 🟢 خفيف | انستغرام يحتاج صورة |
| 🔒 | صلاحيات الدالة مفتوحة | 🔒 أمني | المستخدمين يقدروا يتجاوزوا Edge Function |

---

## 🛠️ خطة الإصلاح المقترحة

### المرحلة A: إصلاح الأخطاء الحرجة (بدون انتظار رفيقك)
1. إصلاح اسم الإجراء بـ `business_service.dart`
2. إضافة منع تكرار المشاركة (Flutter + SQL)
3. إصلاح منطق منح النقاط
4. إضافة migration لإلغاء صلاحيات anon/authenticated
5. إزالة الكود الميت من `user-rewards`
6. إصلاح API القديم بـ `matching_offers_screen`

### المرحلة B: إضافة النشر التلقائي الحقيقي (بعد ما رفيقك يجهّز الصفحات)
1. إنشاء Edge Function `social-publish`
2. إضافة إعدادات التوكنز بـ `app_config`
3. تعديل `generateSocialPost` ليرجع `{text, imageUrl}`
4. استخدام `i_soc` كعلم تفعيل النشر التلقائي
5. ربط الزر بالـ Edge Function بدل شريط المشاركة الأصلي
