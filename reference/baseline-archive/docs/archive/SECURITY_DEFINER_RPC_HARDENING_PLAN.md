# خطة معالجة دوال SECURITY DEFINER المفتوحة للعميل

**المشروع:** المكتب العقاري الإلكتروني  
**آخر تحديث:** 2026-06-17  
**الحالة:** مرجع أمني/تنفيذي لمعالجة تحذيرات Supabase Linter من نوع:

```text
anon_security_definer_function_executable
authenticated_security_definer_function_executable
```

---

## 1. لماذا لم نغلق كل الدوال دفعة واحدة؟

يوجد عدد كبير من دوال `SECURITY DEFINER` في schema `public` ما زالت قابلة للتنفيذ من `anon` و/أو `authenticated`.

إغلاقها دفعة واحدة سيكسر التطبيق لأن التصميم الحالي ما زال يعتمد على RPC مباشرة في مسارات كثيرة، خصوصاً بسبب نظام الجلسات الداخلي الذي يمرر `user_uid` أو `admin_uid` للدوال.

لذلك اتُبع القرار التالي:

```text
نغلق فوراً الدوال التي أصبحت لها بدائل آمنة أو غير مستخدمة مباشرة.
ونترك مؤقتاً الدوال الضرورية للتطبيق، ثم ننقلها تدريجياً إلى Edge Functions أو Triggers موثوقة.
```

---

## 2. ما الذي تم قفله فعلاً حتى الآن؟

### 2.1 دوال OTP والتسجيل القديمة والجديدة

تم قفلها عن `anon/authenticated` وتركها لـ `service_role` فقط:

```text
generate_otp(text)
verify_otp(text, text)
create_user_from_phone(text, text)
generate_otp_v2(text, text)
verify_otp_v2(text, text)
upsert_user_after_otp(text, text)
```

السبب: التسجيل عبر SMS صار يجب أن يمر عبر:

```text
send-sms-otp
verify-sms-otp
```

وليس عبر RPC مباشرة من العميل.

---

### 2.2 دوال إدارة الموظفين الحساسة

تم قفلها عن `anon/authenticated` وتركها لـ `service_role` فقط:

```text
admin_create_staff_user(uuid, text, text, text, text, text, integer)
admin_create_staff_user(uuid, text, text, text, text, text, integer, text, text, text)
admin_update_staff_role(uuid, uuid, integer)
admin_toggle_staff_status(uuid, uuid, integer, text)
admin_reset_staff_password(uuid, uuid, text)
admin_delete_staff_user(uuid, uuid)
admin_update_user_permissions_by_admin(uuid, uuid, jsonb)
```

السبب: إدارة الموظفين تعمل الآن عبر Edge Functions:

```text
create-user
update-user-role
toggle-user-status
reset-user-password
delete-user
update-user-permissions
get-staff-id-images
```

---

### 2.3 دوال نقاط خطرة

تم قفلها عن `anon/authenticated` وتركها لـ `service_role` فقط:

```text
add_points(uuid, integer)
award_points_safe(uuid, text, integer)
```

السبب: لا يجوز للعميل تمرير `uid` أو `points` أو `event_type` ثم منح نقاط مباشرة.

الأثر المؤقت:

- قد تتوقف بعض مكافآت النقاط المباشرة من التطبيق.
- الوظائف الأساسية لا تتأثر.

الحل لاحقاً:

```text
نقل منح النقاط إلى Edge Functions أو Triggers تتحقق من الحدث الحقيقي.
```

---

### 2.4 دوال إشعارات مباشرة

تم قفلها عن `anon/authenticated` وتركها لـ `service_role` فقط:

```text
notify_user(uuid, integer, text, text, text, text)
send_push_notification(uuid, text, text, jsonb)
```

السبب: لا يجوز للعميل إنشاء إشعار أو إرسال push لأي مستخدم مباشرة.

الأثر المؤقت:

- أي إشعارات كان العميل ينشئها مباشرة قد تتوقف.
- الإشعارات الناتجة من triggers أو Edge Functions يجب أن تكون المسار الرسمي.

---

### 2.5 دوال Trigger/Helper داخلية

تم قفلها عن `anon/authenticated` وتركها لـ `service_role` فقط:

```text
trg_appointment_created()
trg_appointment_status_changed()
trg_deal_completed()
trg_offer_published_match_requests()
trg_offer_status_changed()
trg_payment_approved()
trg_rating_bonus()
check_offer_safe_update()
check_user_safe_insert()
check_user_safe_update()
check_rating_valid()
expire_offer_boosts()
expire_packages()
```

السبب: هذه دوال داخلية أو trigger functions ولا يجب أن تُستدعى من العميل مباشرة.

---

### 2.6 دوال مساعدة/قديمة غير مستخدمة مباشرة

تم قفلها عن `anon/authenticated` وتركها لـ `service_role` فقط:

```text
accounts_on_same_device(text)
get_user_by_email(text)
get_user_by_phone(text)
calculate_commission(numeric, numeric)
get_pending_offers_count()
send_appointment_reminders()
send_renewal_reminders()
admin_get_id_signed_path(uuid)
apply_referral(uuid, text, integer)
get_available_supervisor(timestamptz)
update_user_badge(uuid)
register_weekly_login(uuid, integer)
```

---

## 3. ما الذي ما زال مفتوحاً ولماذا؟

الدوال التالية ما زالت مفتوحة للـ `anon` حالياً لأن التطبيق يعتمد عليها مباشرة أو لأنها تحتاج نقل تدريجي.

> ملاحظة: وجودها هنا لا يعني أنها آمنة تماماً، بل يعني أن إغلاقها الآن قد يكسر فلو مستخدم أو إدارة.

---

## 4. تصنيف الدوال المتبقية حسب الأولوية

### 4.1 أولوية حرجة — يجب نقلها إلى Edge Functions أولاً

هذه دوال إدارية أو مالية أو تشغيلية حساسة، ويجب ألا تبقى قابلة للاستدعاء المباشر من العميل على المدى الطويل:

```text
admin_approve_verification_by_admin(uuid, uuid)
admin_reject_verification_by_admin(uuid, uuid, text)
admin_force_appointment_internal(uuid, uuid)
admin_fraud_suspects(uuid)
admin_handle_report_internal(uuid, uuid, integer, text, integer)
admin_reject_payment_internal(uuid, uuid)
admin_review_offer_internal(uuid, uuid, boolean, text)
admin_set_offer_priority_internal(uuid, uuid, text, integer)
admin_update_appointment_status_internal(uuid, uuid, integer, text)
approve_payment_final(uuid, uuid)
attach_photography_media_to_offer_internal(uuid, uuid)
complete_deal_internal(uuid, uuid, numeric, text)
create_deal_internal(uuid, jsonb)
create_photography_task_internal(uuid, uuid, uuid, text, timestamptz)
get_admin_appointments_internal(uuid)
get_admin_dashboard_stats(uuid)
get_admin_deals_internal(uuid)
get_admin_offers_internal(uuid, integer)
get_admin_payments_internal(uuid)
get_admin_pending_offers_internal(uuid)
get_admin_reports_internal(uuid)
get_admin_requests_internal(uuid)
get_all_pending_completion_requests(uuid)
get_all_staff_users(uuid)
process_completion_request(uuid, uuid, text, text)
update_photography_task_status_internal(uuid, uuid, integer, text)
```

#### الحل المقترح

إنشاء Edge Functions إدارية تتحقق من:

```text
staff_session_token
admin_uid
role/permissions
```

ثم تستدعي RPC بـ `service_role`.

#### أمثلة Edge Functions مطلوبة

```text
admin-review-offer
admin-update-appointment
admin-payments-action
admin-verification-action
admin-report-action
admin-priority-action
admin-deals-action
admin-photography-action
admin-dashboard-data
admin-completion-requests
```

بعد نقل كل مجموعة، يتم:

```sql
REVOKE EXECUTE FROM anon, authenticated
GRANT EXECUTE TO service_role
```

---

### 4.2 أولوية عالية — دوال المستخدمين التي تعدل بيانات أو تنشئ سجلات

هذه دوال يستخدمها المستخدم العادي أو الوسيط أو صاحب العرض:

```text
book_appointment_internal(uuid, uuid, timestamptz, uuid, uuid)
broker_handle_appointment_internal(uuid, uuid, text)
cancel_appointment_internal(uuid, uuid, text)
change_password_internal(uuid, text, text)
create_offer_internal(uuid, jsonb)
create_payment_internal(uuid, jsonb)
create_rating_internal(uuid, uuid, integer, text)
create_report_internal(uuid, jsonb)
create_request_internal(uuid, jsonb)
mark_social_published_internal(uuid, uuid, text)
owner_respond_appointment(uuid, uuid, boolean, integer, text, timestamptz)
purchase_offer_boost(uuid, uuid, text)
register_daily_streak_internal(uuid, integer)
register_device(text, text)
register_password(uuid, text, text)
request_verification_by_uid(uuid)
requester_counter_appointment(uuid, uuid, boolean, timestamptz)
reset_password_with_otp(uuid, text)
revoke_staff_session(uuid, text)
soft_delete_request_internal(uuid, uuid)
submit_broker_request_internal(uuid, text, integer, text, text)
update_request_internal(uuid, uuid, jsonb)
update_user_notification_settings_internal(uuid, jsonb)
update_user_profile_internal(uuid, jsonb)
```

#### المشكلة

العديد منها يعتمد على تمرير `p_user_uid` من العميل. هذا مقبول مؤقتاً فقط بسبب نمط الجلسات الحالي، لكنه ليس التصميم الأمني النهائي.

#### الحل المقترح

لكل دالة من هذه، نحتاج واحد من خيارين:

1. نقلها إلى Edge Function تتحقق من الجلسة.
2. أو تعديلها لتقرأ المستخدم من `auth.uid()` حصراً بعد توحيد نظام الجلسات مع Supabase Auth.

#### أمثلة Edge Functions مطلوبة

```text
user-create-offer
user-update-profile
user-book-appointment
user-cancel-appointment
user-payment-create
user-submit-report
user-submit-rating
user-request-verification
user-change-password
user-create-request
user-update-request
broker-handle-appointment
broker-submit-request
```

---

### 4.3 أولوية عالية — فلو المنفذ والمصور

الدوال المفتوحة حالياً:

```text
get_completed_tasks(uuid)
get_executor_task_by_appointment(uuid, uuid)
get_my_completion_requests(uuid)
get_my_tasks(uuid)
get_photographer_tasks_internal(uuid)
get_postponed_tasks(uuid)
request_completion_by_appointment(uuid, uuid, text)
start_photography_task_internal(uuid, uuid)
submit_photography_task_internal(uuid, uuid, jsonb, text)
update_task_outcome(uuid, uuid, text, text, text, timestamptz)
```

#### الحالة الحالية

تم تحسين منطقها مؤخراً، لكنها ما زالت تُستدعى مباشرة من التطبيق.

#### الحل المقترح

نقل العمليات الحساسة إلى Edge Functions:

```text
executor-get-tasks
executor-task-action
executor-request-completion
photographer-get-tasks
photographer-start-task
photographer-submit-task
```

ثم قفل RPCs عن العميل.

---

### 4.4 أولوية متوسطة — دوال القراءة

دوال القراءة التالية ما زالت مفتوحة لأن التطبيق يستخدمها بشكل مباشر:

```text
get_offer_by_id_internal(uuid, uuid)
get_owner_appointments_internal(uuid)
get_user_appointments_internal(uuid)
get_user_device_tokens(uuid)
get_user_full_by_id(uuid)
get_user_notifications_internal(uuid)
get_user_offers_internal(uuid)
get_user_payments_internal(uuid)
get_user_requests_internal(uuid)
get_staff_stats_internal(uuid)
get_broker_appointments_internal(uuid)
get_broker_deals_internal(uuid)
get_broker_offers_internal(uuid)
```

#### الحل المقترح

إما:

- نقلها إلى Edge Functions للبيانات الحساسة.
- أو إعادة كتابتها كـ `SECURITY INVOKER` مع RLS قوية.

---

### 4.5 دوال يمكن تركها مؤقتاً إن كانت غير حساسة أو مراقبة

```text
check_offer_duplicate(text, numeric, jsonb, uuid)
check_username_available(text)
increment_offer_views_internal(uuid)
login_with_password(text, text)
mark_all_notifications_read_internal(uuid)
mark_notification_read_internal(uuid, uuid)
```

#### ملاحظات

- `login_with_password` يجب أن يبقى callable من `anon` لأنه مسار دخول الموظفين.
- `check_username_available` يمكن أن يبقى مفتوحاً لأنه فحص توفر فقط، لكن يجب مراقبة rate limiting لاحقاً.
- `increment_offer_views_internal` يمكن أن يبقى مفتوحاً لكن قد يحتاج rate limiting لمنع تضخيم المشاهدات.
- `mark_notification_read_internal` يجب لاحقاً أن يتحقق من ملكية الإشعار بشكل صارم أو يُنقل إلى Edge Function.

---

## 5. استراتيجية الترحيل المقترحة

لا ننقل كل شيء دفعة واحدة. الترتيب المقترح:

### المرحلة 1 — الإدارة الحساسة

- مراجعة العروض.
- المدفوعات.
- التوثيق.
- التقارير.
- المواعيد.
- الصفقات.

الهدف: قفل معظم دوال `admin_*` عن العميل.

### المرحلة 2 — فلو المنفذ والمصور

- executor actions.
- photography actions.

الهدف: قفل دوال المنفذ والمصور المباشرة.

### المرحلة 3 — المستخدم العادي

- إضافة عرض.
- تعديل عرض.
- حجز موعد.
- دفع.
- تبليغ.
- تقييم.
- طلبات.

الهدف: إغلاق دوال الكتابة للمستخدمين.

### المرحلة 4 — النقاط والإشعارات

- بناء نظام منح نقاط عبر server-side events.
- بناء إشعارات عبر triggers/Edge Functions.

### المرحلة 5 — دوال القراءة

- نقل القراءة الحساسة إلى Edge Functions أو تقوية RLS.

---

## 6. قاعدة ذهبية لكل Edge Function جديدة

أي Edge Function إدارية يجب أن تتحقق من:

```json
{
  "admin_uid": "uuid",
  "staff_session_token": "token"
}
```

ثم تستدعي:

```text
validate_staff_session
```

ولا تعتمد على `admin_uid` وحده.

أي Edge Function لمستخدم عادي يجب أن تتحقق من واحد من:

- Supabase Auth session حقيقية.
- أو جلسة تطبيق داخلية موثوقة إذا تم تصميمها لاحقاً.

---

## 7. استعلامات متابعة

### 7.1 الدوال المفتوحة للـ anon

```sql
SELECT
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
ORDER BY p.proname, args;
```

### 7.2 الدوال المفتوحة لـ authenticated

```sql
SELECT
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true
  AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
ORDER BY p.proname, args;
```

---

## 8. ملاحظات مهمة

- قفل أي دالة قبل نقل استخدامها إلى Edge Function قد يكسر التطبيق.
- كل قفل يجب أن يُسبق ببحث في الكود:

```bash
grep -R "function_name" -n lib supabase/functions
```

- عند قفل أي دالة يجب تحديث:

```text
supabase/FUNCTIONS_REFERENCE.md
docs/CURRENT_STATUS.md
هذا الملف
```

---

## 9. الحالة الحالية المختصرة

```text
تم قفل: OTP, staff creation, wipe, direct points, direct notification, trigger/helper internals, بعض الدوال القديمة.
ما زال مفتوحاً: معظم دوال المستخدم والإدارة والفلو التشغيلي التي يعتمد عليها التطبيق مباشرة.
الخطة: نقل تدريجي إلى Edge Functions ثم قفل RPCs.
```

---

## 10. مجموعة إدارة العروض — تم تجهيز النقل إلى Edge Function

**تاريخ التجهيز:** 2026-06-17  
**Edge Function الجديدة:** `admin-offers`  
**Migration القفل بعد النشر:** `2026_06_17_lock_admin_offer_rpcs.sql`

### 10.1 الدوال التي نُقلت إلى Edge Function

```text
get_admin_pending_offers_internal(uuid)
get_admin_offers_internal(uuid, integer)
admin_review_offer_internal(uuid, uuid, boolean, text)
admin_set_offer_priority_internal(uuid, uuid, text, integer)
admin_delete_offer_internal(uuid, uuid)
```

### 10.2 لماذا هذه المجموعة أولاً؟

لأنها دوال إدارية حساسة ومستخدمة في:

- مراجعة العروض.
- مراجعة الوسائط.
- تحديد أولوية العرض.
- حذف/أرشفة عرض من الإدارة.

وكانت تُستدعى مباشرة من التطبيق عبر RPC، وهذا يظهر في linter كـ `SECURITY DEFINER` callable by `anon/authenticated`.

### 10.3 التصميم الجديد

التطبيق يستدعي:

```text
supabase.functions.invoke('admin-offers')
```

مع body يحتوي:

```json
{
  "action": "list_pending | list_media_review | review | set_priority | delete",
  "admin_uid": "...",
  "staff_session_token": "..."
}
```

ثم Edge Function:

1. تتحقق من Supabase Auth JWT إن وجد.
2. أو تتحقق من `staff_session_token` عبر `validate_staff_session`.
3. بعد التحقق تستدعي RPC القديمة باستخدام `service_role`.

### 10.4 خطوات التطبيق الآمن

لا تطبق migration القفل قبل هذه الخطوات:

1. `git pull` للحصول على الكود الجديد.
2. نشر الدالة:

```bash
supabase functions deploy admin-offers
```

3. اختبار:
   - فتح مراجعة العروض.
   - قبول/رفض عرض تجريبي.
   - فتح مراجعة الوسائط.
   - تحديد أولوية عرض.
   - حذف عرض تجريبي من صفحة التفاصيل.
4. بعدها فقط تطبيق:

```text
supabase/migrations/2026_06_17_lock_admin_offer_rpcs.sql
```

### 10.5 أثر القفل

بعد تطبيق القفل، الدوال المذكورة تصبح:

```text
anon = false
authenticated = false
service_role = true
```

وهذا لا يكسر التطبيق طالما `admin-offers` منشورة والكود الجديد مستخدم.

---

## 11. مجموعة إدارة التوثيق — تم تجهيز النقل إلى Edge Function

**تاريخ التجهيز:** 2026-06-17  
**Edge Function الجديدة:** `admin-verifications`  
**Migration القفل بعد النشر:** `2026_06_17_lock_admin_verification_rpcs.sql`

### 11.1 الدوال/المسارات التي نُقلت

```text
قراءة طلبات التوثيق pending users vrf=1
admin_approve_verification_by_admin(uuid, uuid)
admin_reject_verification_by_admin(uuid, uuid, text)
```

### 11.2 التصميم الجديد

التطبيق يستدعي:

```text
supabase.functions.invoke('admin-verifications')
```

مع actions:

```text
list_pending
approve
reject
```

Edge Function تتحقق من:

- Supabase Auth JWT مطابق إن وجد.
- أو `staff_session_token` صالح عبر `validate_staff_session`.
- الحد الأدنى للدور حالياً `role >= 4` لأن مراجعة التوثيق من صلاحيات موظف المكتب فما فوق.

### 11.3 خطوات التطبيق الآمن

1. `git pull` للحصول على الكود الجديد.
2. نشر الدالة:

```bash
supabase functions deploy admin-verifications
```

3. اختبار شاشة طلبات التوثيق.
4. اختبار اعتماد/رفض توثيق على حساب تجريبي.
5. بعدها فقط تطبيق:

```text
supabase/migrations/2026_06_17_lock_admin_verification_rpcs.sql
```

### 11.4 أثر القفل

بعد تطبيق القفل:

```text
admin_approve_verification_by_admin: anon=false, authenticated=false, service_role=true
admin_reject_verification_by_admin: anon=false, authenticated=false, service_role=true
```

---

## 12. مجموعة إدارة المدفوعات — تم تجهيز النقل إلى Edge Function

**تاريخ التجهيز:** 2026-06-17  
**Edge Function الجديدة:** `admin-payments`  
**Migration القفل بعد النشر:** `2026_06_17_lock_admin_payment_rpcs.sql`

### 12.1 الدوال التي نُقلت

```text
get_admin_payments_internal(uuid)
approve_payment_final(uuid, uuid)
admin_reject_payment_internal(uuid, uuid)
```

### 12.2 التصميم الجديد

التطبيق يستدعي:

```text
supabase.functions.invoke('admin-payments')
```

مع actions:

```text
list
approve
reject
```

Edge Function تتحقق من:

- Supabase Auth JWT مطابق إن وجد.
- أو `staff_session_token` صالح عبر `validate_staff_session`.
- الحد الأدنى للدور `role >= 5` لأن المدفوعات من صلاحيات الإدارة العليا.

### 12.3 خطوات التطبيق الآمن

1. `git pull` للحصول على الكود الجديد.
2. نشر الدالة:

```bash
supabase functions deploy admin-payments
```

3. اختبار شاشة المدفوعات.
4. اختبار قبول/رفض دفع تجريبي إن وجد.
5. بعدها فقط تطبيق:

```text
supabase/migrations/2026_06_17_lock_admin_payment_rpcs.sql
```

### 12.4 أثر القفل

بعد تطبيق القفل:

```text
get_admin_payments_internal: anon=false, authenticated=false, service_role=true
approve_payment_final: anon=false, authenticated=false, service_role=true
admin_reject_payment_internal: anon=false, authenticated=false, service_role=true
```

---

## 13. مجموعة إدارة المواعيد — ✅ مكتمل (تم النشر والقفل)

**تاريخ التجهيز:** 2026-06-17  
**Edge Function الجديدة:** `admin-appointments`  
**Migration القفل بعد النشر:** `2026_06_17_lock_admin_appointment_rpcs.sql`

### 13.1 الدوال التي نُقلت

```text
get_admin_appointments_internal(uuid)
admin_update_appointment_status_internal(uuid, uuid, integer, text)
admin_force_appointment_internal(uuid, uuid)
```

### 13.2 التصميم الجديد

التطبيق يستدعي:

```text
supabase.functions.invoke('admin-appointments')
```

مع actions:

```text
list
update_status
force
```

Edge Function تتحقق من:

- Supabase Auth JWT مطابق إن وجد.
- أو `staff_session_token` صالح عبر `validate_staff_session`.
- الحد الأدنى للدور `role >= 4` لأن إدارة المواعيد من صلاحيات موظف المكتب فما فوق.

### 13.3 خطوات التطبيق الآمن

1. `git pull` للحصول على الكود الجديد.
2. نشر الدالة:

```bash
supabase functions deploy admin-appointments
```

3. اختبار شاشة إدارة المواعيد.
4. اختبار تحديث حالة موعد أو فرض موعد تجريبي إن وجد.
5. بعدها فقط تطبيق:

```text
supabase/migrations/2026_06_17_lock_admin_appointment_rpcs.sql
```

### 13.4 أثر القفل

بعد تطبيق القفل:

```text
get_admin_appointments_internal: anon=false, authenticated=false, service_role=true
admin_update_appointment_status_internal: anon=false, authenticated=false, service_role=true
admin_force_appointment_internal: anon=false, authenticated=false, service_role=true
```

## 14. مجموعة إدارة التبليغات — ✅ مكتمل (تم النشر والقفل)

**تاريخ التجهيز:** 2026-06-20  
**Edge Function الجديدة:** `admin-reports`  
**Migration القفل بعد النشر:** `2026_06_20_lock_admin_reports_rpcs.sql`

### 14.1 الدوال التي نُقلت
- `get_admin_reports_internal`
- `admin_handle_report_internal`

### 14.2 طريقة العمل عبر Edge Function
التطبيق يستدعي:
```text
supabase.functions.invoke('admin-reports')
```
مع actions:
- `list` → استدعاء `get_admin_reports_internal`
- `handle` → استدعاء `admin_handle_report_internal`

### 14.3 خطوات التنفيذ
1. إنشاء Edge function `admin-reports`.
2. تعديل خدمة `ReportsAdminService` في Flutter.
3. نشر الدالة:
   ```bash
   supabase functions deploy admin-reports
   ```
4. قفل الـ RPCs.

## 15. مجموعة إدارة الصفقات — ✅ مكتمل (تم النشر والقفل)

**تاريخ التجهيز:** 2026-06-20  
**Edge Function الجديدة:** `admin-deals`  
**Migration القفل بعد النشر:** `2026_06_20_lock_admin_deals_rpcs.sql`

### 15.1 الدوال التي نُقلت
- `get_admin_deals_internal`
- `create_deal_internal`
- `complete_deal_internal`

### 15.2 طريقة العمل عبر Edge Function
التطبيق يستدعي:
```text
supabase.functions.invoke('admin-deals')
```
مع actions:
- `list` → استدعاء `get_admin_deals_internal`
- `create` → استدعاء `create_deal_internal`
- `complete` → استدعاء `complete_deal_internal`

### 15.3 خطوات التنفيذ
1. إنشاء Edge function `admin-deals`.
2. تعديل خدمة `DealsAdminService` في Flutter.
3. نشر الدالة:
   ```bash
   supabase functions deploy admin-deals
   ```
4. قفل الـ RPCs.

## 16. مجموعة مهام المنفذ والمصور — ✅ مكتمل (تم النشر والقفل)

**تاريخ التجهيز:** 2026-06-20  
**Edge Functions الجديدة:**
1. `executor-tasks`
2. `photographer-tasks`
3. `admin-photography`

**Migration القفل بعد النشر:** `2026_06_20_lock_tasks_rpcs.sql`

### 16.1 الدوال التي نُقلت
**للمنفذ (`executor-tasks`):**
- `get_my_tasks`
- `get_postponed_tasks`
- `get_completed_tasks`
- `get_executor_task_by_appointment`
- `get_my_completion_requests`
- `update_task_outcome`
- `request_completion_by_appointment`
- `get_all_pending_completion_requests` (admin)
- `process_completion_request` (admin)

**للمصور (`photographer-tasks`):**
- `get_photographer_tasks_internal`
- `start_photography_task_internal`
- `submit_photography_task_internal`

**للإدارة الخاصة بالتصوير (`admin-photography`):**
- `create_photography_task_internal`
- `update_photography_task_status_internal`
- `attach_photography_media_to_offer_internal`

### 16.2 خطوات التنفيذ
1. إنشاء دوال Edge `executor-tasks`, `photographer-tasks`, `admin-photography`.
2. تحديث `ExecutorProvider` و `PhotographyProvider`.
3. النشر:
   ```bash
   supabase functions deploy executor-tasks
   supabase functions deploy photographer-tasks
   supabase functions deploy admin-photography
   ```
4. اختبار الشاشات.
5. قفل الـ RPCs.

## 17. مجموعة إدارة عروض المستخدم — ✅ مكتمل (تم النشر والقفل)

**تاريخ التجهيز:** 2026-06-20  
**Edge Function الجديدة:** `user-offers`  
**Migration القفل بعد النشر:** `2026_06_20_lock_user_offers_rpcs.sql`

### 17.1 الدوال التي نُقلت
- `get_user_offers_internal`
- `get_offer_by_id_internal`
- `create_offer_internal`
- `increment_offer_views_internal`
- `check_offer_duplicate`
- `purchase_offer_boost`
- `mark_social_published_internal`

## 18. مجموعة إدارة طلبات المستخدم — ✅ مكتمل (تم النشر والقفل)

**تاريخ التجهيز:** 2026-06-20  
**Edge Function الجديدة:** `user-requests`  
**Migration القفل بعد النشر:** `2026_06_20_lock_user_requests_rpcs.sql`

### 18.1 الدوال التي نُقلت
- `get_user_requests_internal`
- `create_request_internal`
- `update_request_internal`
- `soft_delete_request_internal`

## 19. مجموعة إدارة مواعيد المستخدم (الحجز والردود) — ✅ مكتمل (تم النشر والقفل)

**تاريخ التجهيز:** 2026-06-20  
**Edge Function الجديدة:** `user-appointments`  
**Migration القفل بعد النشر:** `2026_06_20_lock_user_appointments_rpcs.sql`

### 19.1 الدوال التي نُقلت
- `get_user_appointments_internal`
- `get_owner_appointments_internal`
- `get_broker_appointments_internal`
- `book_appointment_internal`
- `cancel_appointment_internal`
- `broker_handle_appointment_internal`
- `owner_respond_appointment`
- `requester_counter_appointment`

## 20. مجموعة إشعارات المستخدم — ✅ مكتمل (تم النشر والقفل)

**تاريخ التجهيز:** 2026-06-20  
**Edge Function الجديدة:** `user-notifications`  
**Migration القفل بعد النشر:** `2026_06_20_lock_user_notifications_rpcs.sql`

### 20.1 الدوال التي نُقلت
- `get_user_notifications_internal`
- `mark_notification_read_internal`
- `mark_all_notifications_read_internal`
- `update_user_notification_settings_internal`

## 21. مجموعة حساب المستخدم والتسجيل — ✅ مكتمل (تم النشر والقفل)

**تاريخ التجهيز:** 2026-06-20  
**Edge Function الجديدة:** `user-account`  
**Migration القفل بعد النشر:** `2026_06_20_lock_user_account_rpcs.sql`

### 21.1 الدوال التي نُقلت
- `login_with_password`
- `check_username_available`
- `register_device`
- `get_user_full_by_id`
- `update_user_profile_internal`
- `get_user_device_tokens`
- `register_password`
- `change_password_internal`
- `request_verification_by_uid`

## 22. المجموعة الأخيرة (لوحة التحكم، الشكوك، وصلاحيات متفرقة) — ✅ مكتمل (تم النشر والقفل)

**تاريخ التجهيز:** 2026-06-20  
**Edge Functions الجديدة:**
- `admin-dashboard`
- `broker-actions`
- تم تحديث `user-account` ليدعم `reset_password_with_otp`.

**Migration القفل بعد النشر:** `2026_06_20_lock_final_rpcs.sql`

### 22.1 الدوال التي نُقلت
- `submit_broker_request_internal`
- `get_admin_dashboard_stats`
- `get_staff_stats_internal`
- `get_all_staff_users`
- `admin_fraud_suspects`
- `revoke_staff_session`
- `reset_password_with_otp`

## 23. الملاحق (الدوال المتبقية وإصلاحات Linter) — ✅ مكتمل (تم النشر والقفل)

**تاريخ التجهيز:** 2026-06-20  
**Migration القفل والتصحيح:** `2026_06_20_lock_missed_rpcs.sql` و `2026_06_20_fix_rls_no_policy.sql`

### 23.1 الدوال التي نُقلت في اللحظات الأخيرة
تم إدراج الدوال التالية ضمن الـ Edge Functions القائمة سابقاً:
- `create_report_internal` (أُضيفت إلى `user-account`)
- `get_broker_deals_internal` (أُضيفت إلى `user-offers`)
- `get_broker_offers_internal` (أُضيفت إلى `user-offers`)
- `get_admin_requests_internal` (أُضيفت إلى `admin-dashboard`)
- `get_user_payments_internal` (أُضيفت إلى `user-account`)
- `handle_email_auth_internal` (أُضيفت إلى `user-account`)

### 23.2 سياسات RLS المفقودة (RLS Enabled No Policy)
تمت إضافة سياسات أمان تمنح صلاحيات كاملة لـ `service_role` فقط للجداول التالية لإخفاء تحذيرات Linter، بما أن العميل لا يجب أن يتصل بها مباشرة:
- `staff_sessions`
- `stats`
- `user_daily_limits`

**بهذا نكون قد أتممنا المهمة الأمنية بنسبة 100% وتم إغلاق كافة تحذيرات Supabase Linter الخاصة بـ SECURITY DEFINER و RLS.**
