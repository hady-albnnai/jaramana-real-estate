# 📋 خطة تنفيذ نظام الاستشارة القانونية (محادثة داخل التطبيق)

**التاريخ:** 2026-08-12  
**الحالة:** 📝 خطة (بانتظار الموافقة النهائية)  
**التقدير:** ~5 ساعات عمل

---

## 📊 الوضع الحالي

### ✅ الموجود:
- جدول `legal_consultations` (user_uid, lawyer_uid, service_type, subject, price, status)
- Edge Function `legal-actions` بـ 4 actions: `book_consultation`, `list_my_consultations`, `get_lawyer_consultations`, `update_consultation_status`
- شاشة `legal_consultation_booking_screen.dart` (اختيار خدمة + موضوع + دفع)
- لوحة المحامي `lawyer_dashboard_screen.dart` (1116 سطر — تبويب الاستشارات موجود)
- دالة ضغط الصور `StorageService.compressImage()` (quality: 50%)
- FCM Push Notifications (مفعّل)
- Supabase Realtime (متاح)
- Storage buckets (متاحة)

### ❌ المفقود:
- نظام المحادثة (Chat) — جدول + Edge + شاشة
- إرفاق مستندات في الاستشارة
- مؤقت 15 دقيقة
- Voice Notes
- إخفاء اسم المحامي
- شاشة شرح الآلية
- تنبيه الوقت المتأخر
- إعادة تفعيل الطلب

---

## 🏗️ خطة التنفيذ (6 مراحل)

---

### المرحلة 1: قاعدة البيانات (Migration SQL)

**الملف:** `supabase/migrations/2026_08_12_consultation_chat_system.sql`

#### 1.1 تعديل جدول `legal_consultations`

```sql
-- إضافة أعمدة جديدة
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS attachments TEXT[] DEFAULT '{}';
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS lawyer_alias TEXT DEFAULT '';
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS chat_started_at TIMESTAMPTZ;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS chat_duration_minutes INT DEFAULT 15;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS extended BOOLEAN DEFAULT FALSE;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS extended_by TEXT;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS reactivate_count INT DEFAULT 0;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS last_reactivate_at TIMESTAMPTZ;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS rating INT;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS rating_comment TEXT;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS converted_to_onsite BOOLEAN DEFAULT FALSE;
```

#### 1.2 إنشاء جدول `consultation_chats`

```sql
CREATE TABLE IF NOT EXISTS consultation_chats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id UUID NOT NULL REFERENCES legal_consultations(id),
  sender_id UUID NOT NULL REFERENCES users(id),
  message_type TEXT NOT NULL CHECK (message_type IN ('text', 'voice', 'image', 'system')),
  content TEXT NOT NULL DEFAULT '',
  file_url TEXT,
  file_name TEXT,
  duration_seconds INT, -- للملفات الصوتية
  is_read BOOLEAN DEFAULT FALSE,
  i_del INT DEFAULT 0,
  ts_crt TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_consultation_chats_consultation ON consultation_chats(consultation_id, ts_crt);
CREATE INDEX IF NOT EXISTS idx_consultation_chats_sender ON consultation_chats(sender_id);

-- RLS
ALTER TABLE consultation_chats ENABLE ROW LEVEL SECURITY;
-- المحامي والطالب يقرآن رسائل استشارتهما فقط
-- الإدراج عبر Edge Function فقط (service_role)
REVOKE ALL ON consultation_chats FROM anon, authenticated;
GRANT SELECT, INSERT ON consultation_chats TO service_role;
```

#### 1.3 Storage Bucket للملفات

```sql
-- bucket للملفات الصوتية والصور في الاستشارات
INSERT INTO storage.buckets (id, name, public) VALUES ('consultation_files', 'consultation_files', false)
ON CONFLICT (id) DO NOTHING;
```

---

### المرحلة 2: Edge Function — `legal-actions` (تعديل)

**الملف:** `supabase/functions/legal-actions/index.ts`

#### 2.1 تعديل action: `book_consultation`
- إضافة `attachments` (قائمة مسارات الصور المرفوعة)
- إضافة `lawyer_alias` = "محامي المكتب الأول/الثاني/الثالث" (حسب ترتيب المحامي)
- التحقق من الوقت (11م - 9ص) وإضافة تنويه في الرد
- تغيير الأسعار: 500 (هاتفية) + 2000 (حضورية) — حذف التوثيق الشامل
- حذف `service_type = 2` (باقة التوثيق)

#### 2.2 إضافة action: `reactivate_consultation`
- إذا مرّت ساعة بدون رد من المحامي → المستخدم يفعّل الطلب من جديد
- زيادة `reactivate_count` + تحديث `last_reactivate_at`
- إشعار المحامي من جديد
- لا حاجة لدفع مجدد

#### 2.3 إضافة action: `send_chat_message`
- التحقق: الاستشارة موجودة + الحالة = confirmed + المحادثة مفتوحة
- التحقق: الوقت لم ينتهي (chat_started_at + chat_duration_minutes)
- حفظ الرسالة في `consultation_chats`
- إشعار الطرف الآخر (FCM)
- أنواع الرسائل: text, voice, image

#### 2.4 إضافة action: `get_chat_messages`
- إرجاع كل رسائل الاستشارة (مرتبة بالتاريخ)
- توقيع روابط الملفات (signed URLs)
- تحديد الرسائل غير المقروءة

#### 2.5 إضافة action: `start_chat`
- المحامي يفتح المحادثة → يُسجّل `chat_started_at = NOW()`
- إرسال رسالة system: "بدأت المحادثة — لديك 15 دقيقة"
- إشعار المستخدم (FCM)

#### 2.6 إضافة action: `extend_chat`
- المحامي يمدد 5 دقائق (مرة واحدة فقط)
- التحقق: `extended = false` → `extended = true`
- تحديث `chat_duration_minutes = 20`
- رسالة system: "تم تمديد المحادثة 5 دقائق إضافية"

#### 2.7 إضافة action: `rate_consultation`
- المستخدم يقيّم المحامي (1-5 نجوم + تعليق اختياري)
- إلزامي قبل إغلاق الاستشارة

#### 2.8 تعديل action: `update_consultation_status`
- إضافة حالة "قيد الدراسة" (status = 4)
- إضافة تحويل لحضورية (خصم 500 من 2000)

---

### المرحلة 3: شاشة المستخدم — شرح الآلية + إرفاق المستندات

**الملف:** `lib/screens/legal/legal_consultation_booking_screen.dart` (تعديل)

#### 3.1 إضافة شاشة شرح الآلية (قبل كل شيء)
```
┌─────────────────────────────────────────┐
│  ⚖️ كيف تعمل الاستشارة القانونية؟      │
│                                         │
│  1. اشرح مشكلتك + أرفق المستندات       │
│  2. ادفع المبلغ (500 ل.س)              │
│  3. سيتم الرد خلال ساعة من تقديم الطلب │
│  4. المحامي يدرس مشكلتك قبل القبول     │
│  5. بعد القبول → تفتح المحادثة          │
│  6. يبدأ العد: 15 دقيقة                 │
│                                         │
│  ⚠️ هذه الخدمة للاستشارات البسيطة      │
│  📍 إذا مشكلتك معقدة → احجز حضوري     │
│                                         │
│  ⏰ إذا الوقت بين 11م - 9ص:            │
│     قد يتأخر الرد لبعد التاسعة صباحاً   │
│                                         │
│  ⏳ في حال عدم الرد خلال ساعة:          │
│     يمكنك إعادة تفعيل الطلب بدون دفع    │
│                                         │
│  [متابعة ←]                             │
└─────────────────────────────────────────┘
```

#### 3.2 تعديل قائمة الخدمات
```dart
// حذف باقة التوثيق الشامل — تعديل الأسعار
final _services = [
  {
    'title': 'استشارة هاتفية صوتية',
    'price': 500,  // بدل 50000
    'duration': '15 دقيقة',
    'icon': Icons.phone_in_talk,
    'desc': 'اتصال صوتي مباشر مع محامي المكتب للإجابة عن استفساراتك القانونية البسيطة.',
  },
  {
    'title': 'جلسة استشارة مكتبية حضورية',
    'price': 2000,  // بدل 200000
    'duration': 'لغاية ساعة واحدة',
    'icon': Icons.business,
    'desc': '...',
  },
];
```

#### 3.3 إضافة إرفاق مستندات (حتى 5 صور)
- زر "إرفاق مستندات" مع عداد (0/5)
- ضغط الصور عبر `StorageService.compressImage()`
- رفع إلى `consultation_files` bucket
- عرض الصور المرفقة مع زر حذف

#### 3.4 تعديل طريقة الدفع
- `formatPrice` → تمرير `currency: 1` (ليرة سورية)
- عرض السعر: "500 ل.س" بدل "$50,000"

#### 3.5 إضافة تنويه الوقت المتأخر
```dart
bool get _isLateNight {
  final hour = DateTime.now().hour;
  return hour >= 23 || hour < 9;
}
// عرض تنويه إذا _isLateNight == true
```

#### 3.6 إضافة زر "إعادة تفعيل الطلب"
- يظهر للاستشارات المعلقة (status=0) اللي مر عليها أكثر من ساعة
- يستدعي `reactivate_consultation` action

---

### المرحلة 4: شاشة المحادثة (Chat UI) — جديدة

**الملف:** `lib/screens/legal/consultation_chat_screen.dart` (جديد)

#### 4.1 البنية
```
┌─────────────────────────────────────────┐
│ ← محامي المكتب الأول    ⏱️ 12:34      │
├─────────────────────────────────────────┤
│                                         │
│  📋 نظام: بدأت المحادثة                │
│                                         │
│  👤 أنا: عندي عقد إيجار...             │
│  📎 [صورة_العقد.jpg]                   │
│                                         │
│  ⚖️ محامي المكتب: حسب المادة 123...   │
│  🎤 [رسالة صوتية 0:45]                 │
│                                         │
│  🔔 تنبيه: بقي 3 دقائق                │
│                                         │
│  ⏱️ نظام: تم تمديد المحادثة 5 دقائق  │
│                                         │
├─────────────────────────────────────────┤
│  🎤  │  اكتب رسالتك...    │ 📎  │ ➤  │
└─────────────────────────────────────────┘
```

#### 4.2 المكونات
- **AppBar:** اسم المحامي (alias) + مؤقت العد التنازلي
- **Messages List:** فقاعات رسائل (نص/صوت/صورة/نظام)
- **Input Area:** حقل نص + زر صورة + زر تسجيل صوتي + زر إرسال
- **Voice Recording:** `flutter_sound` أو `record` package
- **Timer:** `Timer.periodic` كل ثانية — يحسب الوقت المتبقي
- **Alerts:** تنبيه 3 دقائق + 1 دقيقة قبل الانتهاء

#### 4.3 أنواع الرسائل (Bubbles)
| النوع | الشكل |
|-------|-------|
| text | فقاعة نص عادية |
| voice | ▶️ شريط صوتي مع مدة + تشغيل |
| image | صورة مصغرة — اضغط للتكبير |
| system | نص رمادي في المنتصف |

#### 4.4 بعد انتهاء الوقت
- المحادثة تُقفل (input مخفي)
- رسالة system: "انتهت مدة الاستشارة"
- تظهر أزرار: ⭐ تقييم + 🔄 تحويل لحضورية

---

### المرحلة 5: لوحة المحامي — إدارة الاستشارات

**الملف:** `lib/screens/lawyer/lawyer_dashboard_screen.dart` (تعديل التبويب)

#### 5.1 تعديل تبويب الاستشارات
- عرض الطلبات المعلقة مع الموضوع + المستندات
- زر "دراسة الطلب" → يفتح تفاصيل الطلب + الصور
- زر "قبول وبدء المحادثة" → يستدعي `start_chat`
- زر "رفض" مع سبب

#### 5.2 عند فتح المحادثة (من طرف المحامي)
- نفس شاشة Chat (consultation_chat_screen.dart)
- المحامي يرى اسم الطالب الحقيقي
- زر "تمديد 5 دقائق" (مرة واحدة)
- لا يرى الطالب اسم المحامي أو رقمه

---

### المرحلة 6: الإشعارات + التقييم + التحويل

#### 6.1 إشعارات FCM
| الحدث | المستلم | النص |
|-------|---------|------|
| حجز استشارة جديد | المحامي | "⚖️ استشارة جديدة من [اسم]" |
| المحامي قبل | الطالب | "✅ تم قبول استشارتك — افتح المحادثة" |
| رسالة جديدة | الطرف الآخر | "💬 رسالة جديدة في الاستشارة" |
| تنبيه 3 دقائق | الطرفين | "⏱️ بقي 3 دقائق على انتهاء الاستشارة" |
| تمديد | الطالب | "⏱️ تم تمديد المحادثة 5 دقائق" |

#### 6.2 شاشة التقييم (بعد الانتهاء)
```dart
// Dialog بسيط
// ⭐⭐⭐⭐⭐ (1-5 نجوم)
// حقل تعليق (اختياري)
// زر "إرسال التقييم"
```

#### 6.3 تحويل لحضورية
- يظهر فقط بعد انتهاء المحادثة
- يفتح شاشة حجز موعد حضوري
- يخصم 500 من 2000 = يدفع 1500 فقط
- نفس آلية الدفع (قناة + إثبات)

---

## 📁 الملفات المُعدّلة/الجديدة

### ملفات جديدة:
| # | الملف | الوصف |
|---|-------|-------|
| 1 | `supabase/migrations/2026_08_12_consultation_chat_system.sql` | Migration |
| 2 | `lib/screens/legal/consultation_chat_screen.dart` | شاشة المحادثة |
| 3 | `lib/models/consultation_chat_model.dart` | نموذج الرسالة |
| 4 | `lib/models/consultation_model.dart` | نموذج الاستشارة |

### ملفات مُعدّلة:
| # | الملف | التعديل |
|---|-------|---------|
| 5 | `supabase/functions/legal-actions/index.ts` | 6 actions جديدة + تعديل 2 |
| 6 | `lib/screens/legal/legal_consultation_booking_screen.dart` | شرح + إرفاق + أسعار |
| 7 | `lib/providers/legal_provider.dart` | دوال Chat الجديدة |
| 8 | `lib/screens/lawyer/lawyer_dashboard_screen.dart` | تبويب الاستشارات |
| 9 | `lib/core/router/app_router.dart` | route للشاشة الجديدة |

---

## ⏱️ ترتيب التنفيذ

| المرحلة | الوقت | الاعتمادية |
|---------|-------|-------------|
| 1. Migration (قاعدة البيانات) | 30 دقيقة | — |
| 2. Edge Function (legal-actions) | 1.5 ساعة | بعد #1 |
| 3. شاشة المستخدم (شرح + إرفاق) | 1 ساعة | بعد #1 |
| 4. شاشة المحادثة (Chat UI) | 1.5 ساعة | بعد #2 |
| 5. لوحة المحامي | 30 دقيقة | بعد #4 |
| 6. إشعارات + تقييم + تحويل | 30 دقيقة | بعد #4 |
| **المجموع** | **~5.5 ساعات** | |

---

## 🧪 خطة الاختبار

| # | الاختبار | الخطوات المتوقعة |
|---|----------|-----------------|
| 1 | شاشة الشرح تظهر | اضغط "استشارة قانونية" → تظهر الشاشة |
| 2 | إرفاق مستندات | ارفق 3 صور → تظهر + ضغطها |
| 3 | الدفع 500 ل.س | اختر هاتفية → ادفع → يظهر "500 ل.س" |
| 4 | تنويه الوقت المتأخر | جرّب بعد 11م → يظهر التنويه |
| 5 | المحامي يقبل | سجل دخول كمحامي → اقبل الطلب |
| 6 | المحادثة تفتح | المحامي يفتح المحادثة → يبدأ العد |
| 7 | إرسال رسائل | نص + صوت + صورة من الطرفين |
| 8 | إخفاء اسم المحامي | الطالب يرى "محامي المكتب الأول" فقط |
| 9 | تمديد 5 دقائق | المحامي يمدد → العد يتغير |
| 10 | تنبيه 3 دقائق | انتظر حتى 12 دقيقة → يظهر التنبيه |
| 11 | انتهاء الوقت | 15 دقيقة → المحادثة تُقفل |
| 12 | التقييم | ⭐⭐⭐⭐⭐ + تعليق |
| 13 | إعادة تفعيل | اطلب استشارة → انتظر ساعة → أعد تفعيل |
| 14 | تحويل لحضوري | بعد الانتهاء → حوّل → ادفع 1500 |

---

## ⚠️ ملاحظات مهمة

1. **ضغط الصور:** `StorageService.compressImage()` موجودة وتُستخدم حالياً في:
   - ✅ رفع صور العروض (`uploadOfferImages`)
   - ✅ صور الهوية (`setup_identity_screen`)
   - ✅ إيصال الدفع (`payment_screen`)
   - ✅ قنوات الدفع (`payment_channels_editor_screen`)
   - ✅ صور المستندات (`_uploadDocImage` → `uploadOfferImage`)
   - 🆕 **ستُستخدم لصور الاستشارات** (consultation_files)

2. **Voice Notes:** نحتاج `flutter_sound` أو `record` package — نتحقق من pubspec.yaml

3. **Realtime:** Supabase Realtime متاح — سنستخدمه للرسائل الفورية

4. **إخفاء المحامي:** `lawyer_alias` يُخزّن في `legal_consultations` عند الحجز
