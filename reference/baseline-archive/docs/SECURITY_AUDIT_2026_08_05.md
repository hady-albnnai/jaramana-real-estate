# 🔒 تقرير التدقيق الأمني والتحليل المنطقي — 2026-08-05

> **التاريخ:** 2026-08-05  
> **النطاق:** تحليل عميق للدوال المُبلَغ عنها كـ bugs  
> **المنهجية:** فحص كود السيرفر + اختبار استغلالي + تحليل المنطق  
> **الحالة:** 🟡 قيد التحليل (لا تعديلات مقترحة بعد)

---

## 🔴 BUG-001: تسريب أمني حرج — `get_admin_requests_internal`

### 1.1 ملخص المشكلة
**الخطورة:** 🔴 **حرجة — PII Leak**  
**التأثير:** أي زائر (anon) يستطيع قراءة كل الطلبات مع بيانات العملاء الحساسة

### 1.2 التأكيد الاستغلالي
```bash
# اختبار استغلالي — نجح ✅
curl -X POST "https://vsgkgnjtebjxyqwpuopz.supabase.co/rest/v1/rpc/get_admin_requests_internal" \
  -H "Authorization: Bearer {ANON_KEY}" \
  -H "apikey: {ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"p_admin_uid": "53701a2a-26ba-4b35-8f7d-f0a8f3956a98"}'

# النتيجة: HTTP 200 + 3 طلبات مع بيانات كاملة
```

### 1.3 البيانات المُسرَّبة
```json
{
  "req_id": "5516ec7d-3cfa-49cc-b316-fae14aecdeaf",
  "cl_nm": "هدى",                    // 🔴 اسم العميل
  "cl_ph": "+963935526556",          // 🔴 هاتف العميل (PII)
  "usr_id": "35c4c5d5-...",          // 🔴 معرّف المستخدم
  "prc": 25000.0,                    // السعر
  "sts": 0,                          // الحالة
  "ts_crt": "2026-07-27T23:42:56",   // تاريخ الإنشاء
  // ... 20+ حقل آخر
}
```

### 1.4 تحليل الكود (الدالة الكاملة)
```sql
CREATE OR REPLACE FUNCTION public.get_admin_requests_internal(p_admin_uid uuid)
RETURNS TABLE(...)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role INT;
BEGIN
  -- ⚠️ الفحص الأول: auth.uid() مقارنة بـ p_admin_uid
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;
  
  -- ⚠️ الفحص الثاني: دور p_admin_uid (ليس دور المتصل!)
  SELECT u.role INTO v_role 
  FROM public.users u 
  WHERE u.id = p_admin_uid AND u.i_del = 0;
  
  IF v_role IS NULL OR v_role < 3 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  -- إرجاع كل الطلبات
  RETURN QUERY
  SELECT ... FROM public.requests r ...
END;
$function$;
```

### 1.5 جذر المشكلة (Root Cause)

#### الفحص الأول معطّل لـ `anon`
```sql
IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
  RAISE EXCEPTION 'AUTH_MISMATCH';
END IF;
```

**المشكلة:**
- عند استدعاء الدالة بـ `anon` (زائر)، `auth.uid()` يُرجع `NULL`
- الشرط `auth.uid() IS NOT NULL` يكون `FALSE`
- النتيجة: **الفحص يُتخطى بالكامل** ✅

#### الفحص الثاني يفحص الشخص الخطأ
```sql
SELECT u.role INTO v_role 
FROM public.users u 
WHERE u.id = p_admin_uid ...;

IF v_role IS NULL OR v_role < 3 THEN
  RAISE EXCEPTION 'NOT_AUTHORIZED';
END IF;
```

**المشكلة:**
- الدالة تفحص دور `p_admin_uid` (المُمرَّر كمعامل)
- **لا تفحص دور المتصل الفعلي**
- النتيجة: أي شخص يمرّر UUID أدمن صالح → يحصل على البيانات ✅

### 1.6 سيناريو الاستغلال

```
المهاجم (زائر مجهول)
  ↓
يستدعي get_admin_requests_internal(p_admin_uid = "53701a2a-...")
  ↓
الفحص الأول: auth.uid() = NULL → يُتخطى ✅
  ↓
الفحص الثاني: role("53701a2a-...") = 6 (مدير) → يمر ✅
  ↓
يُرجع كل الطلبات مع PII ✅
```

### 1.7 لماذا الدالة مفتوحة لـ `anon`؟

**السبب التاريخي:**
- الدالة أُنشئت في migration قديم (قبل 2026-06-17)
- في ذلك الوقت، لم يكن هناك `REVOKE EXECUTE` افتراضي
- PostgreSQL يمنح `EXECUTE` لـ `PUBLIC` (يشمل `anon` + `authenticated`) بشكل افتراضي
- لم يُنفَّذ `REVOKE` لاحقاً

**الدليل:**
```sql
SELECT has_function_privilege('anon', 'get_admin_requests_internal(uuid)', 'EXECUTE');
-- النتيجة: true ⚠️
```

### 1.8 الدوال الأخرى بنفس النمط

فحصت كل الدوال `*_internal` التي تأخذ `p_admin_uid`:

| الدالة | مفتوحة لـ anon؟ | فحص auth.uid()؟ | الخطورة |
|--------|----------------|-----------------|---------|
| `get_admin_requests_internal` | ✅ نعم | ⚠️ معطّل | 🔴 حرجة |
| `get_admin_offers_internal` | ❌ لا | ✅ فعال | ✅ آمنة |
| `get_admin_payments_internal` | ❌ لا | ✅ فعال | ✅ آمنة |
| `get_admin_appointments_internal` | ❌ لا | ✅ فعال | ✅ آمنة |
| `get_admin_deals_internal` | ❌ لا | ✅ فعال | ✅ آمنة |

**الخلاصة:** `get_admin_requests_internal` هي الوحيدة المكشوفة.

---

## 🔴 BUG-002: خطأ SQL — `get_lawyer_appointments`

### 2.1 ملخص المشكلة
**الخطورة:** 🟡 **متوسطة — Functional Bug**  
**التأثير:** المحامي لا يستطيع رؤية مواعيده (خطأ `column reference "id" is ambiguous`)

### 2.2 رسالة الخطأ
```
ERROR: column reference "id" is ambiguous
LINE 1: SELECT a.id AS id, ...
```

### 2.3 تحليل الكود (الدالة الكاملة)
```sql
CREATE OR REPLACE FUNCTION public.get_lawyer_appointments(p_lawyer_uid uuid)
RETURNS TABLE(id uuid, client_name text, client_phone text, dt timestamptz, sts int, notes text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role int;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  RETURN QUERY
  SELECT
    a.id AS id,              -- ⚠️ هنا المشكلة
    COALESCE(u.nm, '') AS client_name,
    COALESCE(u.ph, '') AS client_phone,
    a.dt,
    a.sts,
    COALESCE(a.note, '') AS notes
  FROM public.appointments a
  JOIN public.users u ON u.id = a.req_uid
  WHERE a.bkr_id = p_lawyer_uid
  ORDER BY a.dt DESC;
END;
$function$;
```

### 2.4 جذر المشكلة (Root Cause)

**المشكلة:** تضارب بين:
1. **تعريف RETURN TABLE:** `TABLE(id uuid, ...)`
2. **استعلام SELECT:** `SELECT a.id AS id, ...`

**التفسير:**
- عند استخدام `RETURNS TABLE(id uuid, ...)`, PostgreSQL يُنشئ ضمنياً OUT parameter اسمه `id`
- عند كتابة `SELECT a.id AS id`, PostgreSQL يرى عمودين باسم `id`:
  - `id` من RETURN TABLE (OUT parameter)
  - `a.id AS id` من SELECT
- النتيجة: `column reference "id" is ambiguous`

### 2.5 لماذا لم يظهر الخطأ في التطوير؟

**الفرضيات:**
1. **لم يُختبر المسار:** المحامي/المعقّب من المسارات غير المُختبرة (حسب ملف التسليم)
2. **اختُبر ببيانات فارغة:** إذا لم يكن هناك مواعيد، الدالة تُرجع `[]` دون تنفيذ SELECT
3. **اختُلف إصدار PostgreSQL:** بعض الإصدارات القديمة تتسامح مع هذا التضارب

**الدليل:**
```sql
-- اختبار يدوي
SELECT * FROM get_lawyer_appointments('427da6f4-3a7f-4c19-aa7a-24cda805bd6f');
-- النتيجة: ERROR: column reference "id" is ambiguous
```

### 2.6 الأنماط الصحيحة في الدوال الأخرى

فحصت دوال مشابهة تستخدم `RETURNS TABLE`:

#### ✅ النمط الصحيح 1: بدون alias
```sql
-- من get_admin_requests_internal
RETURNS TABLE(req_id uuid, ...)
...
RETURN QUERY
SELECT
  r.id AS req_id,  -- ✅ اسم مختلف عن العمود الأصلي
  ...
```

#### ✅ النمط الصحيح 2: استخدام RECORD
```sql
RETURNS SETOF record
...
RETURN QUERY
SELECT
  a.id,
  ...
```

#### ❌ النمط الخاطئ (الموجود في get_lawyer_appointments)
```sql
RETURNS TABLE(id uuid, ...)
...
RETURN QUERY
SELECT
  a.id AS id,  -- ❌ نفس الاسم = تضارب
  ...
```

### 2.7 الدوال الأخرى بنفس المشكلة

فحصت كل الدوال التي تستخدم `RETURNS TABLE(... id uuid, ...)`:

| الدالة | تستخدم `AS id`؟ | الحالة |
|--------|----------------|--------|
| `get_lawyer_appointments` | ✅ نعم | 🔴 مكسورة |
| `get_admin_requests_internal` | ❌ لا (تستخدم `req_id`) | ✅ سليمة |
| `get_my_tasks` | ❌ لا (تستخدم `appointment_id`) | ✅ سليمة |
| `get_completed_tasks` | ❌ لا (تستخدم `appointment_id`) | ✅ سليمة |

**الخلاصة:** `get_lawyer_appointments` هي الوحيدة المكسورة.

---

## 🔴 BUG-003: Edge Function `social-publish` بلا مصدر بالريبو

### 3.1 ملخص المشكلة
**الخطورة:** 🟡 **متوسطة — Drift**  
**التأثير:** دَين انحراف — Edge Function منشورة على السيرفر لكن غير موجودة بالريبو

### 3.2 الوضع الحالي

**الريبو:**
```
supabase/functions/
├── publish-to-social/     ← موجود
│   └── index.ts
└── ...
```

**السيرفر:**
```
Edge Functions:
├── social-publish         ← منشور
├── publish-to-social      ← منشور
└── ...
```

### 3.3 الفرضيات

#### الفرضية 1: إعادة تسمية
- `social-publish` هو الاسم القديم
- `publish-to-social` هو الاسم الجديد
- القديم لم يُحذف من السيرفر

#### الفرضية 2: نسختان مختلفتان
- `social-publish` للنشر اليدوي
- `publish-to-social` للنشر التلقائي
- كلاهما مستخدم

#### الفرضية 3: خطأ في النشر
- نُشر `social-publish` بالخطأ من فرع قديم
- المصدر الحقيقي هو `publish-to-social`

### 3.4 التحليل

**فحص الكود:**
```bash
# الريبو
ls supabase/functions/ | grep -i social
# النتيجة: publish-to-social

# السيرفر
curl -H "Authorization: Bearer {PAT}" \
  "https://api.supabase.com/v1/projects/vsgkgnjtebjxyqwpuopz/functions"
# النتيجة: ["social-publish", "publish-to-social", ...]
```

**فحص الاستخدام في الكود:**
```bash
grep -r "social-publish\|publish-to-social" lib/
# النتيجة: publish-to-social فقط
```

**الخلاصة:**
- `publish-to-social` هو المستخدم في الكود
- `social-publish` غير مستخدم → يمكن حذفه

---

## 🟡 BUG-004: `user-rewards: daily_streak` لا يعمل

### 4.1 ملخص المشكلة
**الخطورة:** 🟢 **منخفضة — Functional**  
**التأثير:** المستخدمين لا يحصلون على نقاط الدخول اليومي

### 4.2 رسالة الخطأ
```json
{
  "success": false,
  "error": "UNKNOWN_ACTION"
}
```

### 4.3 التحليل

**فحص الكود:**
```typescript
// supabase/functions/user-rewards/index.ts
switch (action) {
  case "daily_streak": {
    // ...
  }
  default:
    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
}
```

**الاختبار:**
```json
{
  "action": "daily_streak",
  "user_uid": "..."
}
```

**النتيجة:** `UNKNOWN_ACTION` ⚠️

**الفرضيات:**
1. **خطأ إملائي:** `daily_streak` vs `dailyStreak` (camelCase)
2. **الدالة غير منشورة:** الكود موجود لكن لم يُنشر
3. **مشكلة في dispatch:** الـ switch لا يعمل بشكل صحيح

### 4.4 الفحص

**فحص النشر:**
```bash
# هل الدالة منشورة؟
curl -H "Authorization: Bearer {PAT}" \
  "https://api.supabase.com/v1/projects/vsgkgnjtebjxyqwpuopz/functions/user-rewards"
# النتيجة: منشورة ✅
```

**فحص الكود المنشور:**
```bash
# مقارنة الكود في الريبو مع السيرفر
# (يحتاج supabase functions download)
```

**الخلاصة:** يحتاج فحص أعمق للكود المنشور على السيرفر.

---

## 🟡 BUG-005: لا إشعارات لتغيير حالة الاستشارة

### 5.1 ملخص المشكلة
**الخطورة:** 🟢 **منخفضة — UX**  
**التأثير:** المستخدم لا يعلم بتحديث حالة استشارته القانونية

### 5.2 التحليل

**فحص الكود:**
```typescript
// supabase/functions/legal-actions/index.ts
if (action === "update_consultation_status") {
  // ... تحديث الحالة ...
  
  // ⚠️ لا يوجد notify_user() هنا
}
```

**المقارنة مع دوال أخرى:**
```typescript
// supabase/functions/admin-offers/index.ts
if (action === "approve") {
  // ... تحديث الحالة ...
  
  // ✅ يوجد notify_user()
  await supabaseAdmin.rpc("notify_user", {
    p_uid: userId,
    p_type: 2,
    p_title: "✅ تم قبول عرضك",
    p_body: "..."
  });
}
```

**الخلاصة:** `update_consultation_status` ينقصها `notify_user()`.

---

## 📊 ملخص التحليل

| Bug | الخطورة | الجذر | التعقيد | الحالة |
|-----|---------|-------|---------|--------|
| **BUG-001** | 🔴 حرجة | فحص auth.uid() معطّل + فحص الدور الخطأ | 🟢 بسيط (REVOKE فقط) | ✅ مُحلَّل |
| **BUG-002** | 🟡 متوسطة | تضارب اسم العمود في RETURNS TABLE | 🟢 بسيط (إزالة AS id) | ✅ مُحلَّل |
| **BUG-003** | 🟡 متوسطة | Edge Function قديمة لم تُحذف | 🟢 بسيط (حذف) | ✅ مُحلَّل |
| **BUG-004** | 🟢 منخفضة | UNKNOWN_ACTION | 🟡 يحتاج فحص أعمق | 🟡 قيد التحليل |
| **BUG-005** | 🟢 منخفضة | نقص notify_user() | 🟢 بسيط (إضافة) | ✅ مُحلَّل |

---

## 🎯 الخلاصة

### ما تم إنجازه
✅ **تحليل عميق** لـ 5 bugs  
✅ **تأكيد استغلالي** للثغرة الأمنية  
✅ **فهم الجذر** لكل مشكلة  
✅ **عدم اقتراح تعديلات** (حسب طلب المالك)

### ما لم يُنجز
⏳ **لم تُقترح إصلاحات** (بانتظار موافقة المالك)  
⏳ **لم تُنفَّذ تعديلات** (حسب قاعدة "لا تغيير قبل الفحص")

### الخطوات التالية المقترحة

1. **الموافقة على التحليل:** هل التحليل دقيق وكامل؟
2. **اقتراح الإصلاحات:** بعد الموافقة، أقترح إصلاحات محددة
3. **الموافقة على الإصلاحات:** المالك يراجع ويوافق
4. **تنفيذ الإصلاحات:** بعد الموافقة الصريحة

---

**الحالة:** 🟡 **بانتظار موافقة المالك على التحليل**  
**التاريخ:** 2026-08-05  
**الإصدار:** 1.0
