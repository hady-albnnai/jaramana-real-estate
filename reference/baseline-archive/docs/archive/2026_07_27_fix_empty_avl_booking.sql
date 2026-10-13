-- ============================================================
-- تصحيح بيانات يُنفَّذ مرة واحدة — 2026-07-27
-- البلاغ: «لا توجد مواعيد متاحة حالياً» عند حجز موعد معاينة
-- السبب: عروض محفوظة بـ avl فارغة {} أو أيام مفعّلة بلا فترات
--        مثل {"mon":[],"thu":[]} (كانت تُحفظ بصمت من التطبيق)
-- الحل: أي عرض حي بدون أي فترة معاينة فعلية → «جاهز بأي وقت»
-- آمن للتكرار (idempotent) — الصفوف المصححة لا تدخل الشرط مجدداً
-- ============================================================

-- الخطوة 1/3: معاينة الصفوف التي ستُعدَّل (قراءة فقط — لا تغيّر شيئاً)
SELECT id, ttl, avl, sts
FROM public.offers
WHERE i_del = 0
  AND NOT (COALESCE(avl, '{}'::jsonb) ? 'any')
  AND NOT EXISTS (
    SELECT 1
    FROM jsonb_each(COALESCE(avl, '{}'::jsonb)) e
    WHERE jsonb_typeof(e.value) = 'array'
      AND jsonb_array_length(e.value) > 0
  );

-- الخطوة 2/3: التعديل الفعلي — نفس شرط المعاينة حرفياً
-- الصيغة {"any":["00:00-23:59"]} هي نفسها التي يكتبها التطبيق
UPDATE public.offers
SET avl = jsonb_build_object('any', jsonb_build_array('00:00-23:59'))
WHERE i_del = 0
  AND NOT (COALESCE(avl, '{}'::jsonb) ? 'any')
  AND NOT EXISTS (
    SELECT 1
    FROM jsonb_each(COALESCE(avl, '{}'::jsonb)) e
    WHERE jsonb_typeof(e.value) = 'array'
      AND jsonb_array_length(e.value) > 0
  );

-- الخطوة 3/3: التحقق النهائي — كل عرض حي لازم يطلع عنده أي من:
--   {"any": [...]}   أو   يوم واحد على الأقل فيه فترة غير فارغة
SELECT id, ttl, avl
FROM public.offers
WHERE i_del = 0;
