# 📜 ميثاق المنطق النهائي — تطبيق عقارات السويداء

> هذا المستند يحدد القواعد المنطقية التي تحكم عمل التطبيق،
> لضمان تحوله من منصة إعلانية إلى **مكتب عقاري إلكتروني** متكامل.
> أي تعديل برمجي يخالف هذا الميثاق يُرفض.

---

## 🏢 أولاً: فلسفة "المكتب العقاري" (Office Identity)

- التطبيق ليس وسيطاً سلبياً، بل هو **المكتب** الذي يدير العملية.
- **قاعدة النشر:** لا يظهر اسم صاحب العقار/السيارة للعامة.
  العرض يُنشر باسم المكتب.
- **التسمية الديناميكية:** يُستبدل اسم المستخدم بـ "وصف الحالة"
  بناءً على (الدور + الرتبة + التوثيق) عبر دالة
  `BusinessService.getUserPublicLabel(user)`.
- **مركزية التواصل:** جميع الطلبات والاتصالات تمر عبر إدارة المكتب لضمان:
  1. حماية خصوصية الملاك.
  2. ضمان تحصيل عمولات المكتب.
  3. فلترة الجادين من غير الجادين.

### قواعد التسمية الحالية
| الحالة | التسمية الظاهرة |
|--------|------------------|
| وسيط + بدأ التوثيق | وسيط معتمد ✓ |
| وسيط + لم يبدأ | وسيط شريك |
| مستخدم + بدأ التوثيق | عميل موثق ✓ |
| مستخدم + رتبة ≥ خبير | عميل مميز ⭐ |
| مستخدم + رتبة ≥ نشط | عميل نشط |
| مستخدم عادي | عميل |

الصيغة النهائية: `منشور بواسطة المكتب • <التسمية>`

---

## 🛡️ ثانياً: التوثيق والموثوقية (Verification vs Trust)

### 1. التوثيق الرسمي (Verification — ✓)
- **المستخدم العادي:** رفع الهوية **اختياري**.
- **الوسيط:** رفع الهوية والوثائق التجارية **إلزامي**.
  لا يمكن تفعيل حساب الوسيط دون مراجعة إدارية.
- شارة "موثق" تظهر فقط بعد مراجعة إدارية رسمية.

#### حقل `users.vrf` (تم تنفيذه)
| القيمة | المعنى |
|--------|--------|
| `0` | غير موثق (افتراضي) |
| `1` | قيد المراجعة (المستخدم رفع وثائقه) |
| `2` | موثق رسمياً (الإدارة وافقت) |

- ملف الـ migration: `supabase/migrations/2026_06_06_user_verification_status.sql`
- الحقل في الكود: `UserModel.vrf` + المساعدات
  `hasStartedVerification` و `isVerifiedOfficial`.

### 2. الموثوقية السلوكية (Trust — ⭐)
سلم المراتب بناءً على النقاط (يحل محل سلم المعادن السابق):

| المستوى | الاسم | الرمز | النقاط | الدلالة |
|---------|-------|------|--------|---------|
| 0 | جديد | 🔰 | 0 | بدأ رحلته الآن |
| 1 | نشط | 📈 | 10,000 | يتفاعل بانتظام |
| 2 | موثوق | 🤝 | 20,000 | أثبت جديته بصفقات ناجحة |
| 3 | خبير | 🎓 | 30,000 | سجل حافل بالصفقات |
| 4 | نخبة | ⭐ | 40,000 | أعلى درجات الثقة |

> ❗ المعادن (برونزي/فضي/ذهبي) محجوزة **فقط** للباقات المدفوعة (`pkg`)،
> ولا تُستخدم أبداً للمراتب السلوكية (`bdg`).

---

## 💰 ثالثاً: النظام المالي والتحفيزي

### 1. الباقات (الاستثمار المادي — `pkg`)
- تبقى بأسماء المعادن: مجاني / فضي / ذهبي.
- تحدد صلاحيات الحساب (عدد العروض، مدة الظهور).

### 2. النقاط (الاستثمار السلوكي — `pts`)
- تُكسب من:
  - تسجيل دخول يومي (50 نقطة، مفتاح `strk`).
  - إضافة عرض (`addO`).
  - إتمام صفقة (`dlD`).
  - دعوة صديق (`ref`) — كود إحالة في setup_profile.
  - النشر على السوشال (`soc`).
- تُستخدم لـ: ترقية العروض (Boost/Pin/Featured) عبر `purchase_offer_boost`،
  رفع الرتبة السلوكية تلقائياً.

### 3.2 نظام الإحالة (Referral)
- كل مستخدم له كود فريد = أول 8 أحرف من uid (uppercase).
- يُدخل المستخدم الجديد كود محيله في setup_profile.
- يُستدعى RPC `apply_referral(p_new_uid, p_referrer_code)` تلقائياً.
- الطرفان يحصلان على نقاط الإحالة (`pts.ref` ≈ 1500).
- يُحدّث `users.ref_cnt` للمحيل تلقائياً.

### 3.3 نظام التقييم (Rating)
- جدول `ratings(reviewer_uid, target_uid, stars 1-5, comment)`.
- يُعرض زر التقييم في `my_appointments_screen` للمواعيد المنتهية (sts=2).
- Widget `RatingDialog.show()` مشترك للاستخدام في أي مكان.
- Trigger `trg_rating_bonus` يمنح المستهدف 200 نقطة تلقائياً عند تقييم 5 نجوم.
- لا يمكن تقييم النفس + يجب تسجيل الدخول.

## 📄 §4 الأداء والقابلية للتوسع

### 4.2 Pagination
- `OfferProvider.pageSize = 20`.
- `loadMoreOffers()` تستخدم Supabase `.range(from, to)`.
- في `home_screen` يُربط عبر `NotificationListener<ScrollNotification>`
  يطلق تحميل صفحة جديدة قبل 200 بكسل من النهاية.
- منع التكرار: استبعاد العروض الموجودة مسبقاً قبل الإضافة.
- معطّل تلقائياً أثناء البحث (`_isSearching`).

### 4.3 عقدة حالات المواعيد (Appointment Status Contract)
- الحقول المرجعية:
  - `appointments.req_uid` = المستخدم الذي حجز الموعد.
  - `appointments.own_id` = مالك العرض.
  - `appointments.bkr_id` = الوسيط/المعالج إن وُجد.
- الحالات الرسمية المعتمدة:

| القيمة | المعنى |
|---|---|
| `0` | قيد الانتظار |
| `1` | مؤكد |
| `2` | مكتمل |
| `3` | ملغي |
| `4` | مرفوض |
| `5` | لم يحضر |

- أي شاشة أو Provider أو RPC يجب أن يلتزم بهذه القيم حصراً.
- شاشة **مواعيدي** للمستخدم يجب أن تعتمد على `req_uid` لا `own_id`.

---

## 🚫 رابعاً: الأمان والسيطرة

- **الحظر الفوري:** عند تغيير `sts` إلى محظور، يُطرد المستخدم
  فوراً عبر Realtime.
- **قفل البيانات:** بمجرد توثيق الحساب رسمياً، تُقفل حقول الهوية،
  ولا تُعدّل إلا بطلب مراجعة إداري.
- **هوية الموظف (Staff Identity):**
  - الموظفون (Role >= 2) لا يتبعون نظام النقاط أو التوثيق الاختياري.
  - عند إضافة موظف، يتم إدخال (الرقم الوطني SID، العنوان AD، وصورة الهوية IMG) إجبارياً.
  - الموظف المضاف عبر الإدارة يُعتبر "موثقاً رسمياً" (vrf=2) تلقائياً.
  - شاشة الملف الشخصي للموظف تعرض المنصب والبيانات الوظيفية بدلاً من بيانات العميل.
- **حماية الخصوصية:** بيانات الاتصال (هاتف/إيميل) لا تظهر للعامة،
  تظهر فقط للإدارة وللوسيط المعتمد بعد موافقة الإدارة.
- **منع التلاعب بالعملات:** سعر الباقة بالدولار، وأي تحويل لليرة
  يتم آلياً حسب سعر الصرف المعتمد في `app_config`.

---

## 🔗 المراجع التقنية

| المفهوم | الموقع في الكود |
|---------|------------------|
| توليد التسمية المهنية | `lib/core/services/business_service.dart` → `getUserPublicLabel()` |
| اسم الرتبة السلوكية | `lib/models/user_model.dart` → `badgeName` |
| إثراء قوائم العروض بالتسمية | `lib/providers/offer_provider.dart` → `_enrichOwnerLabels()` |
| عرض التسمية في تفاصيل العرض | `lib/screens/visitor/offer_detail_screen.dart` |
| عرض التسمية في بطاقات العروض | `lib/widgets/offer_card.dart` |
| حالة بدء التوثيق | `lib/models/user_model.dart` → `hasStartedVerification` |
| التوثيق الرسمي المعتمد | `lib/models/user_model.dart` → `isVerifiedOfficial` (vrf=2) |
| Migration التوثيق | `supabase/migrations/2026_06_06_user_verification_status.sql` |
| طلب التوثيق من المستخدم | `lib/screens/user/profile_screen.dart` → `_requestVerification()` |
| مراجعة الإدارة لطلبات التوثيق | `lib/screens/admin/verifications_review_screen.dart` |
| اعتماد/رفض التوثيق | `lib/providers/admin_provider.dart` → `approveVerification` / `rejectVerification` |
| توضيح الحجز عبر المكتب | `lib/widgets/book_appointment_sheet.dart` |
| إشعار نتيجة التوثيق | `lib/providers/admin_provider.dart` → `_notifyVerificationResult()` |
| شارة التوثيق في تفاصيل المستخدم (إدارة) | `lib/screens/admin/user_details_screen.dart` |
| إلزام الوسيط الجديد بالتوثيق | `lib/screens/user/become_broker_screen.dart` |
| تطبيق كود الإحالة عند التسجيل | `lib/screens/auth/setup_profile_screen.dart` → `apply_referral` RPC |
| ترقية العرض بالنقاط (Boost) | `lib/screens/user/boost_offer_screen.dart` → `purchase_offer_boost` RPC |
| زر "ترقية بالنقاط" في تفاصيل العرض | `lib/screens/visitor/offer_detail_screen.dart` (للمالك) |
| الإقرار والتعهد قبل النشر | `lib/screens/user/add_offer_screen.dart` → `_showPledgeDialog` |
| Dialog التقييم المشترك | `lib/widgets/rating_dialog.dart` → `RatingDialog.show()` |
| زر التقييم بعد موعد منتهٍ | `lib/screens/user/my_appointments_screen.dart` (sts=2) |
| زر التقييم في تفاصيل العرض | `lib/screens/visitor/offer_detail_screen.dart` (للمسجلين غير المالك) |
| متوسط تقييم المالك في تفاصيل العرض | `lib/screens/visitor/offer_detail_screen.dart` → `_ownerAvgRating` |
| شاشة تقييماتي المستلمة | `lib/screens/user/my_ratings_screen.dart` → `/user/my-ratings` |
| Pagination للعروض | `lib/providers/offer_provider.dart` → `loadMoreOffers()` |
| Infinite scroll | `lib/screens/visitor/home_screen.dart` → `NotificationListener` |

---

## 🔒 §5 الأمان (Security Hardening — Phase 8)

### 5.1 منع self-promotion
- Trigger `check_user_safe_update` يمنع المستخدم من تعديل:
  `role, vrf (>1), pt, bg, brk, b_pkg, pkg_end, ref_by, ref_cnt, sts, ban_rsn`.
- Trigger `check_user_safe_insert` يمنع تسجيل بحقول مرفّعة من البداية.
- استثناء وحيد: `vrf: 0 → 1` مسموح (تقديم طلب توثيق).

### 5.2 إخفاء البيانات الشخصية
- `users` لا يقرأها إلا مالكها (policy `Users can read own row only`).
- VIEW `users_public` تكشف فقط: `id, nm, usr, role, brk, brk_cls, brk_nm, bg, vrf, pt, ref_cnt, ts_crt`
  (أُضيف `usr` اسم المستخدم عبر migration 2026-06-13). `pwd` لا يُكشف أبداً.
- الـclient يجب أن يستعمل `users_public` لجلب بيانات الملاك.

### 5.3 منع التقييم الذاتي والمتكرر
- `ratings_no_self`: `CHECK (reviewer_uid <> target_uid)`.
- `UNIQUE(reviewer_uid, target_uid)`: تقييم واحد لكل ثنائي.
- Trigger `check_rating_valid` يشترط موعد منتهٍ أو صفقة مكتملة بين الطرفين.

### 5.4 حماية apply_referral
- محصورة لـ `auth.uid() = p_new_uid` (لا يستطيع طرف ثالث استدعاؤها).
- Rate-limit: 5 إحالات/ساعة لكل محيل.
- مرفوعة من `anon` (لا تعمل بدون تسجيل دخول).

### 5.5 RPCs آمنة للأدمن
- `request_verification_by_uid(p_user_uid)` — المسار المتوافق مع الوضع الحالي لرفع `vrf` من المستخدم، مع مطابقة `auth.uid()` متى كانت الجلسة الحقيقية متاحة.
- `admin_approve_verification_by_admin(p_admin_uid, uid)` — يفحص دور الإداري (`role >= 4`) ويرسل إشعاراً ويوثق الحركة في `activity_log`.
- `admin_reject_verification_by_admin(p_admin_uid, uid, reason)` — يفرض سبب الرفض إجبارياً ويفحص الدور (`role >= 4`) ويوثق في `activity_log`.
- `admin_review_offer_internal(p_admin_uid, p_offer_id, p_approve, p_reject_reason)` — يفحص دور الإداري (`role >= 4`) ويفرض سبب الرفض عند الرفض ويوثق في `activity_log`.
- `approve_payment_final` و `admin_reject_payment_internal` — محصورة للرتبة العليا (`role >= 5`) وتوثق في `activity_log`.
- **(تحديث 2026-08-14) أنواع الدفع التي تعالجها `approve_payment_final`:**
  | `tp` | النوع | `pkg` | الأثر عند الاعتماد |
  |---|---|---|---|
  | 0 | اشتراك باقة | 1 فضية · 2 ذهبية | تجميع الأيام + `pkg_xoff` + `pkg_grace` |
  | 1 | إعلان مميّز | — | `i_fms=1` + تمديد `fms_end` بـ`meta.weeks × 7` |
  | 2 | **استشارة قانونية** | 0 هاتفية (500) · 1 حضورية (2000) | اعتماد الدفعة؛ وإن وُجد `meta.continue_chat` يُجدَّد وقت المحادثة (+15د) ويُربط `payment_id` وتُكتب رسالة `system` |
  حراس فرع `tp=2`: `CONSULTATION_META_INVALID` (بلا `meta.service='legal_consultation'`) ·
  `CONSULTATION_TYPE_INVALID` (`pkg` خارج 0/1) · `CONSULTATION_OWNER_MISMATCH` (محادثة ليست للدافع) ·
  `CHAT_NOT_STARTED` · `CHAT_EXPIRED_7DAYS`.
- **(تحصين 2026-08-16):** مسار الإدارة يستدعي `approve_payment_final_v2`. الحجز الجديد
  يربط دفعة معتمدة غير مستخدمة أو يستهلك رصيداً داخل معاملة ذرية؛ لا إنشاء بلا دفع.
  `renew_chat` المباشر محظور، والتجديد لا يضيف وقتاً إلا بعد اعتماد دفعة
  `meta.continue_chat`. الرسائل تحمل `client_message_id` فريداً، وتغلق المحادثات
  الهاتفية آلياً خلال دقيقة من نهاية مدتها الحالية.
- **(V2 مفعّل 2026-08-16):** الطلب يبدأ بـ`consultation_intents`، والحضورية تحجز
  وقتاً 6 ساعات داخل `lawyer_time_reservations` بقيد EXCLUDE. كل مدة محادثة صف
  في `consultation_chat_sessions`: المحامي يعلن الجاهزية، ثم يبدأ العداد عند
  انضمام المستخدم أو بعد دقيقتين أيهما أسبق. التجديد المعتمد ينشئ جلسة `ready`
  ولا يبدأ الوقت. التحويل ينشئ حضورية ابنة وموعداً `kind=legal` مؤكداً تلقائياً.
  النافذة 30 يوماً، ثم waitlist أو محامٍ آخر بموافقة صريحة. Push عبر outbox.
- **قنوات الدفع والإعدادات:** كل كتابة على `app_config` تمر عبر `admin-config` بمفتاح الخدمة
  (الكتابة المباشرة يرفضها RLS بـ`42501`). الأقسام المسموحة: `pts, com, qta, txts,
  socialPublishing, photoPrice, payChannels, office`. رقم المكتب (`office.phone`) هو **وجهة
  تحويل رصيد الجوال** ويُكتب متزامناً مع `payChannels.balance.number`.
- **(تحديث سجل الحركات 2026-07-02):** يتم تسجيل جميع القرارات والتصرفات الإدارية آلياً في جدول `activity_log` عبر الدالة الموحدة `log_admin_action` لضمان المحاسبة وتتبع الأثر (Audit Trail).

### 5.6 منع phishing notifications
- INSERT في `notifications` محظور من client (`WITH CHECK (false)`).
- الإدراج فقط عبر triggers أو دوال SECURITY DEFINER.
- UPDATE مسموح لـ `i_rd` فقط للمالك.

### 5.7 OTP مع قفل بعد المحاولات
- الاعتماد الحالي يكون على مسار OTP المحدث (`generate_otp_v2` / `verify_otp_v2`) مع الحدّ المعدلي والحذف بعد الاستخدام.
- تم تنظيف `verify_otp_safe` لاحقاً من السيرفر بعد التأكد من عدم استخدامه في التدفق الحالي.

### 5.8 حماية صلاحية النشر (anti-abuse)
- `canPublishOffer` و `create_offer_internal` يحسبان العروض المحذوفة خلال آخر 24 ساعة (منع "احذف وانشر").
- `fail-closed`: عند فشل التحقق، يُمنع النشر بدل السماح.
- **(تحديث 2026-07-02):** عند إضافة عرض من قبل الإدارة بالنيابة عن عميل، يتم توثيق معرف الموظف الإداري في عمود `added_by` (بعد فحص أن المنفذ `role >= 4`)، ويتم إعفاء الإضافة الإدارية من سقف باقة العميل (`QUOTA_EXCEEDED`).
- **(تحديث مدفوعات الباقات 2026-07-02):** تم سحب الإدراج المباشر في جدول `payments` وحصره بالمرور عبر Edge Function `user-account` (`action: create_payment`) لتفعيل الحماية الفولاذية ضد الدفعة المزدوجة المعلقة (`PENDING_PAYMENT_EXISTS`)، مع تطبيع أرقام مرجع الحوالة البنكية.

### 5.9 منع انتحال "المكتب"
- الاسم لا يقبل: `مكتب، إدارة، admin، مدير، إداري، official`.

### 5.10 OTP cryptographic (Phase 9)
- `generate_otp` يستخدم `pgcrypto.gen_random_bytes(3)` بدل `RANDOM()`.
- 24-bit entropy → مقاوم للتنبؤ بـseed.

### 5.11 Device Fingerprinting (Phase 9)
- `users.device_id` + `signup_ip` + `last_ip` + `device_history JSONB`.
- `DeviceService` في الـclient يولّد UUID محلي ويُسجّله عبر `register_device` RPC.
- `apply_referral` ترفض إذا كان المُحال + المحيل من نفس الجهاز أو IP.
- VIEW `fraud_suspects` + RPC `admin_fraud_suspects()` لكشف الحسابات المشبوهة.
- شاشة إدارية: `/admin/fraud-suspects`.

### 5.12 Storage Policies لصور الهوية (Phase 9)
- Bucket جديد **خاص** `ids_private` (public=false).
- المسار: `<userId>/id_<ts>.jpg` — RLS تشترط `auth.uid()::text = folder[1]`.
- المالك + الأدمن (role>=3) فقط يقرؤون.
- الـclient يحفظ المسار النسبي (لا public URL).
- الأدمن يعرض الصورة عبر `createSignedUrl(path, 60)` — رابط 60 ثانية.

### 5.13 Network Security (Phase 9)
- `android:usesCleartextTraffic="false"` + `networkSecurityConfig`.
- `android:allowBackup="false"` (يمنع نسخ بيانات التطبيق).
- ملف `network_security_config.xml` جاهز لـCertificate Pinning مستقبلاً.

| المرجع | الموقع |
|---|---|
| Migration الأمان | `supabase/migrations/2026_06_07_security_hardening.sql` |
| RPC طلب التوثيق | `lib/screens/user/profile_screen.dart` → `request_verification_by_uid` |
| RPC اعتماد/رفض | `lib/providers/admin_provider.dart` → `admin_approve_verification_by_admin` / `admin_reject_verification_by_admin` |
### 5.14 اسم مستخدم + كلمة مرور (Phase 10 — 2026-06-13)
- مسار دخول إضافي فوق واتساب OTP: اسم مستخدم (`usr`) أو هاتف + كلمة مرور (`pwd`).
- `usr`: اسم فريد موحّد (LOWER)، 3–30 حرف، `[a-z0-9_.]` فقط.
- `pwd`: هاش bcrypt فقط (`gen_salt('bf',8)`) — لا يُخزّن نصاً ولا يُسرّب للعميل أبداً.

**تدفق المصادقة:**
1. **الزائر** يتصفّح ويستخدم الفلاتر بحرية كاملة.
2. **عند التفاعل** (مثلاً حجز موعد) → يُطلب الدخول → شاشة `/login` تعرض خيارين:
   - **تسجيل الدخول (Sign In):** اسم مستخدم أو رقم هاتف + كلمة مرور.
   - **إنشاء حساب (Sign Up):** واتساب (أساسي) أو إيميل (ثانوي).
3. **بعد Sign Up (OTP/Magic):** شاشة `/setup-profile` إلزامية لإعداد اسم مستخدم + كلمة مرور فقط.
4. **الدخول لاحقاً:** باسم المستخدم المعيّن أو برقم الهاتف المسجّل + كلمة المرور.
5. **نسيان كلمة المرور:** ← تبويبة واتساب → `reset_password_with_otp`.

**فصل الهوية عن بيانات الدخول:**
- `/setup-profile`: اسم مستخدم + كلمة مرور فقط (بعد الـ OTP).
- `/setup-identity`: رقم وطني + صورة هوية (للتوثيق والوساطة) — تُستدعى من
  `account_info_screen` و `become_broker_screen`.

- `get_user_full_by_id` تُرجع `pwd` كـ flag (`'set'`/`NULL`) لا كهاش.
- Migration: `supabase/migrations/2026_06_13_auth_username_password.sql`.
- RPCs: `register_password`, `login_with_password`, `reset_password_with_otp`,
  `change_password_internal`, `check_username_available`, `get_staff_stats_internal`.
- **(تحديث 2026-07-02):** تم إطاحة أي Fallbacks غير آمنة في دوال Edge Functions الست (`user-account`، `user-appointments`، `user-notifications`، `user-offers`، `user-requests`، `user-rewards`) لفرض التحقق الإلزامي من توكن الـ JWT ومطابقة الـ `user_uid`، مع معالجة مرنة Adaptive لردود الـ JSONB والـ BOOLEAN في دوال كلمات المرور والنقاط.
- **(تحديث دعم العربية 2026-07-02):** تم تمييز وتطبيع الأرقام العربية المشرقية (`٠-٩`) والفارسية (`۰-۹`) في أرقام الهاتف عبر `normalize_sy_phone` ودوال `send-sms-otp`/`verify-sms-otp`. كما تم إتاحة أسماء المستخدمين باللغة العربية مع فرض 3 ضوابط أمنية: (1) منع خلط اللغتين اللاتينية والعربية في الاسم الواحد منعاً لثغرات التشابه البصري (Homoglyph) (2) تطبيع المتشابهات البصرية وإطاحة التشكيل والكشيدة وتوحيد الألف والتاء المربوطة والياء عبر `normalize_arabic_username` في مقارنات التكرار والدخول (3) فرض هذه القيود في واجهة Flutter وسيرفر Supabase معاً.

---

**توقيع:** هذا المنطق هو المرجع الأعلى لكل تعديل برمجي في التطبيق.
عند أي تعارض بين كود وميثاق، يُقدَّم الميثاق ويُعدَّل الكود.

---

## §6 عقد دورة حياة طلب العميل (Request Lifecycle — 2026-06-27)

طلب العميل (`requests`) ليس إعلاناً دائماً؛ له عمر زمني ومسارات إغلاق مسؤولة:

| `requests.sts` | المعنى |
|---|---|
| `0` | نشط |
| `1` | قيد المعالجة — بدأ عليه موعد مرتبط أو متابعة فعلية |
| `2` | تم تلبيته / مغلق بنجاح |
| `3` | ملغي |
| `4` | منتهي الصلاحية |

### قواعد العمر الزمني
- إعدادات العمر من `app_config.main.req`:
  - `d`: مدة الطلب عند الإنشاء، افتراضياً 30 يوم.
  - `warn`: إشعار قبل الانتهاء، افتراضياً 3 أيام.
  - `ren`: مدة التجديد، افتراضياً 30 يوم.
  - `purge`: تنظيف البيانات الحساسة بعد الإغلاق، افتراضياً 180 يوم.
- `expire_requests()` تغلق الطلبات النشطة/قيد المعالجة المنتهية إلى `sts=4`.
- `send_request_renewal_reminders()` يرسل إشعاراً واحداً قبل الانتهاء ويضبط `rmnd_ren=1`.
- `purge_old_closed_requests()` لا يحذف العلاقات فوراً؛ يفرّغ البيانات الحساسة ويضبط `i_del=1` بعد مدة الأرشفة.
- **قاعدة التجديد (Renewal):** تجديد الطلبات والعروض متاح دائماً للحسابات المدفوعة، أما الحسابات المجانية فلا يمكنها التجديد إلا قبل يومين (أو أقل) من تاريخ انتهاء الصلاحية.

### قواعد الإغلاق
- المطابقة لا تغلق الطلب أبداً؛ تستخدم للإشعار وعرض العروض المطابقة فقط.
- الحجز من شاشة تفاصيل الطلب يمرر `requestId` إلى `book_appointment_internal`، فيُحفظ في `appointments.req_id` ويحوّل الطلب إلى `sts=1`.
- موافقة الإدارة على `process_completion_request(..., 'approved')` تغلق الطلب المرتبط بالموعد إلى `sts=2` مع تسجيل:
  `closed_by`, `closed_at`, `closed_reason`, `closed_offer_id`, `closed_appointment_id`, `closed_completion_request_id`.
- إلغاء المستخدم يتم عبر `cancel_request_internal` وليس حذفاً مباشراً، ويُسجل `closed_by=user` و`closed_reason=cancelled_by_user`.
- الإغلاق الإداري يتم عبر `admin_close_request_internal` حصراً لصلاحيات `role >= 4`.
- تظهر معلومات من أغلق الطلب وسببه للإدارة فقط عبر `get_admin_requests_internal`.

### الأمان
- RPCs الخاصة بدورة حياة الطلبات ممنوعة عن `anon/authenticated` وممنوحة لـ `service_role` فقط.
- العميل يستدعي Edge Functions (`user-requests`, `admin-dashboard`) التي تتحقق من الهوية/جلسة الموظف ثم تستدعي RPCs.
- حساب حصة الطلبات يعتمد فقط على الطلبات المفتوحة: `sts IN (0,1)` و`i_del=0`.

---

## §7 عقد قواعد حجز المواعيد (Appointment Booking Rules — 2026-07-02)

المرجع التنفيذي: `book_appointment_internal` في
`supabase/migrations/2026_07_02_appointment_booking_rules.sql` + الواجهة في
`lib/widgets/book_appointment_sheet.dart`.

### الإعدادات (من `app_config.main.appt` — لا Hardcoding)
| المفتاح | المعنى | الافتراضي |
|---|---|---|
| `any_from` | بداية دوام المعاينة لعروض "جاهز بأي وقت" | `09:00` |
| `any_to` | نهاية دوام المعاينة لعروض "جاهز بأي وقت" | `21:00` |
| `gap_mins` | الفارق الأدنى بين موعدين (قاعدة الساعة) | `60` |

### القاعدة 1 — الالتزام بمواعيد صاحب العرض
- الحجز لا يخرج أبداً عن الأيام والفترات التي حددها صاحب العرض في `offers.avl`.
- السيرفر يرفض بـ `DAY_NOT_AVAILABLE` أو `TIME_NOT_IN_AVAILABLE_SLOTS`.
- حالة **"جاهز للمعاينة في أي وقت"** تُخزَّن `avl = {"any": [...]}`:
  - الواجهة تعرض كل أيام الأسبوع السبعة، والدوام من `appt.any_from` حتى `appt.any_to` (09:00–21:00).
  - السيرفر يتعامل مع `any` كإتاحة لكل الأيام ضمن الدوام نفسه.
- `avl` فارغة = لا معاينة على العرض إطلاقاً — السيرفر يرفض بـ `NO_AVAILABILITY`
  (سُدّت ثغرة تخطي الفحص القديمة).

### القاعدة 2 — إسناد المشرف (الأقل مواعيداً + التصعيد)
- يُسند الموعد تلقائياً للمشرف (role=3، نشط) **الأقل مواعيد نشطة** (sts 0/1).
- إن كان الأقل حمولة مشغولاً ضمن فارق `gap_mins` من التوقيت المطلوب → ينتقل تلقائياً للتالي، وهكذا.
- إذا لم يتوفر أي مشرف في التوقيت المطلوب:
  - **لا يُنشأ الموعد**، وتعيد الدالة `{success:false, error:'NO_SUPERVISOR_AVAILABLE', suggested_dt}`.
  - `suggested_dt` = أقرب موعد متاح فعلياً خلال 14 يوماً عبر `suggest_appointment_slot`
    (ضمن avl + بلا تعارض على العرض + مشرف متاح).
  - يُرسل إشعار للطالب (`notify_user`, tp=2) يتضمن الاقتراح أو الطلب باختيار وقت آخر.
  - الواجهة تعرض الاقتراح وتدعو المستخدم لاختيار وقت آخر.
- دالة `get_available_supervisor` موحَّدة مع نفس المنطق (sts 0/1 + فارق الساعة).

### القاعدة 3 — عدم التعارض (فارق الساعة)
- لا يجوز موعدان نشطان (sts 0/1) على نفس العرض بفارق يقل عن `gap_mins` (60 دقيقة):
  موعد 10:00 → أقرب حجز مسموح 11:00. الرفض بـ `TIME_CONFLICT_ON_OFFER`.
- الفارق نفسه مطبق على **جدول المشرف** عند الإسناد.
- الواجهة تظلل مسبقاً كل وقت يقع ضمن أقل من ساعة من موعد نشط
  (عبر `get_booked_slots_internal` التي تعيد أوقات المواعيد النشطة لليوم بتوقيت دمشق).

### قواعد مكملة (كما كانت)
- لا حجز على عرضك (`CANNOT_BOOK_OWN_OFFER`) ولا من الإدارة، العرض منشور فقط (sts=2)،
  الوقت مستقبلي، لا حجز مزدوج لنفس المستخدم (`DUPLICATE_APPOINTMENT`)،
  ولا حجز مع طلب إتمام معلق (`OFFER_HAS_PENDING_COMPLETION`).
- الموعد يُنشأ `sts=0` والتأكيد عبر إدارة المكتب حصراً.

### §7.1 التحقق الإلزامي من رقم الهاتف في حجز المواعيد (2026-07-13)
- **في كل مسارات حجز الموعد** (BookAppointmentSheet) يجب التحقق من وجود رقم هاتف متحقق (`ph` غير فارغ + `vrf != 0`).
  - مستخدمو واتساب (رقم هاتف مسجل + متحقق): ينتقلون مباشرة إلى اختيار اليوم/الفترة/الوقت.
  - مستخدمو الإيميل (بدون هاتف أو غير متحقق): تظهر داخل الـ Sheet خطوة إدخال رقم هاتف + إرسال/تحقق OTP باستخدام AuthProvider.sendSMSOTP + verifySMSOTP.
- يتم فرض هذا التحقق **قبل** عرض واجهة اختيار المواعيد.
- **مسار طلب الفيديو** (من offer_detail_screen): يستخدم نفس الـ Sheet مع علم `isVideoRequest=true`.
  - بعد نجاح الحجز مباشرة: يتم فتح واتساب تلقائياً (url_launcher) على الرقم المخصص أو الرابط الاحتياطي مع رسالة جاهزة تحتوي `#${offerNumber}`.
- **لا يُعرض الفيديو أبداً** بشكل مباشر أو قابل للتحميل للجمهور.
- **التنويه** (في صفحة العرض تحت الصور إن وجد vdo): يظهر "مشاهدة الفيديو (حجز موعد أولاً)" + نص ردع قوي: "حجز الموعد يُعتبر التزاماً. إلغاء متكرر أو عدم حضور قد يؤثر على صلاحية طلبات الفيديو المستقبلية."
- كل نقاط الدخول (تفاصيل العرض، مطابقة، تفاصيل طلب) تستخدم نفس الـ Sheet → يتم التحقق تلقائياً.

### §7.2 إعدادات طلبات الفيديو (يديرها المدير ونائب المدير فقط)
- في شاشة **إعدادات التطبيق** (`/admin/config`) تظهر خانتين جديدتين تحت قسم "🎥 طلبات الفيديو (خاصة)":
  1. `txts.videoRequestWhatsApp` ← **رقم الواتساب المخصص** لطلبات الفيديو (الرئيسي).
  2. `txts.videoRequestGroupLink` ← **رابط المجموعة الاحتياطي** (يُستخدم إذا تم حظر الرقم).
- يمكن تعديلها فقط من قبل:
  - المدير (role=6)
  - نائب المدير (role=5)
- المنطق في `BookAppointmentSheet`:
  - يفضل الرقم المخصص (`videoRequestWhatsApp`) → يفتح wa.me مع الرسالة المسبقة.
  - إذا فارغ → يستخدم رابط المجموعة.
  - آخر حل: الرابط القديم.
- هذا يضمن استمرارية الخدمة في حال حظر أي من الرقم أو المجموعة.

### §7.3 صفحات التواصل الاجتماعي + النشر التلقائي (2026-07-13)

#### أ. الروابط (قابلة للإدارة كاملاً)
- في `app_config.txts`:
  - `facebook`, `instagram`
  - `developerPhone`
  - `socialPages` (map لصفحات إضافية مثل tiktok)
- تظهر في **"عن التطبيق"** (settings) وتُدار من `/admin/config`.

#### ب. آلية النشر التلقائي (الكاملة)

**1. عند إضافة العرض (المستخدم)**
- تشيك بوكس **مفعّل تلقائياً** (يمكن إلغاؤه).
- يحفظ:
  - `i_soc = 1`
  - `socTxt` = قالب جاهز مولّد في `add_offer_screen._generateSocialPostText()`

**2. عند المراجعة (الإدارة) — شاشة offers_review**
- إذا `i_soc=1` → تظهر شارة زرقاء واضحة:
  > 📣 سيُنشر تلقائياً على فيسبوك + إنستغرام (بعد الموافقة)

**3. عند الضغط على "قبول" (اللحظة الحرجة)**
- يُستدعى `admin-offers` Edge → `admin_review_offer_internal`:
  - `sts = 2`, `i_pub = 1`
- **داخل Edge Function (admin-offers/index.ts)** يحدث التالي **تلقائياً**:
  - يفحص `i_soc == 1 && socTxt.length > 10`
  - يضبط `soc_pub = 1` (جاهز للنشر)
  - يمنح نقاط `pts.soc` (100 افتراضياً)
  - يسجل في `activity_log` (action=105)
- رسالة للإدارة: `✅ تم نشر العرض • 📣 تم تفعيل النشر التلقائي على فيسبوك وإنستغرام`

**قيم `soc_pub` (المعتمدة)**
| القيمة | المعنى |
|--------|--------|
| 0      | لم يُفعّل النشر الاجتماعي |
| 1      | مفعّل + جاهز للنشر (بعد الموافقة) |
| 2      | نُشر فعلياً على السوشيال (المرحلة 2) |

**المرحلة 1 (منفذة)**: فقط "جدولة + نقاط + سجل".
**المرحلة 2 (منفذة ومفعّلة تلقائياً منذ 2026-07-14)**: Edge Function `publish-to-social` + Carousel حتى 10 صور + زر يدوي كاحتياط + نشر تلقائي مفعّل افتراضياً `autoPublish=true` + حماية من التكرار عبر `social_publications`. يصبح `soc_pub=2` بعد نجاح Facebook وInstagram معاً. 
- عند الموافقة في `admin-offers` يتم تلقائياً: `soc_pub=1` → إن كان `autoPublish != false` ينشر فوراً عبر `publishOfferToSocial` → إذا نجح → `soc_pub=2` + سجل `activity_log` 106، إذا فشل → يبقى 1 في قائمة "جاهزة للنشر" + سجل 107.
- الصور تُنقّى إلى https فقط (حتى 10) وتُنشر كـ Feed Post بواحد أو Carousel.
- الحماية من التكرار عبر `claim_social_publication` و `social_publications` (حالة لكل منصة + post_id + محاولة + خطأ).
- التشغيل الفعلي يحتاج Meta Secrets/IDs وتطبيق Migration والنشر؛ راجع `SOCIAL_PUBLISH_SETUP_GUIDE_AR.md` و `SOCIAL_PUBLISH_PHASE2_2026-07-13.md`.
- الإعداد في `/admin/config` → مفتاح "النشر التلقائي فور قبول العرض" (افتراضي مفعّل).

#### ج. القالب المولّد (مثال)
```
🏠 عرض جديد على عقارات السويداء

📍 [العنوان]
[عقار/سيارة] [للبيع/للإيجار]
💰 السعر: ...
📌 المنطقة: ...

[الوصف]

للتفاصيل والحجز:
📱 تطبيق عقارات السويداء
#عقارات_السويداء #عروض_عقارية
```

**ملاحظات هامة**:
- النشر **لا يحدث فوراً** عند الإضافة (يجب موافقة الإدارة).
- المستخدم يرى التشيك بوكس فقط عند إضافة عرض.
- كل العروض التي لها `i_soc=1` تُعامل بنفس الطريقة (حتى لو أضيفت من الإدارة).
- لا يؤثر على ميزة الفيديو أو التحقق من الهاتف.

### امتداد القواعد لمسار التراشق (اقتراح وقت بديل) — 2026-07-02
`owner_respond_appointment` و `requester_counter_appointment` تُعيدان الآن **JSONB**
(بدل BOOLEAN) وتفرضان على أي `proposed_dt`:
1. **وقت مستقبلي** — وإلا `{success:false, error:'INVALID_APPOINTMENT_TIME'}`.
2. **قاعدة فارق الساعة على العرض** (مع استثناء الموعد الجاري تعديله نفسه)
   — وإلا `{success:false, error:'TIME_CONFLICT_ON_OFFER'}`.
3. **توفر مشرف** ضمن فارق الساعة (عبر `get_available_supervisor` الموحّدة):
   عند عدم التوفر → فشل مُدار `{success:false, error:'NO_SUPERVISOR_AVAILABLE', suggested_dt}`
   + إشعار للمقترِح بالبديل — **الإشعار يبقى محفوظاً** لأن الفشل يُعاد كقيمة
   لا كـ EXCEPTION (الـ EXCEPTION كانت تعمل rollback وتُفقِد الإشعار).
4. عند نجاح تغيير الوقت يُحدَّث `supervisor_uid` بالمشرف المتاح الجديد.
- فحص `avl` **غير مطبق عمداً** في التراشق (تقويم حر — حسب العقد الأصلي للتفاوض).
- الواجهة (`my_appointments_screen`) تعرض رسالة مخصصة لكل رمز خطأ مع الوقت البديل المقترح.
