-- ============================================================================
-- SEC-004 — منع تسريب بيانات التواصل والموقع الدقيق للزائر المجهول
-- ============================================================================
-- الثغرة (مؤكَّدة حياً 2026-08-14): RLS يحرس **الصفوف** لا **الأعمدة**، و
-- anon يملك SELECT على كل جدول offers ⇒ مكالمة REST واحدة تستخرج:
--   • contact_ph — رقم هاتف صاحب كل عرض
--   • exact_loc  — الإحداثيات الدقيقة (32.618127,36.533897)
--   • usr_id     — معرّف المالك الداخلي
--   • loc->>'d'  — العنوان التفصيلي («ساحة الشعلة طابق رابع»)
-- استُخرجت 5 عروض بأرقامها وعناوينها في طلب واحد.
--
-- وهذا يخالف قاعدة صريحة موثّقة في business_service.dart بطلب المالك:
--   «لا معلومات تواصل لصاحب العرض أبداً — التواصل حصراً عبر واتساب المكتب»
-- الواجهة تحترم القاعدة، لكن REST يلتف عليها بالكامل.
--
-- الحل: منح anon أعمدةً محدَّدة بدل الجدول كله. الأعمدة الحساسة تُقرأ فقط
-- عبر الإيدج (مفتاح الخدمة) الذي يقرّر من يستحقها.
-- ملاحظة: `loc` يبقى مسموحاً لأنه يحمل المدينة والمنطقة (لازمان للبحث)،
-- بينما `exact_loc` (الإحداثيات) يُحجب.
-- ============================================================================

REVOKE SELECT ON public.offers FROM anon;

GRANT SELECT (
  id, offer_number, ttl, descript, typ, sub, cat, trx,
  prc, cur, dsc_pct, dsc_end,
  specs, imgs, vdo, loc,
  sts, i_pub, i_del, i_pin, i_fms, i_bst, i_soc, soc_pub,
  pin_end, fms_end, bst_end,
  vws, fvs, avl, com, brk_pct, doc_tp,
  ts_crt, ts_pub, ts_end, ts_ren
) ON public.offers TO anon;

-- المستخدم المسجَّل عبر Supabase Auth: نفس الحجب (هو أيضاً «زائر» بالنسبة
-- لعروض غيره). المالك يقرأ عرضه عبر user-offers بمفتاح الخدمة.
REVOKE SELECT ON public.offers FROM authenticated;

GRANT SELECT (
  id, offer_number, ttl, descript, typ, sub, cat, trx,
  prc, cur, dsc_pct, dsc_end,
  specs, imgs, vdo, loc,
  sts, i_pub, i_del, i_pin, i_fms, i_bst, i_soc, soc_pub,
  pin_end, fms_end, bst_end,
  vws, fvs, avl, com, brk_pct, doc_tp,
  ts_crt, ts_pub, ts_end, ts_ren
) ON public.offers TO authenticated;

-- الامتيازات الخطرة التي لا معنى لوجودها لدور عام
REVOKE TRUNCATE, REFERENCES, TRIGGER ON public.offers FROM anon, authenticated;
-- ============================================================================
-- SEC-005 — حد محاولات تسجيل الدخول (منع التخمين bruteforce)
-- ============================================================================
-- الثغرة (مؤكَّدة حياً 2026-08-14): ثماني محاولات دخول بكلمات خاطئة متتالية
-- على نفس الحساب مرّت كلها بلا أي إبطاء أو قفل — WRONG_PASSWORD في كل مرة.
-- لا عدّاد، لا تأخير، لا قفل مؤقّت.
--
-- الخطورة العملية: كلمات السر في هذا التطبيق تُنشأ إدارياً وتُسلَّم للموظف،
-- وكثير منها أرقام قصيرة (كل الحسابات التجريبية 12345678). مهاجم يعرف رقم
-- هاتف موظف — وقد صار حصده سهلاً قبل إصلاح BUG-021 — يستطيع تجربة آلاف
-- الاحتمالات في دقائق ويصل إلى حساب مدير.
--
-- التصميم: قفل تصاعدي على مستوى القاعدة (لا الذاكرة، فالإيدج بلا حالة):
--   • 5 محاولات فاشلة خلال 15 دقيقة  ⇒ قفل 15 دقيقة
--   • 10 محاولات خلال ساعة           ⇒ قفل ساعة
--   • النجاح يصفّر العدّاد فوراً
-- ولا نكشف للمهاجم إن كان الحساب موجوداً (نفس الرسالة للحالتين).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.login_attempts (
  id          BIGSERIAL PRIMARY KEY,
  identifier  TEXT        NOT NULL,
  ok          BOOLEAN     NOT NULL DEFAULT FALSE,
  ts_crt      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_login_attempts_id_ts
  ON public.login_attempts (identifier, ts_crt DESC);

ALTER TABLE public.login_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.login_attempts FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.login_attempts TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.login_attempts_id_seq TO service_role;

-- يُستدعى **قبل** فحص كلمة السر. يُرجع الثواني المتبقية للقفل (0 = مسموح).
CREATE OR REPLACE FUNCTION public.check_login_throttle(p_identifier text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_id        TEXT := lower(trim(COALESCE(p_identifier, '')));
  v_fail_15   INT;
  v_fail_60   INT;
  v_last_fail TIMESTAMPTZ;
  v_wait      INT := 0;
BEGIN
  IF v_id = '' THEN
    RETURN jsonb_build_object('allowed', true, 'retry_after', 0);
  END IF;

  SELECT COUNT(*), MAX(ts_crt) INTO v_fail_15, v_last_fail
  FROM public.login_attempts
  WHERE identifier = v_id AND ok = FALSE
    AND ts_crt > NOW() - INTERVAL '15 minutes';

  SELECT COUNT(*) INTO v_fail_60
  FROM public.login_attempts
  WHERE identifier = v_id AND ok = FALSE
    AND ts_crt > NOW() - INTERVAL '60 minutes';

  IF v_fail_60 >= 10 THEN
    v_wait := GREATEST(0, 3600 - EXTRACT(EPOCH FROM (NOW() - v_last_fail))::INT);
  ELSIF v_fail_15 >= 5 THEN
    v_wait := GREATEST(0, 900 - EXTRACT(EPOCH FROM (NOW() - v_last_fail))::INT);
  END IF;

  RETURN jsonb_build_object(
    'allowed',     v_wait <= 0,
    'retry_after', v_wait,
    'fails_15m',   v_fail_15
  );
END;
$fn$;

-- يُستدعى **بعد** كل محاولة. النجاح يمسح سجل الإخفاقات.
CREATE OR REPLACE FUNCTION public.record_login_attempt(p_identifier text, p_ok boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_id TEXT := lower(trim(COALESCE(p_identifier, '')));
BEGIN
  IF v_id = '' THEN RETURN; END IF;

  IF p_ok THEN
    DELETE FROM public.login_attempts WHERE identifier = v_id;
  ELSE
    INSERT INTO public.login_attempts (identifier, ok) VALUES (v_id, FALSE);
    -- تنظيف دوري خفيف: لا نحتفظ بأقدم من 24 ساعة
    DELETE FROM public.login_attempts WHERE ts_crt < NOW() - INTERVAL '24 hours';
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION public.check_login_throttle(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_login_throttle(text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_login_throttle(text) TO service_role;

REVOKE ALL ON FUNCTION public.record_login_attempt(text, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_login_attempt(text, boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_login_attempt(text, boolean) TO service_role;
-- SEC-004 (تعديل): إعادة usr_id للقراءة.
-- السبب: عدّاد الحصة في التطبيق يصفّي بـ`.eq('usr_id', uid)`، وPostgREST
-- يشترط صلاحية SELECT على أي عمود يُستخدم في **التصفية** لا العرض فقط
-- ⇒ حجبه كسر عدّ العروض (أُكِّد حياً بـ42501).
-- المفاضلة: usr_id معرّف داخلي لا يكشف وسيلة تواصل، بينما الخطر الحقيقي
-- كان في contact_ph و exact_loc — وهما يبقيان محجوبين.
GRANT SELECT (usr_id) ON public.offers TO anon, authenticated;
