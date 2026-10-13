# التحليل ما دون الذري والكمومي لنظام الاستشارة القانونية

**التاريخ:** 2026-08-16 — Asia/Damascus  
**النطاق:** تحليل فقط؛ لم يُعدَّل الكود أو السيرفر ضمن هذه الجولة.  
**مصدر الحقيقة:** استعلامات حية + الكود الحالي عند `c31db3f` + الدوال المنشورة.

---

## 1. الحكم التنفيذي

التصميم المتفق عليه قابل للتنفيذ، لكن لا يجوز بناؤه كتعديلات متفرقة على الحقول الحالية. يجب تقديمه كنظام معاملات مترابط خلف Feature Flag، لأن خمسة أنظمة تتقاطع عند كل خطوة:

1. الدفع واعتماده وعكسه.
2. اختيار المحامي وجدول توفره.
3. حجز الوقت ومنع السباق.
4. جلسات المحادثة ومهلة الانضمام.
5. الإشعارات والتنقل والواجهات القديمة.

السبب الحالي لرسالة «لا توجد مواعيد» مثبت: تعارض توقيعي `pick_next_lawyer` يُدفن كقائمة فارغة. المحامي الأول فعّال، وجدوله صحيح، والدالة المباشرة أعادت أكثر من 50 موعداً خلال 14 يوماً، بينما Edge أعاد `success=true, slots=[]`.

---

## 2. الحقائق الحية المثبتة

### المحامي الأول

- `role=7`, `sts=0`, `i_del=0`, `is_active=true`.
- `active_tasks_count=0`.
- الدوام: الأحد–الخميس، 09:00–17:00.
- لا مواعيد مستقبلية متعارضة حالياً.
- أول موعد حي وقت الفحص: 2026-08-16 الساعة 16:00 بتوقيت دمشق.

### المواعيد

- `appointments` لا يملك قيد UNIQUE أو EXCLUDE يمنع تداخل مواعيد المحامي.
- الحماية الحالية هي «اقرأ ثم اكتب»؛ مستخدمان متزامنان قد يجتازان الفحص نفسه.
- لا يوجد عمود نوع للموعد.
- كل الصفوف الحية الحالية مواعيد عروض؛ لا موعد قانونياً حياً وقت الفحص.

### الدفع

- `payments.tp=2` يغطي الهاتفية والحضورية والتجديد.
- `meta.continue_chat` يميز التجديد، لكن لا FK حقيقية إلى الاستشارة.
- لا يوجد ارتباط حقيقي بين الدفعة ومسودة طلب أو حجز موعد.
- السعر خادمي، لكن توجد fallbacks ثابتة 500/2000/15 في SQL وEdge.
- `admin_reverse_payment` لا يعكس أثر الاستشارة (`tp=2`)؛ يتركها للمعالجة اليدوية.

### التخزين

- `payment_proofs`: خاص، حد 10MB، أنواع محددة.
- `consultation_files`: خاص اسماً، لكن بلا حد حجم أو MIME.
- سياسة `consultation_files_select` تسمح لأي `authenticated` بقراءة كل الباكيت، لا المشاركين فقط.
- تطبيق الهاتف يستخدم staff session لا Supabase Auth، لذلك القراءة العملية تمر عبر Edge، لكن السياسة تبقى تسريباً لأي حساب Auth حقيقي.

### الجدولة

- تذكيرات المواعيد كل 15 دقيقة.
- صيانة الاستشارات يومياً 03:30.
- صيانة المواعيد يومياً 03:40.
- إغلاق الهاتفية الحالية كل دقيقة.
- الجدولان اليومي والدقيقة يحملان منطقين مختلفين لمعنى انتهاء الاستشارة.

---

## 3. سجل العيوب المتشعبة

### Q-001 — تعارض توقيع اختيار المحامي (حرج)
يوجد:
- `pick_next_lawyer(uuid[])`
- `pick_next_lawyer(uuid[], boolean default false)`

استدعاء باراميتر واحد ملتبس. يتأثر به:
- جلب مواعيد الحضورية.
- إعادة الإسناد بعد اعتذار المحامي.
- أي مستدعٍ قديم في SQL.

**المطلوب:** توقيع واحد، وتحديث كل المستدعين قبل حذف القديم.

### Q-002 — دفن خطأ اختيار المحامي (حرج)
Edge يهمل `error` من RPC ثم يعيد نجاحاً بقائمة فارغة. Provider يبتلع الخطأ أيضاً. يجب فصل:
- فشل تقني.
- لا محامي.
- لا جدول.
- كل المواعيد محجوزة.

### Q-003 — المحامي المعروض ليس مربوطاً بالموعد (حرج)
الشاشة تجلب سلوت محامٍ، لكن الحجز يعيد اختيار المحامي لاحقاً. لا token أو hold يربط الاثنين.

### Q-004 — سباق الحجز (حرج)
لا قيد قاعدة يمنع تداخل وقت محامٍ. فحص availability ثم INSERT ليس ذرياً.

### Q-005 — إشعارات المواعيد القانونية مضللة (حرج)
INSERT في `appointments` يطلق `trg_appointment_created` الذي يقول:
- «طلب معاينة جديد».
- «صاحب العرض».
- `act=appointment`.

ثم legal-actions يرسل إشعاراً قانونياً إضافياً؛ النتيجة تكرار ونصوص عقارية على جلسة قانونية.

### Q-006 — الموعد القانوني يُصنف تصويراً في Flutter (حرج)
`AppointmentModel.isPhotography` يساوي true عند غياب `off_id`. الموعد القانوني بلا عرض، فيظهر كبطاقة تصوير وتُخفى/تتغير أزراره وحالاته.

### Q-007 — الموعد المختار يعيش في ذاكرة الشاشة فقط (حرج)
`_selectedSlot` لا يُخزن في الدفعة أو مسودة خادمية. إغلاق التطبيق أثناء المراجعة يفقده.

### Q-008 — التحويل الحضوري يحدث قبل الدفع (حرج)
`convert_to_onsite` ينشئ appointment ويغير الهاتفية إلى حضورية قبل تحصيل الفرق، مخالفاً للتصميم المالي والتاريخي.

### Q-009 — الهاتفية الأصلية تُشوّه عند التحويل (مرتفع)
يجب إنشاء حضورية ابنة عبر `parent_consultation_id` لا تغيير الأصل.

### Q-010 — اعتماد التجديد يبدأ الوقت دون انضمام (حرج)
الدالة الحالية تزيد المدة على الخط الزمني القديم فور اعتماد الدفع. المطلوب جلسة جاهزة لا تبدأ حتى استعداد المحامي وانضمام المستخدم/انتهاء دقيقتين.

### Q-011 — لا تاريخ جلسات (حرج)
حقول `chat_started_at/duration/extended/renew_count` لا تمثل عدة جلسات، ولا تسجل سبب البداية أو الانضمام.

### Q-012 — عكس دفعة الاستشارة بلا تعويض (حرج)
عكس tp=2 لا يغلق جلسة جاهزة ولا يلغي موعداً ولا يحرر حجزاً ولا يمنح رصيداً.

### Q-013 — الحجز المؤقت داخل appointments غير صالح (حرج)
لأن INSERT يطلق إشعارات وإحصاءات عامة. يجب فصل reservation عن الموعد النهائي.

### Q-014 — لا FK للموعد القانوني (مرتفع)
`legal_consultations.appointment_id` ليس عليه FK حسب القيود الحية. يمكن أن يشير لموعد محذوف/وهمي.

### Q-015 — أرصدة الاستشارة بلا FKs (مرتفع)
`consultation_credits` لا يظهر له FK حي إلى المستخدم/الاستشارة/الإدارة، ما يسمح بأيتام.

### Q-016 — RLS قديمة لا تطابق staff session (مرتفع)
سياسات appointments/payments/reports تعتمد `auth.uid()`، بينما مستخدم الهاتف يمر عبر Edge. يجب سحب INSERT/UPDATE المباشر غير المستخدم، لا ترك مسارين أمنيين.

### Q-017 — باكيت الاستشارة واسع (حرج أمني)
أي حساب Supabase Auth يستطيع SELECT كل ملفات الاستشارات. المطلوب service_role فقط، وحد حجم/MIME.

### Q-018 — انتهاء الجلسة له مصدران (مرتفع)
cron الدقيقة يغلق عند نهاية الدقائق، والصيانة اليومية تتحدث عن 7 أيام. يجب فصل:
- نهاية session.
- صلاحية القضية للتجديد 7 أيام.
- الإغلاق النهائي.

### Q-019 — التقييم مرتبط بالحالة العامة (مرتفع)
إذا كانت القضية قابلة للتجديد/التحويل بعد انتهاء session، فلا ينبغي اعتبار كل نهاية وقت إغلاقاً نهائياً. يلزم `decision_pending` أو اشتقاق حالة واجهة من الجلسة.

### Q-020 — عدم تطابق المنطقة الزمنية (متوسط)
السيرفر يحسب دمشق، لكن Flutter يستخدم `.toLocal()`؛ جهاز بمنطقة أخرى يعرض وقتاً مختلفاً. يجب إرجاع ISO UTC + عرض دمشق بمحول موحد.

### Q-021 — الإشعارات الجديدة غير معروفة للراوتر (مرتفع)
نحتاج acts مستقلة للجاهزية، الانضمام، البدء التلقائي، التجديد الجاهز، الحجز المؤقت، التحويل، الانتظار، وتوفر الموعد.

### Q-022 — واجهة الإدارة لا تعرف session/intent/hold (مرتفع)
تعرض status العام فقط، ولا تميز دفعة مرتبطة بمسودة، حجز منتهٍ، جلسة جاهزة، أو انتظار انضمام.

### Q-023 — واجهة المحامي تبدأ المؤقت مباشرة (حرج)
زر `start_chat` الحالي = بدء الوقت. يجب أن يصبح «أنا جاهز» ويبدأ نافذة الانضمام.

### Q-024 — النسخة القديمة ستفهم الحالات خطأ (حرج تشغيلي)
تغيير semantics على السيرفر فوراً يكسر المؤقت والأزرار في APK الحالي. يلزم Feature Flag وتوافق مرحلي.

### Q-025 — لا قائمة انتظار للمحامي نفسه (متوسط)
التصميم المعتمد يحتاج waitlist خلال نافذة 30 يوماً ثم إشعار عند فتح/تحرير موعد.

---

## 4. النموذج الهدف

### 4.1 `consultation_intents`
مسودة خادمية قبل الدفع:
- id, user_uid.
- flow: `phone_new | onsite_new | phone_renew | onsite_convert`.
- parent_consultation_id.
- subject, attachments.
- requested_service_type.
- lawyer_uid (خادمي/محمي).
- reservation_id.
- quoted_amount, base_discount, config_version/snapshot.
- status: `draft | payment_pending | paid | materialized | expired | cancelled | failed`.
- idempotency_key.
- created/expires/materialized timestamps.

**قيود:** Intent مفتوح واحد لكل مستخدم ونفس flow/parent، وربط دفعة واحدة.

### 4.2 `consultation_chat_sessions`
كل مدة مدفوعة/أساسية سجل مستقل:
- consultation_id, ordinal.
- kind: `initial | renewal`.
- payment_id nullable للأساسية/غير المجانية حسب التصميم.
- duration_minutes.
- status: `ready | join_window | active | ended | cancelled | reversed`.
- lawyer_ready_at.
- join_deadline.
- user_joined_at.
- starts_at.
- ends_at.
- start_reason: `user_joined | grace_expired`.
- free_extension_minutes / extended_at.
- ready/activate idempotency keys.

**قيود:**
- جلسة واحدة فقط `join_window|active` لكل استشارة.
- ordinal فريد.
- payment_id فريد عند وجوده.

### 4.3 `lawyer_time_reservations`
أفضل من جدول hold منفصل + appointment، لأنه يوحد منع التعارض:
- lawyer_uid, user_uid.
- consultation_intent_id.
- slot_start, slot_end أو `tstzrange`.
- status: `held | confirmed | released | expired | cancelled`.
- hold_expires_at = 6 ساعات.
- appointment_id عند التثبيت.
- idempotency_key.

**القيد الكمومي:** GiST EXCLUDE على `(lawyer_uid WITH =, period WITH &&)` للحالات `held|confirmed`. هذا يجعل واحداً فقط من الطلبين المتزامنين ينجح داخل PostgreSQL.

### 4.4 `consultation_waitlist`
- user_uid, parent_consultation_id, lawyer_uid.
- status active/notified/consumed/cancelled.
- نافذة البحث 30 يوماً.
- منع تكرار انتظار نشط لنفس المستخدم/المحامي/قضية.

### 4.5 تعديلات `appointments`
- إضافة `kind`: `offer | legal` (الـphotography يبقى صفاً مدمجاً افتراضياً من Edge).
- إضافة `consultation_id` FK UNIQUE nullable.
- legal appointments لا تمر بنصوص/إحصاءات العرض.
- backfill كل الصفوف الحالية إلى `offer`.

### 4.6 الربط المالي
الأفضل إضافة `payments.consultation_intent_id` FK nullable بدلاً من الاعتماد على meta فقط. تبقى meta للعرض، لا للهوية المرجعية الأساسية.

---

## 5. آلات الحالات

### Intent
`draft → payment_pending → paid → materialized`

فروع الفشل:
- payment rejected → draft/cancelled.
- hold expired → `payment_pending_needs_slot` (الدفعة لا تعتمد حتى اختيار بديل).
- reversed → materialized effect compensation.

### Chat Session
`ready → join_window → active → ended`

- المحامي يضغط جاهز: `ready→join_window`, `join_deadline=server_now+2m`, و`starts_at=join_deadline` افتراضياً.
- دخول المستخدم قبل deadline: تحديث ذري `starts_at=server_now`, `start_reason=user_joined`.
- عدم الدخول: تبقى `starts_at=deadline`, worker/أي قراءة يحولها active، `grace_expired`.
- التمديد يغير ends_at مرة واحدة فقط.

### Reservation
`held → confirmed → cancelled/released`

- cron: held المنتهي → expired.
- اعتماد الدفع لا ينجح إذا expired؛ تبقى الدفعة pending ويُطلب slot جديد.

### Phone Consultation
طلب/قبول منفصلان عن session. نهاية session لا تعني إغلاق القضية فوراً؛ تصبح واجهياً `awaiting_user_decision` مع خيارات التجديد/التحويل/الإنهاء.

### Onsite Child
Intent تحويل مدفوع → child consultation service_type=1 → appointment kind=legal confirmed تلقائياً.

---

## 6. العقود الذرية

### T1: تحضير هاتفية جديدة
قفل المستخدم/النوع → تحقق عدم وجود مسار مفتوح → إنشاء intent + snapshot سعر → إرجاع intent_id.

### T2: تحضير حضورية
اختيار محامٍ له slot فعلي خلال 30 يوماً → INSERT reservation بقيد EXCLUDE → intent مربوط → السعر.

### T3: إنشاء الدفع
قفل intent → تحقق مالك/حالة/hold → حساب السعر من config/snapshot → INSERT payment مع FK → intent payment_pending.

### T4: اعتماد هاتفية جديدة
قفل payment+intent → تحقق proof/status → إنشاء consultation + تعيين المحامي → إنشاء initial session `ready` بعد قبول المحامي لا الآن → payment approved + intent materialized. كل ذلك في transaction واحدة.

### T5: اعتماد تجديد
قفل payment+intent+parent → إنشاء renewal session `ready` فقط → اعتماد الدفع → إشعار المحامي. لا يبدأ الوقت.

### T6: المحامي جاهز
قفل session → تحقق assigned lawyer/status ready → join window مرة واحدة → إشعار المستخدم. الطلب المكرر يعيد نفس النتيجة.

### T7: انضمام المستخدم
قفل session → تحقق owner + join_window → إن قبل deadline ابدأ الآن؛ إن بعده لا تعدل البداية المخططة → فتح الكتابة بحسب server time.

### T8: اعتماد حضورية جديدة/تحويل
قفل payment+intent+reservation → تحقق reservation held وغير منتهٍ → إنشاء child عند التحويل → إنشاء appointment kind=legal sts=1 → reservation confirmed → payment approved → إشعارات. فشل أي خطوة يلغي الكل.

### T9: عكس الدفع
حسب flow:
- renewal ready غير مبدوء: cancel session.
- renewal active/ended: لا عكس تلقائي دون قرار تعويض.
- onsite قبل الموعد: cancel appointment + release reservation + credit/refund policy.
- new phone before lawyer/session: cancel consultation أو grant credit.
كل أثر يسجل في activity_log.

---

## 7. مصفوفة الفشل والتعويض

| الفشل | النتيجة الصحيحة |
|---|---|
| رفع proof ثم فشل payment | حذف proof غير المرتبط |
| حجز slot ثم لم يدفع | تحرير بعد 6 ساعات |
| دفع مع hold منتهي | لا اعتماد؛ اختيار slot جديد بنفس الدفعة |
| مستخدمان لنفس slot | واحد ينجح، الآخر `SLOT_NO_LONGER_AVAILABLE` |
| اعتماد مكرر | نفس النتيجة بلا إشعار/خدمة ثانية |
| المحامي يضغط جاهز مرتين | نفس join window |
| المستخدم يدخل من جهازين | أول join فقط يحدد البداية |
| دخول في لحظة deadline | lock يحدد سبباً واحداً وبداية واحدة |
| Push يفشل | صف in-app موجود؛ الوقت خادمي لا يعتمد التسليم |
| التطبيق يغلق | intent/session/reservation كلها خادمية |
| المحامي يتعطل قبل موعد تحويل | لا نقل تلقائي؛ waitlist/موافقة محامٍ آخر |
| عكس الدفع | compensation بحسب الحالة لا UPDATE sts فقط |
| فشل إشعار بعد transaction | outbox/retry، لا rollback للخدمة المدفوعة |

---

## 8. الإشعارات المطلوبة

Acts جديدة:
- `legal_lawyer_ready`
- `legal_user_joined`
- `legal_session_auto_started`
- `legal_session_started`
- `legal_session_ended`
- `legal_renewal_paid_ready`
- `legal_slot_held`
- `legal_slot_expiring`
- `legal_onsite_confirmed`
- `legal_waitlist_available`
- `legal_payment_needs_new_slot`

Push لا يحمل موضوع القضية أو نص الرسائل. Deep links تتجه إلى chat/session أو appointment بحسب الدور.

**تحسين اعتمادية:** جدول notification_outbox فريد بـevent_key؛ worker يرسل Push ويعيد المحاولة. صف الإشعار داخل التطبيق جزء من transaction، Push أثر خارجي غير ذري.

---

## 9. الأمان والخصوصية

1. سحب سياسات authenticated العامة من consultation_files؛ service_role فقط.
2. ضبط bucket: حد 8MB، MIME صور + audio/mp4 حسب المسار/الفعل.
3. كل signed URL بعد تحقق participant/manager read-only.
4. manager view لا يغير is_read.
5. intents/reservations/sessions: RLS service_role فقط؛ التطبيق عبر Edge.
6. سحب INSERT المباشر القديم على payments/appointments إن لم يعد له مستدعٍ.
7. audit لكل جاهزية/انضمام/بدء تلقائي/عكس/تغيير محامٍ.
8. عدم كشف lawyer_uid؛ opaque reservation/intent IDs فقط.

---

## 10. توافق النسخة القديمة وخطة الإطلاق

### المرحلة A — إضافية وآمنة
- إصلاح overload واختيار المواعيد أولاً.
- إضافة الجداول/الأعمدة/القيود دون حذف حقول.
- backfill appointments.kind='offer'.
- backfill الاستشارات القديمة إلى sessions تاريخية بلا إشعار.
- `consultationFlowV2=false`.

### المرحلة B — Edge مزدوج
- الأفعال الجديدة V2.
- الأفعال القديمة تعمل semantics القديمة أو تعيد ردوداً عربية آمنة.
- القراءة تُرجع الحقول القديمة المشتقة من session للـAPK القديم.

### المرحلة C — Flutter
- مودال انتهاء الوقت.
- شاشة join window.
- دفع مرتبط بالintent.
- تقويم 30 يوماً + hold.
- انتظار/محامٍ آخر بموافقة.
- appointment.kind legal.

### المرحلة D — تفعيل محدود
- allowlist حساب هناء + المحامي الأول + الإدارة.
- E2E كامل.

### المرحلة E — تعميم
- feature flag عام.
- مراقبة 24 ساعة.
- تعطيل crons القديمة المتعارضة.
- حذف overload القديم فقط بعد grep حي لكل المستدعين.

### الرجوع
- flip flag إلى V1.
- لا حذف للجداول الجديدة.
- إيقاف workers الجديدة.
- fields legacy مستمرة مشتقة.
- لا rollback destructive للبيانات المدفوعة.

---

## 11. ترحيل البيانات الحالية

لكل استشارة:
- بلا chat_started: لا session نشطة.
- بدأت وانتهت: session تاريخية ended بنفس البداية/المدة.
- نشطة: session active مع ends_at مشتق.
- extended=true: free_extension_minutes=5.
- renew_count>0: لا يمكن إعادة بناء حدود كل تجديد بدقة من الصف وحده؛ تُنشأ جلسة legacy مجمعة وتوسم `migration_quality=aggregated`.
- converted_to_onsite القديمة: تحقق يدوي وربط parent/child إن أمكن، لا اختراع تاريخ.

لا إشعارات ولا نقاط ولا دفعات أثناء backfill.

---

## 12. مصفوفة الاختبار الكمومي

### التزامن
- مستخدمان يحجزان slot نفسه بالميلي ثانية.
- اعتماد payment مرتين.
- جاهزية المحامي من جهازين.
- join من جهازين.
- join عند `deadline-1ms`, `deadline`, `deadline+1ms`.
- extend مع end worker في اللحظة نفسها.
- reverse مع approve في اللحظة نفسها.

### الزمن
- دمشق صيف/شتاء، جهاز بتوقيت ألمانيا/UTC.
- app background أثناء join window.
- Push متأخر/مغلق.
- server clock فقط.

### المال
- مبلغ معدل.
- intent لشخص آخر.
- hold لشخص آخر.
- payment صحيح وhold منتهي.
- عكس قبل/بعد بدء session.
- فرق تحويل = onsite-base phone فقط.

### الأدوار
- مستخدم، محامٍ مسند، محامٍ آخر، نائب، مدير، نسخة قديمة.

### الوسائط
- رفع ثم crash.
- ملف MIME مزيف.
- تجاوز الحجم/المدة.
- signed URL بعد انتهاء صلاحيته.

### التنقل
- كل act من إشعار داخل التطبيق وPush والتطبيق مقتول/خلفية/مفتوح.

---

## 13. ترتيب التنفيذ المقترح

1. **Hotfix مستقل:** overload + error propagation + 30-day actual-free picker.
2. **Migration 1:** kind/FKs/security hardening.
3. **Migration 2:** intents + reservations + exclusion + waitlist.
4. **Migration 3:** chat sessions + backfill + new workers.
5. **Edge:** transaction actions + outbox + compensation.
6. **Flutter:** booking/payment/join/modal/appointments.
7. **Admin/Lawyer:** حالات جديدة وأزرار جاهزية/تعويض.
8. **E2E allowlist.**
9. **تعميم وتنظيف القديم.**

لا يُمزج hotfix الحالي مع إعادة التصميم في commit واحد؛ يجب أن يبقى إصلاح المواعيد قابلاً للإثبات والرجوع منفرداً.

---

## 14. القرارات المثبتة

- تقويم 30 يوماً.
- hold ست ساعات.
- موعد منشور + دفع معتمد = تأكيد تلقائي.
- المحامي نفسه أولاً عند التحويل.
- عند انعدام 30 يوماً: waitlist أو محامٍ آخر بموافقة أو تجديد هاتفي.
- خصم الهاتفية الأساسية فقط.
- التجديد لا يبدأ عند الدفع.
- المحامي يعلن الجاهزية.
- المستخدم يملك دقيقتين.
- البداية عند join أو deadline أيهما أسبق.
- التحويل Child لا mutation للأصل.

---

## 15. بوابات السماح قبل البرمجة

- موافقة على هذه الوثيقة.
- تنفيذ hotfix المواعيد واختباره منفرداً.
- snapshot حي للدوال/القيود قبل كل migration.
- كل migration idempotent ورباعي التحصين.
- لا deploy بلا `git pull` و`--no-verify-jwt`.
- لا تفعيل V2 قبل بناء APK واختبار الحسابات الثلاثة.

**الخلاصة:** التحليل دون الذري كشف أن أكبر خطر ليس المؤقت نفسه، بل الربط بين المال والزمن والموعد والإشعار. التصميم أعلاه يجعل PostgreSQL هو الحكم عند التزامن، ويعامل Push والواجهة كآثار قابلة لإعادة المحاولة، لا كمصدر حقيقة.
