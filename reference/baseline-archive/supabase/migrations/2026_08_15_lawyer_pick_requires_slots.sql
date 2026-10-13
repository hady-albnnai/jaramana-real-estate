-- ============================================================================
-- 2026_08_15 — LAW-002: الإسناد الحضوري يتجاهل أوقات دوام المحامي
-- ============================================================================
-- اكتُشف أثناء اختبار PAY-001: كل محاولة حجز حضوري تفشل بـ
-- SLOT_NO_LONGER_AVAILABLE رغم توفّر 80 موعداً.
--
-- السبب الجذري:
--   `pick_next_lawyer` ترتّب بـ(الأقل انشغالاً ثم الأقدم) ولا تنظر إلى
--   `avl` إطلاقاً. فأُسند الطلب لمحامي ٢ (0 مهام) الذي `avl = {}` ⇒
--   `get_lawyer_free_slots` تُرجع صفر مواعيد له ⇒ التحقق يفشل ⇒ الحجز
--   يُرفض **حتماً** مهما اختار المستخدم من مواعيد.
--   والأسوأ: المستخدم يرى مواعيد محامٍ (الذي بُنيت له الشاشة) ثم يُسنَد
--   طلبه لمحامٍ آخر بلا أوقات — تناقض داخلي كامل.
--
-- الإصلاح: معامل اختياري `p_require_slots` — عند طلب جلسة حضورية نستبعد
-- من لا أوقات لديه. الاستشارة الهاتفية تبقى بلا هذا القيد (لا تحتاج
-- مواعيد)، فقاعدة المالك «الدور والأقل انشغالاً» تبقى سارية فيها.
--
-- ⚠️ الترتيب لا يتغيّر: الأقل انشغالاً ثم الأقدم — نُصفّي فقط من يستحيل
--    عليه استقبال الحجز.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.pick_next_lawyer(
  p_exclude        uuid[] DEFAULT '{}'::uuid[],
  p_require_slots  boolean DEFAULT false
)
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  SELECT lp.uid
  FROM lawyer_profiles lp
  JOIN users u ON u.id = lp.uid
  WHERE lp.is_active = TRUE          -- ① متاح (زر التوفر)
    AND u.role = 7
    AND u.sts  = 0
    AND u.i_del = 0
    AND NOT (lp.uid = ANY(COALESCE(p_exclude, '{}')))
    -- ④ LAW-002: للحجز الحضوري فقط — من لا أوقات لديه لا يستقبل موعداً
    AND (
      NOT p_require_slots
      OR (lp.avl IS NOT NULL AND lp.avl <> '{}'::jsonb AND lp.avl <> 'null'::jsonb)
    )
  ORDER BY lp.active_tasks_count ASC, -- ② الأقل انشغالاً
           lp.created_at ASC          -- ③ الدور (الأقدم)
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.pick_next_lawyer(uuid[], boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.pick_next_lawyer(uuid[], boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pick_next_lawyer(uuid[], boolean) TO service_role;

-- تمرير النوع من دالة إنشاء الاستشارة (1 = حضورية ⇒ تتطلب أوقاتاً)
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

  IF p_service_type IS NULL OR p_service_type NOT IN (0, 1) THEN
    RAISE EXCEPTION 'INVALID_SERVICE_TYPE';
  END IF;

  -- 🔒 CONS-001: حارس «نفس النوع» (دفعة معلّقة أو استشارة قائمة)
  SELECT COUNT(*) INTO v_pending_pay
    FROM payments
   WHERE uid = p_user_uid AND tp = 2 AND sts = 0
     AND COALESCE(pkg, 0) = p_service_type;
  IF v_pending_pay > 0 THEN
    RAISE EXCEPTION 'PENDING_CONSULTATION_PAYMENT_EXISTS';
  END IF;

  SELECT COUNT(*) INTO v_open_cons
    FROM legal_consultations
   WHERE user_uid = p_user_uid AND service_type = p_service_type
     AND status IN (0, 1, 5);
  IF v_open_cons > 0 THEN
    RAISE EXCEPTION 'OPEN_CONSULTATION_EXISTS';
  END IF;

  -- ⚖️ LAW-002: الحضورية تتطلب محامياً له أوقات دوام مضبوطة
  v_lawyer_uid := public.pick_next_lawyer('{}', p_service_type = 1);

  RETURN QUERY
  INSERT INTO legal_consultations (user_uid, lawyer_uid, service_type, subject, price, status, ts_crt, ts_upd)
  VALUES (p_user_uid, v_lawyer_uid, p_service_type, p_subject, p_price, 0, NOW(), NOW())
  RETURNING *;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_legal_consultation_internal(uuid, integer, text, numeric) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_legal_consultation_internal(uuid, integer, text, numeric) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_legal_consultation_internal(uuid, integer, text, numeric) TO service_role;
