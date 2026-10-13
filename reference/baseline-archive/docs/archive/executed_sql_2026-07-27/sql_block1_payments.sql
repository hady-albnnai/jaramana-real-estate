-- ╔══════════════════════════════════════════════╗
-- ║ كتلة 1 — دورة حياة الدفعات (التراكم + سبب الرفض + الممولة)
-- ║ شغّلها كاملة في SQL Editor — آمنة للتكرار (idempotent)
-- ╚══════════════════════════════════════════════╝

-- 1) عمود الرصيد المضاف بالتراكم
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS pkg_xoff integer NOT NULL DEFAULT 0;

-- 2) حذف النسخة القديمة (باراميترين) حتى ما يصير overload
DROP FUNCTION IF EXISTS public.admin_reject_payment_internal(uuid, uuid);

-- 3) رفض v2 — مع سبب الرفض (يُحفظ في meta ويصل للمستخدم)
CREATE OR REPLACE FUNCTION public.admin_reject_payment_internal(p_admin_uid uuid, p_payment_id uuid, p_reason text DEFAULT '')
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 5 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE payments
  SET sts = 2, appr_by = p_admin_uid,
      meta = COALESCE(meta, '{}'::jsonb) || jsonb_build_object(
        'reject_reason', COALESCE(NULLIF(BTRIM(p_reason), ''), ''),
        'reject_ts', NOW())
  WHERE id = p_payment_id AND sts = 0;
  IF FOUND THEN
    PERFORM public.log_admin_action(p_admin_uid, 106,
      'رفض دفعة — السبب: ' || LEFT(COALESCE(NULLIF(BTRIM(p_reason), ''), 'بدون سبب'), 120),
      p_payment_id::TEXT, 'payments');
  END IF;
  RETURN FOUND;
END; $function$;

-- 4) اعتماد v3 — نموذج التراكم للباقات + تفعيل الممولة
CREATE OR REPLACE FUNCTION public.approve_payment_final(p_payment_id uuid, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_user_id UUID; v_pkg_id INT; v_admin_role INT;
  v_payment_status INT; v_payment_type INT; v_meta JSONB;
  v_config JSONB; v_pkg_duration INT; v_grace_days INT;
  v_old_pkg INT; v_old_end TIMESTAMPTZ; v_old_xoff INT;
  v_offer UUID; v_weeks INT; v_base TIMESTAMPTZ; v_new_end TIMESTAMPTZ;
  v_new_pkg INT; v_new_xoff INT; v_o_old INT; v_o_new INT;
  v_active BOOLEAN; v_upgraded BOOLEAN := false;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_id AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;
  SELECT uid, pkg, sts, tp, meta INTO v_user_id, v_pkg_id, v_payment_status, v_payment_type, v_meta
  FROM payments WHERE id = p_payment_id;
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_FOUND'); END IF;
  IF COALESCE(v_payment_status, -1) <> 0 THEN RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_PENDING'); END IF;
  SELECT value INTO v_config FROM app_config WHERE key = 'main';

  IF COALESCE(v_payment_type, -1) = 0 THEN
    v_pkg_duration := (v_config->'pkg'->(v_pkg_id::text)->>'d')::INT;
    v_grace_days := COALESCE((v_config->'pkg'->>'grace_days')::INT, 3);
    IF v_pkg_duration IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'PKG_DURATION_NOT_FOUND'); END IF;
    SELECT b_pkg, pkg_end, COALESCE(pkg_xoff, 0)
      INTO v_old_pkg, v_old_end, v_old_xoff
      FROM users WHERE id = v_user_id;

    -- نموذج التجميع (2026-07-27): الباقة الجديدة تُضاف للرصيد، ولا يُلغى شيء مدفوع.
    -- ترقية ← سقف القديمة ينتقل للإضافي (pkg_xoff) وتصبح الجديدة الأساس.
    -- تجديد/شراء أدنى ← سقف المشترى يُضاف للإضافي والأساس يبقى الأعلى.
    -- الأيام تُضاف فوق المتبقي دائماً. عند الانتهاء يسقط الكل مع التاريخ الموحد.
    v_active := COALESCE(v_old_pkg, 0) > 0 AND v_old_end IS NOT NULL AND v_old_end > NOW();
    IF v_active THEN
      v_base := v_old_end;
      v_o_old := (v_config->'pkg'->(v_old_pkg::text)->>'o')::INT;
      v_o_new := (v_config->'pkg'->(v_pkg_id::text)->>'o')::INT;
      IF v_pkg_id > v_old_pkg THEN
        v_new_pkg := v_pkg_id;
        v_new_xoff := v_old_xoff + COALESCE(v_o_old, 0);
        v_upgraded := true;
      ELSE
        v_new_pkg := GREATEST(v_old_pkg, v_pkg_id);
        v_new_xoff := v_old_xoff + COALESCE(v_o_new, 0);
      END IF;
    ELSE
      v_base := NOW();
      v_new_pkg := v_pkg_id;
      v_new_xoff := 0;
    END IF;
    v_new_end := v_base + (v_pkg_duration || ' days')::interval;
    UPDATE payments SET sts = 1, appr_by = p_admin_id WHERE id = p_payment_id AND sts = 0;
    UPDATE users SET b_pkg = v_new_pkg, pkg_xoff = v_new_xoff, pkg_end = v_new_end,
      pkg_grace = v_new_end + (v_grace_days || ' days')::interval, ts_upd = NOW()
    WHERE id = v_user_id;
    RETURN jsonb_build_object('success', true, 'type', 'package', 'pkg', v_new_pkg,
      'until', to_char(v_new_end, 'YYYY-MM-DD'),
      'upgraded', v_upgraded, 'stacked', v_active,
      'quota', ((v_config->'pkg'->(v_new_pkg::text)->>'o')::INT + v_new_xoff));
  END IF;

  IF COALESCE(v_payment_type, -1) = 1 THEN
    v_offer := NULLIF(v_meta->>'offer_id', '')::UUID;
    v_weeks := COALESCE((v_meta->>'weeks')::INT, 0);
    IF v_offer IS NULL OR v_weeks < 1 THEN
      RETURN jsonb_build_object('success', false, 'error', 'FEATURED_META_INVALID');
    END IF;
    UPDATE offers
    SET fms_end = GREATEST(NOW(), COALESCE(fms_end, NOW())) + ((v_weeks * 7) || ' days')::interval
    WHERE id = v_offer AND i_del = 0
    RETURNING fms_end INTO v_new_end;
    IF v_new_end IS NULL THEN
      RAISE EXCEPTION 'OFFER_NOT_FOUND';
    END IF;
    UPDATE payments SET sts = 1, appr_by = p_admin_id WHERE id = p_payment_id AND sts = 0;
    RETURN jsonb_build_object('success', true, 'type', 'featured', 'offer_id', v_offer,
      'until', to_char(v_new_end, 'YYYY-MM-DD'));
  END IF;

  RETURN jsonb_build_object('success', false, 'error', 'UNSUPPORTED_PAYMENT_TYPE');
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END; $function$;

-- 5) تحصين — service_role فقط (الإيدج فنكشن تنادي بالمفتاح)
REVOKE EXECUTE ON FUNCTION public.admin_reject_payment_internal(p_admin_uid uuid, p_payment_id uuid, p_reason text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_payment_internal(p_admin_uid uuid, p_payment_id uuid, p_reason text) TO service_role;
REVOKE EXECUTE ON FUNCTION public.approve_payment_final(p_payment_id uuid, p_admin_id uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_payment_final(p_payment_id uuid, p_admin_id uuid) TO service_role;
