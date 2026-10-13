# 🧪 ملف الاختبار الشامل — E2E Test Playbook
> **الغرض:** اختبار التطبيق كاملاً **كل دور بدوره** عن بُعد، بنفس منهجية جولة 2026-07-27 ليلة الإطلاق.
> يُستخدم مع «بروتوكول عمل الوكيل عن بُعد» في `DEVELOPMENT_GUIDELINES.md` — اقرأه أولاً.
> **ممنوع كتابة أسرار (توكنات/كلمات سر) في هذا الملف — تُطلب من المالك عند كل جلسة.**

---

## 1) الأدوار والجلسات

| الدور | role | الجلسة | الاستخدام |
|---|---|---|---|
| مجهول (anon) | — | مفتاح publishable فقط | بروبات التحصين والخصوصية (صفر كتابة) |
| مستخدم عادي تجريبي | 0 | `login_with_password` | إنشاء عروض/دفعات، كوتا، إيصالات |
| وسيط تجريبي | 1 | نفس الطريقة | كوتا الوسيط، عمولات |
| موظف/مشرف | 4–5 | نفس الطريقة | أدوات المكتب (مراجعة عروض…) |
| مدير (المالك مؤقتاً عند الاختبار) | 6 | نفس الطريقة | اعتماد/رفض، إعدادات، كل الأدوات |

**الحصول على جلسة** (أي دور):
```
POST {BASE}/functions/v1/user-account
apikey+Authorization: Bearer {ANON_KEY}
{"action":"login_with_password","identifier":"<من_المالك>","password":"<من_المالك>"}
→ result.staff_session.session_token (64 حرف) — تعيش بالذاكرة فقط
```
**الإلزام بعد كل جلسة اختبار:** `revoke_staff_session` بـ `user_uid`+`session_token` ثم تأكيد `INVALID_SESSION`.

**الثوابت:** BASE من `lib/core/constants/supabase_constants.dart` (supabaseUrl)، ANON_KEY = supabasePublishableKey (مكشوف بالتصميم — ليس سراً).

---

## 2) قواعد اللعب (قبل أي اختبار)

1. **صفر كتابة افتراضياً** — القيم الخربة تموت بالـ cast قبل الجسم (`uuid:"x"`).
2. **الكتابة الواعية فقط** على حسابات اختبار، بسبب موسوم 🧪، وبتنظيف فوري (اعتماد/رفض).
3. **ردود المعاملات دليل موثوق** — رد approve من داخل الـ RPC أقوى من أي قراءة لاحقة.
4. **البوش لا يُفحص عن بُعد** — سؤال واحد للمالك «وصل الإشعار؟» يغلقه.
5. **وثّق كل نتيجة بتاريخها** — سطر في `CURRENT_STATUS.md` آخر الجولة.
6. **الفحص الحي قبل الريبو دائماً** — الدامب `functions_dump.sql` محدّث بختم 2026-07-27 ويُقرأ قبل أي تخطيط، لكن الـ probes هي الفيصل.

---

## 3) مصفوفة الاختبارات — دوراً بدور

### 👤 anon (بدون جلسة) — أمن وخصوصية فقط
| # | الاختبار | الأمر | النجاح |
|---|---|---|---|
| A1 | تحصين RPCs المدفوعات | POST `/rest/v1/rpc/admin_reject_payment_internal` / `approve_payment_final` / `create_offer_internal` / `create_payment_internal` بقيم خربة | `42501` ×4 |
| A2 | تحصين helpers الثمانية | `app_assert_password/phone/price/text_len/username` + `app_clean_text` + `normalize_sy_phone` + `normalize_arabic_username` | `42501` ×8 |
| A3 | خصوصية البروفايل | `get_user_full_by_id` بـ uuid عشوائي | `42501` |
| A4 | خصوصية مدفوعات المستخدم | `user-account` action=`user_payments` بـ uid غريب بلا جلسة | `AUTH_TOKEN_REQUIRED` |
| A5 | حارس الإيدج الإدارية | `admin-payments` بلا جلسة | `ADMIN_SESSION_REQUIRED` |
| A6 | **السحب الشامل** | بروب كل دالة بوصل `functions_dump.sql` بقيم خربة؛ صنّف بجدول Evidence Classes من الدستور | الكل 42501 أو PGRST202(triggers/تواقيع أعيد تشكيلها) — صفر P0001/22P02 |
| A7 | سياسات التخزين | إدراج صورة 1×1 بـ `payment_proofs` (INSERT مسموح سياسياً للدفعات)، محاولة SELECT/DELETE لاحقاً | INSERT ينجح / قراءة ومسح يرفضان |

### 🙋 المستخدم العادي (role 0)
| # | الاختبار | النمط | النجاح |
|---|---|---|---|
| U1 | دخول + بروفايل | login ثم `get_full_profile` بجلسته | بياناته فقط |
| U2 | خصوصية عكسية | `user_payments` بدون جلسته بجلسته ✓ — وبلا جلسة ✗ | كما A4 |
| U3 | إنشاء دفعة باقة (كل قناة فعالة: sham_cash / syriatel_cash / balance) | `user-account` action=`create_payment` (tp=0, amt=price×rate حي من config, cur=1, proof بمفتاح موجود بالباكيت, ref موسوم) | نشأت pending — وتفشل المكررة لنفس الباقة (PENDING_PAYMENT_EXISTS) |
| U4 | دفعة ممولة | tp=1 + meta{offer_id لعرضه, weeks∈1..4} | pending؛ وأسبوع غير 1..4 يرفض INVALID_FEATURED_AD_META |
| U5 | كوتا العروض | بعد اعتماد باقة (انظر M-Admin): أنشئ عروضاً حتى السقف | QUOTA_EXCEEDED عند السقف الفعلي = pkg.o + xoff |
| U6 | قراءة مدفوعاته | `user_payments` | يظهر السبب عند المرفوضة من meta.reject_reason |
| U7 | جلسته تموت | بعد revoke: أي action | INVALID_SESSION |

### 🧑‍💼 الوسيط (role 1) — اختياري الجولة القادمة
| # | الاختبار | النجاح |
|---|---|---|
| B1 | كوتا الوسيط الافتراضية (5) بلا باقة | create_offer ×6 → السادس يرفض |
| B2 | broker_offers / broker_deals عبر user-offers | ترجع عروضه وصفقاته فقط |

### 👑 المدير (role 6) — قلب دورة المدفوعات
| # | الاختبار | النمط | النجاح (توقع حسابي دقيق) |
|---|---|---|---|
| M1 | قائمة الدفعات | `admin-payments` action=list | يرى المعلقة مع meta |
| M2 | **رفض بسبب** | reject + reason عربية | sts=2, appr_by=uid المدير, meta:{reject_reason,reject_ts}؛ إشعار للمستخدم (يُسأل المالك: وصل؟) |
| M3 | **اعتماد باقة جديدة** | approve لدفعة tp=0 pkg=1 | {success, type:package, pkg:1, quota= pkg.o(التكوين الحي), until= اليوم+d يوم, stacked:false, upgraded:false} |
| M4 | **التراكم — ترقية** | باقة أعلى لنفس المستخدم وهي فعالة | {pkg: الأعلى, quota= o_الجديد + o_القديم, until= نهاية_القديم + d_الجديد, upgraded:true, stacked:true} |
| M5 | **التراكم — تجديد/أدنى** | نفس/أدنى وهي فعالة | quota يزيد بـ o_المشترى، الأساس GREATEST، الأيام تتراكم فوق المتبقي |
| M6 | **اعتماد ممولة** | approve tp=1 | {type:featured, until= max(NOW,fms_end)+7×weeks} ثم قراءة العرض: fms_end مطابق |
| M7 | دالة رفض/اعتماد غير موجودة بلا توقيعها الصحيح | توقيع قديم (2 باراميتر) | PGRST202 لا غيره (الـ overload القديم ميت) |

### 📱 يُختبر على الجهاز فقط (لا يُفحص عن بُعد)
| الميزة | كيف | النجاح |
|---|---|---|
| تشيكبوكس فيديو العرض | إضافة عرض ← علّم «أرفق فيديو» ← أنشئ | واتساب ينفتح مع «رقم العرض الخاص بك <num>» تلقائياً |
| بوش الرفض/الاعتماد | اعتماد سيرفري عادي | إشعار يصل الجهاز المسجل عليه الحساب |
| overflow الشاشات الصغيرة (TECNO KI7) | login/OTP/packages | بلا RenderFlex overflow |
| أسعار SYP الحمراء | الباقات/الممولة بعد فتحة تطبيق جديدة | فضي=1500، ذهبي=3750 ل.س (rate=150 حي) |

---

## 4) السحب الأمني الشامل (دورة A6) — بروتوكول جاهز

1. استخرج `name(argtypes)` لكل `CREATE OR REPLACE FUNCTION public.` من `supabase/functions_dump.sql`.
2. **عايِر** أولاً على 3 معروفة التحصين (admin_reject_payment_internal 3-arg، approve_payment_final، create_offer_internal) ← لازم 42501 وإلا منهجيتك مكسورة (توقيع/نقل).
3. بروب لكل دالة: uuid=`"x"`، text=`""`، int=`0`، jsonb=`{}`، bool=`false`.
4. صنّف: 42501=✅ | PGRST202=triggers/تواقيع تغيرت (قارن مع setup.sql) | P0001/22P02/scalar-return = **تسريب** ← تقرير للمالك + ثلاثي التحصين بعد موافقته.
5. سجّل النتائج بتاريخها في CURRENT_STATUS.md.

**المرجعية 2026-07-27:** 173 دالة؛ 147 محصنة + 17 triggers + 8 helpers كانت مفتوحة (قُفلت لاحقاً نفس الليلة) + واحدة (admin_reject_payment_internal الجديدة) تسربت عبر PUBLIC وأُقفلت. **اليوم: الكل أخضر.**

---

## 5) سجل الأدلة المرجعية (نتائج جولة الإطلاق 2026-07-27 — توقعات الريغرشن)

| الدليل الحي | القيمة |
|---|---|
| اعتماد فضي | quota=15 (=pkg.1.o)، until=+45d (=pkg.1.d)، stacked/upgraded=false |
| تراكم ذهبي فوق فضي فعالة | pkg=2، **quota=55** (40+15 إلى xoff)، until= نهاية الفضي +60d، stacked=true |
| ممولة أسبوع | until=+7d، fms_end بالعرض مطابق للرد (GREATEST) |
| رفض | sts=2 + meta.reject_reason/reject_ts + بوش **وصل فعلاً للجهاز** ✅ |
| syriatel_cash بعد إصلاح payments_channel_check | create ينجح (كان يفشل بالقيد) |
| الجلسات | revoke ← INVALID_SESSION |
| معدل الصرف الحي | usdToSypRate=150 (فضي 1500 / ذهبي 3750) |
| خطوات ممولة fmsp | w1=500 w2=950 w3=1350 w4=1800 ل.س |

### جولة مسائية بنفس اليوم — نقاط/حجز (أُضيفت بعد إصلاحات `07bef3b`..`02bd37b`)

| الدليل الحي | القيمة |
|---|---|
| سكب نقاط `manual_add` (دور 0) | **403 EVENT_NOT_ALLOWED** — ممنوع سيرفرياً |
| سحب `addO` لنفسي (دور 0) | **403 ADMIN_ONLY_EVENT** |
| like بلا offer_id | **400 OFFER_ID_REQUIRED** |
| حدث مجهول | 403 EVENT_NOT_ALLOWED |
| حد الإعجابات اليومي (وصل 10) | رد نظيف `{error: DAILY_LIMIT_REACHED, limit: 10}` — بلا تغليف success (رسالة «النقاط ترجع بكرا 🌙») |
| **حجز موعد متكامل عن بُعد** | book ← `appointment_id` + **supervisor مُسند تلقائياً** (supertester) + list يعرضه + `get_booked_slots` يُظهر "10:00" محجوزة + cancel ينظّف ✅ |
| avl العروض بعد اللاصقة | 3/3 عروض `{"any": true}` — صفر عرض بلا مواعيد |

### ⚠️ اكتشاف مفتوح (بانتظار قرار المالك) — مُغلق
- **قناة تعديل/حذف العرض ميتة خادمياً (قديم، مو من إصلاحات الليلة):** `OfferProvider.updateOffer()` يكتب PATCH مباشر بـ anon والسيرفر يرفض `42501` بعد سحب RLS الوقائي — تعديل العرض وحذفه من شاشة المستخدم لا يُحفظان. الإصلاح المقترح: action `update_offer` بإيدج `user-offers` (تحقق جلسة + ملكية + whitelist حقول، بلا SQL).
  **✅ أُغلق (2026-07-27):** أكشنز `update_offer`/`delete_offer` بالإيدج + تريغر منحة `addO` — ريغرشن متوقع بعد النشر: تعديل عرض مملوك ينجح ويعيده للمراجعة (sts=1)، تعديل عرض غريب ⇒ `NOT_OFFER_OWNER` 403، بلا جلسة ⇒ 401؛ اعتماد عرض يمنح صاحبه `pts.addO` مرة واحدة (حد 3/يوم).

---

## 6) نهاية كل جولة اختبار (Checklist)

- [ ] كل جلسة أنشأتها = مُلغاة ومُثبت `INVALID_SESSION`
- [ ] لا pending دفعات اعتبارية متروكة (اعتمد/ارفض الكل)
- [ ] توثيق CURRENT_STATUS.md بتاريخ اليوم
- [ ] الريبو = الحقيقة (setup.sql/migrations محدثة، push ناجح، ls-remote مطابق)
- [ ] اللينتر rerun والتنبيهات الجديدة = صفر (أو موثقة بقرار)
- [ ] تذكير المالك بحذف توكنات GitHub/الجلسات اليتيمة
