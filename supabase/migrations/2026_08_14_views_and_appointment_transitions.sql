-- ============================================================================
-- BUG-024 — عدّاد المشاهدات قابل للتضخيم بلا حد
-- ============================================================================
-- الثغرة (مؤكَّدة حياً 2026-08-14): 20 نداء متتالياً لـincrement_views بلا أي
-- مصادقة رفع العدّاد من 9 إلى 29. لا حد لكل جهاز ولا نافذة زمنية.
--
-- التعليق في الكود توقّع الاستغلال في اتجاه **التقليل** فقط («تمرير viewer_uid
-- لشخص آخر... أي تقليل لا نفع منه للمهاجم») وأغفل الاتجاه المعاكس: التضخيم.
-- والمشاهدات ليست رقماً تجميلياً — صاحب عرض يضخّمها ليبدو عرضه رائجاً، وهي
-- مؤشّر تعتمده الإدارة في التقارير.
--
-- الحل: نافذة تهدئة لكل (عرض + جهاز) — مشاهدة واحدة تُحتسب كل 30 دقيقة.
-- بلا معرّف جهاز نستخدم بصمة الطلب، والافتراضي حدّ عام لكل عرض في الدقيقة.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.offer_view_log (
  offer_id   UUID        NOT NULL,
  viewer_key TEXT        NOT NULL,
  ts_crt     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (offer_id, viewer_key)
);

CREATE INDEX IF NOT EXISTS idx_offer_view_log_ts
  ON public.offer_view_log (ts_crt);

ALTER TABLE public.offer_view_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.offer_view_log FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.offer_view_log TO service_role;

-- يُرجع true إن احتُسبت المشاهدة فعلاً، false إن كانت ضمن نافذة التهدئة.
CREATE OR REPLACE FUNCTION public.increment_offer_view(
  p_offer_id   uuid,
  p_viewer_key text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_key  TEXT := left(coalesce(nullif(trim(p_viewer_key), ''), 'anon'), 120);
  v_last TIMESTAMPTZ;
BEGIN
  IF p_offer_id IS NULL THEN
    RETURN FALSE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.offers WHERE id = p_offer_id AND i_del = 0) THEN
    RETURN FALSE;
  END IF;

  SELECT ts_crt INTO v_last
  FROM public.offer_view_log
  WHERE offer_id = p_offer_id AND viewer_key = v_key;

  -- نافذة التهدئة: 30 دقيقة لكل (عرض + جهاز)
  IF v_last IS NOT NULL AND v_last > NOW() - INTERVAL '30 minutes' THEN
    RETURN FALSE;
  END IF;

  INSERT INTO public.offer_view_log (offer_id, viewer_key, ts_crt)
  VALUES (p_offer_id, v_key, NOW())
  ON CONFLICT (offer_id, viewer_key)
  DO UPDATE SET ts_crt = NOW();

  UPDATE public.offers SET vws = COALESCE(vws, 0) + 1 WHERE id = p_offer_id;

  -- تنظيف خفيف: السجلات الأقدم من يومين لا لزوم لها
  DELETE FROM public.offer_view_log WHERE ts_crt < NOW() - INTERVAL '2 days';

  RETURN TRUE;
END;
$fn$;

REVOKE ALL ON FUNCTION public.increment_offer_view(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.increment_offer_view(uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_offer_view(uuid, text) TO service_role;
CREATE OR REPLACE FUNCTION public.broker_handle_appointment_internal(p_broker_uid uuid, p_appointment_id uuid, p_action text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_cur_sts INT;
  v_allowed BOOLEAN := FALSE;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_broker_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM appointments a
    LEFT JOIN offers o ON o.id = a.off_id
    WHERE a.id = p_appointment_id
      AND (a.bkr_id = p_broker_uid OR a.own_id = p_broker_uid OR o.usr_id = p_broker_uid)
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;

  -- 🔒 BUG-025 (2026-08-14): لم يكن هناك أي فحص للحالة الحالية ⇒ الانتقالات
  -- غير القانونية كلها كانت تمرّ. أُكِّد حياً: موعد **ألغاه العميل** (sts=3)
  -- أُعيد إلى «مؤكَّد» (sts=1) بنداء confirm — أي أن الوسيط يستطيع إحياء
  -- موعد ملغى بلا علم العميل، أو «إتمام» موعد مرفوض ليحتسب في إحصاءاته.
  -- الحالات: 0 بانتظار · 1 مؤكد · 2 تمّت · 3 ملغي · 4 مرفوض.
  -- الانتقالات المسموحة: 0→(1,4) · 1→(2,4) · 2,3,4 نهائية.
  SELECT sts INTO v_cur_sts FROM appointments WHERE id = p_appointment_id;

  IF v_cur_sts IN (2, 3, 4) THEN
    RAISE EXCEPTION 'APPOINTMENT_FINALIZED';
  END IF;

  IF p_action = 'confirm' AND v_cur_sts <> 0 THEN
    RAISE EXCEPTION 'INVALID_TRANSITION';
  END IF;

  IF p_action = 'complete' AND v_cur_sts <> 1 THEN
    RAISE EXCEPTION 'MUST_CONFIRM_BEFORE_COMPLETE';
  END IF;

  IF p_action = 'confirm' THEN
    UPDATE appointments
    SET sts        = 1,
        fbk_own    = 1,
        fbk_own_dt = v_now
    WHERE id = p_appointment_id;
  ELSIF p_action = 'reject' THEN
    UPDATE appointments
    SET sts        = 4,
        fbk_own    = 2,
        fbk_own_dt = v_now,
        dt_end     = v_now
    WHERE id = p_appointment_id;
  ELSIF p_action = 'complete' THEN
    UPDATE appointments
    SET sts    = 2,
        dt_end = v_now
    WHERE id = p_appointment_id;
  ELSE
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  RETURN TRUE;
END;
$function$;
