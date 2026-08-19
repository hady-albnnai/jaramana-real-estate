# ⚛️ التحليل الكمّي الكامل — فلو المحادثة القانونية والتجديد (مستوى الكود)

> تحليل على مستوى الصفر من الكود: كل انتقال حالة، كل نقطة دخول، كل احتمال —
> بالمرجع الدقيق (ملف:سطر). التاريخ: 2026-08-19. الحالة: كود الريبو الحالي.

---

## 0. الكيانات والمصدر الحقيقي للحقيقة

| الكيان | الجدول | حالاته | من يكتبه |
|---|---|---|---|
| الاستشارة | `legal_consultations` | `status` 0 بانتظار · 1 مؤكدة · 2 مكتملة/منتهية · 3 ملغاة · 4 مرفوضة · 5 بانتظار بيانات | `accept_phone_consultation_v2` · `join_chat_session_v2` · `sync/advance` · v3 |
| النية (intent) | `consultation_intents` | `draft` → `payment_pending` → `materialized` / `failed` / `cancelled` / `payment_needs_slot` | `prepare_consultation_intent_v2` · `create_consultation_payment_v2` · v3/v4/v5 · `admin_reverse_payment_v2` |
| الدفعة | `payments` | `sts` 0 قيد المراجعة · 1 معتمدة · 2 مرفوضة · 3 معكوسة | `create_consultation_payment_v2` · `approve_payment_final_v5→v4→v3` · `admin_reverse_payment_v2` |
| الجلسة | `consultation_chat_sessions` | `ready` → `join_window` → `active` → `ended` (+`reversed`) | v3 (renewal) · `accept_phone_consultation_v2` (initial) · `lawyer_ready_chat_session_v2` · `join_chat_session_v2` · `sync/advance` · `admin_reverse_payment_v2` |
| الرسائل | `consultation_chats` | — | `send_chat_message` (بحراسة) |
| push الاحتياطي | `consultation_event_outbox` | `pending` → `sent`/`failed` (كرون كل دقيقة) | v3 · `lawyer_ready` · `join` · التريغر |

**القاعدة الذهبية المستخرجة من الكود:** في V2، **الجلسة هي مصدر الحقيقة للوقت**
(لا `chat_started_at`/`chat_duration_minutes` في جدول الاستشارة — فهما حقول
موروثة تحدّثهما `join_chat_session_v2` و`advance/sync` عند بدء/انتهاء الجلسة فقط).

---

## 1. آلة الحالات الكاملة (من الكود — `2026_08_16_consultation_v2_sessions.sql`)

```
                    (v3: renewal ready)      (accept: initial ready)
                          │                         │
                          ▼                         ▼
   ┌──────────┐  lawyer_ready  ┌──────────────┐  انضمام/مهلة  ┌────────┐  انتهاء  ┌───────┐
   │  ready   │ ─────────────▶ │ join_window  │ ────────────▶ │ active │ ───────▶ │ ended │
   └──────────┘   (دقيقتان)    └──────────────┘   (عند الدخول  └────────┘  (ends_at └───────┘
        ▲                                        أو grace)              أو sync)
        │                                            │
        └──────────── admin_reverse (ready→reversed) ┘
```

**الانتقالات (بالدوال الدقيقة):**

| من | إلى | الدالة | الشرط | الأثر الجانبي |
|---|---|---|---|---|
| — | `ready` (initial) | `accept_phone_consultation_v2` (`v2_atomic_accept.sql:20`) | محامٍ يقبل status 0→1 هاتفية | إشعار المستخدم «✅ قبل المحامي» |
| — | `ready` (renewal) | `approve_payment_final_v3` (`v2_materialization.sql:118-131`) | اعتماد دفعة `phone_renew` | رسالة system + `renew_count+1` + إشعار محامٍ (outbox) |
| `ready` | `join_window` | `lawyer_ready_chat_session_v2` (`v2_sessions.sql:37-62`) | المحامي «أنا جاهز» | إشعار+push للمستخدم «افتح خلال دقيقتين»؛ `join_deadline=+2min`؛ `starts_at=deadline` |
| `join_window` | `active` | `join_chat_session_v2` (`v2_sessions.sql:79-111`) | المستخدم يدخل قبل deadline | `starts_at=now`، عداد كامل؛ إشعار محامٍ «انضم العميل» |
| `join_window` | `active` | `advance_chat_sessions_v2` (كرون/دقيقة) أو `sync_chat_session_v2` | انقضت الدقيقتان | `starts_at=deadline` (تبدأ تلقائياً)؛ إشعار «بدأ تلقائياً» |
| `active` | `ended` | `advance_chat_sessions_v2` / `sync_chat_session_v2` | `ends_at ≤ now` | `legal_consultations.status=2`؛ إشعار «انتهى الوقت» |
| `ready` | `reversed` | `admin_reverse_payment_v2` (`v2_payment_compensation.sql:99-108`) | إلغاء الاعتماد وجلسة الـ renewal لم تُستهلك | `renew_count-1` |
| `ended` | `ready` (جديدة) | v3 (أعلاه) | دفع تجديد جديد معتمد | دورة جديدة |

**حارس لا يوجد في V2 (ثغرة 8):** `prepare_consultation_intent_v2` (phone_new) **بلا**
فحص `OPEN_CONSULTATION_EXISTS` — الحارس موجود فقط في `create_legal_consultation_internal`
القديمة (`2026_08_16_consultation_hardening.sql:71-77`). أي: في مسار V2 يمكن نظرياً
إنشاء استشارة هاتفية ثانية بينما الأولى نشطة (الثغرة قائمة مسبقاً — خارج التجديد).

---

## 2. نقاط الدخول (من الواجهة) — كل زر ومساره

### أ) من داخل المحادثة (`consultation_chat_screen.dart`)
| الزر/الحدث | الكود | النتيجة |
|---|---|---|
| فتح الشاشة | `initState:83` → `_loadV2Session()` ثم `_loadMessages()` | جلسة V2 تُحمَّل أولاً (م13) |
| استطلاع 20 ث | `_renewalPollTimer:110` | يشمل `pending_renewal` أو `_timeUp` أو `ready` — يلتقط الاعتماد/الاستئناف |
| `join_window` (مستخدم) | `_loadV2Session:168-177` | **انضمام تلقائي** → active |
| شريط سفلي | `build:895-905` | ready→«بانتظار المحامي» · join_window→«مهلة» · `_timeUp`+مستخدم→ شريط جدد/قيد المراجعة · وإلا input |
| زر «تجديد» | `_renewChat:513` → `context.push('/legal/consultations?flow=phone_renew&parent=$id')` | ينقل لشاشة الحجز (دفع) |
| حوار الخيارات | `_showEndOptions:478` (تجديد/تحويل/لاحقاً/تقييم) | يظهر **مرة واحدة** عند `ended` و**لا يظهر** إذا `pending_renewal` (إصلاح 2026-08-19) |
| `_startTimer` | `:236` | مع V2: `_timeUp` من الجلسة فقط — لا تنبيهات على جلسات ready (إصلاح «3 دقائق» الخاطئ) |

### ب) من شاشة الحجز (`legal_consultation_booking_screen.dart`)
| الحالة | البطاقة/الزر | الكود | النتيجة |
|---|---|---|---|
| دفعة معلّقة (renewal) | «⏳ دفعتك قيد المراجعة» + «فتح المحادثة المرتبطة» + «تحديث الحالة» | `_pendingBannerFor:1129` · `_buildSuccess:2366-2396` | يستطيع قراءة رسائل المحادثة أثناء الانتظار |
| اعتماد أثناء الانتظار | SYNC-002 | `_loadAll:352-388` | renewal → **يفتح المحادثة تلقائياً** (`/legal/chat/$continueChat`) · جديدة → نموذج الموضوع |
| دفعة معتمدة (renewal) | «تم تأكيد دفعتك — المحادثة جاهزة» + زر «فتح المحادثة» | `_approvedCard:1150-1183` | يدخل المحادثة (ready → بانتظار المحامي) |
| دفعة معتمدة (جديدة) | «إرسال الطلب للمحامي» | `_approvedCard` + `_hasApprovedPaymentFor:424-433` | **تستثني `continue_chat`** (إصلاح «خلل الاتصال») |
| المحادثات السابقة | `_buildPreviousChats:1600-1680` | `has_live_session` (من الإيدج) → «متابعة المحادثة» تفتح مباشرة · وإلا «دفع تجديد» مع `_guardPending` |
| دخول `phone_renew` من الشات | `_initialize:122-130` | `_guardPending(0)` أولاً (إصلاح الدفعة المكررة) ثم شاشة الدفع |
| إلغاء/رجوع | `_returnToCurrentState:810-837` | محادثة مفتوحة → يدخلها · غيرها → الرئيسية بالبطاقات الفعلية |

### ج) من جهة المحامي (`lawyer_dashboard_screen.dart`)
| الحالة | الزر | الكود | النتيجة |
|---|---|---|---|
| `session_status='ready'` أو بلا جلسة وبلا محادثة | «أنا جاهز — إشعار العميل» | `:1443` → `_startChat` → V2 `lawyer_ready_chat_session_v2` | join_window + إشعار المستخدم |
| `session_status='join_window'` | «فتح المحادثة — بانتظار العميل» | `:1446` | يدخل الشات (يُظهر مهلة الانضمام) |
| `session_status='active'` | «فتح المحادثة» + «تمديد 5 دقائق» (مرة) | `:1448-1463` | عداد جارٍ + تمديد مجاني |
| استشارة جديدة (status 0) | «قبول القضية» | `:1380` → `accept_phone_consultation_v2` | status 1 + جلسة ready |

---

## 3. التتبع الكامل لسيناريو التجديد (كل خطوة + المرجع)

```
[1] انتهت الجلسة: advance/sync → session='ended', consultation.status=2
    → في الشات: _timeUp=true (من _loadV2Session:213) → شريط «جدد» (إن لم تكن
      دفعة معلّقة) + حوار الخيارات مرة واحدة
[2] المستخدم يضغط «تجديد» → chat:513 → booking flow=phone_renew&parent=id
[3] _initialize:122 → _guardPending(0): إن كانت دفعة معلّقة → screen6 (قيد
    المراجعة) ويمنع الدفعة المكررة ✅ (إصلاح جديد)
[4] شاشة الدفع (screen5) → _pay → _payV2:557 →
    prepare_consultation_intent_v2(flow='phone_renew', parent=id):
      يتحقق: المحادثة ملكه + هاتفية + lawyer_uid موجود +
      chat_started_at ليس null + <7 أيام (v2_transactions.sql:105-108)
      → intent 'draft', quoted=renew price, lawyer=parent.lawyer
    → create_consultation_payment_v2: payments(tp=2, sts=0,
      meta.continue_chat=parent.id) + intent='payment_pending'
[5] شاشة 6 «⏳ قيد المراجعة» مع زر «فتح المحادثة المرتبطة» + استطلاع 20 ث
    (booking screen _pendingTimer:105) + الشات الخلفي يستطلع أيضاً
[6] الإدارة توافق: admin-payments → approve_payment_final_v5 → v4 → v3
    (phone_renew branch, v2_materialization.sql:115-131):
      • يتحقق: intent payment_pending + parent موجود ومالكه صحيح
        + v_parent.lawyer_uid = intent.lawyer (وإلا CONSULTATION_OWNER_MISMATCH)
      • ينشئ session 'renewal' ready (ordinal+1, payment_id, duration=config)
      • renew_count+1 · رسالة system «تم اعتماد التجديد — X دقيقة»
      • إشعار محامٍ (outbox 'renew-ready') + تحديث active_tasks
      • payments.sts=1 · intent='materialized'
    التريغر trg_consultation_payment_v2 (2026_08_19):
      • إشعار المستخدم «✅ تم اعتماد تجديد المحادثة» ref_id=parent.id
        (إصلاح ref — كان payment_id) + push فوري
[7] انعكاس على الواجهة (حسب مكان المستخدم):
    • على شاشة 6 → SYNC-002 يفتح /legal/chat/$parent (إصلاح)
    • على الرئيسية → _approvedCard (renewal) «فتح المحادثة» (إصلاح)
    • داخل الشات → poll يلتقط session='ready' → «بانتظار استئناف المحامي»
    • في المحادثات السابقة → has_live_session=true → «متابعة المحادثة» (إصلاح)
[8] المحامي يستلم «🔄 تجديد مدفوع جاهز» → يضغط «أنا جاهز» (lawyer_dashboard:1443)
    → lawyer_ready_chat_session_v2 → join_window + إشعار المستخدم
[9] المستخدم في الشات → poll/بث session_changed → _loadV2Session يرى join_window
    → انضمام تلقائي (join_chat_session_v2) → active:
      consultation.status=1, chat_started_at=now, duration=جديد → عداد 15 دقيقة كامل
      (أو إن لم يدخل: advance بعد دقيقتين → active تلقائياً بنفس المدة)
[10] انتهاء المدة → ended → يعود للخطوة [1]
```

---

## 4. كل الاحتمالات الجانبية (تحقق سطراً بسطر)

| # | السيناريو | السلوك الفعلي في الكود | النتيجة |
|---|---|---|---|
| 1 | دفع مكرر أثناء دفعة معلّقة | حارس واجهة `_guardPending` في كل المسارات + `_initialize` (جديد) | ✅ ممنوع |
| 2 | دفعة مرفوضة | إشعار + `_rejectedPaymentCard` + `prepare_rejected_payment_retry_v2` → `retry_consultation_payment_v2` (نفس intent) | ✅ |
| 3 | محادثة أقدم من 7 أيام | `prepare...:105-108` → `CHAT_EXPIRED_7DAYS` | ✅ ممنوع |
| 4 | المحامي غير متاح عند الاعتماد | v3 `phone_renew` → `ASSIGNED_LAWYER_UNAVAILABLE` → فشل الاعتماد (الدفعة تبقى sts=0، والإدارة تعكسها يدوياً) | ⚠️ ثغرة (7) |
| 5 | عكس الاعتماد | جلسة ready→reversed + renew_count-1 · إن استُهلكت → رفض | ⚠️ الشات يعرض input لـ reversed (ثغرة 6) |
| 6 | المستخدم لم يدخل خلال الدقيقتين | advance → active تلقائياً من deadline + إشعار | ✅ |
| 7 | المحامي لم يضغط «أنا جاهز» | تبقى ready بلا مهلة، لا عداد — المستخدم يرى «بانتظار» | ✅ مقصود |
| 8 | اعتماد بعد مرور 7 أيام (تأخر الإدارة) | v3 لا يعيد فحص الـ 7 أيام → ينشئ جلسة رغم الانتهاء → الرسائل ترفض لاحقاً | ⚠️ ثغرة (9) |
| 9 | استشارة جديدة + دفعة تجديد معتمدة | `_hasApprovedPaymentFor` يستثني continue_chat (إصلاح) → لا خلط | ✅ |
| 10 | دفع تجديد من «المحادثات السابقة» لنشطة | `has_live_session` → فتح مباشر بلا دفع | ✅ |
| 11 | انقطاع Realtime | الاستطلاعات (20-45 ث) تغطي كل شاشة مفتوحة | ✅ |
| 12 | فشل push للطرفين | outbox (دقيقة) يعيد المحاولة ×8 | ✅ |
| 13 | `_timeUp` محلي (العداد) يسبق sync | يظهر شريط جدد لحظياً ثم يصحّح sync خلال دقيقة | ✅ غير ضار |
| 14 | رسائل أثناء الانتظار | ممنوعة — الشريط ready بلا input؛ والسيرفر يحرس status | ✅ |

---

## 5. الثغرات المتبقية (بصراحة كاملة — مرتبة بالخطورة)

| # | الخطورة | الوصف | الموضع | الإصلاح المقترح |
|---|---|---|---|---|
| 6 | 🟠 متوسطة | جلسة `reversed` (عكس اعتماد نادر) تعرض للشات input بدل شريط «انتهت» | `consultation_chat_screen.dart:213` (`_timeUp = status=='ended'`) | اعتبار `reversed` كـ ended |
| 7 | 🟠 متوسطة | فشل الاعتماد إذا أصبح المحامي غير نشط (`ASSIGNED_LAWYER_UNAVAILABLE`) → دفعة معلّقة بلا مسار أوتوماتيكي | v3 (`v2_materialization.sql:96-98`) | السماح بإعادة إسناد لـ renewal أو تحويل الدفعة تلقائياً |
| 8 | 🟠 متوسطة (سابقة) | V2 phone_new بلا حارس `OPEN_CONSULTATION_EXISTS` | `prepare_consultation_intent_v2` | إضافة الحارس للـ prepare |
| 9 | 🟡 منخفضة | لا إعادة فحص 7 أيام عند الاعتماد | v3 phone_renew | فحص `now() ≤ chat_started_at+7d` قبل الإنشاء |
| 10 | 🟡 منخفضة | SYNC-002 يدفع `/legal/chat` فوق شاشات موجودة (مكدس مزدوج) | `booking:373-375` | `context.go` بدل push عند الخروج من الشات |

---

## 6. ما غُطي ببلاغات المالك (تتبع بلاغ → إصلاح → موضع)

| بلاغ المالك | السبب الجذري (من الكود) | الإصلاح | الموضع |
|---|---|---|---|
| حوار خيارات يتكرر + «3 دقائق» خاطئ | `_startTimer` كان يضبط `_timeUp` من العداد لا الجلسة | جلسة V2 أولاً + `_timeUp` من الجلسة | `chat:236-260` |
| «قيد المراجعة» بلا المحادثة المرتبطة ولا تحديث | `_resetWizard` كان يصفّر + لا زر | «تحديث الحالة» بلا تصفير + «فتح المحادثة المرتبطة» | `booking:2366-2396` |
| بعد الاعتماد يفتح «استشارة جديدة» ويفشل | SYNC-002 يرسل الجميع للشاشة 4 + `_hasApprovedPaymentFor` يمرر renewal | renewal → فتح المحادثة مباشرة + استثناء continue_chat | `booking:352-388, 424-433` |
| «متابعة → دفع الألف» رغم القبول | الاعتماد على `chat_duration` القديم (لا يمدّده V2) | `has_live_session` من الإيدج + فتح مباشر | `legal-actions:list_my_consultations` · `booking:1600-1680` |
| إشعار «تم اعتماد التجديد» لا يفتح شيئاً | ref=payment_id + حارس الدور | ref=parent + سماح المستخدم | `2026_08_19_consultation_renewal_session.sql` · `notification_router.dart:50` |
| ازدواج محتمل في إشعار المحامي | تكرار منطق v3 في تريغر (نسخة أولى) | حذف التكرار (الإصلاح 2026-08-19) | `2026_08_19_consultation_renewal_session.sql` |

---

## 7. الخلاصة

- **الآلة الأساسية سليمة ومكتملة:** كل انتقال حالة مغطى، وكل نقطة دخول تربط
  بالحالة الصحيحة بعد إصلاحات 2026-08-19.
- **4 ثغرات متبقية** (6-9) كلها **حالات نادرة/طرفية** لا تمس المسار اليومي،
  وموثقة مع إصلاح مقترح جاهز للتنفيذ عند طلبك.
- **شرط النشر:** كل إصلاحات الواجهة مرفوعة؛ السيرفر (`2026_08_19_consultation_renewal_session.sql`
  + `legal-actions` + `admin-dashboard`) ينتظر النشر — بدونها يبقى السلوك القديم.
