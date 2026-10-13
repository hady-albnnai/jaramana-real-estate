# 📋 خطة إعادة هيكلة لوحة الإدارة — عقارات السويداء

**التاريخ:** 2026-06-15
**الحالة:** خطة تصحيح وتنفيذ معتمدة قبل بدء التعديلات
**المرجع الإلزامي:** `docs/LOGIC_SPEC.md` + `DEVELOPMENT_GUIDELINES.md`
**المرجع الشكلي فقط:** مشروع `final-united-real-estate` — ملف `lib/app/modules/admin/views/admin_screen.dart`

---

## 0) توضيح مهم حول مشروع Final

المطلوب **ليس نسخ مشروع Final حرفياً** ولا مطابقة قواعده وجداوله وأدواره مع مشروع عقارات السويداء.

المطلوب هو اقتباس **الهيكلية الإدارية النظيفة** من Final، ثم تكييفها مع منطق مشروع عقارات السويداء:

- Final يستخدم شاشة إدارية مركزية لإدارة الموظفين.
- Final يستخدم قائمة موظفين + بحث + إجراءات من قائمة منسدلة.
- Final ينفذ العمليات الحساسة عبر Edge Functions.
- Final يعرض كلمة السر المولدة/المعاد تعيينها مرة واحدة مع زر نسخ.
- Final يجمع منطق إضافة/تعديل/تعطيل/حذف الموظف في تجربة واحدة واضحة.

أما في عقارات السويداء فيجب الالتزام بما يلي:

- إدارة الحالة تبقى بـ **Provider** وليس GetX.
- جدول المستخدمين هو `users` وليس `profiles`.
- الأدوار أرقام:
  - `0` مستخدم
  - `1` وسيط
  - `2` مصور
  - `3` مشرف/منفذ ميداني
  - `4` موظف مكتب
  - `5` نائب مدير
  - `6` مدير
- التوثيق والصلاحيات وحالات المستخدم يجب أن تلتزم بـ `LOGIC_SPEC.md`.
- لا يجوز تعديل `role` أو `sts` أو حذف مستخدم من العميل مباشرة.
- كل العمليات الحساسة الخاصة بالموظفين يجب أن تمر عبر Edge Functions أو RPCs آمنة خلف Edge Function.

---

## 1) الرؤية النهائية

تحويل قسم الإدارة من لوحة واحدة مزدحمة إلى نظام منظّم حسب الدور:

- المدير يرى مركز إدارة الموظفين أولاً، ومنه يصل لباقي أقسام الإدارة.
- نائب المدير يرى داشبورد خاص به مع وصول محدود حسب الصلاحيات.
- موظف المكتب يرى داشبورد تشغيلي خاص بالمهام اليومية فقط.
- المشرف/المنفذ يرى مهام التنفيذ فقط.
- المصور يرى مهام التصوير فقط.

قاعدة العمل:

> كل دور يبدأ من شاشة تناسبه، ولا يرى شبكة وظائف لا تخصه.

---

## 2) الهيكل المستهدف للمسارات

| الدور | الشاشة الافتراضية | الملاحظات |
|---|---|---|
| مدير `role=6` | `/admin/dashboard` | شاشة إدارة الموظفين الرئيسية + روابط لباقي الإدارة |
| نائب مدير `role=5` | `/deputy/dashboard` | داشبورد نائب المدير + رابط إدارة الموظفين إن كانت صلاحياته تسمح |
| موظف مكتب `role=4` | `/employee/dashboard` | عروض + مواعيد + طلبات إتمام + مستخدمون حسب الصلاحيات |
| مشرف/منفذ `role=3` | `/executor/tasks` | مهام التنفيذ فقط |
| مصور `role=2` | `/photographer/tasks` | مهام التصوير فقط |
| مستخدم/وسيط | مسارات المستخدم/الوسيط | لا يدخل مسارات الإدارة الداخلية |

### قرارات توجيه مهمة

1. `/admin/dashboard` مخصص للمدير فقط كمدخل إدارة الموظفين.
2. `/admin/employee-management` شاشة إدارة الموظفين، ويسمح بها للمدير ونائب المدير فقط إن توفرت الصلاحية.
3. `/deputy/dashboard` و`/employee/dashboard` يجب تعريفهما فعلياً في `GoRouter`، وليس الاكتفاء بالـ redirect.
4. لا يجوز أن يحوّل الراوتر نائب المدير إلى مسار غير معرّف.
5. إذا احتجنا الاحتفاظ بالداشبورد الإداري القديم، ينقل إلى مسار واضح مثل:
   - `/admin/operations-dashboard`
   أو يبقى كملف داخلي لا يكون الشاشة الافتراضية.

---

## 3) شاشة إدارة الموظفين المستوحاة من Final

### 3.1 الوظائف المطلوبة

شاشة `EmployeeManagementScreen` يجب أن تحتوي على:

- تحميل الموظفين الداخليين فقط: `role IN (2,3,4,5,6)` و `i_del=0`.
- بحث بالاسم والهاتف والبريد واسم المستخدم إن وجد.
- بطاقة موظف تحتوي على:
  - الاسم
  - الدور
  - الهاتف
  - البريد إن وجد
  - اسم المستخدم إن وجد
  - الحالة: نشط / مجمد / محظور
- قائمة إجراءات لكل موظف:
  - تغيير الدور
  - تفعيل/تعطيل/تجميد الحساب
  - إعادة تعيين كلمة السر
  - حذف/تعطيل منطقي للموظف
- منع تعديل أو حذف المدير الرئيسي `role=6` من الواجهة ومن السيرفر.
- Dialog لإظهار كلمة السر الجديدة مرة واحدة مع زر نسخ، مثل Final.

### 3.2 اختلافات عقارات السويداء عن Final

في Final كانت العملية تعتمد على:

- `profiles`
- أدوار نصية
- GetX
- `Supabase.instance.client`

في عقارات السويداء يجب أن تعتمد على:

- `users`
- أدوار رقمية
- Provider
- `SupabaseService().client`
- `UserModel`
- `AdminProvider` أو Service واضح لإدارة الموظفين

---

## 4) العمليات الحساسة وEdge Functions

### 4.1 Edge Functions المطلوبة

يجب أن توجد هذه الدوال داخل `supabase/functions/`:

1. `create-user`
2. `update-user-role`
3. `toggle-user-status`
4. `reset-user-password`
5. `delete-user`

### 4.2 قاعدة الأمان

كل Edge Function يجب أن تتحقق من:

- هوية المدير/نائب المدير المرسل للعملية.
- أن المنفّذ يملك الدور والصلاحية المناسبة.
- أن الهدف موجود وغير محذوف.
- منع تعديل/حذف/إعادة تعيين كلمة سر المدير الرئيسي `role=6` إلا وفق سياسة صريحة، والأصل المنع.
- منع نائب المدير من إنشاء أو ترقية مستخدم إلى مدير `role=6`.
- تسجيل العملية في `activity_log` بالأعمدة الصحيحة:
  - `uid`
  - `act`
  - `det`
  - `ts_crt`

### 4.3 ملاحظة مهمة عن كلمة السر

مشروع عقارات السويداء لديه نظام اسم مستخدم وكلمة مرور داخل جدول `users` عبر:

- `usr`
- `pwd`
- `login_with_password`
- `register_password`
- `reset_password_with_otp`

لذلك لا يجوز نسخ منطق Final كما هو إذا كان يعتمد فقط على `auth.admin.createUser` دون إنشاء/تحديث صف صحيح في `users`.

الخيار المعتمد للتنفيذ:

- توليد كلمة سر آمنة.
- إنشاء/تحديث مستخدم التطبيق في `users`.
- تخزين كلمة السر مشفرة عبر `crypt(..., gen_salt(...))` من خلال RPC آمنة أو SQL داخل Edge Function.
- إعادة كلمة السر الصريحة مرة واحدة فقط للواجهة لعرضها للمدير ونسخها.

---

## 5) RPCs / Migrations المطلوبة

يجب إنشاء أو تصحيح Migration واحدة نهائية لإدارة الموظفين، ويفضل باسم واضح مثل:

`supabase/migrations/2026_06_15_admin_employee_management_final.sql`

### 5.1 الدوال المطلوبة داخل PostgreSQL

- `get_all_staff_users(p_admin_uid UUID)`
  - يرجع موظفي `role IN (2,3,4,5,6)`.
  - لا يرجع المحذوفين.
  - يتحقق من أن المستدعي `role >= 5` أو حسب سياسة الصلاحيات المعتمدة.

- `admin_create_staff_user(...)` أو منطق مكافئ خلف Edge Function.

- `admin_update_staff_role(...)`
  - يمنع تعديل المدير الرئيسي.
  - يمنع أدوار غير مسموحة.

- `admin_toggle_staff_status(...)`
  - يستخدم `sts` وفق العقد الحالي:
    - `0` نشط
    - `1` مجمد
    - `2` محظور

- `admin_reset_staff_password(...)`
  - يحدث `pwd` مشفراً.

- `admin_delete_staff_user(...)`
  - soft delete فقط: `i_del=1`.
  - لا يستخدم `soft_delete(p_table,p_id)` العام من الواجهة لإدارة الموظفين.

### 5.2 تحديث setup.sql

حسب `DEVELOPMENT_GUIDELINES.md`:

> أي تغيير في بنية قاعدة البيانات أو دوال أساسية يجب أن ينعكس في `supabase/setup.sql`.

لذلك بعد تثبيت migration النهائية، يجب تحديث `setup.sql` بما يلزم أو توثيق أن الدوال تعتمد على migrations مع مرجع واضح.

---

## 6) تحديث الملفات البرمجية المطلوبة

### 6.1 الراوتر

الملف:

`lib/core/router/app_router.dart`

المطلوب:

- إضافة route فعلي لـ `/deputy/dashboard`.
- إضافة route فعلي لـ `/employee/dashboard`.
- إضافة route لـ `/admin/employee-management` إن لم يكن موجوداً أو إصلاح حمايته.
- منع redirect loop من نائب المدير عند الضغط على إدارة الموظفين.
- ضمان أن كل role يذهب إلى الشاشة الافتراضية الصحيحة.

### 6.2 Provider / Service

الملف الأساسي الحالي:

`lib/providers/admin_provider.dart`

المطلوب:

- إضافة دوال واضحة لإدارة الموظفين:
  - `getAllStaffUsers(adminUid)`
  - `createStaffUser(...)`
  - `updateStaffRole(...)`
  - `toggleStaffStatus(...)`
  - `resetStaffPassword(...)`
  - `deleteStaffUser(...)`
- دوال الإنشاء/الدور/الحالة/إعادة كلمة السر/الحذف يجب أن تستدعي Edge Functions، وليس direct RPC من شاشة Flutter.
- إبقاء RPCs القراءة والإحصائيات حسب الحاجة.

### 6.3 شاشة إدارة الموظفين

الملفات:

- `lib/screens/admin/employee_management/employee_management_screen.dart`
- `lib/screens/admin/employee_management/add_employee_dialog.dart`
- `lib/screens/admin/employee_management/change_role_dialog.dart`
- `lib/screens/admin/employee_management/toggle_status_dialog.dart`

المطلوب:

- إزالة كل رسائل placeholder مثل "سيتم تنفيذها في المرحلة القادمة".
- تنفيذ الإضافة فعلياً.
- تنفيذ reset password فعلياً.
- عرض كلمة السر الجديدة في Dialog قابل للنسخ.
- تحديث القائمة بعد كل عملية ناجحة.
- إظهار رسائل خطأ مفهومة عند فشل Edge Function أو RPC.

### 6.4 داشبورد نائب المدير وموظف المكتب

> تحديث لاحق 2026-06-17: تم إلغاء الفصل العملي لشاشة نائب المدير، وأصبح نائب المدير يستخدم `AdminDashboardScreen` نفسها مع اختلاف الصلاحيات فقط. وتم توحيد موظف المكتب على `/employee/home` وحذف ملف `employee_dashboard_screen.dart` القديم.

الملفات الحالية:

- `lib/screens/admin/admin_dashboard_screen.dart` للمدير ونائب المدير.
- `lib/screens/employee/employee_home_screen.dart` لموظف المكتب.

المطلوب/المطبق:

- إظهار روابط فقط لما تسمح به `PermissionService`.
- عدم إظهار إدارة الموظفين لموظف المكتب.
- منع نائب المدير من إدارة المدير أو نائب آخر.

### 6.5 PermissionService

الملف:

`lib/core/services/permission_service.dart`

المطلوب:

- إضافة/توضيح صلاحية إدارة الموظفين كصلاحية مستقلة إن لزم، مثل:
  - `manageStaff`
- عدم خلطها مع `manageUsers` إذا كانت `manageUsers` مخصصة للمستخدمين والعملاء.
- ضبط الافتراضات:
  - المدير: كل شيء.
  - نائب المدير: إدارة موظفين محدودة + عمليات مالية/تشغيلية حسب السياسة.
  - موظف المكتب: تشغيل فقط.
  - المشرف/المصور: مهامهم فقط.

---

## 7) الحالة الحالية التي يجب تصحيحها قبل إعلان الاكتمال

حسب التدقيق الحالي بتاريخ 2026-06-15:

- `EmployeeManagementScreen` موجودة لكن ليست مكتملة.
- `/deputy/dashboard` و`/employee/dashboard` غير معرفين فعلياً في الراوتر رغم وجود redirect إليهما.
- `get_all_staff_users` مستخدمة في Flutter لكنها غير معرفة في migrations/setup.
- `create-user` و`reset-user-password` موجودتان، لكن باقي Edge Functions المطلوبة غير موجودة.
- Add employee وReset password في الواجهة ما زالت placeholder.
- ملف `docs/ADMIN_IMPLEMENTATION_COMPLETE.md` يقول 100% لكنه لا يطابق الحالة الفعلية.
- تم تصحيح `supabase/FUNCTIONS_REFERENCE.md` ليشير إلى migration النهائية الجديدة.
- تم استبدال الاعتماد على migration القديمة غير المكتملة بملف نهائي صحيح: `2026_06_15_admin_employee_management_final.sql`.

---

## 8) مراحل التنفيذ الجديدة

### المرحلة A — تثبيت الخطة والمرجع

- [x] إعادة قراءة مشروع Final بهدف اقتباس الهيكلية لا النسخ.
- [x] توثيق الاختلافات بين Final وعقارات السويداء.
- [x] تحديث هذه الخطة لتصبح مرجع التنفيذ.

### المرحلة B — إصلاح الراوتر والشاشات حسب الدور

- [x] تعريف `/deputy/dashboard` في `GoRouter`.
- [x] تعريف `/employee/dashboard` في `GoRouter`.
- [x] إصلاح redirect حسب الدور بدون مسارات مكسورة.
- [x] ضبط وصول `/admin/employee-management` للمدير/نائب المدير فقط.
- [x] إبقاء `/executor/tasks` و`/photographer/tasks` لمساراتهم الخاصة.

### المرحلة C — قاعدة البيانات وRPCs

- [x] إنشاء migration نهائية لدوال إدارة الموظفين.
- [x] إضافة `get_all_staff_users` بشكل صحيح.
- [x] تصحيح/استبدال دوال إدارة الموظفين الحالية.
- [x] استخدام أعمدة `activity_log` الصحيحة.
- [x] منع المساس بالمدير الرئيسي من السيرفر.
- [x] تحديث `setup.sql` بمرآة migration النهائية.

### المرحلة D — Edge Functions

- [x] تصحيح `create-user` ليتوافق مع `users.usr/pwd` ومنطق عقارات السويداء.
- [x] تصحيح `reset-user-password` ليتوافق مع `users.pwd`.
- [x] إنشاء `update-user-role`.
- [x] إنشاء `toggle-user-status`.
- [x] إنشاء `delete-user`.
- [x] إضافة تحقق صلاحية داخل كل Function عبر RPCs آمنة.
- [x] إضافة رسائل أخطاء ثابتة وواضحة.

### المرحلة E — ربط Flutter فعلياً

- [x] تحديث `AdminProvider` لاستدعاء Edge Functions.
- [x] تنفيذ AddEmployeeDialog فعلياً.
- [x] تنفيذ Reset Password فعلياً.
- [x] إضافة Password Result Dialog مع نسخ.
- [x] تحديث القائمة بعد كل عملية.
- [x] إزالة كل رسائل "سيتم تنفيذها في المرحلة القادمة".

### المرحلة F — الإحصائيات والصلاحيات

- [x] ربط داشبورد نائب المدير بإحصائيات حقيقية.
- [x] ربط داشبورد موظف المكتب بإحصائيات حقيقية.
- [x] ضبط `PermissionService` حسب الدور.
- [x] منع ظهور روابط لا يملكها المستخدم.

### المرحلة G — التوثيق والاختبار

- [x] تحديث `docs/ADMIN_RESTRUCTURING_PROGRESS.md` بالحالة الفعلية.
- [x] تحديث `docs/ADMIN_IMPLEMENTATION_COMPLETE.md` إلى حالة انتظار الاختبار النهائي دون إعلان 100% سابق لأوانه.
- [x] تحديث `supabase/FUNCTIONS_REFERENCE.md` بالأسماء الصحيحة وحالة النشر.
- [x] تحديث `docs/TEST_CHECKLIST.md` بسيناريوهات إدارة الموظفين.
- [ ] تشغيل تحليل Flutter إن كانت البيئة متاحة.
- [ ] اختبار يدوي للأدوار 2/3/4/5/6.

---

## 9) Definition of Done — شروط اعتبار الخطة مكتملة 100%

لا يجوز إعلان الاكتمال إلا إذا تحققت كل النقاط التالية:

- [ ] لا يوجد route مكسور أو redirect إلى مسار غير معرف.
- [x] شاشة إدارة الموظفين مهيأة لعرض الموظفين فعلياً من قاعدة البيانات عبر `get_all_staff_users` وتم التحقق من RPC على السيرفر.
- [ ] إضافة موظف تعمل وتعيد كلمة سر قابلة للنسخ — ينتظر اختبار عملي عبر التطبيق/HTTP.
- [ ] تغيير الدور يعمل عبر Edge Function آمنة — ينتظر اختبار عملي.
- [ ] التفعيل/التعطيل يعمل عبر Edge Function آمنة — ينتظر اختبار عملي.
- [ ] إعادة تعيين كلمة السر تعمل وتعرض كلمة السر مرة واحدة — ينتظر اختبار عملي.
- [ ] حذف الموظف soft delete ويمنع حذف المدير الرئيسي — ينتظر اختبار عملي.
- [ ] نائب المدير وموظف المكتب لديهما داشبوردات فعالة لا hardcoded.
- [ ] لا توجد رسائل placeholder في الكود.
- [ ] التوثيق مطابق للكود الفعلي.
- [ ] `FUNCTIONS_REFERENCE.md` لا يذكر ملفات أو دوال غير موجودة.
- [x] `setup.sql`/migrations متسقة مع بعضها وتم تطبيق RPCs على السيرفر.
- [ ] تم الالتزام بعدم استخدام GetX في مشروع عقارات السويداء.
- [ ] لا توجد `print` أو `debugPrint` في الكود النهائي.

---

## 10) الملفات المتوقع تعديلها في التنفيذ القادم

### Flutter

- `lib/core/router/app_router.dart`
- `lib/core/services/permission_service.dart`
- `lib/providers/admin_provider.dart`
- `lib/screens/admin/employee_management/employee_management_screen.dart`
- `lib/screens/admin/employee_management/add_employee_dialog.dart`
- `lib/screens/admin/employee_management/change_role_dialog.dart`
- `lib/screens/admin/employee_management/toggle_status_dialog.dart`
- `lib/screens/admin/admin_dashboard_screen.dart`
- `lib/screens/employee/employee_home_screen.dart`
- وربما إنشاء widget مشترك:
  - `lib/screens/admin/employee_management/password_result_dialog.dart`

### Supabase

- `supabase/migrations/2026_06_15_admin_employee_management_final.sql`
- `supabase/functions/create-user/index.ts`
- `supabase/functions/reset-user-password/index.ts`
- `supabase/functions/update-user-role/index.ts`
- `supabase/functions/toggle-user-status/index.ts`
- `supabase/functions/delete-user/index.ts`
- `supabase/setup.sql`
- `supabase/FUNCTIONS_REFERENCE.md`

### Docs

- `docs/ADMIN_RESTRUCTURING_PROGRESS.md`
- `docs/ADMIN_IMPLEMENTATION_COMPLETE.md`
- `docs/TEST_CHECKLIST.md`

---

## 11) ملاحظات تنفيذية نهائية

- هذه الخطة تلغي فكرة أن التنفيذ الحالي مكتمل 100%.
- أي ملف توثيق يقول إن التنفيذ مكتمل يجب تصحيحه بعد التنفيذ الفعلي.
- الأولوية الأولى عند بدء التعديل: الراوتر + `get_all_staff_users` + إلغاء placeholders.
- لا يتم رفع أو إعلان الاكتمال قبل اختبار تدفق كامل لكل دور.

---

**توقيع الخطة:**
تمت إعادة صياغة الخطة بعد مراجعة مشروع Final كمصدر هيكلي فقط، وبعد مطابقة ذلك مع وظائف ومنطق مشروع عقارات السويداء.
---

## ملاحظة لاحقة — خطة الإصلاح ذات الأولوية

بعد نشر إعادة هيكلة إدارة الموظفين، تم إنشاء خطة أوسع لمعالجة المخاطر المعمارية والأمنية:

`docs/PRIORITY_REMEDIATION_PLAN.md`

هذه الخطة الجديدة هي المرجع للمرحلة التالية، وتبدأ من اختبار خط الأساس ثم بناء جلسات موظفين آمنة.
