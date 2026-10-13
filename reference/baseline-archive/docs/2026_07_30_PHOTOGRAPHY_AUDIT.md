# 📸 تقرير الفحص النهائي — مسار المصوّر
> **التاريخ:** 2026-07-30  
> **النطاق:** فحص شامل لكل مكونات التصوير (شاشات + إيدجات + SQL + تنقل + بيانات حية)

---

## ✅ ما يعمل بشكل صحيح (مُثبت حيّاً)

### 🟢 Edge Functions — كل الأكشنات ترد بشكل صحيح

| الإيدج | الأكشن | الحالة | ملاحظات |
|---|---|---|---|
| `photographer-tasks` | `list` | ✅ | يجلب مهام المصوّر فقط — `WHERE photographer_id = uid` |
| `photographer-tasks` | `start` | ✅ | يحوّل sts من 0→1 + إشعار صاحب الطلب |
| `photographer-tasks` | `submit` | ✅ | يرفع الصور + دمج تراكمي سيرفري + إشعار المكتب والعميل |
| `photographer-tasks` | `decline` | ✅ | سبب إلزامي (`DECLINE_REASON_REQUIRED`) + مهمة غير مملوكة = `TASK_NOT_FOUND_OR_NOT_ALLOWED` |
| `admin-photography` | `list_tasks` | ✅ | يجلب 8 مهام — كل الحقول |
| `admin-photography` | `stats` | ✅ | إحصاءات مجمّعة (حسب الحالة + نسبة تحويل + أكثر المصورين إنجازاً) |
| `admin-photography` | `request_photography` | ✅ | مستخدم عادي يرسل طلب + حراسة JWT/staff_session + منع الطلب المكرر |
| `admin-photography` | `my_photo_requests` | ✅ | يجلب طلبات المستخدم فقط |
| `admin-photography` | `cancel_photo_request` | ✅ | إلغاء بسبب إلزامي + sts=0 فقط + إشعار المصوّر |
| `admin-photography` | `assign_photographer` | ✅ | منع موعد ماضي + منع ازدواج المصوّر (`assert_photographer_free`) + إشعارات غنية للطرفين |
| `admin-photography` | `create` | ✅ | إنشاء مهمة مرتبطة بعرض |
| `admin-photography` | `update_status` | ✅ | اعتماد/رفض/إلغاء + إشعار صاحب الطلب |
| `admin-photography` | `attach_media` | ✅ | ربط وسائط المهمة بالعرض |
| `admin-photography` | `offer_photo_info` | ✅ | تنويه إداري «مُصوَّر من المكتب» — خلف حارس دور ≥3 |
| `admin-photography` | `link_offer` | ✅ | ربط مهمة بلا عرض بعرض جديد + إشعار «العرض الخاص بك أصبح منشوراً» |
| كل الأكشنات | `fake_action` | ✅ | يرجع `UNKNOWN_ACTION` (400) — لا أكشنات وهمية |

### 🟢 دوال SQL (8 دوال — كلها SECURITY DEFINER + search_path مُثبّت)

| الدالة | الحالة | ملاحظات |
|---|---|---|
| `get_photographer_tasks_internal(uuid)` | ✅ | فلتر `photographer_id` + حصار دور ≥2 |
| `start_photography_task_internal(uuid,uuid)` | ✅ | حصار ملكية + دور |
| `submit_photography_task_internal(uuid,uuid,jsonb,text,bool)` | ✅ | دمج تراكمي (`p_replace=false`) أو استبدال (`p_replace=true`) — حماية فقدان الصور |
| `create_photography_task_internal(uuid,uuid,uuid,text,timestamptz)` | ✅ | حصار دور ≥3 |
| `update_photography_task_status_internal(uuid,uuid,int,text)` | ✅ | حصار دور ≥3 |
| `attach_photography_media_to_offer_internal(uuid,uuid)` | ✅ | نسخ الوسائط لجدول العرض |
| `assert_photographer_free(uuid,timestamptz,uuid)` | ✅ | منع ازدواج المصوّر بنافذة `gap_mins` من `app_config` |
| `send_photography_reminders()` | ✅ | تذكير قبل ساعة لكل من المصوّر وصاحب الطلب + بوش FCM + dedup بـ `rmnd_1h` |

### 🟢 التنقل والمسارات

| المسار | الحالة | الحراسة |
|---|---|---|
| `/photographer/tasks` | ✅ | بوابة `isPhotographer \|\| isAdmin` |
| `/user/photography` | ✅ | بوابة صلاحية `user_photography` (دور ≥0) |
| `/admin/photography-management` | ✅ | بوابة صلاحية `photography_management` (دور ≥3) |
| شريط التنقل السفلي — تبويب «تصوير» (index 4) | ✅ | يظهر للمستخدمين العاديين فقط |
| شريط التنقل الداخلي — «مهامي» → `/photographer/tasks` | ✅ | للمصور (isInternal) |
| الشاشة الرئيسية — اختصار «مهام المصور» | ✅ | يظهر للمستخدمين بصلاحية `photographer_tasks` |
| لوحة الموظف — «مهام التصوير» | ✅ | شرط صلاحية `photography_management` |
| لوحة الأقسام — «إدارة مهام التصوير» | ✅ | شرط صلاحية `photography_management` |

### 🟢 كرون التذكيرات

| العنصر | الحالة |
|---|---|
| Job ID 12 — `*/15 * * * *` | ✅ يعمل كل 15 دقيقة |
| يستدعي `send_photography_reminders()` | ✅ |
| نافذة التذكير: 0–60 دقيقة قبل الموعد | ✅ |
| dedup بـ `rmnd_1h=1` (مرة واحدة بالعمر لكل مهمة) | ✅ |
| يُشعر المصوّر + صاحب الطلب + بوش FCM | ✅ |

### 🟢 تدفق تحويل صور المصوّر لعرض

`_createOfferFromTask` (شاشة الإدارة) → يفتح `AdminAddOfferScreen` مع:
- `photoTaskId` → يُستخدم لاستدعاء `link_offer` بعد الإنشاء
- `presetOwnerUid` → مالك العرض = صاحب الطلب
- `presetImages` → صور المصوّر جاهزة
- `presetPhone/presetLocation` → مستخرجة من notes

بعد الإنشاء: نشر مباشر (`admin-offers: review` approve=true) + ربط المهمة بالعرض (`link_offer`) ✅

---

## 🐛 مشاكل حقيقية (4 مشاكل)

### 1. 🔴 `create` لا يفحص تعارض وقت المصوّر

**الموقع:** `admin-photography: create` → `create_photography_task_internal`  
**المشكلة:** عند إنشاء مهمة تصوير من الإدارة (زر ➕ بالشاشة الإدارية) مع تحديد موعد + مصوّر، **لا يُستدعى `assert_photographer_free`**. بينما `assign_photographer` يفحص التعارض.

**الأثر:** إذا أنشأ المدير مهمة بموعد يتعارض مع مهمة أخرى لنفس المصوّر → ازدواج ميداني.

**الحل:** إما إضافة فحص التعارض داخل `create_photography_task_internal` أو استدعاء `assert_photographer_free` في الإيدج قبل الـ RPC (كما في `assign_photographer`).

---

### 2. 🟡 طلب التصوير من المستخدم — تحقق صامت عند الحقول الفارغة

**الموقع:** `photography_service_screen.dart` سطر ~233  
**المشكلة:** عند الضغط على «إرسال الطلب» مع ترك أي حقل فارغ:
```dart
if (nameCtrl.text.trim().isEmpty || descCtrl.text.trim().isEmpty || ...) {
  return; // ← صامت تماماً — بلا رسالة خطأ
}
```
المستخدم يضغط الزر ولا يحصل شيء — بلا أي تنبيه.

**الحل:** إضافة `_snack('يرجى تعبئة كل الحقول المطلوبة')` قبل `return` أو استخدام `errorText` بالحقول.

---

### 3. 🟡 `my_photo_requests` يرجع حقول ناقصة

**الموقع:** `admin-photography: my_photo_requests` → SELECT يحدد أعمدة فقط:
```
id, ttl, notes, sts, ts_scheduled, ts_submit, ts_done, ts_crt, media
```

**المفقود:** `off_id, photographer_id, requested_by, loc, photographer_note, office_note, ts_upd`

**الأثر الحالي:** لا يوجد عطل لأن `PhotographyTaskModel.fromSupabase` يستخدم `?? ''` لكل الحقول. لكن:
- المستخدم لا يرى `office_note` (ملاحظة المكتب عند الرفض) — مهمة UX
- لا يرى `loc` (الموقع)
- لا يعرف إذا المهمة مرتبطة بعرض (`off_id`)

**الحل:** إضافة الأعمدة المفقودة للـ SELECT، أو استخدام `select("*")`.

---

### 4. 🟡 المستخدم لا يستطيع إلغاء طلبه بعد بدء التنفيذ

**الموقع:** `cancel_photo_request` يفرض `eq("sts", 0)` فقط  
**المشكلة:** إذا بدأ المصوّر التنفيذ (sts=1) وقرر العميل الإلغاء — لا يستطيع. الزر يختفي من الشاشة أيضاً (شرط `t.sts == 0`).

**الأثر:** قد يكون هذا مقصوداً بالتصميم (حماية المصوّر من إلغاء مفاجئ بعد البدء). لكنه ليس موثّقاً — لا رسالة توضح للمستخدم لماذا لا يستطيع الإلغاء.

**الحل المقترح:** السماح بالإلغاء حتى sts=1 مع إشعار المصوّر، أو إضافة رسالة توضيحية «لا يمكن الإلغاء بعد بدء التصوير».

---

## ⚠️ نقاط ضعف ومخاطر (5 نقاط)

### 1. 🟡 بيانات اختبار ملوثة — 8 مهام

الجدول `photography_tasks` يحتوي 8 مهام (2 بانتظار + 1 قيد التنفيذ + 2 معتمدة + 3 ملغاة) — أغلبها عناوين غير مفهومة («ويتترترتؤوي»، «ة راةىررل»، «ىىىلل»). هذه بيانات اختبار قديمة قد تؤثر على:
- دقة `stats` (نسبة التحويل = 0% لأن كل `off_id` فارغ)
- تجربة المستخدم عند عرض «طلبات التصوير الخاصة بي»

### 2. 🟡 مهمة بانتظار بلا مصوّر (`e4093306`)

توجد مهمة `sts=0` و `photographer_id=null` و `ts_scheduled=null` — عالقة بلا إسناد. المكتب لم يُسند لها مصوّراً ولا المستخدم يستطيع إلغاءها لأنها ليست طلبه.

### 3. 🟡 مهام لمستخدم2عادي بـ sts=0 و sts=1 مع phototester2

المستخدم2عادي لديه:
- مهمة sts=0 (فيلا مع مسبح) — phototester2 مُسند
- مهمة sts=1 (شقة 3 غرف) — phototester2 بدأ التنفيذ

هذه بيانات اختبار قد تسبب `ACTIVE_PHOTOGRAPHY_REQUEST_EXISTS` عند محاولة إرسال طلب تصوير جديد.

### 4. 🟢 `offer_photo_info` يُنادى بدون `staff_session_token` صريح

شاشة `offer_detail_screen.dart` تنادي `admin-photography: offer_photo_info` بـ `admin_uid` فقط. لكن `SupabaseService.invokeFunction` يُحقن التوكن تلقائياً من SharedPreferences — فالتشغيل سليم. مع ذلك، لو تغيرت طريقة الحقن مستقبلاً قد ينكسر.

### 5. 🟢 لا يوجد حد أقصى لعدد الصور في مهمة التصوير

`_pickMedia` يقبل حتى 20 صورة من `pickMultiImages(limit: 20)`، لكن:
- لا يوجد حد سيرفري — المصوّر يمكنه رفع آلاف الصور نظرياً
- `uploadOfferImages` لا يفحص حجم الملف
- نفس الثغرة المذكورة بالدستور عن `payment_proofs` (anon يرفع بلا حد حجم/نوع)

---

## 💡 اقتراحات تحسين (7 اقتراحات)

### 1. 📊 إظهار `office_note` للمستخدم عند الرفض

عند رفض مهمة تصوير، المستخدم يرى فقط «مرفوضة» بلا سبب. إضافة:
```dart
if (t.sts == 4 && t.officeNote.isNotEmpty)
  Text('السبب: ${t.officeNote}', style: ...)
```
(يتطلب إصلاح المشكلة #3 أعلاه — إضافة `office_note` للـ SELECT)

### 2. 📅 إضافة موعد التصوير للبطاقة بتبويب «مهام اليوم»

حالياً بطاقة المهمة بتبويب «مهام اليوم» تعرض التاريخ فقط في `tsScheduled`، لكن لو المهمة بلا `tsScheduled` لا تعرض شيئاً. يمكن إضافة «بلا موعد محدد» لتنبيه المصوّر.

### 3. 🔄 تحديث القائمة بعد الرفض/البدء

`_startTask` و `_declineTask` يستدعيان `_load()` بعد النجاح — هذا جيد. لكن `_submitToOffice` يستدعي `_load()` فقط عند `ok=true`. إذا فشل الرفع (مثلاً خطأ شبكة)، المستخدم يبقى على نفس الشاشة بلا تحديث — يمكن إضافة `setState` لتفريغ `_isUploading` حتى عند الفشل (وهو موجود فعلاً).

### 4. 📸 معاينة الصور الحقيقية بدلاً من أيقونة

بعد اختيار الصور لرفعها:
```dart
Container(width: 70, height: 70, child: const Center(child: Icon(Icons.image)))
```
يعرض أيقونة بدلاً من صورة مصغّرة حقيقية. يمكن استخدام `Image.file(XFile.path)` لعرض المحتوى المختار.

### 5. 🔔 إشعار المصوّر عند إنشاء مهمة (action: create)

عند إنشاء مهمة تصوير من الإدارة (`create`)، المصوّر **لا يُشعَر** فوراً. بينما عند الإسناد (`assign_photographer`) يُشعَر. الفرق:
- `create` يُسند المصوّر داخل `create_photography_task_internal` لكن لا إشعار
- `assign_photographer` يُشعر المصوّر + صاحب الطلب + المصوّر السابق

**الحل:** إضافة إشعار للمصوّر بعد `create` بنفس نمط `assign_photographer`.

### 6. 🗺️ خريطة الموقع في بطاقة المهمة

الموقع مخزّن كـ JSON داخل `loc` (للمهام المرتبطة بعروض) أو كـ text داخل `notes` (لطلبات المستخدمين). يمكن عرض الموقع على خريطة بسيطة عند الضغط.

### 7. 📱 Pull-to-refresh بتبويب «القادمة»

تبويب «القادمة» (المؤجلة) لا يدعم `RefreshIndicator` بينما تبويبا «مهام اليوم» و«المنفذة» يدعمانه.

---

## 📋 خلاصة الحالة

| المجال | الحالة | عدد |
|---|---|---|
| Edge Functions | ✅ كل الأكشنات تعمل | 15/15 |
| SQL Functions | ✅ كل الدوال محصّنة | 8/8 |
| المسارات (Routes) | ✅ لا مسارات وهمية | 3/3 |
| التنقل | ✅ كل الروابط حية | 6/6 |
| التذكيرات + كرون | ✅ يعمل كل 15 دقيقة | ✓ |
| الإشعارات | ✅ غنية + بوش FCM | ✓ |
| **مشاكل حقيقية** | 🐛 تحتاج إصلاح | **4** |
| **نقاط ضعف** | ⚠️ مقبولة حالياً | **5** |
| **اقتراحات تحسين** | 💡 إثراء | **7** |

### الأولوية المقترحة للإصلاح:
1. 🔴 **#1** — فحص تعارض وقت المصوّر عند `create` (خطأ منطقي)
2. 🟡 **#2** — رسالة خطأ عند ترك حقول فارغة (UX)
3. 🟡 **#3** — إضافة `office_note` و `off_id` للـ SELECT (إثراء معلوماتي)
4. 🔔 **#5 بالاقتراحات** — إشعار المصوّر عند `create` (فجوة إشعارات)
