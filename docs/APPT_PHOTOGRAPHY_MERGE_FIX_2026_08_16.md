# إصلاح انهيار شاشة «مواعيدي» — APPT-001/002/003/004

**التاريخ:** 2026-08-16 · **البلاغ:** المالك — «بس افتح ع مواعيدي» + سجلّ الجهاز

## نص البلاغ الحرفي

```
I/flutter (25559): ! [ERR] رمز غير مترجَم: PostgrestException(message:
{"code":"22P02","details":null,"hint":null,"message":"invalid input syntax
for type uuid: \"\""}, code: 400, details: Bad Request, hint: null)

Another exception was thrown: RangeError (end): Invalid value: Only valid value is 0: 8
```

## السبب الجذري (واحد يولّد كل الأعراض)

الإيدج `user-appointments` (الفعل `list_user_appointments`) يدمج **مهام التصوير**
ضمن قائمة «مواعيدي» بصيغة صف موعد — قرار المالك 2026-07-28. لكن مهمة التصوير
لا عرض لها ولا مالك، فتُرسل هكذا:

```ts
off_id: null,  own_id: null,  req_id: null,  kind: "photography"
```

وفي `AppointmentModel.fromSupabase`: `offId: data['off_id'] ?? ''`
⇒ **`offId` تصبح نصاً فارغاً**.

### الدليل الحي

```sql
select id, ttl, sts, ts_scheduled, requested_by, off_id
from photography_tasks
where requested_by = '99703882-2ff5-46ba-ad2f-1a3262c02eb2';
-- 472bfc44-4d02-450f-ae5b-86a3aaf0e5a6 | so do | 3 | 2026-08-17 10:00 | ✔
```

مهمة واحدة مجدولة لدى هناء ⇒ الشاشة انهارت أول ما وُجدت. قبل طلب التصوير
كانت الشاشة تعمل — لذلك لم يظهر العطل في الجولات السابقة.

## الأعطال والإصلاحات

| الرمز | العطل | الموضع | الإصلاح |
|---|---|---|---|
| **APPT-001** | `fetchOfferById('')` ⇒ `.eq('id','')` ⇒ Postgres **22P02** | `my_appointments_screen.dart` `_load` | تصفية المعرّفات الفارغة قبل الجلب |
| **APPT-002** | `appt.offId.substring(0, 8)` على نص فارغ ⇒ **RangeError** ⇒ انهيار البطاقة | `_myApptCard` | حارس `length >= 8` + تمييز موعد التصوير بعنوانه وأيقونته |
| **APPT-003** | زر التقييم يمرّر `ownId` فارغاً · زر الإلغاء يستدعي مساراً لا وجود له | `_myApptCard` | إخفاء الزرّين لمواعيد التصوير |
| **APPT-004** | حالة التصوير 3 (منجزة) تُقرأ بجدول المواعيد كـ«ملغي» بلون أحمر | `_myApptCard` | جدول حالات منفصل: 1 «مجدول» · 3 «منتهي» |
| **I18N-ERR-002** | نص `PostgrestException` الخام إنجليزي بالكامل ولا يلتقطه القاموس | `error_utils.dart` | انتزاع SQLSTATE + 10 رسائل عربية جديدة + منع أي نص لاتيني من الوصول للمستخدم |

## تفاصيل تحصين `ErrorUtils.normalize`

كان `normalize` يُعيد أول 220 محرفاً من النص الخام عند عدم التعرف — وهذا هو
ما سرّب النص الإنجليزي. الآن ثلاث بوابات متتالية:

1. **انتزاع SQLSTATE**: `RegExp(r'"code"\s*:\s*"([0-9A-Za-z]{5})"')` ⇒ خريطة
   `_pgState` (12 رمزاً: 22P02, 23502, 23503, 23505, 23514, 42501, 42703,
   42883, 40001, 55P03, 57014, PGRST).
2. **أنواع الاستثناءات المعروفة**: `PostgrestException` · `AuthException` ·
   `FunctionException` ⇒ `DB_ERROR` · `SocketException`/`ClientException` ⇒
   `NETWORK_ERROR` · `TimeoutException` ⇒ `TIMEOUT`.
3. **حارس اللغة**: أي نص بلا حرف عربي وفيه حروف لاتينية صغيرة (أي ليس رمزاً
   اصطلاحياً `SNAKE_CASE`) ⇒ `UNKNOWN_ERROR`.

⇒ **مستحيل** بعد اليوم أن يصل نص إنجليزي خام لواجهة المستخدم (§19).

### الرسائل العربية المضافة (10)

| الرمز | الرسالة |
|---|---|
| `DB_ERROR` | حدث خلل أثناء الاتصال بالخادم — أعد المحاولة بعد قليل. |
| `DB_INVALID_INPUT` | إحدى البيانات المُرسلة غير صالحة — أعد فتح الشاشة وحاول مجدداً. |
| `DB_MISSING_FIELD` | هناك حقل مطلوب لم يُملأ — راجع البيانات وأعد الإرسال. |
| `DB_LINK_MISSING` | العنصر المرتبط بهذه العملية لم يعد موجوداً — حدّث القائمة. |
| `DB_DUPLICATE` | هذه البيانات مسجّلة مسبقاً. |
| `DB_CHECK_FAILED` | القيمة المُدخلة خارج النطاق المسموح. |
| `DB_NO_PERMISSION` | ليست لديك صلاحية لتنفيذ هذه العملية. |
| `DB_BUSY` | الخادم مشغول حالياً — أعد المحاولة بعد لحظات. |
| `NETWORK_ERROR` | تعذّر الاتصال بالإنترنت — تحقق من الشبكة وأعد المحاولة. |
| `TIMEOUT` | استغرقت العملية وقتاً طويلاً — أعد المحاولة. |

## الملفات المعدّلة

- `lib/screens/user/my_appointments_screen.dart`
- `lib/models/appointment_model.dart` (حقل `kind` + الخاصية `isPhotography`)
- `lib/core/utils/error_utils.dart`

**لا تعديل على السيرفر ولا على أي Edge Function** — الإصلاح كله في الواجهة.

## التحقق

- `dart analyze` على الملفات الثلاثة: أخطاء الحل (Flutter SDK غير منزَّل §16)
  مطابقة عدداً ونوعاً للأساس البعيد — **لا خطأ جديد**.
- `dart format`: نظيف.

## المظهر بعد الإصلاح

بطاقة موعد التصوير تظهر: 📷 أيقونة كاميرا · العنوان «📸 موعد تصوير — so do» ·
«خدمة تصوير عقاري» بدل رقم العرض · شارة **منتهي** خضراء · اسم **المصوّر** بدل
«المشرف» · بلا زر إلغاء وبلا زر تقييم.
