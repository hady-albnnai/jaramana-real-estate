-- ============================================================================
-- 🔴 إصلاح: الإعلان المميّز المدفوع لا يظهر مميّزاً إطلاقاً
-- التاريخ: 2026-07-29
--
-- الجذر (مُثبت حيّاً): approve_payment_final عند اعتماد دفعة ممولة (tp=1)
-- تكتب fms_end فقط ولا تلمس i_fms. بينما:
--   • الشارة «⭐ مميز» شرطها  offer.iFms == 1   (offer_card.dart:238)
--   • الترتيب بالرئيسية والبحث  .order('i_fms') (offer_provider.dart)
--   • كنس المنتهي شرطه  WHERE i_fms = 1 AND fms_end < NOW()
-- ⇒ الزبون يدفع، الإدارة تعتمد، الرد success:true — ولا يحصل على شيء مرئي،
--   و fms_end يبقى يتيماً للأبد لأن الكنس لا يلتقطه.
--
-- الإصلاح ثلاثي:
--   ① approve_payment_final تضبط i_fms=1 مع fms_end بنفس UPDATE
--   ② expire_offer_boosts تكنس بشرط fms_end وحده (تنظّف اليتامى)
--   ③ تصحيح بيانات لمرة واحدة للعروض المدفوعة الفعّالة
-- ============================================================================

-- ① ─────────────── إصلاح فرع الممولة داخل approve_payment_final
--    نعدّل UPDATE واحدة فقط داخل جسم الدالة الحيّة (بقية المنطق كما هو حرفياً).
DO $$
DECLARE
  v_src TEXT;
  v_new TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'approve_payment_final'
  LIMIT 1;

  IF v_src IS NULL THEN
    RAISE EXCEPTION 'approve_payment_final غير موجودة';
  END IF;

  -- الحارس: إن كانت مُصلَحة سابقاً لا نفعل شيئاً (idempotent)
  IF position('SET i_fms = 1, fms_end = GREATEST' in v_src) > 0 THEN
    RAISE NOTICE 'مُصلَحة سابقاً — لا تغيير';
    RETURN;
  END IF;

  v_new := replace(
    v_src,
    'SET fms_end = GREATEST(NOW(), COALESCE(fms_end, NOW()))',
    'SET i_fms = 1, fms_end = GREATEST(NOW(), COALESCE(fms_end, NOW()))'
  );

  IF v_new = v_src THEN
    RAISE EXCEPTION 'لم يُعثر على نمط UPDATE المتوقع — أوقف ولا تخمّن';
  END IF;

  EXECUTE v_new;
  RAISE NOTICE 'تم تعديل approve_payment_final';
END $$;

-- ② ─────────────── كنس المنتهي: الشرط على fms_end وحده (يلتقط اليتامى)
DO $$
DECLARE
  v_src TEXT;
  v_new TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'expire_offer_boosts'
  LIMIT 1;

  IF v_src IS NULL THEN
    RAISE NOTICE 'expire_offer_boosts غير موجودة — تخطٍّ';
    RETURN;
  END IF;

  IF position('WHERE fms_end IS NOT NULL AND fms_end < NOW()' in v_src) > 0 THEN
    RAISE NOTICE 'الكنس مُصلَح سابقاً';
    RETURN;
  END IF;

  v_new := replace(
    v_src,
    'WHERE i_fms = 1 AND fms_end < NOW()',
    'WHERE fms_end IS NOT NULL AND fms_end < NOW()'
  );

  IF v_new = v_src THEN
    RAISE NOTICE 'نمط الكنس غير متطابق — يُترك كما هو';
    RETURN;
  END IF;

  EXECUTE v_new;
  RAISE NOTICE 'تم تعديل expire_offer_boosts';
END $$;

-- ③ ─────────────── تصحيح البيانات: كل عرض مدفوع فعّال يُرفع علمه
UPDATE public.offers
SET i_fms = 1
WHERE i_del = 0
  AND i_fms = 0
  AND fms_end IS NOT NULL
  AND fms_end > NOW();

-- ============================================================================
-- ✅ تحققات
-- ============================================================================

-- ① الدالة تضبط العلم  → المتوقع: true
SELECT position('SET i_fms = 1, fms_end = GREATEST' in pg_get_functiondef(p.oid)) > 0 AS approve_fixed
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'approve_payment_final';

-- ② الكنس يلتقط اليتامى  → المتوقع: true
SELECT position('WHERE fms_end IS NOT NULL AND fms_end < NOW()' in pg_get_functiondef(p.oid)) > 0 AS sweep_fixed
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'expire_offer_boosts';

-- ③ لا يتامى  → المتوقع: 0
SELECT count(*) AS orphans
FROM public.offers
WHERE i_del = 0 AND i_fms = 0 AND fms_end IS NOT NULL AND fms_end > NOW();
