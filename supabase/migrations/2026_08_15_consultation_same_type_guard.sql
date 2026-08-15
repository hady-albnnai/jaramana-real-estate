-- ============================================================================
-- 2026_08_15 — CONS-001: منع حجز استشارة جديدة من **نفس النوع** أثناء التعليق
-- ============================================================================
-- البلاغ (اختبار حي من المالك 2026-08-15):
--   «يمكن حالياً بعد إرسال إثبات الدفع أن أقوم بحجز استشارة أخرى وهذا مخالف»
--
-- التشخيص:
--   • `create_legal_consultation_internal` كانت **22 سطراً** حارسها الوحيد
--     `AUTH_UID_MISMATCH` — صفر فحص لدفعة معلّقة أو استشارة مفتوحة.
--   • الحارس الوحيد كان **في الواجهة** (`_guardPending` في
--     legal_consultation_booking_screen.dart) ⇒ أي نداء API مباشر يتجاوزه
--     ويُنشئ استشارات بلا حد.
--   • دليل حي: دفعة استشارة معلّقة (500 ل.س، sts=0) بينما
--     legal_consultations لهناء = **صفر صفوف** ⇒ الدفعة بلا استشارة مرتبطة.
--   • تناقض معماري: الباقات محمية خادمياً بـ`PENDING_PAYMENT_EXISTS`
--     (في create_payment_internal) بينما الاستشارات مكشوفة تماماً.
--
-- قرار المالك (حرفياً): «نفس النوع — والأنواع أقصد بها هاتفية أو حضورية»
--   ⇒ هاتفية معلّقة تمنع هاتفية جديدة، ولا تمنع الحضورية، والعكس صحيح.
--   هذا يطابق منطق الواجهة القائم فلا تتناقض الطبقتان.
--
-- نطاق المنع (نفس النوع فقط):
--   1) دفعة استشارة معلّقة  (payments: tp=2, sts=0, pkg=service_type)
--   2) استشارة قائمة غير منتهية (legal_consultations.status ∈ 0,1,5)
--      • 0 بانتظار · 1 قيد التنفيذ · 5 بانتظار استكمال بيانات
--      • 2 تمّت · 3 ملغاة · 4 مرفوضة ⇒ **لا تمنع** (منتهية فعلياً)
--
-- ⚠️ ملاحظة مقصودة: `payments.pkg` هو الذي يحمل `service_type` لدفعات tp=2
--    (0 هاتفية · 1 حضورية) — مؤكَّد من create_payment_internal الذي يقرأ
--    السعر بـ`v_pkg = 1 ⇒ onsite`. لذا المقارنة على pkg لا على عمود آخر.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_legal_consultation_internal(
  p_user_uid     uuid,
  p_service_type integer,
  p_subject      text,
  p_price        numeric
)
RETURNS SETOF legal_consultations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_lawyer_uid  UUID;
  v_pending_pay INT;
  v_open_cons   INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  -- حراسة المدخلات: النوع 0 هاتفية · 1 حضورية لا غير.
  IF p_service_type IS NULL OR p_service_type NOT IN (0, 1) THEN
    RAISE EXCEPTION 'INVALID_SERVICE_TYPE';
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 🔒 CONS-001: حارس «نفس النوع» — خادمي لا يُلتف عليه
  -- ═══════════════════════════════════════════════════════════════════
  -- (أ) دفعة معلّقة لنفس النوع
  SELECT COUNT(*) INTO v_pending_pay
    FROM payments
   WHERE uid = p_user_uid
     AND tp  = 2
     AND sts = 0
     AND COALESCE(pkg, 0) = p_service_type;

  IF v_pending_pay > 0 THEN
    RAISE EXCEPTION 'PENDING_CONSULTATION_PAYMENT_EXISTS';
  END IF;

  -- (ب) استشارة قائمة غير منتهية لنفس النوع
  SELECT COUNT(*) INTO v_open_cons
    FROM legal_consultations
   WHERE user_uid     = p_user_uid
     AND service_type = p_service_type
     AND status IN (0, 1, 5);

  IF v_open_cons > 0 THEN
    RAISE EXCEPTION 'OPEN_CONSULTATION_EXISTS';
  END IF;

  -- المصدر الوحيد لمنطق الإسناد (متاح + الأقل انشغالاً + الأقدم)
  v_lawyer_uid := public.pick_next_lawyer('{}');

  RETURN QUERY
  INSERT INTO legal_consultations (user_uid, lawyer_uid, service_type, subject, price, status, ts_crt, ts_upd)
  VALUES (p_user_uid, v_lawyer_uid, p_service_type, p_subject, p_price, 0, NOW(), NOW())
  RETURNING *;
END;
$function$;

-- ============================================================================
-- §7 رباعي التحصين
-- ============================================================================
REVOKE ALL ON FUNCTION public.create_legal_consultation_internal(uuid, integer, text, numeric) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_legal_consultation_internal(uuid, integer, text, numeric) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_legal_consultation_internal(uuid, integer, text, numeric) TO service_role;
