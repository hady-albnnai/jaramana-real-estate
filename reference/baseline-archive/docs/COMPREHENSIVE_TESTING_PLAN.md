# 🧪 خطة الاختبار الشاملة — المكتب العقاري الإلكتروني

> **التاريخ:** 2026-08-05  
> **الحالة:** 📋 خطة مقترحة (بانتظار موافقة المالك)  
> **النطاق:** اختبار شامل لجميع الوظائف + التحقق من تطابق الكود والسيرفر

---

## 📊 ملخص المشروع

| العنصر | العدد | الحالة |
|--------|------|--------|
| **الجداول** | 23 | ✅ |
| **دوال SQL (RPCs + Triggers)** | 185 | ✅ |
| **Edge Functions** | 33 | ✅ |
| **Providers** | 12 | ✅ |
| **Services** | 13 | ✅ |
| **الشاشات** | 67 | ✅ |
| **Cron Jobs** | 8 | ✅ |
| **الأدوار** | 9 (0-8) | ✅ |
| **حسابات الاختبار** | 19 | ✅ |

---

## 🎯 الأهداف

1. **التحقق من التطابق**: الكود في الريبو ≡ السيرفر الحي
2. **اختبار E2E**: كل سيناريو من البداية للنهاية
3. **اختبار الأمان**: RLS، صلاحيات، تحصين الدوال
4. **اختبار التكامل**: Edge ↔ SQL ↔ Provider ↔ UI
5. **اختبار البيانات**: Cron jobs، triggers، notifications
6. **توثيق الفجوات**: أي مسار غير مُختبر أو غير مكتمل

---

## 🗂️ هيكل الخطة

### المرحلة 0: التحقق من التطابق (Repo ↔ Server Sync)
**المدة المتوقعة:** 2-3 ساعات  
**الأولوية:** 🔴 حرجة (قبل أي اختبار)

#### 0.1 جرد الدوال (Functions Inventory)
```sql
-- السيرفر: قائمة كل الدوال
SELECT n.nspname AS schema, p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS signature,
       p.prosecdef AS security_definer,
       p.prokind AS kind
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.prokind = 'f'
ORDER BY p.proname;
```

**المطلوب:**
- [ ] استخراج قائمة الدوال من السيرفر (185 دالة)
- [ ] مقارنة مع `supabase/FUNCTIONS_REFERENCE.md`
- [ ] تحديد الدوال المفقودة/الزائدة
- [ ] فحص `search_path` لكل `SECURITY DEFINER`
- [ ] فحص `REVOKE/GRANT` لكل دالة

#### 0.2 جرد الجداول (Tables Inventory)
```sql
-- السيرفر: قائمة كل الجداول + الأعمدة
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;
```

**المطلوب:**
- [ ] مقارنة مع `lib/models/*.dart`
- [ ] فحص RLS policies لكل جدول
- [ ] فحص triggers (INSERT/UPDATE/DELETE)
- [ ] فحص constraints (CHECK, UNIQUE, FK)

#### 0.3 جرد Edge Functions
**المطلوب:**
- [ ] قائمة الـ 33 Edge Function المنشورة
- [ ] مقارنة مع `supabase/functions/` في الريبو
- [ ] فحص `--no-verify-jwt` لكل دالة
- [ ] فحص الـ secrets المُستخدمة

#### 0.4 جرد Cron Jobs
```sql
-- السيرفر: كل الـ cron jobs
SELECT jobid, jobname, schedule, command, active
FROM cron.job
ORDER BY jobid;
```

**المطلوب:**
- [ ] 8 cron jobs متوقعة (انظر أعلاه)
- [ ] فحص كل job ينادي الدالة الصحيحة
- [ ] اختبار يدوي لكل job: `SELECT cron.schedule(...)`

#### 0.5 ملف Deviation Report
**المخرج:** `docs/DEVIATION_REPORT_2026_08_05.md`
- كل الفرق بين الريبو والسيرفر
- الأولويات (حرج/متوسط/منخفض)
- خطة الإقفال (migration جديد / deploy / dump)

---

### المرحلة 1: اختبار المصادقة والصلاحيات (Auth & Permissions)
**المدة المتوقعة:** 3-4 ساعات  
**الأولوية:** 🔴 حرجة

#### 1.1 تسجيل الدخول (Login Flows)
| # | السيناريو | المسار | المتوقع | الحالة |
|---|-----------|--------|---------|--------|
| 1.1.1 | دخول باسم مستخدم + كلمة مرور | `/login` | `staff_session` + redirect | ⏳ |
| 1.1.2 | دخول برقم هاتف + كلمة مرور | `/login` | `staff_session` + redirect | ⏳ |
| 1.1.3 | OTP واتساب (إن مفعّل) | `/otp` | upsert user + `/setup-profile` | ⏳ |
| 1.1.4 | OTP SMS | `/otp` | upsert user + `/setup-profile` | ⏳ |
| 1.1.5 | Email Magic Link | `/check-email` | upsert user + `/setup-profile` | ⏳ |
| 1.1.6 | نسيان كلمة المرور | `/login` → OTP | reset + login | ⏳ |
| 1.1.7 | كلمة مرور خاطئة (3 مرات) | `/login` | rate limit | ⏳ |
| 1.1.8 | حساب محظور (`sts=blocked`) | `/login` | رفض واضح | ⏳ |

**حسابات الاختبار:**
```
hady (role 6)          — مدير
مستخدم1عادي (role 1)   — وسيط (مالك العروض)
مستخدم2عادي (role 0)   — مستخدم عادي
phototester1-2 (role 2) — مصوّر
supertester1-2 (role 3) — مشرف
officetester1-2 (role 4) — موظف مكتب
deputytester1-2 (role 5) — نائب مدير
lawyertester1-2 (role 7) — محامي
agenttester1-2 (role 8) — معقّب
brokertester1-2 (role 1) — وسيط
```

**كلمة السر:** `12345678` (كل الحسابات)

#### 1.2 Redirect حسب الدور
| الدور | الـ redirect المتوقع | الحالة |
|-------|---------------------|--------|
| 0 (مستخدم عادي) | `/user/home` | ⏳ |
| 1 (وسيط) | `/broker/dashboard` | ⏳ |
| 2 (مصور) | `/photographer/tasks` | ⏳ |
| 3 (مشرف) | `/employee/home` | ⏳ |
| 4 (موظف مكتب) | `/employee/home` | ⏳ |
| 5 (نائب) | `/admin/dashboard` | ⏳ |
| 6 (مدير) | `/admin/dashboard` | ⏳ |
| 7 (محامي) | `/lawyer/dashboard` | ⏳ |
| 8 (معقّب) | `/expediter/tasks` | ⏳ |

#### 1.3 RLS (Row-Level Security)
**كل جدول من الـ 23 يحتاج فحص:**

```sql
-- مثال: offers
-- anon يقرأ المنشور فقط
SET ROLE anon;
SELECT count(*) FROM offers WHERE i_pub=1;  -- يجب > 0
SELECT count(*) FROM offers WHERE i_pub=0;  -- يجب = 0

-- authenticated يقرأ عروضه + المنشور
SET ROLE authenticated;
SELECT count(*) FROM offers WHERE usr_id = auth.uid();  -- عروضه
SELECT count(*) FROM offers WHERE i_pub=1;  -- المنشور

-- service_role يقرأ كل شيء
SET ROLE service_role;
SELECT count(*) FROM offers;  -- الكل
```

**الجداول للفحص:**
- [ ] `users` (RLS: owner only)
- [ ] `offers` (RLS: anon=منشور، auth=owner+منشور، admin=كل)
- [ ] `appointments` (RLS: participants + admin)
- [ ] `notifications` (RLS: owner only)
- [ ] `requests` (RLS: owner + admin)
- [ ] `payments` (RLS: owner + admin)
- [ ] `ratings` (RLS: public read, auth write with checks)
- [ ] `photography_tasks` (RLS: photographer + admin)
- [ ] `completion_requests` (RLS: executor + admin)
- [ ] `deals` (RLS: participants + admin)
- [ ] `reports` (RLS: reporter + admin)
- [ ] `user_devices` (RLS: owner + service_role)
- [ ] `staff_sessions` (RLS: owner + service_role)
- [ ] `otp_codes` (RLS: service_role only)
- [ ] `activity_log` (RLS: admin only)
- [ ] `offer_documents` (RLS: owner + admin)
- [ ] `expediting_tasks` (RLS: expediter + admin)
- [ ] `legal_consultations` (RLS: lawyer + client + admin)
- [ ] `lawyer_profiles` (RLS: lawyer + admin)
- [ ] `stats` (RLS: public read)
- [ ] `user_daily_limits` (RLS: service_role)
- [ ] `app_config` (RLS: public read, service_role write)
- [ ] `internal_config` (RLS: service_role only)

#### 1.4 تحصين الدوال (Security Hardening)
**كل `SECURITY DEFINER` يحتاج رباعي التحصين:**

```sql
-- فحص كل دالة SECURITY DEFINER
SELECT p.proname, 
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_can_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS svc_can_exec
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.prosecdef = true
ORDER BY p.proname;
```

**المتوقع:**
- `anon_can_exec = false` ✅
- `auth_can_exec = false` ✅
- `svc_can_exec = true` ✅

**إن وجد تسريب (anon/auth = true):**
- سجل في `docs/SECURITY_LEAKS.md`
- أصلح بـ `REVOKE` فوري
- أضف migration

---

### المرحلة 2: اختبار الزائر (Visitor Flows)
**المدة المتوقعة:** 2 ساعة  
**الأولوية:** 🟡 متوسطة

| # | السيناريو | المسار | المتوقع | الحالة |
|---|-----------|--------|---------|--------|
| 2.1 | تصفح العروض المنشورة | `/home` | قائمة عروض + pagination | ⏳ |
| 2.2 | البحث (نص + فلاتر) | `/search` | نتائج دقيقة | ⏳ |
| 2.3 | تفاصيل العرض | `/offer/:id` | كل التفاصيل + صور + موقع | ⏳ |
| 2.4 | محاولة حجز موعد (بلا login) | `/offer/:id` → book | redirect لـ `/login` | ⏳ |
| 2.5 | Infinite scroll | `/home` | تحميل سلس بلا تكرار | ⏳ |
| 2.6 | الفلاتر (نوع/سعر/منطقة) | `/home` | فلترة صحيحة | ⏳ |
| 2.7 | العرض المميّز (Featured) | `/home` | شارة + ترتيب أول | ⏳ |
| 2.8 | عرض منتهي/محذوف | `/offer/:id` | 404 أو رسالة واضحة | ⏳ |

---

### المرحلة 3: اختبار المستخدم العادي (Role 0)
**المدة المتوقعة:** 4-5 ساعات  
**الأولوية:** 🔴 حرجة

#### 3.1 إدارة العروض
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 3.1.1 | إضافة عرض جديد | `user-offers: create` | `create_offer_internal` | `/user/add-offer` | ⏳ |
| 3.1.2 | رفع صور (حتى 10) | `upload-offer-images` | storage RLS | image picker | ⏳ |
| 3.1.3 | تعديل عرض قيد المراجعة (`sts=1`) | `user-offers: update` | `update_offer_internal` | `/user/edit-offer/:id` | ⏳ |
| 3.1.4 | حذف عرض (soft delete) | `user-offers: delete` | `delete_offer_internal` | my offers → delete | ⏳ |
| 3.1.5 | محاولة تعديل عرض منشور (`sts=2`) | `user-offers: update` | يجب رفض | ⏳ |
| 3.1.6 | تجاوز الحصة (quota) | `user-offers: create` | `QUOTA_EXCEEDED` | ⏳ |
| 3.1.7 | النشر الاجتماعي (checkbox) | `user-offers: create` | `i_soc=1` | ⏳ |
| 3.1.8 | الإقرار والتعهد قبل النشر | — | — | `_showPledgeDialog` | ⏳ |

#### 3.2 إدارة الطلبات
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 3.2.1 | إضافة طلب | `user-requests: create` | `create_request_internal` | `/user/add-request` | ⏳ |
| 3.2.2 | تعديل طلب | `user-requests: update` | `update_request_internal` | request detail | ⏳ |
| 3.2.3 | إلغاء طلب | `user-requests: cancel` | `cancel_request_internal` | my requests → cancel | ⏳ |
| 3.2.4 | تجديد طلب | `user-requests: renew` | `renew_request_internal` | my requests → renew | ⏳ |
| 3.2.5 | عرض الطلبات المطابقة | `user-requests: matching` | — | `/matching-offers` | ⏳ |
| 3.2.6 | انتهاء صلاحية الطلب (30 يوم) | — | `expire_requests()` (cron) | ⏳ |
| 3.2.7 | تذكير قبل الانتهاء (3 أيام) | — | `send_request_renewal_reminders()` | ⏳ |

#### 3.3 حجز المواعيد
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 3.3.1 | حجز موعد معاينة | `user-appointments: book` | `book_appointment_internal` | `BookAppointmentSheet` | ⏳ |
| 3.3.2 | التحقق من الهاتف قبل الحجز | — | — | OTP step | ⏳ |
| 3.3.3 | اختيار يوم/وقت من `avl` | — | — | calendar UI | ⏳ |
| 3.3.4 | رفض: وقت خارج `avl` | — | `DAY_NOT_AVAILABLE` | ⏳ |
| 3.3.5 | رفض: تعارض (فارق < ساعة) | — | `TIME_CONFLICT_ON_OFFER` | ⏳ |
| 3.3.6 | رفض: لا مشرف متاح | — | `NO_SUPERVISOR_AVAILABLE` + `suggested_dt` | ⏳ |
| 3.3.7 | رفض: `avl` فارغة | — | `NO_AVAILABILITY` | ⏳ |
| 3.3.8 | رفض: حجز عرضك الخاص | — | `CANNOT_BOOK_OWN_OFFER` | ⏳ |
| 3.3.9 | رفض: موعد مزدوج | — | `DUPLICATE_APPOINTMENT` | ⏳ |
| 3.3.10 | إلغاء موعد | `user-appointments: cancel` | `cancel_appointment_internal` | my appointments | ⏳ |
| 3.3.11 | طلب وقت بديل (counter) | `user-appointments: requester_counter` | `requester_counter_appointment` | my appointments | ⏳ |
| 3.3.12 | طلب فيديو (حجز + واتساب) | `user-appointments: book` | `isVideoRequest=true` | offer detail → video | ⏳ |

#### 3.4 الإشعارات
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 3.4.1 | قائمة الإشعارات | `user-notifications: list` | — | `/user/notifications` | ⏳ |
| 3.4.2 | تعليم كمقروء | `user-notifications: read` | `UPDATE notifications SET i_rd=1` | tap notification | ⏳ |
| 3.4.3 | Push (FCM) عند إشعار جديد | `send-push-notification` | `notify_user()` | background push | ⏳ |
| 3.4.4 | إعدادات Push channels | `user-account: notification_settings` | — | `/user/push-channels` | ⏳ |

#### 3.5 النقاط والباقات
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 3.5.1 | تسجيل دخول يومي (streak) | `user-rewards: daily_login` | `register_daily_streak_internal` | — | ⏳ |
| 3.5.2 | ترقية عرض بالنقاط (boost) | `user-offers: boost` | `purchase_offer_boost` | `/user/boost-offer/:id` | ⏳ |
| 3.5.3 | شراء باقة (فضي/ذهبي) | `user-account: create_payment` | `create_payment_internal` | `/user/packages` | ⏳ |
| 3.5.4 | رفع إيصال الدفع | — | storage `payment_proofs` | payment screen | ⏳ |
| 3.5.5 | الإحالة (referral code) | `user-account: apply_referral` | `apply_referral` | `/user/referral` | ⏳ |

#### 3.6 الملف الشخصي
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 3.6.1 | عرض الملف الشخصي | — | `get_user_full_by_id` | `/user/profile` | ⏳ |
| 3.6.2 | تعديل الاسم/الصورة | `user-account: update_profile` | `update_user_profile_internal` | profile → edit | ⏳ |
| 3.6.3 | طلب توثيق (رفع هوية) | `user-account: request_verification` | `request_verification_by_uid` | profile → verify | ⏳ |
| 3.6.4 | تغيير كلمة المرور | `user-account: change_password` | `change_password_internal` | account info | ⏳ |
| 3.6.5 | المفضلة | — | — | `/user/favorites` | ⏳ |
| 3.6.6 | تقييماتي | — | — | `/user/my-ratings` | ⏳ |
| 3.6.7 | دفعاتي | — | — | `/user/my-payments` | ⏳ |
| 3.6.8 | الطلب becoming broker | `user-account: become_broker` | — | `/user/become-broker` | ⏳ |

---

### المرحلة 4: اختبار الوسيط (Role 1)
**المدة المتوقعة:** 2-3 ساعات  
**الأولوية:** 🟡 متوسطة

| # | السيناريو | المسار | المتوقع | الحالة |
|---|-----------|--------|---------|--------|
| 4.1 | لوحة الوسيط | `/broker/dashboard` | إحصائيات + quick actions | ⏳ |
| 4.2 | عروضي | `/broker/offers` | قائمة عروض الوسيط | ⏳ |
| 4.3 | مواعيدي | `/broker/appointments` | مواعيد الوسيط | ⏳ |
| 4.4 | صفقاتي | `/broker/deals` | صفقات + عمولات | ⏳ |
| 4.5 | إحصائياتي | `/broker/stats` | charts + metrics | ⏳ |
| 4.6 | كوتا الوسيط | — | حساب صحيح | ⏳ |
| 4.7 | عمولات `brk_pct`/`com` | — | حساب صحيح | ⏳ |
| 4.8 | التوثيق الإجباري | `/user/become-broker` | لا يمكن بدون توثيق | ⏳ |

---

### المرحلة 5: اختبار المصوّر (Role 2)
**المدة المتوقعة:** 3-4 ساعات  
**الأولوية:** 🟡 متوسطة

| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 5.1 | قائمة مهام التصوير | `photographer-tasks: list` | `get_photographer_tasks_internal` | `/photographer/tasks` | ⏳ |
| 5.2 | بدء مهمة تصوير | `photographer-tasks: start` | `start_photography_task_internal` | tasks → start | ⏳ |
| 5.3 | تسليم الصور | `photographer-tasks: submit` | `submit_photography_task_internal` | tasks → submit | ⏳ |
| 5.4 | اعتذار عن مهمة | `photographer-tasks: decline` | `decline_photography_task_internal` | tasks → decline | ⏳ |
| 5.5 | تأجيل موعد | `photographer-tasks: postpone` | — | tasks → postpone | ⏳ |
| 5.6 | تذكير قبل ساعة | — | `send_photography_reminders()` (cron) | push notification | ⏳ |
| 5.7 | منع الموعد الماضي | — | check in `book_photography_internal` | — | ⏳ |
| 5.8 | منع تعارض مواعيد المصوّر | — | check in `book_photography_internal` | — | ⏳ |
| 5.9 | إعادة الإسناد عند الاعتذار | — | `reassign_photography_task_internal` | — | ⏳ |
| 5.10 | منع فقدان الصور | — | check in `submit_photography_task_internal` | — | ⏳ |

---

### المرحلة 6: اختبار المشرف (Role 3)
**المدة المتوقعة:** 2-3 ساعات  
**الأولوية:** 🟡 متوسطة

| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 6.1 | الإسناد التلقائي (الأقل حمولة) | `user-appointments: book` | `get_available_supervisor` | — | ⏳ |
| 6.2 | إشعار الإسناد الفوري | — | `trg_appt_notify_supervisor` | push notification | ⏳ |
| 6.3 | قبول موعد | `user-appointments: owner_respond` | `owner_respond_appointment` | my appointments | ⏳ |
| 6.4 | رفض موعد (مع سبب) | `user-appointments: owner_respond` | `owner_respond_appointment` | my appointments | ⏳ |
| 6.5 | اقتراح وقت بديل | `user-appointments: owner_respond` | `owner_respond_appointment` | my appointments | ⏳ |
| 6.6 | إشعار القبول الغني (للطالب) | — | `trg_appt_accept_enrich` | push notification | ⏳ |
| 6.7 | التذكيرات (24س/2س/15د) | — | `send_appointment_reminders()` | push notification | ⏳ |
| 6.8 | إكمال موعد (mark complete) | `user-appointments: complete` | `complete_appointment_internal` | my appointments | ⏳ |
| 6.9 | إلغاء موعد | `user-appointments: cancel` | `cancel_appointment_internal` | my appointments | ⏳ |

---

### المرحلة 7: اختبار موظف المكتب (Role 4)
**المدة المتوقعة:** 2-3 ساعات  
**الأولوية:** 🟡 متوسطة

| # | السيناريو | المسار | المتوقع | الحالة |
|---|-----------|--------|---------|--------|
| 7.1 | شاشة الموظف الرئيسية | `/employee/home` | عمليات يومية | ⏳ |
| 7.2 | إضافة عرض بالنيابة عن عميل | — | `added_by` = employee uid | ⏳ |
| 7.3 | مراجعة العروض المعلقة | — | قائمة `sts=1` | ⏳ |
| 7.4 | قبول/رفض عرض | — | `admin_review_offer_internal` | ⏳ |
| 7.5 | مراجعة طلبات التوثيق | — | قائمة `vrf=1` | ⏳ |
| 7.6 | قبول/رفض توثيق | — | `admin_approve/reject_verification` | ⏳ |

---

### المرحلة 8: اختبار نائب المدير (Role 5)
**المدة المتوقعة:** 2-3 ساعات  
**الأولوية:** 🟡 متوسطة

| # | السيناريو | المسار | المتوقع | الحالة |
|---|-----------|--------|---------|--------|
| 8.1 | لوحة الإدارة | `/admin/dashboard` | إحصائيات شاملة | ⏳ |
| 8.2 | إدارة المدفوعات | `/admin/payments` | قبول/رفض | ⏳ |
| 8.3 | قبول دفعة | — | `approve_payment_final` + ترقية باقة | ⏳ |
| 8.4 | رفض دفعة (مع سبب) | — | `admin_reject_payment_internal` | ⏳ |
| 8.5 | إعدادات فيديو واتساب/مجموعة | `/admin/config` | تعديل `videoRequestWhatsApp` | ⏳ |
| 8.6 | النشر الاجتماعي اليدوي | — | `publish-to-social` | ⏳ |

---

### المرحلة 9: اختبار المدير (Role 6)
**المدة المتوقعة:** 4-5 ساعات  
**الأولوية:** 🔴 حرجة

#### 9.1 لوحة الإدارة
| # | السيناريو | المسار | Expected | الحالة |
|---|-----------|--------|---------|--------|
| 9.1.1 | إحصائيات شاملة | `/admin/dashboard` | `get_admin_dashboard_stats` | ⏳ |
| 9.1.2 | Analytics | `/admin/analytics` | charts + trends | ⏳ |
| 9.1.3 | Reports | `/admin/reports` | تقارير مفصلة | ⏳ |
| 9.1.4 | Resource usage | `/admin/resource-usage` | storage + API calls | ⏳ |

#### 9.2 إدارة الموظفين
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 9.2.1 | قائمة الموظفين | `admin-dashboard: list_staff` | `get_all_staff_users` | `/admin/employee-management` | ⏳ |
| 9.2.2 | إضافة موظف | `create-user` | `admin_create_staff_user` | add employee dialog | ⏳ |
| 9.2.3 | تعديل دور موظف | `update-user-role` | `admin_update_staff_role` | change role dialog | ⏳ |
| 9.2.4 | تفعيل/تعطيل موظف | `toggle-user-status` | `admin_toggle_staff_status` | toggle status dialog | ⏳ |
| 9.2.5 | إعادة تعيين كلمة مرور | `reset-user-password` | `admin_reset_staff_password` | password result dialog | ⏳ |
| 9.2.6 | حذف موظف | `delete-user` | `admin_delete_staff_user` | confirm dialog | ⏳ |
| 9.2.7 | عرض صور الهوية | `get-staff-id-images` | — | employee details | ⏳ |
| 9.2.8 | تحديث صور الهوية | `update-staff-id-images` | — | employee details | ⏳ |

#### 9.3 إدارة العروض
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 9.3.1 | قائمة العروض المعلقة | `admin-offers: list_pending` | `get_admin_offers_internal` | `/admin/review-offers` | ⏳ |
| 9.3.2 | قبول عرض + نشر سوشيال | `admin-offers: approve` | `admin_review_offer_internal` + `publish-to-social` | approve button | ⏳ |
| 9.3.3 | رفض عرض (مع سبب) | `admin-offers: reject` | `admin_review_offer_internal` | reject button | ⏳ |
| 9.3.4 | إضافة عرض بالنيابة | `admin-offers: create` | `create_offer_internal` (added_by=admin) | `/admin/add-offer` | ⏳ |
| 9.3.5 | حذف عرض | `admin-offers: delete` | `admin_delete_offer_internal` | delete button | ⏳ |
| 9.3.6 | إعطاء أولوية (Featured) | `admin-offers: feature` | `admin_feature_offer_internal` | feature button | ⏳ |

#### 9.4 إدارة المواعيد
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 9.4.1 | قائمة كل المواعيد | `admin-appointments: list` | `get_admin_appointments_internal` | `/admin/appointments` | ⏳ |
| 9.4.2 | تفاصيل موعد | — | — | appointment details | ⏳ |
| 9.4.3 | إلغاء موعد إدارياً | `admin-appointments: cancel` | `admin_cancel_appointment_internal` | cancel button | ⏳ |
| 9.4.4 | إعادة تعيين مشرف | `admin-appointments: reassign` | `admin_reassign_supervisor_internal` | reassign button | ⏳ |

#### 9.5 إدارة الصفقات
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 9.5.1 | قائمة الصفقات | `admin-deals: list` | `get_admin_deals_internal` | `/admin/deals` | ⏳ |
| 9.5.2 | إتمام صفقة | `admin-deals: complete` | `admin_complete_deal_internal` | complete button | ⏳ |
| 9.5.3 | إلغاء صفقة | `admin-deals: cancel` | `admin_cancel_deal_internal` | cancel button | ⏳ |
| 9.5.4 | إشعارات البائع/المشتري/السمسار | — | `trg_deal_completed` | push notifications | ⏳ |

#### 9.6 إدارة الطلبات
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 9.6.1 | قائمة كل الطلبات | `admin-dashboard: list_requests` | `get_admin_requests_internal` | `/admin/requests` | ⏳ |
| 9.6.2 | إغلاق طلب إدارياً | `admin-dashboard: close_request` | `admin_close_request_internal` | close button | ⏳ |
| 9.6.3 | عرض معلومات الإغلاق (closed_by/reason) | — | — | request details | ⏳ |

#### 9.7 إدارة التصوير
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 9.7.1 | إحصاءات التصوير | `admin-photography: stats` | `get_photography_stats_internal` | `/admin/photography-management` | ⏳ |
| 9.7.2 | إسناد مصوّر يدوياً | `admin-photography: assign` | `assign_photography_task_internal` | assign button | ⏳ |
| 9.7.3 | إلغاء مهمة تصوير | `admin-photography: cancel` | `cancel_photography_task_internal` | cancel button | ⏳ |
| 9.7.4 | تعديل أجر التصوير | `/admin/config` | `updateConfig` → `photoPrice` | config editor | ⏳ |

#### 9.8 إعدادات التطبيق
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 9.8.1 | قراءة الإعدادات | `admin-config: get` | `SELECT * FROM app_config` | `/admin/config` | ⏳ |
| 9.8.2 | تعديل إعدادات (sections) | `admin-config: update_sections` | `update_sections_internal` | config editor | ⏳ |
| 9.8.3 | تعديل قنوات الدفع | `admin-config: update_pay_channels` | — | payment channels editor | ⏳ |
| 9.8.4 | تعديل أسعار الباقات | `admin-config: update_pkg_prices` | — | config editor | ⏳ |
| 9.8.5 | تعديل سعر الصرف | `admin-config: update_fx_rate` | — | config editor | ⏳ |
| 9.8.6 | النشر التلقائي (autoPublish) | `admin-config: toggle_auto_publish` | — | config editor | ⏳ |

#### 9.9 الأمان والاحتيال
| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 9.9.1 | قائمة المشتبهين | `admin-dashboard: fraud_suspects` | `admin_fraud_suspects` | `/admin/fraud-suspects` | ⏳ |
| 9.9.2 | عرض تفاصيل الاشتباه | — | — | suspect details | ⏳ |
| 9.9.3 | حظر مستخدم | `admin-dashboard: ban_user` | `admin_ban_user_internal` | ban button | ⏳ |
| 9.9.4 | Activity log | — | `activity_log` table | — | ⏳ |

#### 9.10 الصلاحيات
| # | السيناريو | المسار | Expected | الحالة |
|---|-----------|--------|---------|--------|
| 9.10.1 | إدارة صلاحيات الموظفين | `/admin/permissions` | matrix صلاحيات | ⏳ |
| 9.10.2 | تعديل صلاحيات دور | `update-user-permissions` | `update_permissions_internal` | ⏳ |

#### 9.11 العمليات اليومية
| # | السيناريو | المسار | Expected | الحالة |
|---|-----------|--------|---------|--------|
| 9.11.1 | شاشة عمليات المكتب | `/admin/office-operations` | tasks + stats | ⏳ |
| 9.11.2 | طلبات الإتمام المعلقة | `/admin/completion-requests` | قائمة requests | ⏳ |
| 9.11.3 | قبول/رفض إتمام | — | `process_completion_request` | approve/reject | ⏳ |

---

### المرحلة 10: اختبار المحامي (Role 7)
**المدة المتوقعة:** 2-3 ساعات  
**الأولوية:** 🟡 متوسطة

| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 10.1 | لوحة المحامي | — | — | `/lawyer/dashboard` | ⏳ |
| 10.2 | قائمة الاستشارات | `legal-actions: list_consultations` | `get_lawyer_consultations_internal` | lawyer dashboard | ⏳ |
| 10.3 | قبول استشارة | `legal-actions: accept` | `accept_legal_consultation_internal` | accept button | ⏳ |
| 10.4 | رفض استشارة | `legal-actions: reject` | `reject_legal_consultation_internal` | reject button | ⏳ |
| 10.5 | إكمال استشارة | `legal-actions: complete` | `complete_legal_consultation_internal` | complete button | ⏳ |
| 10.6 | إشعارات الاستشارات | — | triggers on `legal_consultations` | push notifications | ⏳ |
| 10.7 | ملف المحامي | — | `lawyer_profiles` | profile section | ⏳ |

---

### المرحلة 11: اختبار المعقّب (Role 8)
**المدة المتوقعة:** 2-3 ساعات  
**الأولوية:** 🟡 متوسطة

| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 11.1 | قائمة مهام التعقيب | `legal-actions: list_expediting` | `get_expediting_tasks_internal` | `/expediter/tasks` | ⏳ |
| 11.2 | تفاصيل مهمة | — | — | `/expediter/task-detail` | ⏳ |
| 11.3 | قبول مهمة | `legal-actions: accept_expediting` | `accept_expediting_task_internal` | accept button | ⏳ |
| 11.4 | إكمال مهمة + رفع مستندات | `legal-actions: complete_expediting` | `complete_expediting_task_internal` | complete + upload | ⏳ |
| 11.5 | مراجعة المستندات (إدارة) | — | — | media review | ⏳ |
| 11.6 | إشعارات التعقيب | — | triggers on `expediting_tasks` | push notifications | ⏳ |

---

### المرحلة 12: اختبار المنفذ (Executor — Role 4 subset)
**المدة المتوقعة:** 2 ساعة  
**الأولوية:** 🟡 متوسطة

| # | السيناريو | Edge Function | SQL | UI | الحالة |
|---|-----------|---------------|-----|-----|--------|
| 12.1 | قائمة مهام الإتمام | `executor-tasks: list` | `get_my_completion_requests` | `/executor/tasks` | ⏳ |
| 12.2 | بدء مهمة | `executor-tasks: start` | `start_completion_request_internal` | tasks → start | ⏳ |
| 12.3 | تنفيذ مهمة + رفع صور | `executor-tasks: execute` | `execute_completion_request_internal` | `/executor/execute/:id` | ⏳ |
| 12.4 | تسليم مهمة | `executor-tasks: submit` | `submit_completion_request_internal` | submit button | ⏳ |
| 12.5 | رفض مهمة | `executor-tasks: reject` | `reject_completion_request_internal` | reject button | ⏳ |

---

### المرحلة 13: اختبار التكامل (Integration Testing)
**المدة المتوقعة:** 3-4 ساعات  
**الأولوية:** 🔴 حرجة

#### 13.1 سلسلة حجز كاملة (E2E)
```
1. مستخدم2عادي يحجز موعد على عرض "يتيني"
2. supertester1 (الأقل حمولة) يُسنَد تلقائياً
3. إشعار فوري لـ supertester1: "📋 أُسند إليك موعد معاينة"
4. مستخدم1عادي (مالك العرض) يُشعَر: "📅 طلب معاينة جديد"
5. مستخدم1عادي يقبل الموعد
6. إشعار غني لـ مستخدم2عادي: "✅ تم تأكيد موعدك — يرجى الحضور..."
7. إشعار لـ supertester1: "✅ تم تأكيد موعدك"
8. تذكير 24س/2س/15د لكل من الطالب والمشرف
9. إكمال الموعد → sts=2
10. زر تقييم يظهر للطالب
11. تقييم 5 نجوم → 200 نقطة للمالك
```

**المطلوب:** تنفيذ كامل السلسلة + توثيق كل خطوة بأرقام قبل/بعد

#### 13.2 سلسلة دفع كاملة (E2E)
```
1. مستخدم2عادي يختار باقة فضية
2. create_payment_internal → payment sts=0 (pending)
3. رفع إيصال الدفع
4. إشعار للإدارة: "💰 طلب دفع جديد"
5. deputytester1 يقبل الدفع
6. approve_payment_final → user.pkg='silver', pkg_end=+45d
7. إشعار للمستخدم: "✅ تم تفعيل باقتك"
8. push notification (FCM)
```

#### 13.3 سلسلة تصوير كاملة (E2E)
```
1. مستخدم2عادي يطلب خدمة تصوير
2. book_photography_internal → photography_task sts=0
3. إشعار لـ phototester1: "📸 مهمة تصوير جديدة"
4. phototester1 يبدأ المهمة → sts=1
5. إشعار لـ مستخدم2عادي: "📸 المصوّر في الطريق"
6. phototester1 يسلم الصور → sts=2
7. إشعار لـ مستخدم2عادي: "✅ تم تسليم الصور"
8. الإدارة تراجع الصور
9. الإدارة توافق → الصور تُنقل لـ offer_documents
10. إشعار لـ phototester1: "✅ تم قبول صورك"
```

#### 13.4 سلسلة طلب كامل (E2E)
```
1. مستخدم2عادي يضيف طلب → request sts=0
2. بعد 27 يوم: تذكير قبل الانتهاء (3 أيام)
3. بعد 30 يوم: expire_requests() → sts=4
4. إشعار للمستخدم: "⏰ انتهى طلبك"
5. المستخدم يجدد الطلب → sts=0, d_exp=+30d
```

#### 13.5 سلسلة صفقة كاملة (E2E)
```
1. موعد مكتمل (sts=2)
2. executor يبدأ طلب إتمام → completion_request sts=0
3. executor ينفذ + يرفع صور → sts=1
4. executor يسلم → sts=2
5. الإدارة توافق → process_completion_request('approved')
6. appointment.sts=2 (completed)
7. request.sts=2 (closed)
8. deal يُنشأ تلقائياً
9. trg_deal_completed → إشعارات للبائع/المشتري/السمسار
10. نقاط للطرفين (dlD)
```

---

### المرحلة 14: اختبار Cron Jobs
**المدة المتوقعة:** 2 ساعة  
**الأولوية:** 🟡 متوسطة

| # | Cron Job | الجدولة | الدالة | الاختبار | الحالة |
|---|----------|---------|--------|----------|--------|
| 14.1 | daily-expire-offers | 3:00 AM | `expire_offers()` | إنشاء عرض `d_exp=NOW()-1d` → تشغيل يدوي → sts=5 | ⏳ |
| 14.2 | daily-expire-boosts | 3:05 AM | `expire_offer_boosts()` | boost `bst_end=NOW()-1h` → تشغيل → i_bst=0 | ⏳ |
| 14.3 | daily-expire-packages | 3:10 AM | `expire_packages()` | user `pkg_end=NOW()-1d` → تشغيل → pkg='free' | ⏳ |
| 14.4 | daily-renewal-reminders | 3:15 AM | `send_renewal_reminders()` | offer `d_exp=NOW()+3d` → تشغيل → إشعار | ⏳ |
| 14.5 | daily-request-renewal-reminders | 3:20 AM | `send_request_renewal_reminders()` | request `d_exp=NOW()+3d` → تشغيل → إشعار | ⏳ |
| 14.6 | daily-expire-requests | 3:25 AM | `expire_requests()` | request `d_exp=NOW()-1d` → تشغيل → sts=4 | ⏳ |
| 14.7 | weekly-purge-old-closed-requests | Sunday 3:35 AM | `purge_old_closed_requests()` | request sts=2 + closed 180d → تشغيل → i_del=1 | ⏳ |
| 14.8 | appointment-reminders-15min | */15 min | `send_appointment_reminders()` + `send_photography_reminders()` | appointment dt=NOW()+25h → تشغيل → rmnd_24=1 | ⏳ |

**طريقة الاختبار:**
```sql
-- تشغيل يدوي
SELECT cron.schedule('test-job', 'now', 'SELECT expire_offers()');
-- ثم فحص النتائج
SELECT * FROM offers WHERE d_exp < NOW();
```

---

### المرحلة 15: اختبار الأمان المتقدم
**المدة المتوقعة:** 3-4 ساعات  
**الأولوية:** 🔴 حرجة

#### 15.1 SQL Injection
- كل Edge Function تحتاج فحص المدخلات
- كل RPC تحتاج فحص `app_assert_*`
- اختبار بقيم خبيثة: `' OR 1=1 --`

#### 15.2 Privilege Escalation
```sql
-- مستخدم عادي يحاول استدعاء دالة أدمن
SET ROLE authenticated;
SELECT admin_approve_verification_by_admin(...);  -- يجب 42501
```

#### 15.3 Self-Promotion Prevention
```sql
-- مستخدم يحاول تعديل دوره
UPDATE users SET role = 6 WHERE id = auth.uid();  -- يجب رفض (trigger)
```

#### 15.4 Rate Limiting
- OTP: 5 محاولات/ساعة
- Referral: 5 إحالات/ساعة
- Login: 10 محاولات/ساعة

#### 15.5 Phishing Prevention
```sql
-- محاولة INSERT مباشر في notifications
INSERT INTO notifications (...) VALUES (...);  -- يجب رفض (WITH CHECK false)
```

#### 15.6 Storage Security
- `offer_images`: RLS (owner OR admin OR service_role)
- `payment_proofs`: RLS (owner + service_role)
- `ids_private`: RLS (owner + admin)

---

### المرحلة 16: اختبار الأداء (Performance)
**المدة المتوقعة:** 2 ساعة  
**الأولوية:** 🟢 منخفضة

| # | السيناريو | المتوقع | الحالة |
|---|-----------|---------|--------|
| 16.1 | تحميل 100 عرض (pagination) | < 2s | ⏳ |
| 16.2 | بحث في 1000 عرض | < 1s | ⏳ |
| 16.3 | تحميل 500 إشعار | < 2s | ⏳ |
| 16.4 | GridView.builder (lazy loading) | سلس | ⏳ |
| 16.5 | Infinite scroll | بلا تأخير | ⏳ |

---

### المرحلة 17: اختبار الـ UI/UX
**المدة المتوقعة:** 3-4 ساعات  
**الأولوية:** 🟡 متوسطة

#### 17.1 Responsive Design
- [ ] موبايل (320px - 599px)
- [ ] تابلت (600px - 1199px)
- [ ] ديسكتوب (1200px+)

#### 17.2 Theme System
- [ ] كل الألوان من `AppTheme`
- [ ] كل الأحجام من `AppTheme`
- [ ] كل المسافات من `AppTheme`

#### 17.3 Accessibility
- [ ] Semantic labels
- [ ] تكبير النصوص
- [ ] قارئات الشاشة

#### 17.4 Error Handling
- [ ] رسائل خطأ واضحة
- [ ] Loading states
- [ ] Empty states
- [ ] Retry buttons

---

## 📋 ملخص الأولويات

| الأولوية | المرحلة | المدة | الحالة |
|----------|---------|-------|--------|
| 🔴 حرجة | 0 (تطابق) | 2-3h | ⏳ |
| 🔴 حرجة | 1 (مصادقة) | 3-4h | ⏳ |
| 🔴 حرجة | 3 (مستخدم عادي) | 4-5h | ⏳ |
| 🔴 حرجة | 9 (مدير) | 4-5h | ⏳ |
| 🔴 حرجة | 13 (تكامل) | 3-4h | ⏳ |
| 🔴 حرجة | 15 (أمان) | 3-4h | ⏳ |
| 🟡 متوسطة | 2 (زائر) | 2h | ⏳ |
| 🟡 متوسطة | 4 (وسيط) | 2-3h | ⏳ |
| 🟡 متوسطة | 5 (مصوّر) | 3-4h | ⏳ |
| 🟡 متوسطة | 6 (مشرف) | 2-3h | ⏳ |
| 🟡 متوسطة | 7 (موظف) | 2-3h | ⏳ |
| 🟡 متوسطة | 8 (نائب) | 2-3h | ⏳ |
| 🟡 متوسطة | 10 (محامي) | 2-3h | ⏳ |
| 🟡 متوسطة | 11 (معقّب) | 2-3h | ⏳ |
| 🟡 متوسطة | 12 (منفذ) | 2h | ⏳ |
| 🟡 متوسطة | 14 (cron) | 2h | ⏳ |
| 🟡 متوسطة | 17 (UI/UX) | 3-4h | ⏳ |
| 🟢 منخفضة | 16 (أداء) | 2h | ⏳ |

**المجموع:** ~50-60 ساعة عمل

---

## 🎯 خطة التنفيذ المقترحة

### الأسبوع 1 (الأولوية الحرجة)
- **اليوم 1:** المرحلة 0 (تطابق)
- **اليوم 2:** المرحلة 1 (مصادقة)
- **اليوم 3-4:** المرحلة 3 (مستخدم عادي)
- **اليوم 5:** المرحلة 9 (مدير — جزئي)

### الأسبوع 2 (باقي الأولوية الحرجة + متوسطة)
- **اليوم 1:** المرحلة 9 (مدير — باقي)
- **اليوم 2:** المرحلة 13 (تكامل E2E)
- **اليوم 3:** المرحلة 15 (أمان)
- **اليوم 4-5:** المراحل 2, 4, 5 (زائر + وسيط + مصوّر)

### الأسبوع 3 (باقي المتوسط + المنخفض)
- **اليوم 1-2:** المراحل 6, 7, 8 (مشرف + موظف + نائب)
- **اليوم 3:** المراحل 10, 11, 12 (محامي + معقّب + منفذ)
- **اليوم 4:** المرحلة 14 (cron)
- **اليوم 5:** المراحل 16, 17 (أداء + UI/UX)

---

## 📊 مخرجات الاختبار

### ملفات التوثيق
1. `docs/DEVIATION_REPORT_2026_08_05.md` — فرق ريبو ↔ سيرفر
2. `docs/SECURITY_LEAKS.md` — تسريبات أمنية (إن وُجدت)
3. `docs/TEST_RESULTS.md` — نتائج كل سيناريو
4. `docs/BUGS_FOUND.md` — البugs المكتشفة
5. `docs/TEST_COVERAGE_REPORT.md` — نسبة التغطية

### ملفات الإصلاح
1. `supabase/migrations/2026_08_XX_*.sql` — إصلاحات SQL
2. Edge Functions محدّثة (إن لزم)
3. Flutter code fixes

---

## ⚠️ قيود وملاحظات

### ما لا يمكن اختباره عن بُعد
- **Push notifications (FCM):** تحتاج جهاز حقيقي (TECNO KI7)
- **WhatsApp OTP:** يحتاج Meta Business API مُفعّل
- **Email Magic Link:** يحتاج SMTP مُفعّل (Resend)
- **Social publishing:** يحتاج Meta Secrets/IDs

### ما يحتاج المالك
- تشغيل `flutter run` على جهازه
- فحص Push notifications يدوياً
- تنفيذ SQL Editor للـ DDL (إن لزم)
- `supabase db dump` لإقفال الانحراف

### حسابات الاختبار
- **كلمة السر:** `12345678` (كل الحسابات)
- **لا تلمس:** `مستخدم2عادي` / `phototester2` (حسابات المالك)
- **إلغاء الجلسات:** `revoke_all_staff_sessions(uid)` بعد كل جولة

---

## ✅ الخلاصة

هذه الخطة تغطي:
- ✅ **185 دالة SQL** (RPCs + triggers)
- ✅ **33 Edge Function**
- ✅ **23 جدول** (RLS + constraints)
- ✅ **8 cron jobs**
- ✅ **9 أدوار** (19 حساب اختبار)
- ✅ **67 شاشة**
- ✅ **50+ سيناريو E2E**
- ✅ **100+ حالة اختبار**

**الهدف النهائي:** تطبيق جاهز 100% للإطلاق، بلا فجوات، بلا تسريبات، بلا انحراف.

---

**الحالة:** 📋 بانتظار موافقة المالك للبدء  
**التاريخ:** 2026-08-05  
**الإصدار:** 1.0
