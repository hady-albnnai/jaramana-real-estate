# 🔧 مقترحات الإصلاح — 2026-08-05

> **التاريخ:** 2026-08-05  
> **الحالة:** 📋 مقترحات (بانتظار موافقة المالك)  
> **القاعدة:** لا تنفيذ قبل الموافقة الصريحة  
> **المنهجية:** إصلاحات دقيقة تحافظ على المنطق الأصلي + لا تفتح ثغرات

---

## 🔴 BUG-001: تسريب أمني — `get_admin_requests_internal`

### 1.1 الإصلاح المقترح

**النوع:** SQL Migration (REVOKE فقط)  
**التعقيد:** 🟢 بسيط جداً  
**التأثير:** إغلاق الثغرة الأمنية فوراً

### 1.2 الكود المقترح

```sql
-- File: supabase/migrations/2026_08_05_fix_admin_requests_security.sql
-- Purpose: إغلاق الثغرة الأمنية في get_admin_requests_internal
-- Impact: يمنع anon/authenticated من استدعاء الدالة

-- ════════════════════════════════════════════════════════════════════════
-- 🔒 Step 1: REVOKE من anon و authenticated
-- ════════════════════════════════════════════════════════════════════════

REVOKE EXECUTE ON FUNCTION public.get_admin_requests_internal(uuid) 
FROM anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════
-- ✅ Step 2: GRANT لـ service_role فقط
-- ════════════════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION public.get_admin_requests_internal(uuid) 
TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- 🧪 Step 3: التحقق
-- ════════════════════════════════════════════════════════════════════════

-- يجب أن يُرجع false
SELECT has_function_privilege('anon', 'get_admin_requests_internal(uuid)', 'EXECUTE') AS anon_can_exec;

-- يجب أن يُرجع false
SELECT has_function_privilege('authenticated', 'get_admin_requests_internal(uuid)', 'EXECUTE') AS auth_can_exec;

-- يجب أن يُرجع true
SELECT has_function_privilege('service_role', 'get_admin_requests_internal(uuid)', 'EXECUTE') AS svc_can_exec;
```

### 1.3 لماذا هذا الإصلاح كافٍ؟

**السبب:**
- الدالة تُستدعى فقط عبر Edge Functions (التي تستخدم `service_role`)
- Edge Functions تتحقق من الهوية داخلياً (`validate_staff_session`)
- لا يوجد أي كود Flutter يستدعي الدالة مباشرة (كلها عبر Edge)

**الدليل:**
```bash
# فحص الاستخدام في الكود
grep -r "get_admin_requests_internal" lib/
# النتيجة: 0 نتائج ✅

# Edge Function المستخدمة
grep -r "get_admin_requests_internal" supabase/functions/
# النتيجة: admin-dashboard/index.ts (يستخدم service_role) ✅
```

### 1.4 التأثير المتوقع

**قبل الإصلاح:**
```bash
curl ... -H "Authorization: Bearer {ANON}" -d '{"p_admin_uid":"..."}'
# HTTP 200 + بيانات كاملة 🔴
```

**بعد الإصلاح:**
```bash
curl ... -H "Authorization: Bearer {ANON}" -d '{"p_admin_uid":"..."}'
# HTTP 401: permission denied ✅
```

### 1.5 خطوات التنفيذ

1. **الموافقة:** المالك يوافق على الإصلاح
2. **اللصق:** المالك يلصق SQL في Supabase SQL Editor
3. **التحقق:** تشغيل الـ SELECTs الثلاثة
4. **الرفع:** commit + push الـ migration file

### 1.6 خطوات التحقق

```bash
# اختبار استغلالي (يجب أن يفشل)
python3 /tmp/test_leak_real.py
# المتوقع: HTTP 401 ✅

# اختبار شرعي (يجب أن ينجح)
# Login كمدير → admin-dashboard Edge Function → يجب أن يعمل ✅
```

---

## 🔴 BUG-002: خطأ SQL — `get_lawyer_appointments`

### 2.1 الإصلاح المقترح

**النوع:** SQL Migration (تعديل الدالة)  
**التعقيد:** 🟢 بسيط  
**التأثير:** إصلاح الخطأ دون تغيير المنطق

### 2.2 الكود المقترح

```sql
-- File: supabase/migrations/2026_08_05_fix_lawyer_appointments.sql
-- Purpose: إصلاح خطأ "column reference 'id' is ambiguous"
-- Impact: المحامي يستطيع رؤية مواعيده

-- ════════════════════════════════════════════════════════════════════════
-- 🔧 Step 1: DROP التوقيع القديم
-- ════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.get_lawyer_appointments(uuid);

-- ════════════════════════════════════════════════════════════════════════
-- ✅ Step 2: CREATE بالتوقيع الصحيح
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_lawyer_appointments(p_lawyer_uid uuid)
RETURNS TABLE(
  appt_id uuid,           -- ✅ غيّرنا من id إلى appt_id
  client_name text,
  client_phone text,
  dt timestamp with time zone,
  sts integer,
  notes text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role int;
BEGIN
  -- فحص الدور (بدون تغيير)
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  -- إرجاع المواعيد (بدون تغيير في المنطق)
  RETURN QUERY
  SELECT
    a.id AS appt_id,      -- ✅ غيّرنا من AS id إلى AS appt_id
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

-- ════════════════════════════════════════════════════════════════════════
-- 🔒 Step 3: رباعي التحصين
-- ════════════════════════════════════════════════════════════════════════

REVOKE ALL ON FUNCTION public.get_lawyer_appointments(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_lawyer_appointments(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_lawyer_appointments(uuid) TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- 🧪 Step 4: التحقق
-- ════════════════════════════════════════════════════════════════════════

-- يجب أن ينجح بدون خطأ
SELECT * FROM get_lawyer_appointments('427da6f4-3a7f-4c19-aa7a-24cda805bd6f') LIMIT 1;
```

### 2.3 لماذا غيّرنا `id` إلى `appt_id`؟

**السبب:**
- `RETURNS TABLE(id uuid, ...)` يُنشئ OUT parameter اسمه `id`
- `SELECT a.id AS id` يُرجع عمود اسمه `id`
- PostgreSQL يرى تضارب بين الاثنين

**الحل:**
- غيّرنا اسم الـ OUT parameter إلى `appt_id`
- غيّرنا الـ alias إلى `AS appt_id`
- النتيجة: لا تضارب ✅

### 2.4 هل هذا يغير المنطق؟

**لا، المنطق مطابق 100%:**
- ✅ نفس فحص الدور (`v_role <> 7`)
- ✅ نفس JOIN (`appointments` + `users`)
- ✅ نفس WHERE (`bkr_id = p_lawyer_uid`)
- ✅ نفس ORDER BY (`dt DESC`)
- ✅ نفس الأعمدة المُرجعة (فقط غيّرنا الاسم)

### 2.5 التأثير على الكود

**فحص الاستخدام:**
```bash
grep -r "get_lawyer_appointments" lib/
# النتيجة: 0 نتائج ✅
```

**الخلاصة:** لا يوجد كود Flutter يستدعي الدالة مباشرة → لا تأثير على الكود.

### 2.6 التأثير على Edge Function

**فحص الاستخدام:**
```bash
grep -r "get_lawyer_appointments" supabase/functions/legal-actions/
# النتيجة: يُستخدم في action: "get_lawyer_appointments"
```

**الكود في Edge Function:**
```typescript
const { data, error } = await supabaseAdmin.rpc("get_lawyer_appointments", {
  p_lawyer_uid: uid
});

// Edge Function يُرجع data كما هي
return json({ success: true, appointments: data ?? [] });
```

**التأثير:**
- Edge Function يُرجع `appointments` array
- كل appointment له `appt_id` بدل `id`
- **لا تأثير على Flutter** لأنه لا يستخدم هذه الدالة

### 2.7 خطوات التنفيذ

1. **الموافقة:** المالك يوافق على الإصلاح
2. **اللصق:** المالك يلصق SQL في Supabase SQL Editor
3. **التحقق:** تشغيل `SELECT * FROM get_lawyer_appointments(...)`
4. **الرفع:** commit + push الـ migration file

### 2.8 خطوات التحقق

```bash
# Login كمحامي
python3 /tmp/test_lawyer_v2.py

# اختبار get_lawyer_appointments
# المتوقع: ينجح بدون خطأ ✅
```

---

## 🔴 BUG-003: Edge Function `social-publish` بلا مصدر

### 3.1 الإصلاح المقترح

**النوع:** حذف Edge Function من السيرفر  
**التعقيد:** 🟢 بسيط جداً  
**التأثير:** إزالة دَين الانحراف

### 3.2 الكود المقترح

```bash
# حذف Edge Function من السيرفر
supabase functions delete social-publish --project-ref vsgkgnjtebjxyqwpuopz
```

### 3.3 لماذا الحذف آمن؟

**الدليل:**
```bash
# 1. الكود يستخدم publish-to-social فقط
grep -r "social-publish" lib/
# النتيجة: 0 نتائج ✅

grep -r "publish-to-social" lib/
# النتيجة: يُستخدم في offer_provider.dart ✅

# 2. الريبو يحتوي publish-to-social فقط
ls supabase/functions/ | grep -i social
# النتيجة: publish-to-social ✅

# 3. السيرفر يحتوي الاثنين
curl ... /functions
# النتيجة: ["social-publish", "publish-to-social", ...]
```

**الخلاصة:**
- `social-publish` غير مستخدم في الكود
- `publish-to-social` هو المستخدم فعلياً
- حذف `social-publish` لا يؤثر على شيء

### 3.4 خطوات التنفيذ

1. **الموافقة:** المالك يوافق على الحذف
2. **الحذف:** المالك ينفذ `supabase functions delete social-publish`
3. **التحقق:** فحص قائمة Edge Functions
4. **التوثيق:** تحديث `docs/CURRENT_STATUS.md`

### 3.5 خطوات التحقق

```bash
# فحص قائمة Edge Functions
curl -H "Authorization: Bearer {PAT}" \
  "https://api.supabase.com/v1/projects/vsgkgnjtebjxyqwpuopz/functions"

# المتوقع: social-publish غير موجودة ✅
```

---

## 🟡 BUG-004: `user-rewards: daily_streak` لا يعمل

### 4.1 الإصلاح المقترح

**النوع:** فحص أعمق (لم يُحدد بعد)  
**التعقيد:** 🟡 متوسط  
**التأثير:** إصلاح نقاط الدخول اليومي

### 4.2 المشكلة

**الاختبار:**
```json
{
  "action": "daily_streak",
  "user_uid": "..."
}
```

**النتيجة:** `UNKNOWN_ACTION` ⚠️

### 4.3 الفرضيات

#### الفرضية 1: خطأ إملائي
- الكود يستخدم `daily_streak` (snake_case)
- الاختبار يستخدم `daily_streak` (snake_case)
- **الخلاصة:** ليس خطأ إملائي ❌

#### الفرضية 2: الدالة غير منشورة
- الدالة منشورة (تحققنا)
- **الخلاصة:** ليست المشكلة ❌

#### الفرضية 3: الكود المنشور قديم
- الكود في الريبو يحتوي `case "daily_streak"`
- الكود المنشور قد لا يحتويه
- **الخلاصة:** يحتاج إعادة نشر ⚠️

### 4.4 الإصلاح المقترح

```bash
# إعادة نشر Edge Function
supabase functions deploy user-rewards \
  --no-verify-jwt \
  --project-ref vsgkgnjtebjxyqwpuopz
```

### 4.5 خطوات التنفيذ

1. **الموافقة:** المالك يوافق على إعادة النشر
2. **النشر:** المالك ينفذ `supabase functions deploy user-rewards`
3. **التحقق:** اختبار `daily_streak` مرة أخرى
4. **التوثيق:** تحديث `docs/CURRENT_STATUS.md`

### 4.6 خطوات التحقق

```bash
# اختبار daily_streak
python3 /tmp/test_rewards.py

# المتوقع: ينجح ويعيد نقاط ✅
```

---

## 🟡 BUG-005: لا إشعارات لتغيير حالة الاستشارة

### 5.1 الإصلاح المقترح

**النوع:** تعديل Edge Function (إضافة notify_user)  
**التعقيد:** 🟡 متوسط  
**التأثير:** إرسال إشعارات عند تغيير حالة الاستشارة

### 5.2 الكود المقترح

**الملف:** `supabase/functions/legal-actions/index.ts`

```typescript
if (action === "update_consultation_status") {
  // ... الكود الحالي (بدون تغيير) ...
  
  const { error: updErr } = await supabaseAdmin
    .from("legal_consultations")
    .update({ status: newStatus, ts_upd: new Date().toISOString() })
    .eq("id", consultId);
  
  if (updErr) {
    return json({ success: false, error: "UPDATE_FAILED" }, 500);
  }

  // ════════════════════════════════════════════════════════════════════════
  // ✅ إضافة: إرسال إشعار للمستخدم
  // ════════════════════════════════════════════════════════════════════════
  
  const statusNames: Record<number, string> = {
    0: "بانتظار المراجعة",
    1: "مؤكدة",
    2: "مكتملة",
    3: "ملغاة",
    4: "مرفوضة"
  };
  
  const statusName = statusNames[newStatus] ?? "محدّثة";
  
  await supabaseAdmin.rpc("notify_user", {
    p_uid: row.user_uid,
    p_type: 2,  // notification type
    p_title: `📋 تحديث حالة الاستشارة`,
    p_body: `تم تحديث حالة استشارتك "${row.subject}" إلى: ${statusName}`,
    p_ref_id: consultId,
    p_action: "consultation_update"
  });

  return json({ success: true });
}
```

### 5.3 لماذا هذا الإصلاح صحيح؟

**المقارنة مع دوال أخرى:**
```typescript
// admin-offers/index.ts — نفس النمط
await supabaseAdmin.rpc("notify_user", {
  p_uid: userId,
  p_type: 2,
  p_title: "✅ تم قبول عرضك",
  p_body: "...",
  p_ref_id: offerId,
  p_action: "offer_approved"
});
```

**الخلاصة:** نفس النمط المُستخدم في باقي Edge Functions.

### 5.4 هل هذا يغير المنطق؟

**لا، إضافة فقط:**
- ✅ نفس فحص الصلاحيات
- ✅ نفس تحديث الحالة
- ✅ نفس التحقق من الانتقالات
- ➕ إضافة `notify_user()` في النهاية

### 5.5 خطوات التنفيذ

1. **الموافقة:** المالك يوافق على التعديل
2. **التعديل:** تعديل `supabase/functions/legal-actions/index.ts`
3. **النشر:** `supabase functions deploy legal-actions --no-verify-jwt`
4. **التحقق:** اختبار تغيير الحالة + فحص الإشعارات
5. **الرفع:** commit + push

### 5.6 خطوات التحقق

```bash
# Login كمحامي
python3 /tmp/test_consultation_v2.py

# تغيير حالة استشارة (0 -> 1)
# Expected: success + notification sent ✅

# Login كمستخدم
python3 /tmp/check_notifications.py

# Expected: إشعار "تم تحديث حالة استشارتك" ✅
```

---

## 📊 ملخص الإصلاحات

| Bug | النوع | التعقيد | التأثير | الحالة |
|-----|-------|---------|---------|--------|
| **BUG-001** | SQL REVOKE | 🟢 بسيط | إغلاق ثغرة أمنية | 📋 مقترح |
| **BUG-002** | SQL تعديل دالة | 🟢 بسيط | إصلاح خطأ SQL | 📋 مقترح |
| **BUG-003** | حذف Edge Function | 🟢 بسيط جداً | إزالة دَين انحراف | 📋 مقترح |
| **BUG-004** | إعادة نشر Edge Function | 🟢 بسيط | إصلاح نقاط يومية | 📋 مقترح |
| **BUG-005** | تعديل Edge Function | 🟡 متوسط | إضافة إشعارات | 📋 مقترح |

---

## 🎯 خطة التنفيذ المقترحة

### الأولوية الحرجة (فوري)
1. ✅ **BUG-001:** REVOKE (SQL)
2. ✅ **BUG-002:** تعديل الدالة (SQL)

### الأولوية المتوسطة (هذا الأسبوع)
3. ✅ **BUG-003:** حذف Edge Function
4. ✅ **BUG-004:** إعادة نشر Edge Function

### الأولوية المنخفضة (لاحقاً)
5. ✅ **BUG-005:** تعديل Edge Function + نشر

---

## ❓ الخطوة التالية

**الخيارات:**

1. **"وافق على الكل"** — أنفذ كل الإصلاحات الخمسة
2. **"وافق على الحرجة فقط"** — أنفذ BUG-001 و BUG-002 فقط
3. **"وافق على بعضها"** — حدد أيها توافق عليه
4. **"عندي ملاحظات"** — عندك أسئلة أو تعديلات على المقترحات

**تذكير:** لا تنفيذ قبل الموافقة الصريحة. الإصلاحات مكتوبة في `PROPOSED_FIXES_2026_08_05.md`.

شو رأيك؟ 🚀
