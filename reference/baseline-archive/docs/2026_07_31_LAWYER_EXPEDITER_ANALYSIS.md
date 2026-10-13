# ⚖️ تحليل مسار المحامي والمعقّب — المنطق الكامل
> **التاريخ:** 2026-07-31
> **النوع:** تحليل فقط — بلا تنفيذ

---

## 🏗️ البنية الحالية

### الأدوار:
| الدور | role | الحسابات التجريبية |
|---|---|---|
| محامي | 7 | `lawyertester1` + `lawyertester2` |
| معقّب | 8 | `agenttester1` + `agenttester2` |

### الجداول:
| الجدول | الأعمدة | البيانات الحالية |
|---|---|---|
| `lawyer_profiles` | uid, whatsapp_phone, office_address, specialization, avl, is_active | **0 صفوف** |
| `expediting_tasks` | id, lawyer_uid, expediter_uid, offer_id, item_type, checklist(jsonb), status, ... | **0 صفوف** |

### Edge Function: `legal-actions` (13 أكشن)
| الأكشن | الدور المطلوب | الحالة |
|---|---|---|
| `get_active_lawyers` | أي مستخدم | ✅ |
| `get_lawyer_profile` | محامي | ✅ |
| `admin_upsert_lawyer` | محامي/أدمن | ✅ |
| `get_available_expediters` | محامي/أدمن | ✅ |
| `create_expediting_task` | محامي | ✅ |
| `get_lawyer_expediting_tasks` | محامي | ✅ |
| `get_lawyer_appointments` | محامي | ✅ |
| `get_my_expediting_tasks` | معقّب | ✅ |
| `update_checklist_item` | محامي/معقّب/أدمن | ✅ |
| `complete_expediting_task` | معقّب | ✅ |
| `approve_expediting_task` | محامي | ✅ |
| `request_checklist_revision` | محامي | ✅ |
| `UNKNOWN_ACTION` | — | ✅ |

### SQL Functions (12):
كلها موجودة وتعمل: `admin_upsert_lawyer_profile`, `get_active_lawyers`, `get_lawyer_profile`, `get_lawyer_appointments`, `get_lawyer_expediting_tasks`, `get_available_expediters`, `get_my_expediting_tasks`, `create_expediting_task_internal`, `approve_expediting_task_internal`, `complete_expediting_task_internal`, `request_expediting_item_revision_internal`, `update_expediting_checklist_item`

---

## 🔄 التدفقات الكاملة

### Flow 1: إعداد المحامي (أول دخول)
```
المحامي يدخل لوحة المحامي (/lawyer/dashboard)
    ↓
checkLawyerProfile() → لا يوجد ملف (lawyer_profiles فارغ)
    ↓
شاشة الإعداد الأولي: رقم واتساب + عنوان المكتب
    ↓
_saveProfile() → legal-actions: admin_upsert_lawyer
    ↓
SQL: admin_upsert_lawyer_profile → INSERT INTO lawyer_profiles
    ↓
✅ profileSetupComplete = true → لوحة المحامي
```

### Flow 2: المحامي يُكلّف معقّب
```
المحامي → تبويب «إضافة مهمة»
    ↓
يختار: نوع (عقار/سيارة) + معقّب + رقم العقار/السيارة + وثائق + تعليمات
    ↓
_createTask() → legal-actions: create_expediting_task
    ↓
SQL: create_expediting_task_internal → INSERT INTO expediting_tasks
    ↓
المهمة تظهر بتبويب «المهام المرسلة»
```

### Flow 3: المعقّب ينفذ المهمة
```
المعقّب يدخل مهام التعقيب (/expediter/tasks)
    ↓
getExpeditingTasks() → legal-actions: get_my_expediting_tasks
    ↓
يختار مهمة → /expediter/task-detail
    ↓
لكل وثيقة: _showEditDialog()
  ├── حالة الاستخراج (مطلوب/قيد الاستخراج/تم/عائق)
  ├── رقم العقار/السيارة/الصحيفة
  ├── صورة السند (من المعرض + base64 → upload to storage)
  └── ملاحظات ميدانية
    ↓
_updateItem() → legal-actions: update_checklist_item
    ↓
SQL: update_expediting_checklist_item → UPDATE checklist JSONB
    ↓
بعد إكمال كل البنود: _completeTask()
    ↓
legal-actions: complete_expediting_task
    ↓
SQL: complete_expediting_task_internal → status = 2
```

### Flow 4: المحامي يراجع ويعتمد
```
المحامي → تبويب «المهام المرسلة»
    ↓
يختار مهمة مكتملة (status=2) → _showTaskReviewDialog()
    ↓
يراجع كل وثيقة + صور السندات (signed URLs)
    ↓
خياران:
  ├── «إعادة هذا السند للمعقب» → _requestRevision()
  │     → legal-actions: request_checklist_revision
  │     → SQL: request_expediting_item_revision_internal
  │     → المعقّب يشوف طلب الإعادة ويعيد الرفع
  │
  └── «اعتماد المهمة» → _approveTask()
        → legal-actions: approve_expediting_task
        → SQL: approve_expediting_task_internal → status = 3
```

### Flow 5: حجز استشارة قانونية (من المستخدم العادي)
```
المستخدم → /legal/consultations
    ↓
يختار الخدمة (هاتفية 50ألف / مكتبية 200ألف / باقة شاملة 700ألف)
    ↓
يكتب ملخص الموضوع
    ↓
_submit() → ⚠️ محاكاة فقط (Future.delayed 800ms)
    ↓
رسالة: «تم إنشاء الطلب، يرجى رفع إيصال الدفع»
    ↓
context.push('/user/payment') ← ⚠️ هل فعلاً يعمل؟
```

---

## 🔔 خريطة الإشعارات

### الإشعارات الموجودة: ❌ **صفر إشعارات**

| الحدث | إشعار متوقع | الحالة |
|---|---|---|
| المحامي يُكلّف معقّب | 🔔 المعقّب: «مهمة تعقيب جديدة» | ❌ **غير موجود** |
| المعقّب يُحدّث بند | 🔔 المحامي: «تحديث على مهمة التعقيب» | ❌ **غير موجود** |
| المعقّب يُتمّم المهمة | 🔔 المحامي: «مهمة مكتملة بانتظار اعتمادك» | ❌ **غير موجود** |
| المحامي يطلب إعادة سند | 🔔 المعقّب: «طلب إعادة: [اسم الوثيقة]» | ❌ **غير موجود** |
| المحامي يعتمد المهمة | 🔔 المعقّب: «تم اعتماد مهمتك ✅» | ❌ **غير موجود** |
| مستخدم يحجز استشارة | 🔔 المحامي: «حجز استشارة جديد» | ❌ **غير موجود** |

### ملاحظة:
لا يوجد أي `INSERT INTO notifications` ولا `send_push_notification` في:
- Edge Function `legal-actions` (صفر إشعارات)
- SQL Functions (12 دالة — ولا وحدة فيها إشعار)
- Triggers على `expediting_tasks` (صفر triggers مخصصة — فقط FK constraints)

---

## 🐛 المشاكل والفجوات

### 🔴 حرجة:

| # | المشكلة | التفصيل |
|---|---|---|
| 1 | **صفر إشعارات بالكامل** | 6 أحداث بلا إشعار — المحامي والمعقّب ما بيعرفوا إلا لما يفتحوا الشاشة |
| 2 | **حجز الاستشارة وهمي** | `_submit()` = محاكاة `Future.delayed(800ms)` + redirect لصفحة دفع — **بلا إنشاء طلب فعلي** |
| 3 | **`legal-actions` مش منشور بـ `--no-verify-jwt`** | نفس مشكلة `broker-actions` — كل العمليات سترجع 401 للمستخدمين الهاتفيين |

### 🟡 متوسطة:

| # | المشكلة | التفصيل |
|---|---|---|
| 4 | **`_lawyerAppointments` يجلب مواعيد بس ما بيعرضها بالكامل** | البطاقة تعرض `client_name` + `client_phone` + `dt` من Map — لكن الـ SQL `get_lawyer_appointments` غير مُتحقق من محتواه الفعلي |
| 5 | **ما في حذف لمهمة التعقيب** | المحامي أنشأ مهمة بالغلط → ما في طريقة يحذفها |
| 6 | **المعقّب ما يقدر يُرجع مهمة** | إذا المعقّب تعذّر عليه التنفيذ → ما في «اعتذار» مثل المصوّر |
| 7 | **الوثائق المرفوعة بلا حد حجم فعلي** | الـ edge يفحص `> 8MB` فقط — بلا فحص نوع الملف الحقيقي |
| 8 | **`_createTask` ما بيفحص تعارض المعقّب** | المعقّب ممكن ياخذ 100 مهمة بنفس الوقت |

### 🟢 بسيطة / تحسينات:

| # | التحسين | التفصيل |
|---|---|---|
| 9 | **القائمة الدائمة للوثائق محلية فقط** | `_customDocTemplates` محفوظة بـ SharedPreferences — بتضيع مع تغيير الجهاز |
| 10 | **ما في إحصائيات للمحامي** | Dashboard بلا أرقام (كم مهمة / كم معتمدة / كم معقّب) |
| 11 | **`legal_consultation_booking_screen` ما بترتبط بأي جدول** | الشاشة standalone — بلا `legal_actions` call |
| 12 | **ما في بحث/فلتر بالمهام** | المحامي عنده 50 مهمة → ما في فلترة بالحالة/النوع/المعقّب |

---

## 📋 أولويات التنفيذ المقترحة

### المرحلة 1: الإصلاحات الحرجة
1. نشر `legal-actions` بـ `--no-verify-jwt`
2. إضافة إشعارات (6 أحداث) — بالـ SQL functions أو triggers
3. إصلاح حجز الاستشارة (إنشاء طلب فعلي أو ربطه بنظام موجود)

### المرحلة 2: تحسينات المنطق
4. حذف مهمة التعقيب (للمحامي)
5. اعتذار المعقّب عن المهمة
6. فلترة المهام (حالة/نوع/معقّب)

### المرحلة 3: إثراء
7. إحصائيات للمحامي
8. حفظ الوثائق المخصصة سيرفرياً
9. ربط الاستشارة القانونية بجدول + إشعار المحامي
