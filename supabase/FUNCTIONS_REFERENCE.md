# 📚 مرجع دوال Supabase (RPC + Edge Functions)

> **مشروع:** عقارات السويداء
> **آخر تحديث:** 2026-07-04 (مطابق لتحديثات السيرفر الحي: إغلاق SECURITY DEFINER بالكامل، دعم الأدوار 7/8، إلزام صورتي هوية للموظف، ودوال `get-staff-id-images` و`update-staff-id-images`)
> **المصدر:** `supabase/setup.sql` + Migrations + Edge Functions

---

## 🟢 حالة التفعيل على السيرفر (vsgkgnjtebjxyqwpuopz)

| الحالة | المحتوى |
|---|---|
| ✅ **مُطبّق على السيرفر** | كل دوال `setup.sql` الأصلية (12 دالة) |
| ✅ **مُطبّق على السيرفر** | Migration المصادقة (`2026_06_05_whatsapp_email_auth.sql`) — 4 دوال + عمود `eml` + توسعة `otp_codes` |
| ✅ **مُطبّق على السيرفر** | Migration الإحصائيات والإحالة (`2026_06_05_stats_triggers_and_wkLogin.sql`) — 6 دوال + 4 triggers + عمودي `ref_by`/`ref_cnt` |
| ✅ **مُطبّق على السيرفر** | Migration ترقيات العروض (`2026_06_05_offer_boosts.sql`) — 2 دالة + 8 أعمدة (`i_pin`, `i_bst`, `i_fms`, `pin_end`, `bst_end`, `fms_end`, `dsc_pct`, `dsc_end`) |
| ✅ **مُطبّق على السيرفر** | Migration الجدولة التلقائية (`2026_06_05_cron_jobs.sql`) — extension `pg_cron` مفعّل + 3 cron jobs نشطة |
| ✅ **مُطبّق على السيرفر** | Migration FCM (`2026_06_05_fcm_setup.sql`) — UNIQUE على device_token + `get_user_device_tokens` + `notify_user` |
| ✅ **مُطبّق على السيرفر** | Migration Notification Triggers (`2026_06_06_notification_triggers.sql`) — 7 دوال + 6 triggers + إعداد `app_config.fcm` |
| ✅ **مُطبّق على السيرفر** | Migration Payment Channels Config (`2026_06_06_payment_channels.sql`) — `payChannels` (4 قنوات) داخل `app_config.main` |
| ✅ **مُطبّق على السيرفر** | Migration Payment Channel + Storage (`2026_06_06_payment_channel_and_storage.sql`) — `payments.channel` TEXT + bucket `config_assets` (عام) + bucket `payment_proofs` (خاص + RLS) |
| ✅ **مُطبّق على السيرفر** | Migration Points Refinement (`2026_06_06_points_refinement.sql`) — `user_daily_limits` table + `award_points_safe` RPC + Pin duration (2 days) + Rating bonus trigger |
| ✅ **مُطبّق على السيرفر** | Migration Payment Approval (`2026_06_06_payment_approval_logic.sql`) — `approve_payment_final` RPC (auto-upgrade package + set end date) |
| ✅ **مُطبّق على السيرفر** | إصلاح RLS policy على جدول offers (INSERT) — `auth.uid() = usr_id` (2026-06-09) |
| ⚠️ **مكتوب لكن لم يُنشر بعد** | Edge Functions: `send-whatsapp-otp`, `verify-whatsapp-otp` (يحتاج `supabase functions deploy` + secrets META) |
| ⚠️ **معلّق** | تفعيل Email SMTP (Resend) — تم في Dashboard ✅ بس Meta WhatsApp credentials لسا (يستخدم وضع التطوير) |
| ✅ **مُطبّق على السيرفر** | `2026_06_10_logic_fixes_appointments_offers.sql` — إصلاح منطق المواعيد + pending offers + create_offer_internal |
| ✅ **مُطبّق على السيرفر** | `2026_06_10_logic_fixes_boosts_payments.sql` — إصلاح boosts والمدفوعات |
| ✅ **مُطبّق على السيرفر** | `2026_06_10_config_package_prices_and_fx.sql` — أسعار الباقات وسعر الصرف من Config |
| ✅ **مُطبّق على السيرفر** | `2026_06_10_auth_uid_alignment_guards.sql` — حراسات جزئية تربط uid المرسل بـ `auth.uid()` عند توفر الجلسة |
| ✅ **مُطبّق على السيرفر** | `2026_06_10_users_public_no_private_img.sql` — إزالة `img` من `users_public` |
| ✅ **مُطبّق على السيرفر** | `2026_06_10_verification_dev_auth_rpcs.sql` — RPCs توثيق متوافقة مع وضع التطوير الحالي |
| ✅ **مُطبّق على السيرفر** | `2026_06_11_drop_obsolete_verification_rpcs.sql` — حذف RPCs التوثيق القديمة غير المستخدمة |
| ✅ **مُطبّق على السيرفر** | `2026_06_11_drop_obsolete_unused_rpcs.sql` — حذف RPCs قديمة غير مستخدمة (`admin_update_user_permissions`, `verify_otp_safe`) |
| ✅ **مُطبّق على السيرفر** | `2026_06_11_real_test_stabilization_internal_rpcs.sql` — 40 دالة RPC لتثبيت المسارات الحساسة قبل الاختبار الحقيقي (تم التحقق من وجودها كاملةً بتاريخ 2026-06-11) |
| ✅ **مُطبّق على السيرفر** | تعديلات نظام المواعيد (2026-06-11 Batch 2): `appointments.supervisor_uid` + `appointments.neog` + `offers.added_by` + دالة `get_available_supervisor` + `owner_respond_appointment` + `requester_counter_appointment` + تحديث `book_appointment_internal` بـ 4 فحوصات + تحديث triggers الإشعارات |
| ✅ **مُطبّق على السيرفر** | إدارة الطلبات (2026-06-11 Batch 3): `get_admin_requests_internal` — تتيح للإدارة قراءة كل الطلبات مع بيانات العميل (cl_nm + cl_ph) |
| ✅ **مُطبّق على السيرفر** | إصلاحات نظام الباقات (2026-06-12 Batch 1): تصحيح `purchase_offer_boost` + `create_offer_internal` + `expire_packages()` + `register_daily_streak_internal` |
| ✅ **مُطبّق على السيرفر** | نظام الباقات الاحترافي (2026-06-12 Batch 2): `users.pkg_grace` + `approve_payment_final` مع grace + `create_payment_internal` يمنع دفعة مزدوجة + `expire_packages` مع إشعار + `send_renewal_reminders()` + cron 3:15 UTC |
| ✅ **مُطبّق على السيرفر** | `app_config.pkg.grace_days = 3` — أيام السماح من Config + `approve_payment_final` يقرأها ديناميكياً |
| ✅ **مُطبّق على السيرفر** | `2026_06_12_executor_workflow.sql` — نظام المنفذ الميداني: جدول `completion_requests` + 4 أعمدة في appointments + 7 RPCs |
| ✅ **مُطبّق على السيرفر** | `2026_06_12_roles_final.sql` — إعادة هيكلة الأدوار (7 أدوار) + تحديث حدود 19 RPC + CHECK CONSTRAINT + Config roles + RLS |
| ✅ **مُطبّق على السيرفر** | `2026_06_12_fix_executor_role_checks.sql` — completion RPCs: role >= 4 + إشعار المكتب فقط |
| ✅ **مُطبّق على السيرفر** | `2026_06_12_deep_audit_fixes.sql` — approve_payment role>=5 + create_offer إعفاء role>=4 + 11 RLS policy محدّثة (role>=4/5/6) |
| ✅ **مُطبّق على السيرفر** | `2026_06_12_booking_and_lifecycle_overhaul.sql` — إعادة كتابة book_appointment (10 فحوصات + avl + منفذ + عدد مواعيد) + دورة حياة العرض (sts 5/6 + إلغاء مواعيد) + 5 دوال role محدّثة |
| ✅ **مُطبّق على السيرفر** | `2026_06_12_lifecycle_final_fixes.sql` — expire فقط المنشور + mark_social بدون ts_upd + إرجاع العرض عند رفض الإتمام |
| ✅ **مُطبّق على السيرفر** | `2026_06_13_notifications_text_and_offer_number.sql` — رقم عرض تسلسلي (offer_number + sequence + trigger) + إشعارات "العرض الخاص بك" |
| ✅ **مُطبّق على السيرفر** | `2026_06_13_locations_and_car_docs.sql` — مناطق (السويداء/صلخد/شهبا) + سند سيارة (carDocTp) + نوع نمرة (plateTp) |
| ✅ **مُطبّق على السيرفر** | `2026_06_13_fix_property_doc_types.sql` — حذف نمرة/وارد من سند العقار (فقط للسيارات) |
| ✅ **مُطبّق على السيرفر** | `2026_06_13_fix_notifications_typ_to_tp.sql` — إصلاح notifications.typ → tp في 5 دوال + DROP/CREATE لـ trg_offer_status_changed |
| ✅ **مُطبّق على السيرفر** | `2026_06_15_admin_employee_management_final.sql` — دوال إدارة الموظفين النهائية: `get_all_staff_users`, `admin_create_staff_user`, `admin_update_staff_role`, `admin_toggle_staff_status`, `admin_reset_staff_password`, `admin_delete_staff_user` |
| ✅ **مُطبّق على السيرفر** | `2026_06_15_admin_dashboard_stats.sql` — دالة `get_admin_dashboard_stats` لإحصائيات لوحة الإدارة المجمعة |
| ✅ **مُطبّق على السيرفر** | `2026_06_15_input_validation_hardening.sql` — helpers للتحقق من المدخلات وتقوية RPCs إنشاء العروض/الطلبات/الملف الشخصي/الموظفين، وتم التحقق من دوال `app_*` ومن الحفاظ على منطق `create_offer_internal` |
| ✅ **منشور على السيرفر** | Edge Functions إدارة الموظفين: `create-user` محدثة لإلزام صورتي الهوية، و`get-staff-id-images` للعرض، و`update-staff-id-images` لتحديث صور هوية موظف موجود |
| 🆕 **جاهز للتطبيق** | `2026_06_17_secure_email_auth_internal.sql` — تأمين Email Magic Link عبر RPC `handle_email_auth_internal` + فهارس unique canonical للإيميل والهاتف |
| 🆕 **جاهز للتطبيق** | `2026_06_17_lock_otp_direct_rpcs.sql` — إغلاق direct execute لدوال OTP/upsert عن `anon/authenticated` وجعلها عبر Edge Functions فقط |
| ✅ **مُطبّق على السيرفر** | `2026_06_17_linter_security_hardening.sql` — إصلاح `users_public` كـ `security_invoker`، ضبط `search_path` لكل دوال public، قفل OTP legacy/direct، قفل `admin_create_staff_user` و`admin_wipe_test_data`، قفل دوال النقاط والإشعارات المباشرة، قفل دوال trigger/helper/legacy helper الداخلية، تشديد `otp_codes/user_devices`، وحذف سياسات list العامة لبكتات public |
| ✅ **منشور ومقفول** | Edge Function `admin-offers` — تعمل إدارة العروض عبر `staff_session_token/service_role`، وتم تطبيق `2026_06_17_lock_admin_offer_rpcs.sql` |
| ✅ **منشور ومقفول** | Edge Function `admin-verifications` — تعمل مراجعة التوثيق عبر `staff_session_token/service_role`، وتم تطبيق `2026_06_17_lock_admin_verification_rpcs.sql` |
| ✅ **منشور ومقفول** | Edge Function `admin-payments` — تعمل إدارة المدفوعات عبر `staff_session_token/service_role`، وتم تطبيق `2026_06_17_lock_admin_payment_rpcs.sql` |
| ✅ **مكتمل** | Edge Function `admin-appointments` تم نشرها وقفل RPCs بنجاح |
| ✅ **مكتمل** | Edge Function `admin-reports` — تنقل إدارة التبليغات خلف `staff_session_token/service_role`، وبعد اختبارها يطبق `2026_06_20_lock_admin_reports_rpcs.sql` |
| ✅ **مكتمل** | Edge Function `admin-deals` — تنقل إدارة الصفقات خلف `staff_session_token/service_role`، وبعد اختبارها يطبق `2026_06_20_lock_admin_deals_rpcs.sql` |
| ✅ **مُطبّق على السيرفر** | `2026_06_15_lock_legacy_admin_rpcs.sql` — إغلاق direct execute للدوال الإدارية القديمة الحساسة بعد نقلها إلى Edge Functions |
| ✅ **مُطبّق على السيرفر** | `2026_06_24_offer_images_storage_policies.sql` — bucket `offer_images` + RLS مقفلة (owner OR admin OR service_role)، لا SELECT policy. Edge Function `upload-offer-images` تتجاوز RLS عبر service_role |
| ✅ **مُطبّق على السيرفر** | `2026_06_13_auth_username_password.sql` — اسم مستخدم `usr` + كلمة مرور مشفّرة `pwd` + 6 RPCs (`register_password`, `login_with_password`, `reset_password_with_otp`, `change_password_internal`, `check_username_available`, `get_staff_stats_internal`) + تحديث `users_public` (إضافة `usr`) + تحديث `get_user_full_by_id` (إضافة `usr` + إخفاء `pwd` خلف flag) |
| 🆕 **جاهز للتطبيق (بانتظار تنفيذه على السيرفر + إعادة نشر `user-appointments`)** | `2026_07_02_appointment_booking_rules.sql` — قواعد الحجز الثلاث: (1) دعم `avl.any` عبر دوام `app_config.appt` + رفض `avl` الفارغة بـ `NO_AVAILABILITY` (2) مشرف الأقل حمولة مع فارق الساعة + عند عدم التوفر إشعار الطالب واقتراح بديل عبر `suggest_appointment_slot` (3) قاعدة فارق الساعة `TIME_CONFLICT_ON_OFFER` على العرض والمشرف + دوال جديدة: `appt_booking_config`, `get_booked_slots_internal`, `suggest_appointment_slot` + توحيد `get_available_supervisor` + **تحويلات توقيع تستلزم DROP** (مثبتة بالفحص الحي للسيرفر 2026-07-02): `get_booked_slots_internal` من `TABLE(booked_time text)` إلى `TEXT[]` (النسخة القديمة كانت تكسر تظليل الأوقات في التطبيق + فلترة تاريخ بـ UTC بدل دمشق)، و`owner_respond_appointment`/`requester_counter_appointment` من `BOOLEAN` إلى `JSONB` مع فرض قواعد فارق الساعة والوقت المستقبلي ومعالجة غياب المشرف على مسار التراشق (LOGIC_SPEC §7) |
| 🆕 **جاهز للتطبيق (بانتظار تنفيذه على السيرفر + إعادة نشر `send-sms-otp` و `verify-sms-otp`)** | `2026_07_02_arabic_phone_and_username_support.sql` — دعم الأرقام العربية المشرقية والفارسية (`٠-٩`، `۰-۹`) في أرقام الهواتف عبر `normalize_sy_phone` + دعم أسماء المستخدمين باللغة العربية مع دالة تطبيع موحدة `normalize_arabic_username` (إطاحة التشكيل والكشيدة وتوحيد الألف والتاء المربوطة والياء) ومنع خلط اللغات في الاسم الواحد (Homoglyph prevention) في `app_assert_username` و `check_username_available` و `register_password` و `login_with_password` |
| 🆕 **جاهز للتطبيق (بانتظار تنفيذه على السيرفر)** | `2026_07_02_fix_create_offer_added_by_and_quota.sql` — تصحيح توثيق عمود `added_by` في جدول العروض ليخزن معرف الموظف الإداري المنفذ عند إضافته العرض بالنيابة عن عميل (مع فحص أن المنفذ `role >= 4`)، وإعفاء العمليات الإدارية من فحص حصص النشر (`QUOTA_EXCEEDED`) |
| ✅ **مُطبّق على السيرفر** | `2026_07_02_lock_security_definer_rpcs.sql` — سحب صلاحيات الاستدعاء المباشر عن دوال `SECURITY DEFINER` الأربع (`check_username_available`, `register_password`, `login_with_password`, `create_offer_internal`) وحصرها بـ `service_role` فقط، لحماية قاعدة البيانات وإغلاق تحذيرات Linter الأمان |
| 🆕 **جاهز للتطبيق (بانتظار تنفيذه على السيرفر)** | `2026_07_02_admin_audit_logging_and_rbac_hardening.sql` — توسيع التسجيل الآلي لتصرفات الإدارة في `activity_log` عبر الدالة الموحدة `log_admin_action` (عند اعتماد/رفض العروض، التوثيق، المدفوعات)، وتعديل رتب المراجعة لتبدأ من 4 فما فوق للعروض والتوثيق ومن 5 فما فوق للمدفوعات، وفرض إلزامية سبب الرفض عند الرفض |
| ✅ **مُطبّق على السيرفر** | `2026_07_04_user_account_password_session_fix.sql` — إصدار جلسة كلمة مرور مخصصة لكل الأدوار بعد تسجيل دخول صحيح، مع بقاء الصلاحيات محكومة عبر `validate_staff_session(p_min_role)` |
| ✅ **مُطبّق على السيرفر** | `2026_07_04_legal_rpcs_security_hardening.sql` — قفل دوال القانون/التعقيب عن `anon/authenticated` وحصرها بـ `service_role`، وتشديد أدوار المحامي `7` والمعقب `8` |
| ✅ **مُطبّق على السيرفر** | `2026_07_04_staff_identity_images_required.sql` — إلزام هوية الموظف الوظيفية، تعطيل overload المختصر، ضبط `vrf=2` للحسابات الداخلية، وفرض المسار الكامل للهوية |

---

## 📋 قائمة الدوال (مرجع حي — راجع الأقسام التفصيلية أدناه)

### دوال RPC (PostgreSQL):

| # | اسم الدالة | المدخلات | المخرج | SECURITY DEFINER |
|---|---|---|---|---|
| **— مصادقة (Auth) —** | | | | |
| 1 | `generate_otp` ⚠️ Legacy | `p_phone TEXT` | `TEXT` | ✅ |
| 2 | `verify_otp` ⚠️ Legacy | `p_phone TEXT, p_code TEXT` | `BOOLEAN` | ✅ |
| 3 | `generate_otp_v2` 🆕 | `p_identifier TEXT, p_channel TEXT` | `TEXT` | 🔒 service_role فقط بعد القفل |
| 4 | `verify_otp_v2` 🆕 | `p_identifier TEXT, p_code TEXT` | `BOOLEAN` | 🔒 service_role فقط بعد القفل |
| 5 | `upsert_user_after_otp` 🆕 | `p_identifier TEXT, p_channel TEXT` | `TABLE(user_id UUID, is_new BOOLEAN)` | 🔒 service_role فقط بعد القفل |
| 6 | `get_user_by_email` 🆕 | `p_email TEXT` | `SETOF users` | ✅ — legacy helper |
| 6.1 | `handle_email_auth_internal` 🆕🔒 | لا مدخلات — يعتمد على `auth.uid()` و`auth.jwt()->email` | `JSONB` | 🆕 جاهز للتطبيق |
| 7 | `get_user_by_phone` | `p_phone TEXT` | `SETOF users` | ✅ |
| 8 | `create_user_from_phone` | `p_phone, p_nm` | `UUID` | ✅ |
| **— اسم مستخدم + كلمة مرور (2026-06-13) —** | | | | |
| 9 | `register_password` 🆕 | `p_user_uid UUID, p_username TEXT, p_password TEXT` | `JSONB` | ✅ |
| 10 | `login_with_password` 🆕 | `p_identifier TEXT, p_password TEXT` | `JSONB` | ✅ |
| 11 | `reset_password_with_otp` 🆕 | `p_user_uid UUID, p_new_password TEXT` | `BOOLEAN` | ✅ |
| 12 | `change_password_internal` 🆕 | `p_user_uid UUID, p_old_password TEXT, p_new_password TEXT` | `BOOLEAN` | ✅ |
| 13 | `check_username_available` 🆕 | `p_username TEXT` | `BOOLEAN` | ✅ |
| 14 | `get_staff_stats_internal` 🆕 | `p_user_uid UUID` | `JSONB` | ✅ |
| 80 | `get_all_staff_users` 🆕🆕 | `p_admin_uid UUID` | `SETOF JSONB` | ✅ |
| 81 | `admin_create_staff_user` 🆕 | `p_admin_uid, p_full_name, p_phone, p_email, p_username, p_password, p_role, p_address, p_sid, p_img` | `JSONB` | ✅ |
| 82 | `admin_update_staff_role` 🆕 | `p_admin_uid, p_target_uid, p_role` | `JSONB` | ✅ |
| 83 | `admin_toggle_staff_status` 🆕 | `p_admin_uid, p_target_uid, p_status, p_reason` | `JSONB` | ✅ |
| 84 | `admin_reset_staff_password` 🆕 | `p_admin_uid, p_target_uid, p_new_password` | `JSONB` | ✅ |
| 85 | `admin_delete_staff_user` 🆕 | `p_admin_uid, p_target_uid` | `JSONB` | ✅ |
| 86 | `get_admin_dashboard_stats` 🆕 | `p_admin_uid UUID` | `JSONB` | ✅ |
| 87 | `admin_fraud_suspects` 🛠️ | `p_admin_uid UUID` | `SETOF fraud_suspects` | ✅ |
| 88 | `admin_wipe_test_data` 🆕🔥 | `p_admin_uid UUID` | `JSONB` | ✅ |
| 90 | `get_executor_task_by_appointment` 🆕 | `p_user_uid UUID, p_appointment_id UUID` | `SETOF task row` | 🆕 جاهز للتطبيق |
| 91 | `get_my_completion_requests` 🆕 | `p_user_uid UUID` | `SETOF request rows` | 🆕 جاهز للتطبيق |
| 92 | `get_photographer_tasks_internal` 🆕 | `p_photographer_uid UUID` | `SETOF photography_tasks` | 🆕 جاهز للتطبيق |
| 93 | `start_photography_task_internal` 🆕 | `p_photographer_uid UUID, p_task_id UUID` | `BOOLEAN` | 🆕 جاهز للتطبيق |
| 89 | `app_clean_text` 🆕 | `p_value TEXT, p_max_len INT` | `TEXT` | ❌ |
| 90 | `app_assert_text_len` 🆕 | `p_value TEXT, p_field TEXT, p_min INT, p_max INT` | `TEXT` | ❌ |
| 91 | `app_assert_username` 🆕 | `p_username TEXT, p_required BOOLEAN` | `TEXT` | ❌ |
| 92 | `app_assert_password` 🆕 | `p_password TEXT, p_min INT` | `TEXT` | ❌ |
| 93 | `app_assert_phone` 🆕 | `p_phone TEXT` | `TEXT` | ❌ |
| 94 | `app_assert_price` 🆕 | `p_value NUMERIC, p_required BOOLEAN` | `NUMERIC` | ❌ |
| **— مستخدمون ونقاط —** | | | | |
| 9 | `update_user_badge` | `p_uid UUID` | `VOID` | ❌ |
| 10 | `add_points` | `p_uid, p_pts` | `VOID` | ❌ |
| 10.1 | `award_points_safe` 🆕🔔 | `p_uid, p_event_type, p_points` | `JSONB` | ✅ |
| 11 | `register_weekly_login` 🆕🆕 | `p_uid UUID, p_pts INT=500` | `BOOLEAN` | ✅ |
| 12 | `apply_referral` 🆕🆕 | `p_new_uid UUID, p_referrer_code TEXT, p_pts INT=1500` | `BOOLEAN` | ✅ |
| **— عروض —** | | | | |
| 13 | `check_offer_duplicate` | `ttl, prc, loc, usr_id` | `BOOLEAN` | ✅ |
| 14 | `get_pending_offers_count` | — | `INTEGER` | ❌ |
| 15 | `expire_offers` | — | `VOID` | ❌ |
| **— ترقيات العروض (spd) —** | | | | |
| 16 | `purchase_offer_boost` 🆕🆕🆕 | `p_uid UUID, p_offer_id UUID, p_boost_type TEXT` | `JSONB` | ✅ |
| 17 | `expire_offer_boosts` 🆕🆕🆕 | — | `INTEGER` | ✅ |
| **— إشعارات FCM (E2) —** | | | | |
| 18 | `get_user_device_tokens` 🆕🆕🆕🆕 | `p_uid UUID` | `TABLE(device_token, platform)` | ✅ |
| 19 | `notify_user` 🆕🆕🆕🆕 | `p_uid, p_type, p_title, p_body, p_ref_id?, p_action?` | `UUID` | ✅ |
| **— صفقات ومواعيد —** | | | | |
| 20 | `calculate_commission` | `prc, pct` | `NUMERIC` | ❌ |
| 21 | `send_appointment_reminders` | — | `VOID` | ❌ |
| **— عام —** | | | | |
| 22 | `soft_delete` | `p_table, p_id` | `VOID` | ✅ |
| 23 | `approve_payment_final` 🆕🔔 | `p_payment_id, p_admin_id` | `JSONB` | ✅ |
| **— Triggers Functions (تُستدعى تلقائياً) —** | | | | |
| 24 | `update_user_stats_on_offer` 🆕🆕 | TRIGGER | `TRIGGER` | ✅ |
| 24 | `update_user_stats_on_request` 🆕🆕 | TRIGGER | `TRIGGER` | ✅ |
| 25 | `update_user_stats_on_appointment` 🆕🆕 | TRIGGER | `TRIGGER` | ✅ |
| 26 | `update_user_stats_on_deal` 🆕🆕 | TRIGGER | `TRIGGER` | ✅ |
| **— إشعارات تلقائية (Notification Triggers — E2+) —** | | | | |
| 27 | `send_push_notification` 🆕🔔 | `p_uid, p_title, p_body, p_data?` | `BIGINT` (request_id) | ✅ |
| 28 | `trg_offer_status_changed` 🆕🔔 | TRIGGER على `offers.sts` | `TRIGGER` | ✅ |
| 29 | `trg_appointment_created` 🆕🔔 | TRIGGER INSERT على `appointments` | `TRIGGER` | ✅ |
| 30 | `trg_appointment_status_changed` 🆕🔔 | TRIGGER على `appointments.sts` | `TRIGGER` | ✅ |
| **— نظام المواعيد الجديد —** | | | | |
| 74 | `get_available_supervisor` 🆕 | `p_dt TIMESTAMPTZ` | `UUID` | ✅ |
| 75 | `owner_respond_appointment` 🆕 | `p_owner_uid, p_appointment_id, p_accept, p_reject_reason, p_reject_text, p_proposed_dt` | `JSONB` (2026-07-02، كانت BOOLEAN) | ✅ |
| 76 | `requester_counter_appointment` 🆕 | `p_user_uid, p_appointment_id, p_accept, p_proposed_dt` | `JSONB` (2026-07-02، كانت BOOLEAN) | ✅ |
| **— إدارة الطلبات (2026-06-11 Batch 3) —** | | | | |
| 77 | `get_admin_requests_internal` 🆕 | `p_admin_uid UUID` | `TABLE(id, typ, elm, cl_nm, cl_ph, prc, cur, notes, specs, usr_id, sts, matches, i_del, ts_crt)` | ✅ |
| **— إصلاحات نظام الباقات والـ Streak (2026-06-12) —** | | | | |
| 78 | `expire_packages` 🆕 | — | `INTEGER` | ✅ مُحدَّثة (grace period + إشعار) |
| 79 | `send_renewal_reminders` 🆕 | — | `INTEGER` | ✅ |
| — | `approve_payment_final` | `p_payment_id UUID, p_admin_id UUID` | `JSONB` | ✅ مُحدَّثة (pkg_grace + منع مزدوج) |
| — | `create_payment_internal` | `p_user_uid UUID, p_payment JSONB` | `SETOF payments` | ✅ مُحدَّثة (منع دفعة مزدوجة) |
| — | `register_daily_streak_internal` | `p_user_uid UUID, p_points INT` | `JSONB` | ✅ مُصحَّح |
| — | `purchase_offer_boost` | `p_uid UUID, p_offer_id UUID, p_boost_type TEXT` | `JSONB` | ✅ مُصحَّح |
| — | `create_offer_internal` | `p_user_uid UUID, p_offer JSONB` | `SETOF offers` | ✅ مُصحَّح |
| 31 | `trg_deal_completed` 🆕🔔 | TRIGGER على `deals.sts` | `TRIGGER` | ✅ |
| 32 | `trg_payment_approved` 🆕🔔 | TRIGGER على `payments.sts` | `TRIGGER` | ✅ |
| 33 | `trg_offer_published_match_requests` 🆕🔔 | TRIGGER على `offers.i_pub` (1→0) | `TRIGGER` | ✅ |
| **— دوال القراءة الداخلية (2026-06-11 Batch) —** | | | | |
| 34 | `get_offer_by_id_internal` | `p_offer_id UUID, p_user_uid UUID?` | `SETOF offers` | ✅ |
| 35 | `get_user_offers_internal` | `p_user_uid UUID` | `SETOF offers` | ✅ |
| 36 | `get_user_requests_internal` | `p_user_uid UUID` | `SETOF requests` | ✅ |
| 37 | `get_user_payments_internal` | `p_user_uid UUID` | `SETOF payments` | ✅ |
| 38 | `get_user_notifications_internal` | `p_user_uid UUID` | `SETOF notifications` | ✅ |
| 39 | `get_user_appointments_internal` | `p_user_uid UUID` | `SETOF appointments` | ✅ |
| 40 | `get_owner_appointments_internal` | `p_owner_uid UUID` | `SETOF appointments` | ✅ |
| 41 | `get_broker_offers_internal` | `p_broker_uid UUID` | `SETOF offers` | ✅ |
| 42 | `get_broker_appointments_internal` | `p_broker_uid UUID` | `SETOF appointments` | ✅ |
| 43 | `get_broker_deals_internal` | `p_broker_uid UUID` | `SETOF deals` | ✅ |
| 44 | `get_admin_pending_offers_internal` | `p_admin_uid UUID` | `SETOF offers` | ✅ |
| 45 | `get_admin_offers_internal` | `p_admin_uid UUID, p_limit INT?` | `SETOF offers` | ✅ |
| 46 | `get_admin_appointments_internal` | `p_admin_uid UUID` | `SETOF appointments` | ✅ |
| 47 | `get_admin_deals_internal` | `p_admin_uid UUID` | `SETOF deals` | ✅ |
| 48 | `get_admin_payments_internal` | `p_admin_uid UUID` | `SETOF payments` | ✅ |
| 49 | `get_admin_reports_internal` | `p_admin_uid UUID` | `SETOF reports` | ✅ |
| **— دوال الكتابة الداخلية (2026-06-11 Batch) —** | | | | |
| 50 | `admin_review_offer_internal` | `p_admin_uid UUID, p_offer_id UUID, p_approve BOOLEAN, p_reason TEXT?` | `BOOLEAN` | ✅ |
| 51 | `create_request_internal` | `p_user_uid UUID, p_request JSONB` | `SETOF requests` | ✅ |
| 52 | `update_request_internal` | `p_user_uid UUID, p_request_id UUID, p_patch JSONB` | `BOOLEAN` | ✅ |
| 53 | `soft_delete_request_internal` | `p_user_uid UUID, p_request_id UUID` | `BOOLEAN` | ✅ |
| 54 | `create_payment_internal` | `p_user_uid UUID, p_payment JSONB` | `SETOF payments` | ✅ |
| 55 | `admin_reject_payment_internal` | `p_admin_uid UUID, p_payment_id UUID` | `BOOLEAN` | ✅ |
| 56 | `create_report_internal` | `p_reporter_uid UUID, p_report JSONB` | `SETOF reports` | ✅ |
| 57 | `admin_handle_report_internal` | `p_admin_uid UUID, p_report_id UUID, p_action INT, p_note TEXT?, p_duration INT?` | `BOOLEAN` | ✅ |
| 58 | `book_appointment_internal` | `p_user_uid UUID, p_offer_id UUID, p_dt TIMESTAMPTZ, p_broker_id UUID?, p_request_id UUID?` | `SETOF appointments` | ✅ |
| 59 | `cancel_appointment_internal` | `p_requester_uid UUID, p_appointment_id UUID, p_reason TEXT?` | `BOOLEAN` | ✅ |
| 60 | `broker_handle_appointment_internal` | `p_broker_uid UUID, p_appointment_id UUID, p_action TEXT` | `BOOLEAN` | ✅ |
| 61 | `admin_update_appointment_status_internal` | `p_admin_uid UUID, p_appointment_id UUID, p_status INT, p_admin_note TEXT?` | `BOOLEAN` | ✅ |
| 62 | `admin_force_appointment_internal` | `p_admin_uid UUID, p_appointment_id UUID` | `BOOLEAN` | ✅ |
| 63 | `create_deal_internal` | `p_admin_uid UUID, p_deal JSONB` | `SETOF deals` | ✅ |
| 64 | `complete_deal_internal` | `p_admin_uid UUID, p_deal_id UUID, p_commission NUMERIC?, p_note TEXT?` | `BOOLEAN` | ✅ |
| 65 | `mark_notification_read_internal` | `p_user_uid UUID, p_notification_id UUID` | `BOOLEAN` | ✅ |
| 66 | `mark_all_notifications_read_internal` | `p_user_uid UUID` | `BOOLEAN` | ✅ |
| 67 | `create_rating_internal` | `p_reviewer_uid UUID, p_target_uid UUID, p_stars INT, p_comment TEXT?` | `BOOLEAN` | ✅ |
| 68 | `register_daily_streak_internal` | `p_user_uid UUID, p_points INT?` | `JSONB` | ✅ |
| 69 | `update_user_profile_internal` 🔒 | `p_user_uid UUID, p_payload JSONB` | `BOOLEAN` | 🔒 مقفولة لـ service_role فقط (تم السحب من anon/authenticated) |
| 70 | `update_user_notification_settings_internal` | `p_user_uid UUID, p_ntf JSONB` | `BOOLEAN` | ✅ |
| 71 | `submit_broker_request_internal` | `p_user_uid UUID, p_business_name TEXT, p_category INT, p_experience TEXT?, p_about TEXT?` | `BOOLEAN` | ✅ |
| 72 | `mark_social_published_internal` | `p_user_uid UUID, p_offer_id UUID, p_text TEXT` | `BOOLEAN` | ✅ |
| 73 | `increment_offer_views_internal` | `p_offer_id UUID` | `BOOLEAN` | ✅ |
| **— نظام المواعيد الجديد (2026-06-11 Batch 2) —** | | | | |
| 74 | `get_available_supervisor` | `p_dt TIMESTAMPTZ` | `UUID` | ✅ |
| 75 | `owner_respond_appointment` | `p_owner_uid UUID, p_appointment_id UUID, p_accept BOOLEAN, p_reject_reason INT, p_reject_text TEXT, p_proposed_dt TIMESTAMPTZ` | `JSONB` (2026-07-02، كانت BOOLEAN) | ✅ |
| 76 | `requester_counter_appointment` | `p_user_uid UUID, p_appointment_id UUID, p_accept BOOLEAN, p_proposed_dt TIMESTAMPTZ` | `JSONB` (2026-07-02، كانت BOOLEAN) | ✅ |

### 🔗 Triggers Active على الجداول:

| Trigger | الجدول | الحدث | الدالة |
|---|---|---|---|
| `trg_offers_stats` | `offers` | INSERT/UPDATE/DELETE | `update_user_stats_on_offer` |
| `trg_requests_stats` | `requests` | INSERT/UPDATE/DELETE | `update_user_stats_on_request` |
| `trg_appointments_stats` | `appointments` | INSERT/UPDATE/DELETE | `update_user_stats_on_appointment` |
| `trg_deals_stats` | `deals` | INSERT/UPDATE/DELETE | `update_user_stats_on_deal` |
| `trg_offer_status_notify` 🔔 | `offers` | UPDATE `sts` | `trg_offer_status_changed` |
| `trg_offer_match_notify` 🔔 | `offers` | UPDATE `i_pub` | `trg_offer_published_match_requests` |
| `trg_appointment_notify` 🔔 | `appointments` | INSERT | `trg_appointment_created` |
| `trg_appointment_status_notify` 🔔 | `appointments` | UPDATE `sts` | `trg_appointment_status_changed` |
| `trg_deal_notify` 🔔 | `deals` | INSERT/UPDATE `sts` | `trg_deal_completed` |
| `trg_payment_notify` 🔔 | `payments` | UPDATE `sts` | `trg_payment_approved` |

### ⏰ Cron Jobs (pg_cron) النشطة على السيرفر:

| jobid | jobname | schedule | الوصف |
|---|---|---|---|
| 1 | `daily-expire-offers` | `0 3 * * *` (3:00 UTC يومياً) | يستدعي `expire_offers()` لإنهاء العروض المنتهية |
| 2 | `daily-expire-boosts` | `5 3 * * *` (3:05 UTC يومياً) | يستدعي `expire_offer_boosts()` لإلغاء الترقيات المنتهية |
| 3 | `hourly-appointment-reminders` | `0 * * * *` (بداية كل ساعة) | يستدعي `send_appointment_reminders()` للتذكير قبل المواعيد |
| 4 | `daily-expire-packages` | `10 3 * * *` (3:10 UTC يومياً) | يستدعي `expire_packages()` لإعادة `b_pkg=0` بعد `pkg_grace` |
| 5 | `daily-renewal-reminders` | `15 3 * * *` (3:15 UTC يومياً) | يستدعي `send_renewal_reminders()` لإرسال تذكيرات التجديد |

**التحقق من حالة الجدولة:**
```sql
SELECT jobname, schedule, active FROM cron.job;
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
```

**ملاحظة التوقيت:** السيرفر يستخدم UTC. للتحويل لتوقيت دمشق (UTC+3)، أضف 3 ساعات. مثلاً `0 3 * * *` UTC = 6:00 صباحاً بتوقيت السويداء.

### Edge Functions (Deno):

| # | الاسم | الغرض | المدخل JSON | المخرج JSON | الحالة |
|---|---|---|---|---|---|
| 1 | `send-whatsapp-otp` 🆕 | يولّد OTP ويرسله عبر Meta WhatsApp Cloud API | `{ phone: "+963..." }` | `{ success, messageId?, devMode?, otp? }` | ⚠️ مكتوب — لم يُنشر |
| 2 | `verify-whatsapp-otp` 🆕 | يتحقق + ينشئ user + يصدر session | `{ phone, code }` | `{ success, userId, isNew, session: { token_hash, ... } }` | ⚠️ مكتوب — لم يُنشر |
| 3 | `send-push-notification` 🆕🆕🆕🆕🆕 | يرسل FCM push لكل أجهزة المستخدم (HTTP v1 API) | `{ uid, title, body, data? }` | `{ success, sent, failed, total }` | ⚠️ مكتوب — لم يُنشر |
| 4 | `verify-sms-otp` 🆕 | يتحقق من SMS OTP وينشئ/يجلب المستخدم عبر service_role | `{ phone, code }` | `{ success, userId, isNew, session }` | ✅ منشور |
| 5 | `create-user` 🆕 | إنشاء موظف داخلي من الإدارة عبر `users.usr/pwd` + رفع صورتي الهوية الخاصة عبر `service_role` | `{ admin_uid, staff_session_token?, full_name, phone, email?, username?, role, address, sid, id_images_base64[2] }` | `{ success, user_id, new_password, id_image_paths }` | ✅ منشور — يتطلب صورتين |
| 6 | `get-staff-id-images` 🆕 | إرجاع روابط مؤقتة لصور هوية موظف للمدير/النائب | `{ admin_uid, staff_session_token?, target_uid }` | `{ success, urls, count }` | ✅ منشور |
| 7 | `update-staff-id-images` 🆕 | تحديث صور هوية موظف موجود وتثبيت `vrf=2` | `{ admin_uid, staff_session_token?, target_uid, id_images_base64[2], id_image_content_type? }` | `{ success, user_id, id_image_paths, count }` | ✅ منشور |
| 8 | `update-user-role` 🆕 | تغيير دور موظف داخلي | `{ admin_uid, staff_session_token?, user_id, role }` | `{ success }` | ✅ منشور |
| 9 | `toggle-user-status` 🆕 | تفعيل/تجميد/حظر موظف | `{ admin_uid, staff_session_token?, user_id, status, reason? }` | `{ success }` | ✅ منشور |
| 10 | `reset-user-password` 🆕 | توليد كلمة سر جديدة وتحديث `users.pwd` | `{ admin_uid, staff_session_token?, user_id }` | `{ success, new_password }` | ✅ منشور |
| 11 | `delete-user` 🆕 | حذف منطقي لموظف داخلي | `{ admin_uid, staff_session_token?, user_id }` | `{ success }` | ✅ منشور |
| 12 | `update-user-permissions` 🆕 | تحديث صلاحيات مستخدم عبر جلسة موظف | `{ admin_uid, staff_session_token?, user_id, permissions }` | `{ success }` | ✅ منشور |
| 13 | `upload-offer-images` 🆕🔒 | رفع صور العروض بأمان عبر service_role (يتحقق من staff_session_token أو JWT) | `multipart/form-data: files, user_id, offer_id?, folder?, admin_uid?` | `{ success, urls, count }` | ⚠️ يُنشر **حصراً** بـ `--no-verify-jwt` (راجع بروتوكول النشر بالدستور — بدونه البوابة ترد 401 `UNAUTHORIZED_NO_AUTH_HEADER` قبل الدالة)؛ الرفع عبر `.upload()` القياسية (`uploadBinary` غير موجودة في عميل JS للـ Deno — 2026-07-26) |
| 14 | `legal-actions` ⚖️🔒 | عمليات المحامي والمعقب: ملف المحامي، إرسال مهمة، تحديث checklist، إتمام مهمة، اعتمادها | `{ action, user_uid, staff_session_token?, ... }` | `{ success, ... }` | ✅ منشور — يحتاج إعادة نشر بعد آخر تعديل |
| 15 | `social-accounts` 🆕 (2026-08-27) | إدارة حسابات النشر الاجتماعي (فيسبوك/إنستغرام) مع توكناتها من داخل التطبيق: list / save (بتحقق تلقائي من Meta) / verify / delete | `{ action, admin_uid, staff_session_token?, id?, platform, name, account_external_id, access_token?, is_active? }` | `{ success, accounts? / account?, verified?, verifiedName?, verifyError? }` | ⚠️ مكتوب — يُنشر بعد تنفيذ migration `2026_08_27_social_accounts_management.sql` — دور ≥5، التوكن يعود مقنّعاً (آخر 4 محارف) |

> ⚠️ **`generate_otp` / `verify_otp` القديمة** ما زالت موجودة للتوافق الخلفي فقط — استخدم النسخة V2 في الكود الجديد.
> 📖 لخطوات تفعيل WhatsApp + Email Magic Link: راجع `docs/AUTH_SETUP.md`

---

## 🆕🆕 الدوال الجديدة (المرحلة 10) — مفصّلة

### `register_weekly_login(p_uid UUID, p_pts INT DEFAULT 500)` → `BOOLEAN`

تفحص آخر تسجيل دخول للمستخدم في `users.wk_lgn`. إذا مرّ 7 أيام أو أكثر → تمنحه `pts.wkL` (500 نقطة) وتضيف الوقت الحالي للقائمة. تعيد `TRUE` إذا منحت النقاط، `FALSE` إذا لم يحن الموعد.

```sql
SELECT register_weekly_login('uuid-...', 500);
```

```dart
// Flutter (يُستدعى تلقائياً من AuthProvider.registerStreak)
final granted = await client.rpc('register_weekly_login',
  params: {'p_uid': uid, 'p_pts': 500});
```

**الجداول المتأثرة:** `users` (UPDATE `wk_lgn`, `pt`, `ts_upd`) + استدعاء `update_user_badge`.

---

### `apply_referral(p_new_uid UUID, p_referrer_code TEXT, p_pts INT DEFAULT 1500)` → `BOOLEAN`

عند تسجيل مستخدم جديد بكود إحالة (أول 8 أحرف من uid المحيل):
- يربط `users.ref_by` = uid المحيل
- يزيد `users.ref_cnt` للمحيل
- يمنح كلا الطرفين `pts.ref` (1500 نقطة)
- يُحدّث البادج لكليهما

```dart
final ok = await client.rpc('apply_referral', params: {
  'p_new_uid': newUid,
  'p_referrer_code': 'A1B2C3D4',
  'p_pts': 1500,
});
```

**الحماية:**
- يرفض الإحالة الذاتية (p_referrer_code → uid نفسه)
- يرفض الإحالة المكررة (إذا `ref_by` موجود مسبقاً)

---

### `update_user_stats_on_*` — Triggers تلقائية

دوال داخلية تستدعى تلقائياً عند أي INSERT/UPDATE/DELETE على الجداول التالية:

| Trigger | يحدّث |
|---|---|
| `trg_offers_stats` | `users.stats.off` (عدد عروض المستخدم النشطة) |
| `trg_requests_stats` | `users.stats.req` (عدد طلباته) |
| `trg_appointments_stats` | `users.stats.app` (عدد مواعيده) |
| `trg_deals_stats` | `users.stats.dl` (عدد صفقاته كبائع أو مشتري) |

**لا تستدعى يدوياً** — تعمل في الخلفية.

---

## 🆕🆕🆕 دوال ترقيات العروض (المرحلة C — spd) — مفصّلة

### `purchase_offer_boost(p_uid UUID, p_offer_id UUID, p_boost_type TEXT)` → `JSONB`

شراء ترقية لعرض موجود باستخدام نقاط المستخدم. تتحقق من الملكية + رصيد النقاط، ثم **تحسب الكلفة من `app_config.spd` على السيرفر** وتطبّق الترقية وتخصم النقاط وتسجّل في `activity_log`.

**الأنواع المدعومة (`p_boost_type`):**

| النوع | الوصف | المدة | الكلفة من Config |
|---|---|---|---|
| `'ren'` | تجديد العرض (تمديد ts_end + تنشيط من المنتهي) | 30 يوم إضافية | `spd.ren` (500) |
| `'pin'` | تثبيت في الأعلى (`i_pin=1`) | 7 أيام | `spd.pin` (2000) |
| `'bst'` | Boost — وصول أكبر (`i_bst=1`) | 14 يوم | `spd.bst` (4000) |
| `'dsc5'` | خصم 5% على عمولة المكتب (`dsc_pct=5`) | 60 يوم | `spd.dsc5` (3000) |
| `'fms'` | عرض مميّز Featured (`i_fms=1`) | 30 يوم | `spd.fms` (8000) |

**المخرج (JSONB):**

```json
// نجاح
{ "success": true, "result": { "boost_type": "pin", "duration_days": 7 }, "new_balance": 1500 }

// فشل (أمثلة)
{ "success": false, "error": "INSUFFICIENT_POINTS", "current_points": 500, "required": 2000 }
{ "success": false, "error": "OFFER_NOT_FOUND" }
{ "success": false, "error": "NOT_OWNER" }
{ "success": false, "error": "INVALID_BOOST_TYPE" }
```

```dart
// Flutter يجب أن يمر عبر Edge Function user-offers وليس RPC مباشر.
final res = await Supabase.instance.client.functions.invoke('user-offers', body: {
  'action': 'purchase_boost',
  'user_uid': uid,
  'offer_id': offerId,
  'boost_type': 'pin',
});
final data = res.data as Map;
if (data['success'] == true) {
  // data['new_balance'] يحوي الرصيد الجديد
}
```

**ملاحظات منطقية وأمنية:**
- الكلفة لا تُقبل من العميل؛ السيرفر يحسبها من `app_config.spd`.
- الدالة ممنوعة عن `anon/authenticated` وممنوحة لـ `service_role` فقط؛ التطبيق يصل إليها عبر Edge Function `user-offers`.
- تم حذف أي اعتماد على `offers.ts_upd` لأن العمود غير موجود في جدول `offers`.
- يتم التسجيل في `activity_log` بصيغة الجدول الحالية: `act=20` و`det` نصي.
- إذا كانت `auth.uid()` متاحة، يجب أن تطابق `p_uid`.
- تجديد عرض مرفوض (`sts=3`) مرفوض من السيرفر.

**الجداول المتأثرة:**
- `offers` (UPDATE: حسب نوع الترقية)
- `users` (UPDATE `pt`)
- `activity_log` (INSERT)

---

### `expire_offer_boosts()` → `INTEGER`

تُلغي تلقائياً جميع الترقيات المنتهية (يرجع عدد الـ pins التي أُلغيت). **مخصصة للـ cron jobs اليومية.**

```sql
SELECT expire_offer_boosts();  -- يرجع: 5 (مثلاً)
```

**ما تفعله:**
- `i_pin=0` و `pin_end=NULL` لكل عرض `pin_end < NOW()`
- نفس الشي لـ `i_bst` و `i_fms`
- `dsc_pct=0` و `dsc_end=NULL` للخصومات المنتهية

**استدعاء يدوي (اختياري):**
```dart
final count = await client.rpc('expire_offer_boosts');
```

---

## 🆕🆕🆕🆕🆕 دوال FCM (المرحلة E2) — مفصّلة

### `get_user_device_tokens(p_uid UUID)` → `TABLE(device_token TEXT, platform TEXT)`

تُرجع كل الـ FCM tokens النشطة (`is_active = TRUE`) لمستخدم معيّن.
**تُستخدم من Edge Function `send-push-notification`** لتحديد الأجهزة المرسل إليها.

```sql
SELECT * FROM get_user_device_tokens('uuid-...');
-- النتيجة:
--   device_token                | platform
--   fNT8z...long-fcm-token      | android
--   eX2P...another-token        | ios
```

**الجدول المتأثر:** `user_devices` (SELECT)

---

### `notify_user(p_uid, p_type, p_title, p_body, p_ref_id?, p_action?)` → `UUID`

تُنشئ سجل إشعار في جدول `notifications` (يظهر داخل التطبيق + يُرسَل عبر Realtime).

**الأنواع (`p_type`):**
| القيمة | الوصف |
|---|---|
| 0 | عروض (offers) |
| 1 | طلبات (requests) |
| 2 | مواعيد (appointments) |
| 3 | مالية (finance) |
| 4 | حساب (account) |
| 5 | تقييم (rating) |

```dart
// مثال: إشعار للمستخدم بقبول عرضه
await client.rpc('notify_user', params: {
  'p_uid': ownerUid,
  'p_type': 0,
  'p_title': 'تمت الموافقة على عرضك ✅',
  'p_body': 'عرض "${offer.ttl}" متاح الآن للجمهور',
  'p_ref_id': offer.id,
  'p_action': 'view_offer',
});
```

**الجدول المتأثر:** `notifications` (INSERT)

**ملاحظة:** لإرسال إشعار **داخل التطبيق + Push notification** معاً، استدعِ:
1. `notify_user(...)` لإنشاء السجل الداخلي
2. `send-push-notification` Edge Function لإرسال الـ Push

(لاحقاً نضيف trigger يستدعيها تلقائياً معاً)

---

## 🆕 دوال المصادقة V2 (واتساب + إيميل)

### `generate_otp_v2(p_identifier TEXT, p_channel TEXT)` → `TEXT`

تولّد OTP موحّد لأي قناة (`whatsapp` / `email` / `sms`). تتضمّن **حد معدّل**: 5 طلبات/10 دقائق لنفس identifier.

```sql
SELECT generate_otp_v2('+963999123456', 'whatsapp');
SELECT generate_otp_v2('user@example.com', 'email');
```

```dart
// عادةً لا تُستدعى مباشرة من Flutter — تُستدعى من داخل Edge Function
final code = await client.rpc('generate_otp_v2',
  params: {'p_identifier': '+963$phone', 'p_channel': 'whatsapp'});
```

**الجدول:** `otp_codes` (INSERT) — يكتب `identifier` و `channel`

> ⚠️ **مهم (إصلاح 2026-06-08):** كان عمود `phone` لا يزال `NOT NULL`، مما يفشل INSERT.
> الحل: شغّل migration `2026_06_08_fix_otp_phone_nullable.sql` الذي يجعل `phone` nullable
> ويُضيف CHECK constraint أن `phone OR identifier` على الأقل موجود.
**استثناء:** يرمي `Too many OTP requests` لو تجاوز الحد

---

### `verify_otp_v2(p_identifier TEXT, p_code TEXT)` → `BOOLEAN`

تتحقق من الكود، تعلّمه `used=1`، وتحذف الأكواد القديمة (>1 يوم).

```dart
final ok = await client.rpc('verify_otp_v2',
  params: {'p_identifier': '+963$phone', 'p_code': code});
```

---

### `upsert_user_after_otp(p_identifier TEXT, p_channel TEXT)` → `TABLE(user_id UUID, is_new BOOLEAN)`

تُستخدم بعد تأكيد OTP الواتساب. تبحث عن user بـ `ph` (للواتساب) أو `eml` (للإيميل)، وتنشئه لو غير موجود.

```dart
final rows = await client.rpc('upsert_user_after_otp',
  params: {'p_identifier': '+963$phone', 'p_channel': 'whatsapp'});
final row = (rows as List).first;
print('userId: ${row['user_id']}, isNew: ${row['is_new']}');
```

---

### `get_user_by_email(p_email TEXT)` → `SETOF users`

مقابل `get_user_by_phone` لكن للإيميل (العمود `eml`).

---

## 🔑 دوال اسم المستخدم + كلمة المرور (2026-06-13)

> Migration: `supabase/migrations/2026_06_13_auth_username_password.sql`
> تضيف طبقة دخول ثانية (اسم مستخدم + كلمة مرور) فوق مسار الواتساب OTP.
> الأعمدة الجديدة: `users.usr` (اسم مستخدم فريد، LOWER) + `users.pwd` (هاش bcrypt).

### `register_password(p_user_uid UUID, p_username TEXT, p_password TEXT)` → `JSONB`

تُسجّل اسم مستخدم + كلمة مرور لمستخدم موجود (بعد أول OTP واتساب). تُستدعى من
`setup_profile_screen`. تطبّع اسم المستخدم (LOWER + TRIM) وتشفّر كلمة المرور بـ
bcrypt (`crypt` + `gen_salt('bf', 8)`).

**التحققات (تطلق استثناء عند الفشل):**
| الخطأ | الشرط |
|---|---|
| `USERNAME_LENGTH` | الطول خارج 3–30 |
| `USERNAME_INVALID_CHARS` | أحرف خارج `[a-z0-9_.]` |
| `PASSWORD_TOO_SHORT` | أقصر من 6 |
| `USERNAME_TAKEN` | اسم مستخدم محجوز لمستخدم آخر |
| `USER_NOT_FOUND` | المستخدم غير موجود/محذوف |

```dart
final res = await client.rpc('register_password', params: {
  'p_user_uid': uid,
  'p_username': username,
  'p_password': password,
});
// → { "success": true, "username": "hady" }
```

---

### `login_with_password(p_identifier TEXT, p_password TEXT)` → `JSONB`

تسجيل الدخول باسم مستخدم **أو** رقم هاتف + كلمة مرور. تبحث أولاً بـ `usr`
ثم بـ `normalize_sy_phone(ph)`.

**التحققات:** `USER_NOT_FOUND`, `NO_PASSWORD_SET` (سجّل عبر واتساب أولاً),
`USER_BANNED` (sts=2), `USER_FROZEN` (sts=1), `WRONG_PASSWORD`.

```dart
final res = await client.rpc('login_with_password', params: {
  'p_identifier': 'hady',  // أو '+963938862469'
  'p_password': password,
});
// → { "success": true, "user_id": "...", "role": 0, "nm": "Hady Albnnai" }
```

---

### `reset_password_with_otp(p_user_uid UUID, p_new_password TEXT)` → `BOOLEAN`

تعيين كلمة مرور جديدة بعد التحقق عبر OTP (نسيان كلمة المرور). فحص `PASSWORD_TOO_SHORT`
و `USER_NOT_FOUND`.

---

### `change_password_internal(p_user_uid UUID, p_old_password TEXT, p_new_password TEXT)` → `BOOLEAN`

تغيير كلمة المرور من شاشة الإعدادات (يتطلب كلمة المرور القديمة).
الأخطاء: `NO_PASSWORD_SET`, `WRONG_OLD_PASSWORD`, `PASSWORD_TOO_SHORT`.

---

### `check_username_available(p_username TEXT)` → `BOOLEAN`

فحص لحظي لتوفر اسم المستخدم أثناء الكتابة. تُرجع `FALSE` إذا أقصر من 3 أحرف أو
محجوز. تُستخدم في `setup_profile_screen` للإظهار الفوري (✓ أخضر / ✗ أحمر).

```dart
final ok = await client.rpc('check_username_available',
  params: {'p_username': 'hady'});  // → true / false
```

---


### `handle_email_auth_internal()` → `JSONB`

دالة آمنة لمسار Email Magic Link. لا تستقبل الإيميل من العميل نهائياً، بل تقرأه من Supabase Auth JWT بعد فتح رابط الإيميل.

المخرجات:

```json
{
  "success": true,
  "user_id": "public-users-uuid",
  "is_new": true,
  "email": "user@example.com"
}
```

الحماية:

- ترفض التنفيذ بدون جلسة Supabase Auth حقيقية: `auth.uid() IS NULL`.
- ترفض الإيميل الفارغ أو غير الصالح.
- ترفض pseudo emails مثل `@whatsapp.local`.
- تستخدم advisory lock لمنع إنشاء حسابين لنفس الإيميل بالتوازي.
- تنشئ مستخدم الإيميل الجديد بـ `id = auth.uid()` لتحسين توافق RLS مستقبلاً.
- صلاحية التنفيذ لـ `authenticated` فقط، وليست لـ `anon`.
- تعتمد unique index على `lower(trim(eml))` للحسابات النشطة.

### `get_staff_stats_internal(p_user_uid UUID)` → `JSONB`

إحصائيات مخصّصة لكل موظف حسب دوره (تُعرض في الملف الشخصي). تعتمد على الأدوار
النهائية (`roles_final`):

| الدور | المفاتيح المُرجَعة |
|---|---|
| `2` (مصور) | `completed_tasks`, `pending_tasks`, `submitted_tasks` |
| `3` (مشرف ميداني) | `completed_visits`, `completion_requests`, `active_tasks` |
| `4` (موظف مكتب) | `reviewed_offers`, `managed_appointments`, `processed_completions` |
| `≥5` (نائب/مدير) | `total_deals`, `approved_payments`, `pending_payments`, `verified_users`, `pending_verifications`, `total_users`, `active_offers` |

كل النتائج تضمّ `role` أيضاً. المستخدم العادي (role=0/1) لا يحصل على مفاتيح إضافية
(تُعرض له النقاط/streak من `get_user_full_by_id`).

---

### تغييرات على دوال/عروض موجودة

| العنصر | التغيير |
|---|---|
| `users_public` (VIEW) | أُضيف عمود `usr` (اسم المستخدم). `pwd` لا يُكشف. |
| `get_user_full_by_id` | تحوّلت من `RETURNS SETOF users` إلى `RETURNS TABLE(...)` — أُضيف `usr`، وأُخفي `pwd` خلف flag (`'set'`/`NULL`) بدل تسريب الهاش. تتطلب `DROP FUNCTION` ثم `CREATE` (لا يمكن تغيير نوع الإرجاع عبر `CREATE OR REPLACE`). |

---



## 🔐 Database Linter Security Hardening — 2026-06-17

Migration mirror: `2026_06_17_linter_security_hardening.sql`

تم تنفيذ إصلاحات linter التالية على السيرفر وتوثيقها في migration مرجعية:

| التصنيف | الإجراء | الحالة |
|---|---|---|
| `security_definer_view` | تحويل `public.users_public` إلى `security_invoker=true` | ✅ |
| `function_search_path_mutable` | ضبط `search_path = public, extensions, pg_temp` لكل دوال `public` | ✅ |
| `rls_policy_always_true` على `otp_codes` | حذف سياسة `public` المفتوحة واستبدالها بـ `service_role` فقط | ✅ |
| `rls_policy_always_true` على `user_devices` | استبدال سياسة `USING true / WITH CHECK true` بسياسات own-device أو `service_role` | ✅ |
| `public_bucket_allows_listing` | حذف سياسات SELECT الواسعة من `config_assets` و`offer_images` لمنع listing | ✅ |
| Legacy OTP RPCs | قفل `generate_otp`, `verify_otp`, `create_user_from_phone` عن `anon/authenticated` وتركها لـ `service_role` | ✅ |
| Staff creation RPCs | قفل نسختي `admin_create_staff_user` عن `anon/authenticated`، وتشغيلها عبر Edge Function فقط | ✅ |
| Test wipe RPC | قفل `admin_wipe_test_data` عن `anon/authenticated` | ✅ |



### تحديث مهم — قفل دوال الإشعارات المباشرة

تم قفل الدوال التالية عن `anon` و`authenticated` وتركها لـ `service_role` فقط:

- `notify_user(uuid, integer, text, text, text, text)`
- `send_push_notification(uuid, text, text, jsonb)`

السبب: لا يجوز للعميل إنشاء إشعار أو إرسال push لأي مستخدم مباشرة.
الأثر المتوقع: أي إشعارات كانت تُنشأ من العميل مباشرة قد تتوقف مؤقتاً. الإشعارات المهمة يجب أن تنتقل إلى Triggers أو Edge Functions موثوقة.

### تحديث مهم — قفل دوال النقاط المباشرة

تم قفل الدوال التالية عن `anon` و`authenticated` وتركها لـ `service_role` فقط:

- `add_points(uuid, integer)`
- `award_points_safe(uuid, text, integer)`

السبب: الدالتان تسمحان للعميل بتمرير `uid` وعدد النقاط أو نوع الحدث، وهذا غير آمن حتى مع وجود حدود يومية.
الأثر المتوقع: قد تتوقف مؤقتاً بعض مكافآت النقاط التي كانت تُمنح من التطبيق مباشرة مثل نقاط المشاركة أو بعض الأحداث اليومية، لكن الوظائف الأساسية لا تتأثر.

الحل المعتمد لاحقاً: نقل منح النقاط إلى Edge Functions أو Triggers تتحقق من الحدث فعلياً من السيرفر، ولا تقبل عدد النقاط من العميل.

ملاحظات مهمة:

- حسب فحص السيرفر الحي بتاريخ 2026-07-04: عدد دوال `SECURITY DEFINER` القابلة للتنفيذ من `anon/authenticated` = `0`. كل المسارات الحساسة تمر عبر Edge Functions أو `service_role`.
- سيتم نقل الدوال الحساسة تدريجياً إلى Edge Functions قبل قفلها نهائياً.
- حذف سياسات SELECT العامة من public buckets لا يمنع الوصول عبر public URL، لكنه يمنع listing واسع عبر Storage API.

## 🧭 Executor & Photography Flow Fixes — 2026-06-17

Migration: `2026_06_17_executor_photography_flow_fixes.sql`

أضيفت دوال لتصحيح فلو المنفذ والمصور:

| الدالة | الغرض |
|---|---|
| `get_executor_task_by_appointment` | جلب مهمة منفذ واحدة مباشرة بدل إعادة تحميل قوائم اليوم/المؤجلة داخل شاشة التنفيذ |
| `get_my_completion_requests` | عرض طلبات الإتمام التي أرسلها المنفذ نفسه فقط، بدل استخدام دالة المكتب التي تعرض كل الطلبات |
| `get_photographer_tasks_internal` | جلب مهام المصور عبر RPC آمنة بدل القراءة المباشرة من الجدول |
| `start_photography_task_internal` | تحويل مهمة التصوير من بانتظار/مرفوضة إلى قيد التنفيذ عند ضغط المصور زر بدء المهمة |

ملاحظات منطقية:

- شاشة المنفذ تعرض تبويب `طلبات الإتمام` لحالات طلباته: قيد المراجعة/مقبول/مرفوض.
- شاشة المصور تمنع تكرار المهمة بين `مهام اليوم` و`القادمة`.
- تم استخدام `task.id` كمفتاح UI بدلاً من `hashCode`.

## 🌐 Edge Functions

### `send-whatsapp-otp`

```bash
curl -X POST 'https://<project>.supabase.co/functions/v1/send-whatsapp-otp' \
  -H "apikey: <anon_key>" -H "Content-Type: application/json" \
  -d '{"phone":"+963912345678"}'
```

**Secrets المطلوبة** (Supabase Dashboard → Edge Functions → Secrets):
- `META_WHATSAPP_TOKEN`
- `META_PHONE_NUMBER_ID`
- `META_OTP_TEMPLATE_NAME` (افتراضي: `otp_login`)
- `META_OTP_TEMPLATE_LANG` (افتراضي: `ar`)

**وضع التطوير:** لو ما كانت الـ secrets موجودة، الدالة ترجع `{ devMode: true, otp: "123456" }` بدل إرسال فعلي.

### `verify-whatsapp-otp`

```bash
curl -X POST 'https://<project>.supabase.co/functions/v1/verify-whatsapp-otp' \
  -H "apikey: <anon_key>" -H "Content-Type: application/json" \
  -d '{"phone":"+963912345678","code":"123456"}'
```

ترجع `session.token_hash` يستخدمه Flutter مع `auth.verifyOTP(type: OtpType.magiclink, tokenHash: ...)` لاستلام session.

---


### `verify-sms-otp`

Edge Function جديدة لمسار التحقق من SMS OTP. تمنع العميل من استدعاء `verify_otp_v2` و`upsert_user_after_otp` مباشرة.

المدخل:

```json
{
  "phone": "+9639xxxxxxxx",
  "code": "123456"
}
```

المخرج:

```json
{
  "success": true,
  "userId": "public-user-id",
  "isNew": false,
  "session": {
    "email": "sms_9639xxxxxxxx@whatsapp.local",
    "token_hash": "..."
  }
}
```

بعد نشرها وإغلاق RPCs المباشرة:

- `generate_otp_v2` يعمل عبر `send-sms-otp` و`send-whatsapp-otp` فقط.
- `verify_otp_v2` يعمل عبر `verify-sms-otp` و`verify-whatsapp-otp` فقط.
- `upsert_user_after_otp` يعمل عبر Edge Functions بـ `service_role` فقط.





## 🛡️ Edge Function — `admin-appointments`

تنقل إدارة المواعيد من RPC مباشر إلى Edge Function محمية بجلسة موظف.

Actions المدعومة:

| action | RPC خلفية | الغرض |
|---|---|---|
| `list` | `get_admin_appointments_internal` | جلب كل المواعيد للإدارة |
| `update_status` | `admin_update_appointment_status_internal` | تحديث حالة موعد وملاحظة الإدارة |
| `force` | `admin_force_appointment_internal` | فرض موعد إدارياً |

الحد الأدنى للدور: `role >= 4`.

بعد النشر والاختبار، تُقفل RPCs الخلفية عن `anon/authenticated` وتبقى لـ `service_role` فقط عبر:

```text
2026_06_17_lock_admin_appointment_rpcs.sql
```

## 🛡️ Edge Function — `admin-payments`

تنقل إدارة المدفوعات من RPC مباشر إلى Edge Function محمية بجلسة موظف.

Actions المدعومة:

| action | RPC خلفية | الغرض |
|---|---|---|
| `list` | `get_admin_payments_internal` | جلب المدفوعات للإدارة العليا |
| `signed_proof_url` | Storage بمفتاح الخدمة | توليد رابط مؤقت لإثبات دفعة بعد قراءة المسار من `payment_id` |
| `approve` | `approve_payment_final` | اعتماد دفعة وتفعيل الباقة |
| `reject` | `admin_reject_payment_internal` | رفض دفعة |
| `reverse` | `admin_reverse_payment` | عكس اعتماد دفعة مع إلغاء أثرها |

الحد الأدنى للدور: `role >= 5`.

الحالة الحالية: منشورة ومختبرة، وRPCs الخلفية مقفلة عن `anon/authenticated` وتعمل عبر `service_role` فقط.

Migration المطبق:

```text
2026_06_17_lock_admin_payment_rpcs.sql
```

## 🛡️ Edge Function — `admin-verifications`

تنقل مراجعة توثيق المستخدمين من قراءة مباشرة/RPC مباشر إلى Edge Function محمية بجلسة موظف.

Actions المدعومة:

| action | الغرض |
|---|---|
| `list_pending` | جلب المستخدمين أصحاب `vrf=1` لمراجعة التوثيق |
| `approve` | اعتماد التوثيق عبر `admin_approve_verification_by_admin` |
| `reject` | رفض التوثيق عبر `admin_reject_verification_by_admin` |

الحالة الحالية: منشورة ومختبرة، وRPCs الخلفية مقفلة عن `anon/authenticated` وتعمل عبر `service_role` فقط.

Migration المطبق:

```text
2026_06_17_lock_admin_verification_rpcs.sql
```

## 🛡️ Edge Function — `admin-offers`

تنقل عمليات إدارة العروض الحساسة من RPC مباشر إلى Edge Function تتحقق من جلسة الموظف أولاً.

Actions المدعومة:

| action | RPC خلفية | الغرض |
|---|---|---|
| `list_pending` | `get_admin_pending_offers_internal` | جلب عروض قيد المراجعة |
| `list_media_review` | `get_admin_offers_internal` | جلب عروض لمراجعة الوسائط |
| `review` | `admin_review_offer_internal` | قبول/رفض عرض |
| `set_priority` | `admin_set_offer_priority_internal` | تحديد أولوية العرض |
| `delete` | `admin_delete_offer_internal` | أرشفة عرض إدارياً |

متطلبات الأمان:

- يجب إرسال `admin_uid`.
- يجب وجود Supabase Auth JWT مطابق، أو `staff_session_token` صالح.
- الحالة الحالية: منشورة ومختبرة، وRPCs الخلفية مقفلة عن `anon/authenticated` وتعمل عبر `service_role` فقط.

Migration المطبق:

```text
2026_06_17_lock_admin_offer_rpcs.sql
```

## 🧑‍💼 Edge Functions — إدارة الموظفين

> هذه الدوال لا تنفذ المنطق مباشرة من العميل. كل دالة تتحقق أولاً من جلسة إدارية موثوقة عبر أحد مسارين:
> 1. جلسة Supabase Auth حقيقية تطابق المستخدم الإداري.
> 2. أو `staff_session_token` صالح صادر من `login_with_password` ومتحقق منه عبر `validate_staff_session`.
>
> بعد التحقق تستدعي RPC آمنة بـ `service_role`. معرفة `admin_uid` وحدها غير كافية.

### Secrets المطلوبة

تحتاج الدوال التالية إلى Service Role داخل Supabase Edge Runtime:

- `SUPABASE_URL` أو `PROJECT_URL`
- `SUPABASE_SERVICE_ROLE_KEY` أو `SERVICE_ROLE_KEY`

### 1. `create-user`

ينشئ موظفاً داخلياً في جدول `users`، ويولد كلمة سر جديدة متوافقة مع نظام `users.pwd`. حقول العنوان والرقم الوطني إجبارية، ورفع صورتي الهوية (`id_images_base64`) إلزامي بحد أدنى صورتين داخل bucket خاص `ids_private` عبر `service_role`، ثم يخزن المسارات في `users.img` ويضبط `vrf=2` للتوثيق الوظيفي.

```json
{
  "admin_uid": "uuid-of-manager-or-deputy",
  "staff_session_token": "token-from-login",
  "full_name": "اسم الموظف",
  "phone": "09xxxxxxxx",
  "email": "optional@example.com",
  "username": "office_1",
  "address": "عنوان الموظف",
  "sid": "الرقم الوطني",
  "role": 4,
  "id_images_base64": ["base64-front", "base64-back"],
  "id_image_content_type": "image/jpeg"
}
```

المخرج:

```json
{
  "success": true,
  "user_id": "new-user-uuid",
  "new_password": "generated-password",
  "id_image_paths": ["staff-uid/staff_id_..._1.jpg", "staff-uid/staff_id_..._2.jpg"]
}
```


ملاحظات حماية:

- `id_images_base64` يجب أن يحتوي صورتين على الأقل: وجه وقفا، وإلا يرجع `ID_IMAGES_REQUIRED_MIN_2`.
- `address` و `sid` إجباريان.
- النسخة القديمة المختصرة من `admin_create_staff_user` معطلة برسالة `FULL_IDENTITY_REQUIRED` حتى لا يُنشأ أي حساب داخلي بلا هوية.
- عند فشل رفع/حفظ صور الهوية يتم تعطيل الحساب المنشأ فوراً حتى لا يبقى حساب داخلي نشط بلا صور.
- الأدوار المدعومة داخلياً: `2,3,4,5,7,8` مع حصر إنشاء نائب المدير بالمدير.

### 2. `get-staff-id-images`

يرجع روابط مؤقتة signed URLs لصور هوية موظف داخلي، لاستخدامها في شاشة تفاصيل الموظف.

```json
{
  "admin_uid": "uuid-of-manager-or-deputy",
  "staff_session_token": "token-from-login",
  "target_uid": "staff-user-uuid"
}
```

المخرج:

```json
{
  "success": true,
  "urls": ["signed-url-front", "signed-url-back"],
  "count": 2
}
```

ملاحظات حماية:

- المدير `role=6` يستطيع عرض هويات الموظفين.
- نائب المدير `role=5` يستطيع عرض هويات الموظفين الأدنى منه، ولا يستطيع عرض بيانات نائب/مدير آخر.
- الروابط مؤقتة لمدة 300 ثانية.

### 3. `update-staff-id-images`

يحدّث صور هوية موظف داخلي موجود، ويستخدم عند تصحيح حساب قديم أو استبدال صور الهوية. يحفظ مساري الصورتين في `users.img` كـ JSON Array، ويضبط `vrf=2`.

```json
{
  "admin_uid": "uuid-of-manager-or-deputy",
  "staff_session_token": "token-from-login",
  "target_uid": "staff-user-uuid",
  "id_images_base64": ["base64-front", "base64-back"],
  "id_image_content_type": "image/jpeg"
}
```

المخرج:

```json
{
  "success": true,
  "user_id": "staff-user-uuid",
  "id_image_paths": ["staff-uid/staff_id_..._1.jpg", "staff-uid/staff_id_..._2.jpg"],
  "count": 2
}
```

ملاحظات حماية:

- يتطلب `staff_session_token` صالحاً و `role >= 5`.
- المدير `role=6` يستطيع تحديث الجميع.
- نائب المدير لا يستطيع تحديث صور الإدارة العليا أو الأدوار القانونية الأعلى رقمياً، إلا حسابه نفسه.
- يجب إرسال صورتين على الأقل، وإلا يرجع `ID_IMAGES_REQUIRED_MIN_2`.
- الصور القديمة في `ids_private` تُحذف بعد نجاح حفظ الصور الجديدة.

### 4. `update-user-role`

```json
{
  "admin_uid": "uuid-of-manager-or-deputy",
  "staff_session_token": "token-from-login",
  "user_id": "target-user-uuid",
  "role": 3
}
```

المخرج:

```json
{ "success": true }
```

### 5. `toggle-user-status`

حالات `users.sts`:

| القيمة | المعنى |
|---|---|
| `0` | نشط |
| `1` | مجمد |
| `2` | محظور |

```json
{
  "admin_uid": "uuid-of-manager-or-deputy",
  "staff_session_token": "token-from-login",
  "user_id": "target-user-uuid",
  "status": 1,
  "reason": "سبب اختياري"
}
```

المخرج:

```json
{ "success": true }
```

### 6. `reset-user-password`

يولد كلمة سر جديدة، يحدث `users.pwd` مشفراً، ويرجع كلمة السر الصريحة مرة واحدة فقط.

```json
{
  "admin_uid": "uuid-of-manager-or-deputy",
  "staff_session_token": "token-from-login",
  "user_id": "target-user-uuid"
}
```

المخرج:

```json
{
  "success": true,
  "new_password": "generated-password"
}
```

### 7. `delete-user`

ينفذ حذفاً منطقياً فقط: `users.i_del = 1`.

```json
{
  "admin_uid": "uuid-of-manager-or-deputy",
  "staff_session_token": "token-from-login",
  "user_id": "target-user-uuid"
}
```

المخرج:

```json
{ "success": true }
```

### 8. `update-user-permissions`

يحدّث صلاحيات مستخدم عبر جلسة إدارية صالحة.

```json
{
  "admin_uid": "uuid-of-manager-or-deputy",
  "staff_session_token": "token-from-login",
  "user_id": "target-user-uuid",
  "permissions": ["review_offers", "manage_appointments"]
}
```

المخرج:

```json
{ "success": true }
```

### قواعد حماية مشتركة

- لا يمكن تعديل أو حذف المدير الرئيسي `role=6`.
- نائب المدير لا يستطيع إدارة نائب مدير آخر أو إنشاء نائب مدير.
- كل عملية تسجل في `activity_log`.
- الأدوار المسموحة لإنشاء/تعديل الموظفين حالياً: `2`, `3`, `4`, `5`, `7`, `8` حسب صلاحية المنفذ، مع الانتباه أن `7` محامي و`8` معقب وليسا إدارة رغم أن رقمهما أعلى.

---

---

## 🔐 Staff Sessions — حماية العمليات الإدارية الحساسة

تمت إضافة طبقة جلسات داخلية للموظفين لمنع الاعتماد على `admin_uid` وحده في Edge Functions الإدارية.

### الجداول والدوال

| العنصر | الغرض | الحالة |
|---|---|---|
| `staff_sessions` | تخزين جلسات الموظفين بهاش للتوكن وانتهاء صلاحية | ✅ مطبق على السيرفر |
| `_issue_staff_session` | إصدار توكن بعد تسجيل دخول كلمة مرور لموظف داخلي | ✅ مطبق على السيرفر |
| `validate_staff_session` | التحقق من `staff_session_token` داخل Edge Functions | ✅ مطبق على السيرفر |
| `revoke_staff_session` | إلغاء جلسة حالية عند تسجيل الخروج | ✅ مطبق على السيرفر |
| `revoke_all_staff_sessions` | إلغاء كل جلسات موظف | ✅ مطبق على السيرفر |

### أثرها على Edge Functions

الدوال الإدارية التالية أصبحت تتطلب أحد مسارين للتحقق:

1. جلسة Supabase Auth حقيقية تطابق المستخدم الإداري.
2. أو `staff_session_token` صالح صادر من `login_with_password`.

الدوال المعنية:

- `create-user`
- `get-staff-id-images`
- `update-staff-id-images`
- `update-user-role`
- `toggle-user-status`
- `reset-user-password`
- `delete-user`
- `update-user-permissions`

> تم تطبيق migration على السيرفر والتحقق من إصدار جلسة للمدير. تم أيضاً تطبيق hotfix لمسار `pgcrypto` عبر `search_path = public, extensions`.

## 🧹 Input Validation & Abuse Hardening

تم تطبيق migration:

`2026_06_15_input_validation_hardening.sql`

ويضيف helpers للتحقق والتنظيف على السيرفر، ويقوّي RPCs رئيسية مثل:

- `register_password`
- `admin_create_staff_user`
- `update_user_profile_internal`
- `create_request_internal`
- `update_request_internal`
- `create_offer_internal`

### دوال التحقق المساعدة

| الدالة | الغرض |
|---|---|
| `app_clean_text` | تنظيف النصوص من control characters وتوحيد الفراغات وقص الطول |
| `app_assert_text_len` | تنظيف نص والتحقق من الحد الأدنى/الأقصى ومنع `<` و`>` |
| `app_assert_username` | توحيد وفحص اسم المستخدم `[a-z0-9_.]` بطول 3–30 |
| `app_assert_password` | فرض طول كلمة المرور، حالياً 8 أحرف على الأقل |
| `app_assert_phone` | تطبيع وفحص رقم هاتف سوري بصيغة `+9639xxxxxxxx` |
| `app_assert_price` | رفض السعر غير الموجب أو الكبير جداً |

تم التحقق من عملها على السيرفر، وتم تصحيح منطق الإنتاج في `create_offer_internal` بتاريخ 2026-07-02 لضمان تسجيل معرف الموظف الإداري المنفذ في عمود `added_by` عند إضافته العرض بالنيابة عن عميل عادي، مع إعفاء العمليات الإدارية من حصة العميل (`QUOTA_EXCEEDED`).

---

## 🔐 دوال المصادقة والتحقق (3)

### 1. `generate_otp(p_phone TEXT)` → `TEXT`

تولّد كود OTP عشوائي 6 أرقام وتحفظه في جدول `otp_codes` (ينتهي بعد 5 دقائق).

```sql
-- SQL
SELECT generate_otp('+963999123456');
-- يُرجع: "993744" مثلاً
```

```dart
// Flutter
final otpCode = await client.rpc(
  'generate_otp',
  params: {'p_phone': '+963$phone'},
);
print('🔑 OTP Code: $otpCode');
```

**الجدول المتأثر:** `otp_codes` (INSERT)
**الأمان:** `SECURITY DEFINER` (يتجاوز RLS)

---

### 2. `verify_otp(p_phone TEXT, p_code TEXT)` → `BOOLEAN`

تتحقق من كود OTP: إذا صحيح → تعلّمه كمستخدم (used=1) → تحذفه → ترجع `true`.

```sql
-- SQL
SELECT verify_otp('+963999123456', '993744');
-- يُرجع: true أو false
```

```dart
// Flutter
final isValid = await client.rpc(
  'verify_otp',
  params: {'p_phone': '+963$phone', 'p_code': code},
);
if (isValid) {
  // OTP صحيح — ادخل المستخدم
}
```

**الجدول المتأثر:** `otp_codes` (UPDATE + DELETE)
**الأمان:** `SECURITY DEFINER`

---

### 3. `create_user_from_phone(p_phone TEXT, p_nm TEXT DEFAULT '')` → `UUID`

تبحث عن مستخدم بالهاتف:
- إذا موجود → ترجع الـ ID الخاص فيه
- إذا جديد → تنشئه وتعطيه **1000 نقطة** تسجيل أولي

```sql
-- SQL
SELECT create_user_from_phone('+963999123456', 'أحمد');
-- يُرجع: UUID جديد أو موجود
```

```dart
// Flutter
final userId = await client.rpc(
  'create_user_from_phone',
  params: {'p_phone': '+963$phone', 'p_nm': name},
);
// userId = "a1b2c3d4-..."
```

**الجداول المتأثرة:** `users` (SELECT أو INSERT) + `add_points()` (UPDATE pt, bg, bg_ts)
**الأمان:** `SECURITY DEFINER`

---

## 👤 دوال المستخدمين (2)

### 4. `get_user_by_phone(p_phone TEXT)` → `SETOF users`

تبحث عن مستخدم (أو مستخدمين) بالهاتف — ترجع المستخدم كامل إذا موجود.

```sql
-- SQL
SELECT * FROM get_user_by_phone('+963999123456');
```

```dart
// Flutter
final users = await client.rpc(
  'get_user_by_phone',
  params: {'p_phone': '+963$phone'},
);
// List<Map<String, dynamic>>
```

**الجدول:** `users` (SELECT WHERE ph = ? AND i_del = 0)
**الأمان:** `SECURITY DEFINER`

---

### 5. `update_user_badge(p_uid UUID)` → `VOID`

تحدّث بادج المستخدم تلقائياً حسب النقاط:

| النقاط | البادج |
|---|---|
| < 10,000 | 🔰 جديد (0) |
| >= 10,000 | 🥉 برونزي (1) |
| >= 20,000 | 🥈 فضي (2) |
| >= 30,000 | 🥇 ذهبي (3) |
| >= 40,000 | 💎 ماسي (4) |

```sql
-- SQL
SELECT update_user_badge('a1b2c3d4-...');
-- يحدّث bg و bg_ts في جدول users
```

```dart
// Flutter
await client.rpc('update_user_badge', params: {'p_uid': userId});
```

**الجدول المتأثر:** `users` (UPDATE bg, bg_ts)
**ملاحظة:** عادةً تُستدعى عبر `add_points()` — ما تحتاج استدعاءها مباشرة

---

## 🏠 دوال العروض (3)

### 6. `check_offer_duplicate(p_ttl TEXT, p_prc NUMERIC, p_loc JSONB, p_usr_id UUID)` → `BOOLEAN`

تتحقق إذا في عرض بنفس العنوان والسعر (من مستخدم آخر) — يعني مكرر محتمل.

```sql
-- SQL
SELECT check_offer_duplicate('شقة في المزرعة', 500000000, '{"r":0,"d":"المزرعة"}', 'uuid1');
-- يُرجع: true أو false
```

```dart
// Flutter
final isDup = await client.rpc(
  'check_offer_duplicate',
  params: {
    'p_ttl': title,
    'p_prc': price,
    'p_loc': {'r': region, 'd': location},
    'p_usr_id': currentUserId,
  },
);
if (isDup) {
  // عرض مكرر — حذّر المستخدم
}
```

**الجدول:** `offers` (SELECT WHERE ttl = ? AND prc = ? AND i_del = 0 AND usr_id != ?)
**الأمان:** `SECURITY DEFINER`

---

### 7. `expire_offers()` → `VOID`

تنهي العروض القديمة (أكثر من 30 يوم) تلقائياً — تغير حالتها من `1` أو `2` إلى `4` (منتهي).

```sql
-- SQL
SELECT expire_offers();
-- تُستدعى بـ Scheduled Function كل يوم
```

```dart
// Flutter (يُستدعى يدوياً أو بـ cron)
await client.rpc('expire_offers');
```

**الجدول المتأثر:** `offers` (UPDATE sts=4, ts_end=NOW())
**الشرط:** `sts IN (1, 2) AND i_del = 0 AND ts_crt < NOW() - INTERVAL '30 days'`

---

### 8. `get_pending_offers_count()` → `INTEGER`

ترجع عدد العروض اللي لسه **قيد المراجعة** (sts = 1) — مفيدة للوحة الإدارة.

```sql
-- SQL
SELECT get_pending_offers_count();
-- يُرجع: 15 مثلاً
```

```dart
// Flutter
final count = await client.rpc('get_pending_offers_count');
print('عروض بانتظار المراجعة: $count');
```

**الجدول:** `offers` (COUNT WHERE sts = 1 AND i_del = 0)

---

## 💰 دوال مالية وإدارية (4)

### 9. `calculate_commission(p_prc NUMERIC, p_pct NUMERIC)` → `NUMERIC`

تحسب العمولة: `السعر × النسبة ÷ 100` (مقربة لمنزلتين عشريتين).

```sql
-- SQL
SELECT calculate_commission(500000000, 3);
-- يُرجع: 15000000.00
```

```dart
// Flutter
final commission = await client.rpc(
  'calculate_commission',
  params: {'p_prc': price, 'p_pct': percentage},
);
```

**ملاحظة:** ما بتعدل أي جدول — مجرد حساب رياضي

---

### 10. `add_points(p_uid UUID, p_pts INTEGER)` → `VOID`

تضيف نقاط للمستخدم + تُحدّث البادج تلقائياً.

```sql
-- SQL
SELECT add_points('a1b2c3d4-...', 500);
-- يزيد pt بـ 500 + يحدّث bg و bg_ts
```

```dart
// Flutter
await client.rpc(
  'add_points',
  params: {'p_uid': userId, 'p_pts': points},
);
```

**الجدول المتأثر:** `users` (UPDATE pt + call update_user_badge)

**نقاط المكافآت (من Config):**

| النشاط | النقاط |
|---|---|
| تسجيل أول حساب | +1000 |
| تسجيل دخول أسبوعي | +500 |
| إضافة عرض | +500 |
| حضور موعد | +300 |
| إتمام صفقة | +2000 |
| إحالة صديق | +1500 |
| Streak يومي | +200 |
| مشاركة اجتماعية | +100 |
| لايك | +5 (حد يومي 10) |
| مشاركة | +10 (حد يومي 5) |
| تعليق | +20 (حد يومي 3) |
| هدية نقاط | حتى 500 (مرة بالأسبوع) |

**نقاط الخصم (من Config):**

| السبب | الخصم |
|---|---|
| عدم الحضور | -500 |
| إلغاء 3 مرات | -300 |
| رفض 3 عروض | -1000 |
| تبليغ خاطئ | -2000 |
| حظر نهائي | -40000 |

---

### 11. `soft_delete(p_table TEXT, p_id UUID)` → `VOID`

حذف ناعم — بدل ما تحذف السجل فعلياً، تحط `i_del = 1`.

```sql
-- SQL
SELECT soft_delete('offers', 'a1b2c3d4-...');
-- يحدّث i_del = 1 في الجدول المحدد
```

```dart
// Flutter
await client.rpc(
  'soft_delete',
  params: {'p_table': 'offers', 'p_id': offerId},
);
```

**الأمان:** `SECURITY DEFINER` (يتجاوز RLS)
**ملاحظة:** تقبل اسم أي جدول + الـ ID

---

### 12. `send_appointment_reminders()` → `VOID`

ترسل تذكيرات المواعيد القريبة — تُعلّم `rmnd_2` و `rmnd_24`.

```sql
-- SQL
SELECT send_appointment_reminders();
-- تُستدعى بـ Scheduled Function كل ساعة
```

```dart
// Flutter (يُستدعى بـ cron job)
await client.rpc('send_appointment_reminders');
```

**المنطق:**
- تذكير قبل **ساعتين**: `rmnd_2 = 1` إذا `dt <= NOW() + 2h AND dt > NOW() AND rmnd_2 = 0`
- تذكير قبل **24 ساعة**: `rmnd_24 = 1` إذا `dt <= NOW() + 24h AND dt > NOW() AND rmnd_24 = 0`
- ما بتأثر على المواعيد الملغاة قسرياً (`i_force = 1`)

**الجدول المتأثر:** `appointments` (UPDATE rmnd_2, rmnd_24)

---

## 📊 ملخص الجداول المتأثرة

| الجدول | دوال القراءة | دوال الكتابة | Triggers تلقائية |
|---|---|---|---|
| `users` | `get_user_by_phone`, `get_user_by_email` 🆕 | `create_user_from_phone`, `upsert_user_after_otp` 🆕, `update_user_badge`, `add_points`, `register_weekly_login` 🆕🆕, `apply_referral` 🆕🆕, `purchase_offer_boost` 🆕🆕🆕 (يخصم pt) | — (يُحدَّث `stats` عبر triggers على جداول أخرى) |
| `offers` | `check_offer_duplicate`, `get_pending_offers_count` | `expire_offers`, `purchase_offer_boost` 🆕🆕🆕, `expire_offer_boosts` 🆕🆕🆕 | `trg_offers_stats` 🆕🆕 → `users.stats.off` |
| `activity_log` | — | `purchase_offer_boost` 🆕🆕🆕 (يسجّل كل عملية شراء) | — |
| `user_devices` | `get_user_device_tokens` 🆕🆕🆕🆕 | (يُكتب من Flutter `FCMService.setup()`) | — |
| `notifications` | — | `notify_user` 🆕🆕🆕🆕 (INSERT) | — |
| `requests` | — | — | `trg_requests_stats` 🆕🆕 → `users.stats.req` |
| `appointments` | — | `send_appointment_reminders` | `trg_appointments_stats` 🆕🆕 → `users.stats.app` |
| `deals` | — | — | `trg_deals_stats` 🆕🆕 → `users.stats.dl` |
| `otp_codes` | `verify_otp`, `verify_otp_v2` 🆕 | `generate_otp`, `verify_otp`, `generate_otp_v2` 🆕, `verify_otp_v2` 🆕 | — |

---

## 🔒 ملخص الأمان

| الدالة | SECURITY DEFINER | تتجاوز RLS |
|---|---|---|
| `generate_otp` | ✅ | ✅ |
| `verify_otp` | ✅ | ✅ |
| `generate_otp_v2` 🆕 | ✅ | ✅ |
| `verify_otp_v2` 🆕 | ✅ | ✅ |
| `upsert_user_after_otp` 🆕 | ✅ | ✅ |
| `get_user_by_email` 🆕 | ✅ | ✅ |
| `get_user_by_phone` | ✅ | ✅ |
| `check_offer_duplicate` | ✅ | ✅ |
| `soft_delete` | ✅ | ✅ |
| `create_user_from_phone` | ✅ | ✅ |
| `register_weekly_login` 🆕🆕 | ✅ | ✅ |
| `apply_referral` 🆕🆕 | ✅ | ✅ |
| `purchase_offer_boost` 🆕🆕🆕 | ✅ | ✅ |
| `expire_offer_boosts` 🆕🆕🆕 | ✅ | ✅ |
| `get_user_device_tokens` 🆕🆕🆕🆕 | ✅ | ✅ |
| `notify_user` 🆕🆕🆕🆕 | ✅ | ✅ |
| `update_user_stats_on_offer` 🆕🆕 | ✅ | ✅ |
| `update_user_stats_on_request` 🆕🆕 | ✅ | ✅ |
| `update_user_stats_on_appointment` 🆕🆕 | ✅ | ✅ |
| `update_user_stats_on_deal` 🆕🆕 | ✅ | ✅ |
| `send_push_notification` 🆕🔔 | ✅ | ✅ |
| `trg_offer_status_changed` 🆕🔔 | ✅ | ✅ |
| `trg_appointment_created` 🆕🔔 | ✅ | ✅ |
| `trg_appointment_status_changed` 🆕🔔 | ✅ | ✅ |
| `trg_deal_completed` 🆕🔔 | ✅ | ✅ |
| `trg_payment_approved` 🆕🔔 | ✅ | ✅ |
| `trg_offer_published_match_requests` 🆕🔔 | ✅ | ✅ |
| `calculate_commission` | ❌ | ❌ |
| `update_user_badge` | ❌ | ❌ |
| `get_pending_offers_count` | ❌ | ❌ |
| `add_points` | ❌ | ❌ |
| `expire_offers` | ❌ | ❌ |
| `send_appointment_reminders` | ❌ | ❌ |

---

## 📁 الملفات المرتبطة

| الملف | المحتوى |
|---|---|
| `supabase/setup.sql` | الكود الكامل (مصدر الحقيقة) |
| `supabase/migrations/2026_06_05_whatsapp_email_auth.sql` 🆕 | Migration #1: V2 RPCs + `eml` + `otp_codes` channel — **مطبّق ✅** |
| `supabase/migrations/2026_06_05_stats_triggers_and_wkLogin.sql` 🆕🆕 | Migration #2: 4 triggers + `register_weekly_login` + `apply_referral` + `ref_by`/`ref_cnt` — **مطبّق ✅** |
| `supabase/migrations/2026_06_05_offer_boosts.sql` 🆕🆕🆕 | Migration #3: `purchase_offer_boost` + `expire_offer_boosts` + 8 أعمدة ترقيات — **مطبّق ✅** |
| `supabase/migrations/2026_06_05_cron_jobs.sql` 🆕🆕🆕🆕 | Migration #4: جدولة 3 cron jobs (expire_offers + expire_boosts + reminders) — **مطبّق ✅** |
| `supabase/migrations/2026_06_05_fcm_setup.sql` 🆕🆕🆕🆕🆕 | Migration #5: UNIQUE token + `get_user_device_tokens` + `notify_user` — **مطبّق ✅** |
| `supabase/migrations/2026_06_06_notification_triggers.sql` 🔔 | Migration #6: 7 دوال + 6 triggers لربط الإشعارات بالأحداث — **مطبّق ✅** |
| `supabase/migrations/2026_06_06_payment_channels.sql` 💳 | Migration #7: `payChannels` (4 قنوات) داخل `app_config.main` — **مطبّق ✅** |
| `supabase/migrations/2026_06_06_payment_channel_and_storage.sql` 💳📁 | Migration #8: `payments.channel` TEXT + bucket `config_assets` + bucket `payment_proofs` + RLS — **مطبّق ✅** |
| `supabase/migrations/2026_06_10_logic_fixes_appointments_offers.sql` 🛠️ | إصلاح منطق المواعيد + pending offers + `create_offer_internal` — **مطبّق ✅** |
| `supabase/migrations/2026_06_10_logic_fixes_boosts_payments.sql` 🛠️ | إصلاح `purchase_offer_boost` و `approve_payment_final` — **مطبّق ✅** |
| `supabase/migrations/2026_06_10_config_package_prices_and_fx.sql` 🛠️ | نقل أسعار الباقات وسعر الصرف إلى Config — **مطبّق ✅** |
| `supabase/migrations/2026_06_10_auth_uid_alignment_guards.sql` 🛠️ | حراسات جزئية لربط uid المرسل بـ `auth.uid()` عندما تتوفر الجلسة الحقيقية — **مطبّق ✅** |
| `supabase/migrations/2026_06_10_users_public_no_private_img.sql` 🛠️ | إزالة `img` من `users_public` بعد نقل الهوية إلى bucket خاص — **مطبّق ✅** |
| `supabase/migrations/2026_06_10_verification_dev_auth_rpcs.sql` 🛠️ | RPCs توثيق متوافقة مع وضع التطوير الحالي — **مطبّق ✅** |
| `supabase/migrations/2026_06_11_drop_obsolete_verification_rpcs.sql` 🧹 | حذف RPCs التوثيق القديمة غير المستخدمة — **مطبّق ✅** |
| `supabase/migrations/2026_06_11_drop_obsolete_unused_rpcs.sql` 🧹 | حذف `admin_update_user_permissions` و `verify_otp_safe` بعد التحقق من عدم استخدامهما — **مطبّق ✅** |
| `supabase/migrations/2026_06_11_real_test_stabilization_internal_rpcs.sql` 🛠️ | دفعة RPCs إضافية لتثبيت ما قبل الاختبار الحقيقي — **جاهز للتطبيق** |
| `supabase/migrations/2026_06_24_offer_images_storage_policies.sql` 📁🔒 | إنشاء bucket `offer_images` + RLS policies مقفلة (INSERT owner OR admin (role>=4)، UPDATE owner OR admin (role>=4)، DELETE owner OR admin (role>=4)، لا SELECT policy) — **مطبّق ✅** |
| `supabase/functions/send-push-notification/index.ts` 🆕🆕🆕🆕🆕 | Edge Function لإرسال FCM Push عبر Service Account |
| `lib/services/fcm_service.dart` 🆕🆕🆕🆕🆕 | خدمة FCM Flutter (تهيئة + token + معالجات الإشعارات) |
| `lib/screens/user/boost_offer_screen.dart` 🆕🆕🆕 | شاشة شراء ترقيات العروض (5 خيارات: ren/pin/bst/dsc5/fms) |
| `supabase/functions/send-whatsapp-otp/index.ts` 🆕 | Edge Function لإرسال OTP عبر Meta WhatsApp — **لم يُنشر ⚠️** |
| `supabase/functions/verify-whatsapp-otp/index.ts` 🆕 | Edge Function للتحقق وإصدار session — **لم يُنشر ⚠️** |
| `supabase/functions/upload-offer-images/index.ts` 🆕🔒 | Edge Function لرفع صور العروض بأمان عبر service_role (يتحقق من staff_session_token أو JWT) — **جاهز للنشر ⚠️** |
| `lib/core/constants/db_constants.dart` | أسماء الدوال كـ constants |
| `lib/services/auth_service.dart` | استخدام WhatsApp OTP + Email Magic Link (الـ V2) |
| `lib/screens/auth/login_screen.dart` | شاشة تسجيل الدخول بتبويبتين (واتساب/إيميل) |
| `lib/screens/auth/setup_profile_screen.dart` 🆕🆕 | إكمال الملف + رفع صورة الهوية + الإقرار والتعهد |
| `lib/screens/user/packages_screen.dart` 🆕 | شاشة عرض الباقات (تقرأ `app_config.pkg`) |
| `lib/screens/user/payment_screen.dart` 🆕 | شاشة دفع الاشتراك (تكتب في `payments` بـ `tp=0`) |
| `lib/screens/user/edit_offer_screen.dart` 🆕 | تعديل العرض (تستخدم `OfferProvider.updateOffer`/`softDeleteOffer`) |
| `lib/screens/user/become_broker_screen.dart` 🆕 | طلب وساطة (تحدّث `brk_nm`/`brk_cls` + log في `activity_log`) |
| `lib/screens/user/request_detail_screen.dart` 🆕 | تفاصيل الطلب + `BusinessService.matchOffersForRequest` |
| `lib/screens/user/add_offer_screen.dart` 🆕🆕 | إضافة عرض + Step 4 (سند الملكية + إقرار) |
| `lib/screens/user/referral_screen.dart` 🆕🆕 | شاشة الإحالة + كود + رابط + مشاركة |
| `lib/screens/visitor/offer_detail_screen.dart` 🆕🆕 | تفاصيل العرض + زر التبليغ (`_reportOffer`) |
| `docs/AUTH_SETUP.md` 🆕 | **دليل تفعيل المصادقة الكامل** (Meta + Supabase Email + Deploy) |
| `docs/CURRENT_STATUS.md` | الحالة الحالية المختصرة للمشروع |
| `docs/FEATURES_AUDIT.md` | تدقيق الميزات الحالي بعد إعادة الهيكلة |
| `docs/NEXT_DEVELOPMENT_ITEMS.md` | المهام المتبقية غير المنفذة / المؤجلة |
| `DEVELOPMENT_GUIDELINES.md` | قواعد التطوير الإلزامية |

---

## 🆕 تحديث 2026-06-10 — دوال الإدارة الداخلية والمصور

تمت إضافة دوال RPC جديدة لدعم الإدارة الداخلية، الصلاحيات، وضع المصادقة التطويري، ومنع تكرار الهاتف.

### إدارة الصلاحيات والأدوار

#### `admin_update_user_permissions_by_admin(p_admin_uid UUID, p_target_uid UUID, p_perm JSONB)` → `BOOLEAN`

- النسخة المعتمدة حالياً لإدارة الصلاحيات.
- متوافقة مع وضع التطوير الحالي حيث قد لا تكون `auth.uid()` متاحة.
- تفحص دور `p_admin_uid` من جدول `users`.
- تتطلب `role >= 3`.
- تستخدمها شاشة `/admin/permissions`.
- تم حذف النسخة الأقدم `admin_update_user_permissions` بعد التأكد من عدم استخدامها.

#### `admin_update_user_role(p_admin_uid UUID, p_target_uid UUID, p_role INT)` → `BOOLEAN`

- تغيير دور مستخدم من الإدارة.
- تتطلب `p_admin_uid` بدور نائب/مدير (`role >= 3`).
- تحل مشكلة نجاح وهمي عند التحديث المباشر بسبب RLS/Triggers.

#### `admin_set_user_status(p_admin_uid UUID, p_target_uid UUID, p_status INT, p_reason TEXT)` → `BOOLEAN`

- تغيير حالة المستخدم:
  - `0` نشط
  - `1` مجمّد
  - `2` محظور
- تتطلب `role >= 2` للمستخدم الإداري.

---

### منع تكرار الهاتف

#### `normalize_sy_phone(p_phone TEXT)` → `TEXT`

- توحيد أرقام سوريا لصيغة واحدة.
- أمثلة تتحول إلى نفس الصيغة:
  - `09xxxxxxxx`
  - `9639xxxxxxxx`
  - `009639xxxxxxxx`
  - `+9639xxxxxxxx`
- النتيجة القياسية: `+9639xxxxxxxx`.

#### `ux_users_normalized_phone_active`

- Unique index على:

```sql
normalize_sy_phone(ph)
```

- يمنع إنشاء أكثر من حساب فعال لنفس رقم الهاتف بصيغ مختلفة.

#### `upsert_user_after_otp(p_identifier TEXT, p_channel TEXT)` → `TABLE(user_id UUID, is_new BOOLEAN)`

- تم تحديثها لتستخدم `normalize_sy_phone` عند قناة `whatsapp` أو `sms`.
- مهم لأن وضع التطوير الحالي يعتمد عليها عند تسجيل الدخول.

---

### دوال التوثيق المتوافقة مع وضع التطوير

#### `request_verification_by_uid(p_user_uid UUID)` → `BOOLEAN` 🔒 مقفولة لـ service_role

- تم قفل صلاحياتها على السيرفر الحي حصراً لـ `service_role` (مسحوبة من `anon` و`authenticated` و`PUBLIC`)؛ التطبيق يصل إليها عبر Edge Function `user-account` (`action: request_verification`).

- بديل متوافق مع وضع التطوير الحالي عندما لا تكون `auth.uid()` متاحة.
- ينفذ نفس منطق RPC التوثيق القديم الذي تم الاستغناء عنه (`request_verification`) مع توافق أفضل مع وضع التطوير الحالي:
  - يتحقق من وجود المستخدم.
  - يرفض إذا كان موثقاً أو طلبه قيد المراجعة.
  - يشترط وجود `sid` + `img`.
  - يرفع `vrf` إلى `1`.
- إذا كانت `auth.uid()` متاحة، يجب أن تطابق `p_user_uid`.

#### `admin_approve_verification_by_admin(p_admin_uid UUID, p_target_uid UUID)` → `BOOLEAN`

- اعتماد توثيق مستخدم عبر نسخة متوافقة مع وضع التطوير الحالي.
- تفحص دور `p_admin_uid` من جدول `users` (`role >= 2`).
- إذا كانت `auth.uid()` متاحة، يجب أن تطابق `p_admin_uid`.
- ترسل إشعاراً داخلياً للمستخدم بعد الاعتماد.

#### `admin_reject_verification_by_admin(p_admin_uid UUID, p_target_uid UUID, p_reason TEXT)` → `BOOLEAN`

- رفض توثيق مستخدم مع سبب اختياري.
- تتبع نفس سياسة النسخة السابقة لكن بصيغة متوافقة مع الوضع التطويري الحالي.

---

### إنشاء العرض في وضع التطوير

#### `create_offer_internal(p_user_uid UUID, p_offer JSONB)` → `SETOF offers`

- إنشاء عرض عبر RPC بدل INSERT مباشر.
- يحل مشاكل RLS عندما لا تكون `auth.uid()` متاحة في WhatsApp dev fallback.
- يستخدمها `OfferProvider.addOffer`.
- تتحقق أن المستخدم موجود ونشط (`sts=0`, `i_del=0`).
- تُرجع العرض بحالة `sts=1` (قيد المراجعة) وتمنع النشر المباشر من العميل.
- تفرض على السيرفر: الهاتف الإلزامي، السعر الصالح، الحصة، وكشف التكرار.
- إذا كانت `auth.uid()` متاحة، يجب أن تطابق `p_user_uid`.

---

### مهام التصوير

#### جدول `photography_tasks`

يدير مهام التصوير المستقلة.

الحالات:

| sts | الحالة |
|---:|---|
| 0 | بانتظار المصور |
| 1 | قيد التنفيذ |
| 2 | مرسلة للمكتب |
| 3 | معتمدة |
| 4 | مرفوضة |
| 5 | ملغاة |

#### `create_photography_task_internal(p_admin_uid UUID, p_offer_id UUID, p_photographer_id UUID, p_notes TEXT, p_ts_scheduled TIMESTAMPTZ)` → `SETOF photography_tasks`

- إنشاء مهمة تصوير من الإدارة.
- تفحص أن `p_admin_uid` له `role >= 2`.
- تستخدمها شاشة `/admin/photography-management`.

#### `submit_photography_task_internal(p_photographer_uid UUID, p_task_id UUID, p_media JSONB, p_photographer_note TEXT)` → `BOOLEAN`

- إرسال مهمة التصوير من المصور إلى المكتب.
- تفحص أن المهمة تخص المصور.
- تحدث الحالة إلى `2` مرسلة للمكتب.
- تستخدمها شاشة `/photographer/tasks`.

#### `update_photography_task_status_internal(p_admin_uid UUID, p_task_id UUID, p_status INT, p_office_note TEXT)` → `BOOLEAN`

- تغيير حالة مهمة التصوير من الإدارة.
- تستخدم للرفض أو الإلغاء أو التحديث الإداري.

#### `attach_photography_media_to_offer_internal(p_admin_uid UUID, p_task_id UUID)` → `BOOLEAN`

- تعتمد مهمة التصوير.
- تدمج `photography_tasks.media` داخل `offers.imgs` بدون تكرار.
- تحول المهمة إلى حالة `3` معتمدة.

---

## ملفات migrations المرتبطة — 2026-06-10

| الملف | الغرض |
|---|---|
| `2026_06_10_internal_permissions.sql` | إضافة `users.perm` ودالة الصلاحيات الأساسية |
| `2026_06_10_add_media_review_permission.sql` | إضافة صلاحية `media_review` للدالة |
| `2026_06_10_photography_tasks.sql` | جدول مهام التصوير وصلاحياته الأساسية |
| `2026_06_10_admin_user_role_and_phone_uniqueness.sql` | إصلاح تغيير الأدوار والحالات ومنع تكرار الهاتف |
| `2026_06_10_offer_create_rpc_and_admin_quota.sql` | إنشاء العروض عبر RPC وإعفاء الإدارة من الحصة |
| `2026_06_10_fix_upsert_user_phone_normalization.sql` | تطبيع الهاتف داخل `upsert_user_after_otp` |
| `2026_06_10_photography_dev_auth_rpcs.sql` | دوال مهام التصوير المتوافقة مع وضع التطوير |

---

## 🆕 تغييرات الجداول — 2026-06-11 (نظام المواعيد الجديد)

### أعمدة جديدة في `appointments`

| العمود | النوع | الغرض |
|---|---|---|
| `supervisor_uid` | `UUID REFERENCES users(id)` | المشرف المعيَّن تلقائياً عند الحجز |
| `neog` | `JSONB DEFAULT '[]'` | تاريخ جولات التراشق على الموعد (5 جولات كحد أقصى) |

بنية `neog`:
```json
[
  {"round": 1, "by": "owner", "at": "...", "action": "counter", "proposed": "2026-06-20T10:00:00"},
  {"round": 2, "by": "requester", "at": "...", "action": "counter", "proposed": "2026-06-21T14:00:00"}
]
```

### عمود جديد في `offers`

| العمود | النوع | الغرض |
|---|---|---|
| `added_by` | `UUID REFERENCES users(id)` | uid الموظف/المدير الذي أضاف العرض — للإدارة فقط، لا يظهر للجمهور |

### بنية `avl` المعتمدة (فترات من-إلى)

```json
{
  "wed": ["10:00-13:00", "15:00-17:00"],
  "fri": ["09:00-11:00"]
}
```

---

## منطق نظام الحجز الجديد (2026-06-11) — مُحدَّث 2026-07-02

> ⚠️ النسخة المعتمدة حالياً: `2026_07_02_appointment_booking_rules.sql` — المرجع: `LOGIC_SPEC.md §7`.

### فحوصات `book_appointment_internal` بالترتيب (نسخة 2026-07-02):
1. **فحص `avl`** — الحجز حصراً ضمن أيام/فترات صاحب العرض. `avl` فارغة → `NO_AVAILABILITY`. مفتاح `any` = كل الأيام ضمن دوام `app_config.appt` (`any_from`–`any_to`، افتراضياً 09:00–21:00).
2. **فحص التعارض (قاعدة الساعة)** — لا موعد نشط (sts 0/1) على نفس العرض ضمن أقل من `appt.gap_mins` (60 دقيقة) من الوقت المطلوب → `TIME_CONFLICT_ON_OFFER`.
3. **فحص المشرف** — الأقل مواعيد نشطة، مع استبعاد المشغول ضمن فارق الساعة، وانتقال تلقائي للتالي. لا مشرف متاح → تعيد `{success:false, error:'NO_SUPERVISOR_AVAILABLE', suggested_dt}` + إشعار للطالب (`notify_user`, tp=2) مع اقتراح أقرب موعد عبر `suggest_appointment_slot` (بحث 14 يوماً).
4. **الإنشاء** — ينشأ الموعد بـ `sts=0` مع `supervisor_uid` محجوز مبدئياً

### دوال مساعدة جديدة (2026-07-02):
| الدالة | الوظيفة |
|---|---|
| `appt_booking_config()` | قراءة `app_config.main.appt` مع افتراضيات آمنة |
| `get_booked_slots_internal(p_offer_id UUID, p_date DATE)` | أوقات المواعيد النشطة (HH24:MI بتوقيت دمشق) ليوم محدد — لتظليل الأوقات في الواجهة |
| `suggest_appointment_slot(p_offer_id UUID, p_from TIMESTAMPTZ)` | أقرب موعد متاح فعلياً (avl + لا تعارض + مشرف متاح) خلال 14 يوماً |

### دورة التراشق (`owner_respond_appointment` + `requester_counter_appointment`):
- **5 جولات كحد أقصى** — بعدها يُلغى تلقائياً
- **رفض "الوقت لا يناسب" (reason=0)** → تقويم حر لاقتراح بديل (تُلغى قاعدة avl)
- **رفض "غير مهتم" (reason=1)** → يُحذف العرض soft delete تلقائياً
- **رفض "آخر" (reason=2)** → حقل نص حر + إشعار الإدارة للمراجعة
- **القاعدة الذهبية**: لا تظهر أي معلومة عن طالب الحجز لصاحب العرض أو الوسيط

### تعيين المشرف (`get_available_supervisor`) — موحَّد 2026-07-02:
- يختار مشرف (role=3) ليس لديه موعد نشط (sts 0/1) ضمن فارق `gap_mins` من الوقت المطلوب
- الأولوية: الأقل مواعيداً نشطة → الأقدم تسجيلاً (ts_crt)
- إذا لا يوجد مشرف متاح → `NO_SUPERVISOR_AVAILABLE`
- ⚠️ منطقها الآن مطابق تماماً للكود داخل `book_appointment_internal` (كان بينهما تضارب sts=1 مقابل sts 0/1)

---

## 🆕 إضافة 2026-06-12 — نظام الباقات

### دالة جديدة: `expire_packages()`

```sql
expire_packages() RETURNS INTEGER
```

- تُعيد `b_pkg = 0` لكل مستخدم انتهت باقته (`pkg_end < NOW()`)
- مجدولة يومياً: `10 3 * * *` (3:10 UTC = 6:10 صباحاً بتوقيت دمشق)
- تُرجع عدد المستخدمين الذين طُبّق عليهم التغيير

### تصحيح `purchase_offer_boost`

- `activity_log` كانت تستخدم `action(TEXT)` و`details(JSONB)` ← خطأ
- الآن تستخدم `act=20` (INT) و`det=text` ← صحيح

---

## 🆕 تغييرات الجداول — 2026-06-12 (نظام الباقات الاحترافي)

### عمود جديد في `users`

| العمود | النوع | الغرض |
|---|---|---|
| `pkg_grace` | `TIMESTAMPTZ` | نهاية فترة السماح = `pkg_end + 3 أيام` — محمي بـ `check_user_safe_update` trigger |

### منطق Grace Period

```
pkg_end > NOW()           → باقة نشطة         → effectivePkg = b_pkg
pkg_grace > NOW() > pkg_end → فترة سماح (3 أيام) → effectivePkg = b_pkg (نفس المزايا)
NOW() > pkg_grace          → expire_packages     → b_pkg = 0
```

### Getters الجديدة في `UserModel`

| Getter | المعنى |
|---|---|
| `effectivePkg` | الباقة الفعلية مع مراعاة grace period |
| `isPkgActive` | هل pkg_end > NOW() |
| `isInGracePeriod` | هل pkg_end < NOW() < pkg_grace |
| `graceDaysLeft` | أيام السماح المتبقية |

### Getter جديد في `ConfigModel`

| Getter | المعنى | القيمة الافتراضية |
|---|---|---|
| `pkgGraceDays` | عدد أيام السماح من `pkg.grace_days` | 3 أيام |

### شاشة جديدة: `/user/my-payments`

- سجل دفعات المستخدم (معلقة / مقبولة / مرفوضة)
- زر "محاولة مجدداً" للدفعات المرفوضة
- رابط من شاشة الباقات والملف الشخصي

---

## 🆕 تحسينات تجربة الزائر — 2026-06-12

### تحديث `searchOffers` في `OfferProvider`

أُضيفت معاملات جديدة:

| المعامل | النوع | الوصف |
|---|---|---|
| `minPrice` | `double?` | الحد الأدنى للسعر |
| `maxPrice` | `double?` | الحد الأقصى للسعر |
| `currency` | `int?` | العملة (0=دولار، 1=ل.س) |

### تحسينات الشاشات

| الشاشة | التحسين |
|---|---|
| `offer_detail_screen` | Slider الصور + dots + عداد + السعر مع تنسيق + loc['city'] + specs + زر حجز ذكي |
| `offer_card` | شارة نوع المعاملة (بيع/إيجار) |
| `book_appointment_sheet` | فحص تسجيل الدخول — الزائر يرى شاشة دخول |
| `home_screen` | Shimmer + عداد النتائج + رسالة "لا نتائج" ذكية |
| `search_screen` | فلتر السعر (من/إلى) + اختيار العملة |

## 🛡️ Edge Function — `admin-reports`
**الحالة:** جاهزة للنشر والقفل
**الأذونات:** `service_role` للـ Supabase client، ويتطلب `staff_session_token` صالح من العميل بصلاحية `>= 3`.

**الغرض:**
نقل عمليات إدارة التبليغات التي يقوم بها الإداريون إلى بيئة آمنة لا تعتمد على الـ RPC المباشر المفتوح.

**Actions المدعومة:**
1. `list` — استدعاء `get_admin_reports_internal` لجلب التبليغات.
2. `handle` — استدعاء `admin_handle_report_internal` لمعالجة تبليغ (تحذير، تجميد، حظر).

## 🛡️ Edge Function — `admin-deals`
**الحالة:** جاهزة للنشر والقفل
**الأذونات:** `service_role` للـ Supabase client، ويتطلب `staff_session_token` صالح من العميل بصلاحية `>= 3`.

**الغرض:**
نقل عمليات إدارة الصفقات التي يقوم بها الإداريون إلى بيئة آمنة لا تعتمد على الـ RPC المباشر المفتوح.

**Actions المدعومة:**
1. `list` — استدعاء `get_admin_deals_internal` لجلب الصفقات.
2. `create` — استدعاء `create_deal_internal` لإنشاء صفقة جديدة.
3. `complete` — استدعاء `complete_deal_internal` لإتمام الصفقة وإضافة العمولة.

## 🛡️ Edge Functions للمهام والتصوير
**الحالة:** جاهزة للنشر والقفل
**الأذونات:** `service_role` للـ Supabase client، ويتطلب `staff_session_token` صالح من العميل.

1. **`executor-tasks`**: تدير مهام المنفذ، تتطلب صلاحية `>= 2` (منفذ أو أعلى).
2. **`photographer-tasks`**: تدير مهام المصور، تتطلب صلاحية `>= 2` (مصور أو أعلى).
3. **`admin-photography`**: تدير مهام التصوير من طرف الإدارة، تتطلب صلاحية `>= 3` (مكتب أو أعلى).

## 🛡️ Edge Function — `upload-offer-images`
**الحالة:** ✅ منشور — يحتاج إعادة نشر (`supabase functions deploy upload-offer-images`) بعد آخر تعديل (استخدام `upload()` بدلاً من `uploadBinary()`)
**الأذونات:** `service_role` للـ Supabase client (داخل السيرفر)، ويتطلب `staff_session_token` (من x-staff-session-token header) أو JWT auth.
**الغرض:** رفع صور العروض بأمان بدون الاعتماد على `auth.uid()` في RLS (لأن التطبيق يستخدم custom auth).
**المدخلات (multipart/form-data):**
- `files` — ملفات الصور (متعددة)
- `user_id` — مجلد المستخدم (uid)
- `offer_id` — مجلد العرض (default: draft)
- `folder` — offers | images | videos (default: offers)
- `admin_uid` — مطلوب مع `staff_session_token` للموظفين
**العملية:**
1. إذا وجد `x-staff-session-token` → تتحقق من `validate_staff_session(admin_uid, token)`.
2. وإلا → تتحقق من JWT auth.
3. ترفع بـ `service_role` داخل `offer_images` bucket.
4. تُرجع `public URLs`.

**الملاحظة:** `upload-offer-images` تستخدم `upload()` (Supabase JS v2) وليس `uploadBinary()`.

---

## 🛡️ Edge Function — `user-offers`
**الحالة:** ✅ مكتمل (تم تشديد الأمن وإطاحة الـ Fallback في 2026-07-02 لفرض مطابقة توكن JWT مع الـ `user_uid`).
**الأذونات:** `service_role` للـ Supabase client، وتتحقق من `JWT Token` الخاص بالمستخدم العادي، باستثناء دالة زيادة المشاهدات التي يمكن استدعاؤها من الزوار.

## 🛡️ Edge Function — `user-requests`
**الحالة:** ✅ مكتمل (تم إطاحة الـ Fallback الانتحالي في 2026-07-02، وتم تحديث المزود والواجهة لمرير وترجمة استثناءات التحقق الصارمة كـ `PHONE_INVALID` و`QUOTA_EXCEEDED` مع تطبيع الأرقام العربية).
**الأذونات:** `service_role` للـ Supabase client، وتتحقق من `JWT Token` الخاص بالمستخدم العادي، وتضمن أن الـ `user_uid` المطلوب مطابق لصاحب الجلسة.

## 🛡️ Edge Function — `user-appointments`
**الحالة:** ✅ مكتمل (تم إطاحة الـ Fallback الانتحالي).
**الأذونات:** `service_role` للـ Supabase client، وتتحقق من `JWT Token`، وتضمن أن الـ `user_uid` المطلوب مطابق لصاحب الجلسة (سواء كان المستخدم كطالب للموعد، أو مالكاً، أو وسيطاً).

## 🛡️ Edge Function — `user-notifications`
**الحالة:** ✅ مكتمل (تم إطاحة الـ Fallback الانتحالي).
**الأذونات:** `service_role` للـ Supabase client، وتتحقق من `JWT Token` وتضمن المطابقة.

## 🛡️ Edge Function — `user-account`
**الحالة:** ✅ مكتمل (تمت معالجة التوافق Adaptive Handling لردود الـ JSONB والـ BOOLEAN وتوحيد أسماء بارامترات الـ payload ونقل إنشاء المدفوعات `create_payment` عبر Edge Function لمنع الدفعة المزدوجة في دوال إعداد كلمة المرور وتغييرها وتحديث الملف الشخصي ومنح النقاط وإبطال جلسة الموظف).
**الأذونات:** `service_role` للـ Supabase client، تدعم دوال لا تتطلب توثيق كالتسجيل، وتدعم دوال تتطلب `JWT Token` ومطابقة الـ UID لحماية الملف الشخصي.

## 🛡️ Edge Function — `user-rewards` 🆕
**الحالة:** ✅ مكتمل (تم إضافة دالة `validateUser` وتشديد الأمن في 2026-07-02 لمنع استدعاء مكافآت التقييم والستريك والإحالات بدون توكن مصادقة مطابق).
**الأذونات:** يتطلب `JWT Token` صالح ومطابق للـ `user_uid`.
**الغرض:** إدارة المكافآت والنقاط اليومية والإحالات ومكافآت التقييم 5 نجوم.

## 🛡️ Edge Function — `admin-dashboard`
**الحالة:** ✅ مكتمل
**الأذونات:** يتطلب `staff_session_token` صالح من العميل.
**الغرض:** جلب إحصائيات الإدارة وإحصائيات الموظف وقائمة المشتبه بهم بالاحتيال وإبطال جلسة الموظف.

## 🛡️ Edge Function — `broker-actions`
**الحالة:** ✅ مكتمل
**الأذونات:** يتحقق من `JWT Token`.
**الغرض:** تسجيل طلبات المستخدمين ليصبحوا وسطاء عقاريين.

---

## 🔒 المخطط الداخلي والمشغلات (Internal Schema & Triggers) - تحديث نهائي

| اسم الكائن | النوع | الوصف |
| --- | --- | --- |
| internal | SCHEMA | مخطط داخلي آمن لعزل الدوال الحساسة عن الـ REST API. |
| internal.notify_admin_on_new_offer | FUNCTION | ترسل إشعارات فورية للإدارة (Role 4, 5, 6) عند إضافة أي عرض جديد. |
| trg_notify_new_offer | TRIGGER | مشغل على جدول العروض يضمن عمل الإشعارات آلياً من السيرفر. |
| offer_number_seq | SEQUENCE | التسلسل المسؤول عن توليد أرقام العروض التسلسلية (1, 2, 3...). |

## 🛡️ تحديثات الصلاحيات (Roles Update)
- تم توحيد عمود "role" مع "rl" في جدول المستخدمين لضمان الانسجام.
- الرتبة **6** تمثل المدير العام وهي الرتبة الأعلى في النظام.
- الرتبة **7** تمثل المحامي المعتمد للاستشارات وتدقيق العقود.
- الرتبة **8** تمثل معقب المعاملات الميداني.
- ميزات معاينة السندات مرتبطة برتبة **4 فما فوق**.

---

## ⚖️ دوال وجداول القسم القانوني وتعقيب المعاملات (Phase 1)

| اسم الكائن | النوع | الوصف |
| --- | --- | --- |
| `lawyer_profiles` | TABLE | جدول ملفات المحامين (أرقام الواتساب، التخصص، وجدول مواعيد الدوام `avl`). |
| `expediting_tasks` | TABLE | جدول مهام استخراج الثبوتيات المحالة من المحامي للمعقب مع قوائم التدقيق التفاعلية. |
| `admin_upsert_lawyer_profile` | RPC | إضافة أو تحديث ملف المحامي وضبط أوقاته المتاحة (Role >= 5). |
| `get_active_lawyers` | RPC | جلب قائمة المحامين المتاحين ومواعيدهم وحملهم التشغيلي التراكمي. |
| `create_expediting_task_internal` | RPC | إنشاء مهمة تعقيب من محامٍ `role=7` إلى معقب نشط `role=8` مع إشعار المعقب. |
| `update_expediting_checklist_item` | RPC | تحديث حالة وقيمة أي بند في قائمة تدقيق المعقب (إدخال أرقام السيارات والعقارات ورفع الروابط)، وتحويل المهمة إلى قيد الاستخراج عند بدء العمل. |
| `complete_expediting_task_internal` | RPC | تأكيد المعقب أنه أتم كل البنود بنجاح؛ يشترط كل checklist status=2، يضبط `status=2`, `completed_at`, ويشعر المحامي. |
| `approve_expediting_task_internal` | RPC | اعتماد المحامي لإنجاز المعقب؛ يضبط `status=3` ويشعر المعقب. |

---

## ⚖️ Edge Function — `legal-actions` (تحديث 2026-07-04)

**الحالة:** ✅ منشورة، وتحتاج إعادة نشر بعد إضافة إتمام/اعتماد مهمة التعقيب.
**الأذونات:** تتحقق من JWT إن وجد، أو `staff_session_token` عبر `validate_staff_session(p_min_role=0)`، ثم تفحص الدور صراحة:

- المحامي: `role=7`
- المعقب: `role=8`
- الإدارة العليا: `role IN (5,6)` فقط لإدارة ملف المحامي

### Actions المعتمدة

| Action | من يستطيع | الوصف |
|---|---|---|
| `get_lawyer_profile` | محامي | جلب ملف المحامي ورقم الواتساب والاختصاص. |
| `admin_upsert_lawyer` | محامي لنفسه أو مدير/نائب | إعداد/تحديث ملف المحامي بدون تغيير الدور. |
| `get_available_expediters` | محامي أو مدير/نائب | جلب المعقبين النشطين. |
| `create_expediting_task` | محامي | إرسال مهمة تعقيب إلى معقب نشط، وتوليد إشعار للمعقب. |
| `get_lawyer_expediting_tasks` | محامي | قائمة المهام التي أرسلها المحامي. |
| `get_lawyer_appointments` | محامي | مواعيد المحامي. |
| `get_my_expediting_tasks` | معقب | قائمة مهام المعقب المستلمة. |
| `upload_consultation_attachment` | مستخدم مسجّل | رفع صورة مستند إلى `consultation_files` بمسار مبني خادمياً من UID. |
| `discard_consultation_attachments` | صاحب الملفات | تنظيف الرفع غير المكتمل فقط؛ الملفات المرتبطة باستشارة لا تُحذف. |
| `book_consultation` | مستخدم مسجّل | إنشاء طلب الاستشارة وربط المستندات المرفوعة والدفعة المقبولة. |
| `get_consultation_files` | صاحب الاستشارة أو المحامي المسند أو الإدارة | توليد روابط مؤقتة لمستندات الاستشارة الخاصة قبل القبول وبعده. |
| `update_checklist_item` | المحامي أو المعقب صاحب المهمة | تحديث بند من checklist. |
| `complete_expediting_task` | المعقب صاحب المهمة | تأكيد أن المهمة اكتملت بعد اكتمال كل البنود، وإشعار المحامي. |
| `approve_expediting_task` | المحامي صاحب المهمة | اعتماد إنجاز المعقب، وإشعار المعقب. |

### دورة الحالة في `expediting_tasks.status`

| القيمة | المعنى |
|---|---|
| `0` | بانتظار المعقب |
| `1` | قيد الاستخراج / بدأ العمل على checklist |
| `2` | مكتملة من المعقب وبانتظار اعتماد المحامي |
| `3` | معتمدة من المحامي |

### كيف يؤكد المعقب الإنجاز؟

1. يدخل المعقب إلى تفاصيل المهمة.
2. يعلّم كل بنود checklist كـ `تم الاستخراج والرفع` (`status=2`).
3. يظهر زر **إتمام المهمة وإشعار المحامي**.
4. عند الضغط يستدعي التطبيق:

```json
{
  "action": "complete_expediting_task",
  "task_id": "task-uuid",
  "expediter_notes": "ملاحظات ختامية اختيارية"
}
```

السيرفر يرفض الإتمام إن بقي أي بند غير مكتمل ويرجع:

```json
{ "success": false, "error": "CHECKLIST_NOT_COMPLETE", "incomplete_count": 3 }
```

### كيف يشعر المحامي؟

عند نجاح `complete_expediting_task_internal` يتم إدراج إشعار:

```text
ttl = مهمة تعقيب مكتملة
act = expediting_task_completed
ref_id = task_id
```

وتتحول المهمة في تبويب **المهام المرسلة** إلى حالة:

```text
مكتملة — بانتظار اعتمادك
```

ثم يضغط المحامي زر **اعتماد إنجاز المعقب وإشعاره** لاستدعاء:

```json
{
  "action": "approve_expediting_task",
  "task_id": "task-uuid"
}
```

بعد الاعتماد يتم إشعار المعقب:

```text
ttl = تم اعتماد مهمة التعقيب
act = expediting_task_approved
ref_id = task_id
```

---

## 🔒 فحص أمان السيرفر الحي — 2026-07-05

نتائج الفحص المباشر على قاعدة الإنتاج:

| الفحص | النتيجة |
|---|---|
| دوال `SECURITY DEFINER` المفتوحة لـ `anon/authenticated` | `0` ✅ |
| جداول public بدون RLS | `0` ✅ |
| جداول RLS Enabled No Policy | `0` ✅ |
| `users_role_check` | `role >= 0 AND role <= 8` ✅ |
| `users_public` | `security_invoker=true` ✅ |
| `ids_private` | private bucket ✅ |
| `payment_proofs` | private bucket ✅ |

تم تطبيق:

```text
supabase/migrations/2026_07_05_rls_service_role_policy_cleanup.sql
```

السياسات المضافة موجهة إلى `service_role` فقط للجداول الداخلية:

- `staff_sessions_service_role_all`
- `stats_service_role_all`
- `user_daily_limits_service_role_all`

اختبارات الرفض بدون جلسة:

| المسار | النتيجة المتوقعة والمحققة |
|---|---|
| `create-user` بدون `staff_session_token` | `ADMIN_SESSION_REQUIRED` |
| `update-staff-id-images` بدون `staff_session_token` | `ADMIN_SESSION_REQUIRED` |
| `legal-actions` بدون جلسة | `AUTH_TOKEN_REQUIRED` |
| `user-account` بدون جلسة | `AUTH_TOKEN_REQUIRED` |
| `admin-dashboard` بدون جلسة | `STAFF_SESSION_REQUIRED` |
| RPC مباشر إلى `complete_expediting_task_internal` عبر anon | `permission denied` |
| RPC مباشر إلى `approve_expediting_task_internal` عبر anon | `permission denied` |
| RPC مباشر إلى `create_expediting_task_internal` عبر anon | `permission denied` |

---

## ⚖️ تحديث تعقيب المعاملات — صور الوثائق ومراجعة المحامي 2026-07-05

تمت إضافة bucket خاص:

```text
expediting_docs
```

الغرض منه حفظ صور السندات/الوثائق التي يرفعها المعقب. لا تُخزن روابط عامة داخل قاعدة البيانات، بل مسارات خاصة يتم تحويلها إلى signed URLs مؤقتة عند جلب المهام عبر `legal-actions`.

### حقول checklist الموسعة

كل بند في checklist قد يحتوي:

```json
{
  "key": "doc_key",
  "title": "اسم الوثيقة",
  "status": 0,
  "required_copies": 2,
  "lawyer_instructions": "تعليمات المحامي",
  "input_value": "بيانات المعقب",
  "notes": "ملاحظات المعقب",
  "attachment_url": "private/storage/path.jpg",
  "attachment_signed_url": "temporary-signed-url",
  "revision_notes": "سبب إعادة المحامي للوثيقة"
}
```

### Action: `update_checklist_item`

يدعم الآن رفع صورة مباشرة:

```json
{
  "action": "update_checklist_item",
  "task_id": "uuid",
  "item_key": "extract",
  "status": 2,
  "input_value": "رقم الصحيفة",
  "attachment_base64": "base64-image",
  "attachment_content_type": "image/jpeg",
  "notes": "تم الاستخراج"
}
```

### Action: `request_checklist_revision`

يستخدمه المحامي عند مراجعة مهمة مكتملة من المعقب ووجود سند غير صحيح:

```json
{
  "action": "request_checklist_revision",
  "task_id": "uuid",
  "item_key": "extract",
  "revision_notes": "الصورة غير واضحة، أعد رفع نسخة مصدقة"
}
```

الأثر:

- يتحول بند الوثيقة إلى `status=1`.
- تتحول المهمة إلى `status=1`.
- يتم تصفير `completed_at`.
- يتم إشعار المعقب.

### RPCs المقفلة

- `request_expediting_item_revision_internal(uuid, uuid, text, text)` — `service_role` فقط.
- `update_expediting_checklist_item(...)` — `service_role` فقط.
- كل الاستدعاءات تمر عبر `legal-actions` بعد التحقق من الدور والملكية.

---

## 📊 مراقبة استهلاك السيرفر والتخزين — 2026-07-05

تمت إضافة RPC:

```text
get_resource_usage_internal(p_admin_uid uuid)
```

**الأمان:** `SECURITY DEFINER` ومقفلة عن `anon/authenticated`، وتعمل عبر `service_role` فقط.
**الأدوار:** `role IN (4,5,6)` فقط: موظف مكتب، نائب مدير، مدير.

وتتم قراءتها عبر Edge Function:

```json
{
  "action": "resource_usage",
  "admin_uid": "uuid",
  "staff_session_token": "token"
}
```

### القياسات الدقيقة المتاحة

- حجم قاعدة البيانات الكامل عبر `pg_database_size(current_database())`.
- حجم schema `public` و `storage`.
- حجم كل bucket وعدد الملفات من `storage.objects.metadata.size`.
- حجم الملفات المرفوعة في الشهر الحالي.
- أكبر الجداول حسب `pg_total_relation_size` مع حجم الفهارس وعدد الصفوف التقديري.
- توزيع ملفات Storage حسب `mimetype`.

### ملاحظة مهمة حول التراسل/Bandwidth

قاعدة البيانات لا تملك عدّاداً دقيقاً للـ egress/API bandwidth الحقيقي. لذلك الشاشة تعرض القياسات الدقيقة المتاحة من قاعدة البيانات وStorage، وتعرض ملاحظة بأن قياس التراسل الحقيقي يحتاج:

- Supabase Dashboard/Analytics.
- أو Supabase Management API.
- أو Log Drain / أداة مراقبة خارجية.

### الواجهة

تمت إضافة شاشة Flutter:

```text
/admin/resource-usage
```

وتظهر في:

- أقسام الإدارة.
- عمليات المكتب.

---

## 2026-07-25 — إضافة إجراءات التوثيق بالهوية وطلبات التصوير للمستخدم

### `user-account` → action: `upload_id_images`
رفع وثائق الهوية للمستخدم (رقم وطني + صورة أمامية و/أو خلفية) عبر `service_role` لأن الرفع المباشر من العميل إلى `ids_private` محظور بـ RLS (جلسات مخصصة لا تحمل `auth.uid()`).

- **المدخلات:** `action`, `user_uid`, `sid` (إلزامي), `front_b64` و/أو `back_b64`, `front_ext`/`back_ext` اختياري (`jpg|png|webp`).
- **التحقق:** نفس بوابة `validateUser` (JWT أو `staff_session_token`).
- **السلوك:** فك base64 والتحقق من الحجم؛ فحص/إنشاء bucket `ids_private` (private) احتياطياً؛ رفع بمسار `{uid}/id_{front|back}_{ts}.ext`؛ دمج مع الصور القديمة وحذف المستبدلة بعد نجاح الحفظ؛ تحديث `users.sid` و `users.img` (JSON array `[أمامي, خلفي]` عند الوجهين).
- **الأخطاء:** `SID_REQUIRED`, `SID_TOO_LONG`, `IMAGES_REQUIRED`, `IMAGE_TOO_LARGE`, `INVALID_IMAGE_DATA`, `EMPTY_IMAGE`, `ID_UPLOAD_FAILED:*`, `SAVE_FAILED:*`, `BUCKET_UNAVAILABLE:*`.

### `admin-photography` → action: `my_photo_requests`
جلب طلبات التصوير الخاصة بالمستخدم نفسه (شاشة خدمة التصوير `/user/photography`).

- **المدخلات:** `action`, `user_uid` (+ `staff_session_token` تلقائياً من العميل).
- **التحقق:** نفس منطق `request_photography` (JWT أو `validate_staff_session` بـ `p_min_role=0`).
- **الإرجاع:** حتى 20 مهمة من `photography_tasks` حيث `requested_by = userUid` (id, ttl, notes, sts, ts_scheduled, ts_submit, ts_done, ts_crt).

### `admin-photography` → action: `list_tasks` (2026-07-25 — جولة 2)
عرض كل مهام التصوير للإدارة عبر `service_role` لأن الاستعلام المباشر من العميل محظور بـ RLS (جلسات مخصصة لا تحمل `auth.uid()`).

- **التحقق:** `validateActor` بدور ≥ 3.
- **المدخلات:** `admin_uid`, `status` اختياري (sts 0..5).
- **الإرجاع:** حتى 200 مهمة كاملة الأعمدة مرتبة بـ `ts_crt DESC`.

### `admin-photography` → action: `assign_photographer` (2026-07-25 — جولة 2)
إسناد مصور لمهمة بانتظار (sts=0) — يغلق الحلقة لطلبات التصوير القادمة من المستخدمين (`off_id = null`).

- **التحقق:** دور ≥ 3 + التحقق أن المُسند إليه مؤهل (`role >= 2` أو `perm` يحوي `photographer_tasks`) وغير محذوف/موقوف.
- **المدخلات:** `admin_uid`, `task_id`, `photographer_id`, `ts_scheduled` اختياري.
- **السلوك:** تحديث `photographer_id` + `ts_scheduled` فقط للمهام التي `sts = 0`.
- **الأخطاء:** `MISSING_REQUIRED_FIELDS`, `PHOTOGRAPHER_NOT_FOUND`, `USER_NOT_A_PHOTOGRAPHER`, `TASK_NOT_PENDING`.
- **ملاحظة:** `my_photo_requests` أصبح يعيد `media` أيضاً لعرض الوسائط للمستخدم بعد الاعتماد (sts=3).

### `admin-photography` → action: `cancel_photo_request` (2026-07-25 — جولة 3)
إلغاء طلب تصوير من صاحبه — فقط للمهام بانتظار (`sts = 0`) والمملوكة له.

- **التحقق:** نفس `verifyUserUid` (JWT أو staff_session_token).
- **المدخلات:** `user_uid`, `task_id`.
- **السلوك:** `sts = 5` + `ts_done`؛ يشعر المصور المُسند إن وُجد.

### إشعارات دورة التصوير (2026-07-25 — جولة 3)
- طلب جديد → إشعار كل موظف نشط `role>=3`.
- إسناد → إشعار المصور. نتيجة نهائية (3/4/5) أو ربط بالعرض → إشعار صاحب الطلب. إلغاء من المالك → إشعار المصور المُسند.
- كلها ثانوية (try/catch) ولا تكسر العملية الأساسية.

### تعديل أمني مرخّص بشروط: `upload-offer-images` (2026-07-25 — جولة 4)
توثيق `staff_session_token` أصبح `p_min_role = 0` (قبول حاملي جلسات المستخدمين العاديين بدخول هاتفي)، مع حفاظ على الأمان:
- `role >= 2` → موظف: يرفع لأي مجلد كما السابق.
- `role < 2` → مستخدم عادي: فحص `UNAUTHORIZED_FOLDER` يلزمه بمجلده الخاص فقط (`{folder}/{uid}/...`).
السبب: كان رفع صور العروض مكسوراً كلياً للمستخدمين العاديين بالهاتف (401 لكل ملف).

## 2026-07-26 — دالة جديدة: `admin-config` (كتابة آمنة لإعدادات app_config)

### السبب (مؤكد حياً نفس اليوم)
سياسة كتابة `app_config` تشترط `auth.uid()` مع role≥6، وجلسات الهاتف (staff sessions) لا تملك `auth.uid()`
↔ شاشة إعدادات التطبيق كانت تفشل بالحفظ بصمت للمدير والنائب. الحل: كتابة عبر service_role بعد تحقق الجلسة.

### `admin-config` → action: `update_texts`
تحديث مفاتيح نصية داخل `txts.*` بقائمة بيضاء حصرية (تمنع الكتابة العشوائية بالإعدادات):

- **القائمة البيضاء (مرحلة 1):** `videoRequestWhatsApp`, `videoRequestGroupLink`.
- **التحقق:** `validateActor` بدور ≥ 5 (JWT أو staff_session_token) — صاحب صلاحية "إعدادات التطبيق".
- **المدخلات:** `admin_uid`, `action: "update_texts"`, `texts: { key: value }`.
- **التنظيف:** إزالة محارف التحكم + قص 300 حرف كحد أقصى لكل قيمة.
- **السلوك:** يقرأ `value` الحالي، يدمج `txts` فقط (باقي الأقسام لا تُمس)، ويكتب upsert على `key='main'`.
- **التدقيق:** `log_admin_action` كود `120` (توسعة أكواد: 101-107 للعروض/السوشيال)، ref=`app_config/main` — أفضل-جهد.
- **الأخطاء:** `ADMIN_SESSION_REQUIRED`, `INVALID_ADMIN_SESSION`, `TEXTS_OBJECT_REQUIRED`, `KEY_NOT_ALLOWED`, `NO_KEYS_PROVIDED`, `UNKNOWN_ACTION`.
- **ملاحظة توسعية:** باقي أقسام الإعدادات (نقاط/حصص/سوشيال...) تُنقل لاحقاً كأفعال whitelist إضافية بمراحل منفصلة.

### إصلاح مصاحب: أسماء معاملات `log_admin_action` (2026-07-26)
التواقيع الحية المؤكدة: `(p_admin_uid, p_act, p_det, p_ref_id, p_ref_col)`.
كان `admin-offers` (موضعان) و`publish-to-social` (موضع) ينادونها بـ
`p_action/p_details/p_target_id/p_target_table` → PostgREST لا يطابق أسماء المعاملات
والأخطاء تُبتلع داخل try/catch → سجلات تدقيق ضائعة بصمت. صُححت الأسماء في الثلاثة.
(نداءات `p_action` في `admin-reports` و`user-appointments` صحيحة — تعود لدوال أخرى، لم تُمس.)

---

## 🆕 2026-08-27 — إدارة حسابات النشر الاجتماعي (multi-account publishing)

### الهدف
استبدال مفاتيح البيئة الثابتة (`META_*`) بنظام حسابات يُدار **من داخل التطبيق**:
أي عدد من صفحات فيسبوك وحسابات إنستغرام مع توكناتها، والناشر يوزّع كل عرض مقبول
على الحسابات المفعّلة كلها.

### القاعدة/RPC (migration: `2026_08_27_social_accounts_management.sql`)

| العنصر | الوصف |
|---|---|
| `social_accounts` (جدول) | platform (facebook/instagram) + name + account_external_id (Page ID / IG ID) + access_token + verified_name + is_active/is_verified + last_error — RLS بلا سياسات عملاء + REVOKE من anon/authenticated (service_role حصراً) |
| `social_publications.account_id` | عمود جديد يربط كل منشور بحسابه (الصفوف القديمة تبقى NULL) |
| فهرسان جزئيان فريدان | `(offer_id, account_id) WHERE account_id IS NOT NULL` + `(offer_id, platform) WHERE account_id IS NULL` — حلّا محل القيد القديم `UNIQUE(offer_id, platform)` وأتاحا تعدد الحسابات |
| `claim_social_publication` (مُعاد إنشاؤها) | نفس التوقيع `(p_offer_id, p_platform, p_attempt_token)` — لكن `ON CONFLICT` يستهدف الفهرس الجزئي للمسار البيئي (account_id IS NULL) |
| `claim_social_publication_v2` 🆕 | `(p_offer_id, p_account_id, p_platform, p_attempt_token)` — حجز ذرّي لكل (عرض، حساب) |

### Edge Function: `social-accounts`
- **الأفعال:** `list` / `save` (إضافة+تعديل، توكن فارغ عند التعديل = إبقاء الحالي) / `verify` / `delete` (ناعم i_del=1).
- **الأمان:** `validateActor` دور ≥5 (نمط admin-config) · `save` يتحقق تلقائياً لدى Meta (Graph API) ويرجع اسم الصفحة الحقيقي · **التوكن لا يعود للعميل أبداً** — `tokenMasked` (آخر 4 محارف) + `tokenLength`.
- **التدقيق:** `log_admin_action` أكواد `130` (حفظ) / `131` (تحقق) / `132` (حذف) — بدون قيم توكن.
- **الأخطاء:** `ADMIN_SESSION_REQUIRED`, `INVALID_ADMIN_SESSION`, `INVALID_PLATFORM`, `ACCOUNT_NAME_REQUIRED`, `INVALID_ACCOUNT_EXTERNAL_ID`, `ACCESS_TOKEN_REQUIRED`, `INVALID_ACCESS_TOKEN`, `ACCOUNT_NOT_FOUND`, `ACCOUNT_ID_REQUIRED`, `META_VERIFY_EMPTY_RESPONSE`.

### `_shared/social_publisher.ts` — الناشر متعدد الحسابات
- `loadAccounts`: يقرأ الحسابات المفعّلة من `social_accounts`؛ **إن لم يوجد أي حساب يعود للمسار البيئي القديم** (توافق خلفي كامل).
- لكل حساب: `runAccount` → حجز (v2 للحسابات القاعدية، القديمة للبيئية) → نشر → تسجيل في `social_publications`.
- **لا نشر بدون صورة عامة واحدة على الأقل لكل المنصات** (`PUBLIC_IMAGE_REQUIRED` قبل أي حساب) — متوافق مع بوابة IMG-001 (قرار المالك 2026-08-15: «لا اعتماد لعرض بلا صورة»); عملياً كل عرض معتمد يحمل صوراً لأن بوابة الاعتماد ترفض غير ذلك.
- `soc_pub=2` عند نجاح كل الحسابات فقط؛ نتيجة كل منصة تبقى في `facebook`/`instagram` (توافق شكلي مع العميل) + تفصيل `accounts[]`.

### أثر على الواجهة (Flutter)
- شاشة جديدة `social_accounts_screen.dart` بمسار `/admin/social-accounts` (صلاحية `manage_config`): إضافة/تعديل/حذف/تحقق + عرض الاسم الحقيقي والتوكن المقنّع.
- بلاطة جديدة في أقسام الإدارة + مدخل من محرر الإعدادات (قسم صفحات التواصل).
- `offers_review_screen`: الحفاظ على منع «بلا صور» (متوافق مع IMG-001 — قرار المالك) · نصوص محدّثة · معالجة `NO_SOCIAL_ACCOUNTS_CONFIGURED`.
- رسائل عربية جديدة في `ErrorUtils` لكل رموز الأخطاء أعلاه.

**المرجع الكامل (خطوات النشر والتشغيل):** `docs/SOCIAL_ACCOUNTS_MANAGEMENT_2026_08_27.md`
