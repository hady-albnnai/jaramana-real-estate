# تحديث 2026-07-04 — رسائل الواجهة + تغيير كلمة المرور + الثيم النهاري

## 1) إصلاح الرسائل خلف النوافذ المنبثقة

تم استبدال الاعتماد المباشر على `ScaffoldMessenger.of(context).showSnackBar(...)` بطبقة رسائل علوية موحدة عبر:

- `AppTheme.showSnackBar(context, SnackBar(...))`
- `AppTheme.hideSnackBar(context)`

الرسائل الآن تُعرض في `rootOverlay` فوق الـ Dialogs و BottomSheets، لذلك لا تختفي خلف النوافذ المنبثقة.

## 2) إصلاح تغيير كلمة المرور من الملف الشخصي

### Flutter

تم تصحيح مفاتيح الطلب المرسلة إلى Edge Function `user-account`:

- `p_old_password` ⟵ كان خطأ
- `p_new_password` ⟵ كان خطأ
- أصبحت:
  - `old_password`
  - `new_password`

الملفات:

- `lib/screens/user/account_info_screen.dart`
- `lib/screens/lawyer/lawyer_dashboard_screen.dart`

كما تم رفع تحقق طول كلمة المرور في واجهة معلومات الحساب إلى 8 أحرف.

### Supabase Edge Functions

تم تعديل `user-account` ليقبل جلسة تسجيل الدخول المخصصة للمستخدم العادي عبر `validate_staff_session` مع:

```ts
p_min_role: 0
```

وتم تمرير session token في الهيدر عند عدم وجود JWT من:

- `lib/core/network/supabase_service.dart`

كما تم توحيد نفس الإصلاح لمسارات المستخدم التي قد تعمل بعد تسجيل الدخول بكلمة مرور:

- `user-account`
- `user-offers`
- `user-requests`
- `user-appointments`
- `user-notifications`
- `user-rewards`
- `broker-actions`

## 3) Migration جديدة للجلسات

تمت إضافة:

- `supabase/migrations/2026_07_04_user_account_password_session_fix.sql`

الهدف: ضمان أن `_issue_staff_session` يصدر session token لكل الأدوار بعد تسجيل دخول صحيح بكلمة المرور، مع بقاء الصلاحيات محكومة عند التحقق عبر `p_min_role`.

## 4) الثيم النهاري الأبيض/الذهبي

تم نقل الثيم العام إلى لوحة ألوان نهارية:

- خلفية التطبيق: أبيض دافئ
- البطاقات/الأسطح: أبيض
- النصوص: داكنة
- اللون الأساسي: ذهبي

مع إبقاء `AppTheme.deepBlack` كلون داكن للأزرار والنص فوق الذهب حتى لا يضعف التباين.

## يلزم بعد الرفع

نشر Edge Functions المعدلة:

```bash
supabase functions deploy user-account
supabase functions deploy user-offers
supabase functions deploy user-requests
supabase functions deploy user-appointments
supabase functions deploy user-notifications
supabase functions deploy user-rewards
supabase functions deploy broker-actions
```

ثم تطبيق Migration على قاعدة البيانات الحية أو تشغيل migrations عبر Supabase CLI.
