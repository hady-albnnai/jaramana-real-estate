-- ============================================================================
-- 2026_08_15 — CONS-002: الحارس يحسب المحادثة المنتهية «قائمة» فيسدّ الطريق
-- ============================================================================
-- بلاغ المالك (اختبار حي): «بعد ما يقبل المحامي وأحاول أكمّل، برجع
-- يطلعلي لازم أدفع».
--
-- التشخيص الحي على استشارة هناء (1467b5ed):
--   • chat_started_at قبل 22.9 دقيقة · chat_duration_minutes = 15
--   • الواجهة تحسبها **منتهية** (timeUp) ⇒ لا تعرضها كاستشارة نشطة
--   • السيرفر (CONS-001) يحسبها **قائمة** لأن status = 1 فقط
--   ⇒ تناقض: المستخدم لا يرى استشارته النشطة (فيظن أن عليه البدء من
--     جديد)، وحين يحاول يرفضه السيرفر بـOPEN_CONSULTATION_EXISTS التي
--     تُترجَم لرسالة توحي بأن عليه الدفع ⇒ طريق مسدود تماماً.
--
-- القاعدة الصحيحة: **المحادثة المنتهية وقتها لم تعد قائمة**، فلا تمنع
-- المستخدم من حجز استشارة جديدة (وهذا هو مصدر دخل المكتب أصلاً — تجديد
-- أو استشارة جديدة). المنع يبقى فقط على:
--   • status = 0 (بانتظار قبول المحامي) — لم تبدأ بعد
--   • status = 5 (بانتظار استكمال بيانات) — الكرة بملعب المستخدم
--   • status = 1 **والمحادثة لم تبدأ** — مقبولة وتنتظر فتح المحامي
--   • status = 1 والمحادثة **جارية ووقتها لم ينتهِ** — نشطة فعلاً
--
-- ⚠️ هذا يطابق منطق الواجهة حرفاً بحرف (timeUp) فلا تتناقض الطبقتان مجدداً.
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

  IF p_service_type IS NULL OR p_service_type NOT IN (0, 1) THEN
    RAISE EXCEPTION 'INVALID_SERVICE_TYPE';
  END IF;

  -- (أ) دفعة معلّقة لنفس النوع
  SELECT COUNT(*) INTO v_pending_pay
    FROM payments
   WHERE uid = p_user_uid AND tp = 2 AND sts = 0
     AND COALESCE(pkg, 0) = p_service_type;
  IF v_pending_pay > 0 THEN
    RAISE EXCEPTION 'PENDING_CONSULTATION_PAYMENT_EXISTS';
  END IF;

  -- (ب) استشارة قائمة فعلاً لنفس النوع
  -- 🔧 CONS-002: المحادثة المنتهية وقتها لا تُحسب قائمة (مطابق للواجهة).
  SELECT COUNT(*) INTO v_open_cons
    FROM legal_consultations
   WHERE user_uid     = p_user_uid
     AND service_type = p_service_type
     AND (
          status IN (0, 5)                       -- لم تبدأ / تنتظر بياناتك
       OR (status = 1 AND chat_started_at IS NULL)  -- مقبولة ولمّا تُفتح
       OR (status = 1 AND chat_started_at IS NOT NULL
           AND NOW() < chat_started_at
                       + make_interval(mins => COALESCE(chat_duration_minutes, 15)))
     );
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
